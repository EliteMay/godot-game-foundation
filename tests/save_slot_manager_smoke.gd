extends Node

const SaveSystem = preload("res://addons/game_foundation/save/save_system.gd")
const SaveSlotManager = preload(
	"res://addons/game_foundation/save/save_slot_manager.gd"
)

const TEST_ROOT: String = "user://tests/phase14_save_slots"
const SINGLE_SAVE_PATH: String = "user://tests/phase14_single_save.json"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()

	var manager := SaveSlotManager.new()
	_expect_ok(
		manager.configure({
			"slots_root": TEST_ROOT,
			"current_game_schema_version": 2,
			"migrator": Callable(self, "_migrate_payload"),
		}),
		"save slot manager should configure"
	)

	_expect_code(
		manager.slot_path("../escape"),
		"invalid_slot_id",
		"slot ids must not allow path traversal"
	)
	_expect_code(
		manager.slot_path("UpperCase"),
		"invalid_slot_id",
		"slot ids should use the stable lowercase contract"
	)

	var single_saved: Dictionary = SaveSystem.save_game(
		{"legacy_single_save": true, "score": 5},
		2,
		SINGLE_SAVE_PATH
	)
	_expect_ok(single_saved, "existing single-save API should remain usable")
	_expect_equal(
		SaveSystem.DEFAULT_SAVE_PATH,
		"user://save.json",
		"Phase 14 must not change the legacy single-save default path"
	)
	var single_loaded: Dictionary = SaveSystem.load_game(SINGLE_SAVE_PATH, 2)
	_expect_ok(single_loaded, "existing single-save API should still load")
	_expect_true(
		bool((single_loaded.get("payload", {}) as Dictionary).get("legacy_single_save", false)),
		"single-save payload should remain unchanged"
	)

	_expect_code(
		SaveSystem.save_game(
			{"value": 1},
			2,
			TEST_ROOT + "/reserved.json",
			{"saved_at_unix": 1}
		),
		"reserved_metadata_key",
		"slot extensions must not replace Foundation metadata"
	)

	var alpha_created: Dictionary = manager.create_slot(
		"alpha",
		{"score": 10, "chapter": 1},
		{
			"display_name": "Alpha",
			"summary": {"chapter": 1, "play_seconds": 60},
		}
	)
	_expect_code(alpha_created, "slot_created", "alpha slot should be created")
	_expect_true(
		FileAccess.file_exists(TEST_ROOT + "/alpha.json"),
		"alpha primary file should exist"
	)
	_expect_code(
		manager.create_slot("alpha", {"score": 999}),
		"slot_already_exists",
		"create_slot must never overwrite an existing slot"
	)

	var inspected_alpha: Dictionary = SaveSystem.inspect_game(
		TEST_ROOT + "/alpha.json",
		false
	)
	_expect_ok(inspected_alpha, "slot save should be inspectable without loading gameplay")
	var alpha_envelope_metadata: Dictionary = (
		inspected_alpha.get("metadata", {}) as Dictionary
	)
	var alpha_slot_meta: Dictionary = (
		alpha_envelope_metadata.get("slot", {}) as Dictionary
	)
	_expect_equal(
		String(alpha_slot_meta.get("slot_id", "")),
		"alpha",
		"slot identity should live in save metadata, outside game payload"
	)
	_expect_equal(
		int(alpha_slot_meta.get("game_schema_version", 0)),
		2,
		"slot metadata should carry game schema"
	)

	var beta_created: Dictionary = manager.create_slot(
		"beta",
		{"score": 20, "chapter": 2},
		{
			"display_name": "Beta",
			"summary": {"chapter": 2},
		}
	)
	_expect_ok(beta_created, "beta slot should be created")

	await get_tree().create_timer(1.05, true, false, true).timeout
	var alpha_saved: Dictionary = manager.save_slot(
		"alpha",
		{"score": 30, "chapter": 3},
		{
			"summary": {"chapter": 3, "play_seconds": 180},
		}
	)
	_expect_code(alpha_saved, "slot_saved", "alpha slot should update")
	_expect_true(
		FileAccess.file_exists(SaveSystem.backup_path(TEST_ROOT + "/alpha.json")),
		"updating a slot should preserve the prior valid save as backup"
	)

	var listed: Dictionary = manager.list_slots()
	_expect_ok(listed, "slot list should succeed")
	var slots: Array = listed.get("slots", []) as Array
	_expect_equal(slots.size(), 2, "two active slots should be listed")
	if slots.size() >= 2:
		_expect_equal(
			String((slots[0] as Dictionary).get("slot_id", "")),
			"alpha",
			"most recently updated slot should be first"
		)
	_expect_equal(
		(listed.get("invalid_slots", []) as Array).size(),
		0,
		"healthy slots should not produce invalid entries"
	)

	var continued: Dictionary = manager.continue_latest()
	_expect_code(
		continued,
		"continue_slot_loaded",
		"Continue Latest should load the newest healthy slot"
	)
	_expect_equal(
		String(continued.get("slot_id", "")),
		"alpha",
		"Continue Latest should choose alpha"
	)
	_expect_equal(
		int((continued.get("payload", {}) as Dictionary).get("score", 0)),
		30,
		"Continue Latest should return the current payload"
	)

	_write_text(TEST_ROOT + "/alpha.json", "{broken-json")
	var recovered: Dictionary = manager.load_slot("alpha")
	_expect_ok(recovered, "corrupt slot primary should recover through SaveSystem backup")
	_expect_true(
		bool(recovered.get("recovered_from_backup", false)),
		"slot load should expose backup recovery"
	)
	_expect_equal(
		int((recovered.get("payload", {}) as Dictionary).get("score", 0)),
		30,
		"backup should reflect the last successfully loaded healthy primary"
	)
	_expect_code(
		manager.save_slot("alpha", {"score": 40}),
		"slot_not_writable",
		"a corrupt primary must not be overwritten even when its backup is loadable"
	)
	_expect_equal(
		_read_text(TEST_ROOT + "/alpha.json"),
		"{broken-json",
		"failed save must preserve the corrupt primary for recovery"
	)

	await get_tree().create_timer(1.05, true, false, true).timeout
	_expect_ok(
		manager.save_slot(
			"beta",
			{"score": 25, "chapter": 2},
			{"summary": {"chapter": 2, "play_seconds": 240}}
		),
		"beta should update before delete"
	)
	_expect_true(
		FileAccess.file_exists(SaveSystem.backup_path(TEST_ROOT + "/beta.json")),
		"beta should have a recovery backup before delete"
	)
	_expect_code(
		manager.delete_slot("beta"),
		"slot_deleted",
		"explicit slot delete should succeed"
	)
	_expect_true(
		not FileAccess.file_exists(TEST_ROOT + "/beta.json"),
		"deleted slot primary should leave the active namespace"
	)
	_expect_true(
		not FileAccess.file_exists(SaveSystem.backup_path(TEST_ROOT + "/beta.json")),
		"explicit delete should also remove the slot backup"
	)
	_expect_code(
		manager.save_slot("beta", {"score": 500}),
		"slot_not_writable",
		"stale runtime state must not recreate a deleted slot through save_slot"
	)

	var new_game: Dictionary = manager.create_new_game(
		{"score": 0, "chapter": 1},
		{
			"display_name": "New Run",
			"summary": {"chapter": 1},
		}
	)
	_expect_code(
		new_game,
		"new_game_slot_created",
		"new game helper should create a distinct slot"
	)
	var new_slot_id: String = String(new_game.get("slot_id", ""))
	_expect_true(not new_slot_id.is_empty(), "new game helper should return a slot id")
	_expect_true(
		new_slot_id != "alpha",
		"new game helper must not reuse an existing slot"
	)
	_expect_true(
		FileAccess.file_exists(TEST_ROOT + "/" + new_slot_id + ".json"),
		"new game slot should materialize independently"
	)
	_expect_equal(
		_read_text(TEST_ROOT + "/alpha.json"),
		"{broken-json",
		"creating a new game must not overwrite another slot"
	)

	var cloud_descriptor: Dictionary = manager.cloud_slot_descriptor(new_slot_id)
	_expect_ok(cloud_descriptor, "cloud extension descriptor should resolve")
	_expect_equal(
		String(cloud_descriptor.get("cloud_provider", "")),
		"external_adapter",
		"Foundation Core should keep cloud provider integration outside the slot manager"
	)

	var legacy_root: String = TEST_ROOT + "_legacy"
	var legacy_manager := SaveSlotManager.new()
	_expect_ok(
		legacy_manager.configure({
			"slots_root": legacy_root,
			"current_game_schema_version": 1,
		}),
		"legacy slot manager should configure"
	)
	_expect_ok(
		legacy_manager.create_slot(
			"legacy",
			{"score": 7},
			{"display_name": "Legacy"}
		),
		"legacy schema slot should be created"
	)
	var migrated_manager := SaveSlotManager.new()
	_expect_ok(
		migrated_manager.configure({
			"slots_root": legacy_root,
			"current_game_schema_version": 2,
			"migrator": Callable(self, "_migrate_payload"),
		}),
		"new schema slot manager should configure"
	)
	var migrated: Dictionary = migrated_manager.load_slot("legacy")
	_expect_ok(migrated, "slot load should reuse the Generic Save migration hook")
	_expect_true(bool(migrated.get("migrated", false)), "legacy slot should report migration")
	_expect_equal(
		int((migrated.get("payload", {}) as Dictionary).get("schema_marker", 0)),
		2,
		"migrated slot payload should come from the game migrator"
	)

	_cleanup()
	_finish()


