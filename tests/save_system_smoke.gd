extends Node

const SaveSystemScript = preload("res://addons/game_foundation/save/save_system.gd")
const AutoSaveServiceScript = preload("res://addons/game_foundation/save/auto_save_service.gd")

const TEST_DIR := "user://game_foundation_save_tests"
const PRIMARY := TEST_DIR + "/primary.json"
const VERSIONED := TEST_DIR + "/versioned.json"
const MIGRATION := TEST_DIR + "/migration.json"
const AUTOSAVE := TEST_DIR + "/autosave.json"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()

	var payload := {
		"profile": {
			"name": "test-player",
			"level": 7,
		},
		"inventory": ["iron", "wood"],
		"flags": {
			"intro_complete": true,
		},
	}

	_expect_ok(SaveSystemScript.validate_payload(payload), "JSON-compatible payload should validate")
	_expect_code(
		SaveSystemScript.validate_payload({"position": Vector3(1, 2, 3)}),
		"unsupported_type",
		"Vector3 must be rejected by JSON contract"
	)
	_expect_code(
		SaveSystemScript.validate_payload({1: "invalid"}),
		"non_string_key",
		"non-String Dictionary keys must be rejected"
	)
	_expect_code(
		SaveSystemScript.save_game(payload, 1, "res://save.json"),
		"unsafe_path",
		"runtime save must be restricted to user://"
	)

	var first_save: Dictionary = SaveSystemScript.save_game(payload, 1, PRIMARY)
	_expect_ok(first_save, "first save should succeed")
	_expect_true(
		not FileAccess.file_exists(SaveSystemScript.temp_path(PRIMARY)),
		"temp file should not remain after save"
	)

	var first_load: Dictionary = SaveSystemScript.load_game(PRIMARY, 1)
	_expect_ok(first_load, "saved payload should load")
	_expect_equal(String(first_load.get("source", "")), "primary", "load source should be primary")
	var loaded_payload: Dictionary = first_load.get("payload", {})
	_expect_equal(
		int((loaded_payload.get("profile", {}) as Dictionary).get("level", 0)),
		7,
		"loaded payload should preserve nested values"
	)

	var updated_payload := payload.duplicate(true)
	updated_payload["profile"]["level"] = 8
	_expect_ok(
		SaveSystemScript.save_game(updated_payload, 1, PRIMARY),
		"second save should succeed"
	)
	_expect_true(
		FileAccess.file_exists(SaveSystemScript.backup_path(PRIMARY)),
		"second save should retain a backup"
	)

	_write_text(PRIMARY, "{broken-json")
	var recovered: Dictionary = SaveSystemScript.load_game(PRIMARY, 1)
	_expect_ok(recovered, "corrupted primary should recover from valid backup")
	_expect_equal(String(recovered.get("source", "")), "backup", "recovery source should be backup")
	_expect_true(
		bool(recovered.get("recovered_from_backup", false)),
		"backup recovery flag should be true"
	)

	_expect_ok(
		SaveSystemScript.save_game({"value": 3}, 3, VERSIONED),
		"newer schema fixture should save"
	)
	var too_new: Dictionary = SaveSystemScript.load_game(VERSIONED, 2)
	_expect_code(too_new, "game_schema_too_new", "newer game schema must be rejected")
	_expect_equal(
		String(too_new.get("source", "")),
		"primary",
		"newer schema must not silently fall back"
	)

	_expect_ok(
		SaveSystemScript.save_game({"score": 4}, 1, MIGRATION),
		"migration fixture should save"
	)
	_expect_code(
		SaveSystemScript.load_game(MIGRATION, 2),
		"migration_required",
		"older game schema should require a migrator"
	)

	var migrated: Dictionary = SaveSystemScript.load_game(
		MIGRATION,
		2,
		Callable(self, "_migrate_payload")
	)
	_expect_ok(migrated, "migration hook should load older payload")
	_expect_true(bool(migrated.get("migrated", false)), "migrated flag should be true")
	var migrated_payload: Dictionary = migrated.get("payload", {})
	_expect_equal(int(migrated_payload.get("score", 0)), 40, "migrator should transform payload")
	_expect_equal(
		int(migrated_payload.get("schema_marker", 0)),
		2,
		"migrator should receive target version"
	)

	var service := AutoSaveServiceScript.new()
	service.save_path = AUTOSAVE
	service.debounce_seconds = 0.05
	add_child(service)
	await get_tree().process_frame

	_expect_code(
		service.request_save({"value": 1}, 1),
		"autosave_queued",
		"autosave should queue"
	)
	_expect_code(
		service.request_save({"value": 2}, 1),
		"autosave_queued",
		"later autosave should replace pending state"
	)
	_expect_true(service.has_pending_save(), "autosave should report pending state")

	await get_tree().create_timer(0.12).timeout
	_expect_true(not service.has_pending_save(), "autosave should flush after debounce")

	var autosave_load: Dictionary = SaveSystemScript.load_game(AUTOSAVE, 1)
	_expect_ok(autosave_load, "autosave result should load")
	var autosave_payload: Dictionary = autosave_load.get("payload", {})
	_expect_equal(
		int(autosave_payload.get("value", 0)),
		2,
		"debounce should persist latest payload"
	)

	_expect_code(
		service.request_save({"value": 9}, 1),
		"autosave_queued",
		"manual flush fixture should queue"
	)
	_expect_ok(service.flush_pending(), "flush_pending should save immediately")
	var flushed: Dictionary = SaveSystemScript.load_game(AUTOSAVE, 1)
	_expect_ok(flushed, "flushed autosave should load")
	_expect_equal(
		int((flushed.get("payload", {}) as Dictionary).get("value", 0)),
		9,
		"flush should persist pending payload"
	)

	service.queue_free()
	_cleanup()
	_finish()


func _migrate_payload(payload: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var migrated := payload.duplicate(true)
	if from_version == 1 and to_version == 2:
		migrated["score"] = int(migrated.get("score", 0)) * 10
		migrated["schema_marker"] = to_version
	return migrated


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("test fixture could not open " + path)
		return
	file.store_string(text)
	file.flush()
	file.close()


func _cleanup() -> void:
	var paths := [
		PRIMARY,
		SaveSystemScript.backup_path(PRIMARY),
		SaveSystemScript.temp_path(PRIMARY),
		SaveSystemScript.backup_path(PRIMARY) + SaveSystemScript.TEMP_SUFFIX,
		VERSIONED,
		SaveSystemScript.backup_path(VERSIONED),
		SaveSystemScript.temp_path(VERSIONED),
		MIGRATION,
		SaveSystemScript.backup_path(MIGRATION),
		SaveSystemScript.temp_path(MIGRATION),
		AUTOSAVE,
		SaveSystemScript.backup_path(AUTOSAVE),
		SaveSystemScript.temp_path(AUTOSAVE),
	]
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR)


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


func _expect_code(result: Dictionary, expected: String, message: String) -> void:
	if String(result.get("code", "")) != expected:
		_fail(
			message
			+ " / expected="
			+ expected
			+ " actual="
			+ String(result.get("code", ""))
		)


func _expect_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail(
			message
			+ " / expected="
			+ str(expected)
			+ " actual="
			+ str(actual)
		)


func _fail(message: String) -> void:
	_failed = true
	push_error("SAVE_SYSTEM_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("SAVE_SYSTEM_SMOKE: PASS")
		get_tree().quit(0)