func _migrate_payload(
	payload: Dictionary,
	from_version: int,
	to_version: int
) -> Dictionary:
	var migrated: Dictionary = payload.duplicate(true)
	migrated["migrated_from"] = from_version
	migrated["schema_marker"] = to_version
	return migrated


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write fixture: " + path)
		return
	file.store_string(text)
	file.close()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("could not read fixture: " + path)
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _cleanup() -> void:
	_cleanup_root(TEST_ROOT)
	_cleanup_root(TEST_ROOT + "_legacy")
	for path in [
		SINGLE_SAVE_PATH,
		SaveSystem.backup_path(SINGLE_SAVE_PATH),
		SaveSystem.temp_path(SINGLE_SAVE_PATH),
		SaveSystem.backup_path(SINGLE_SAVE_PATH) + SaveSystem.TEMP_SUFFIX,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _cleanup_root(root: String) -> void:
	if not DirAccess.dir_exists_absolute(root):
		return
	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if directory.current_is_dir():
			continue
		DirAccess.remove_absolute(root + "/" + entry)
	directory.list_dir_end()
	DirAccess.remove_absolute(root)


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


func _expect_code(
	result: Dictionary,
	expected: String,
	message: String
) -> void:
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


func _expect_equal(
	actual: Variant,
	expected: Variant,
	message: String
) -> void:
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
	push_error("SAVE_SLOT_MANAGER_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("SAVE_SLOT_MANAGER_SMOKE: PASS")
		get_tree().quit(0)
