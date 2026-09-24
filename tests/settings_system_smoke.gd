extends Node

const SettingsSystem = preload("res://addons/game_foundation/settings/settings_system.gd")
const SettingsRuntime = preload("res://addons/game_foundation/settings/settings_runtime.gd")

const TEST_DIR := "user://game_foundation_settings_tests"
const SETTINGS_PATH := TEST_DIR + "/settings.json"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()

	var gameplay_defaults := {
		"mouse_sensitivity": 0.25,
		"camera": {
			"fov": 90,
		},
	}

	var defaults: Dictionary = SettingsSystem.default_settings(gameplay_defaults)
	_expect_equal(
		float((defaults.get("audio", {}) as Dictionary).get("master", -1.0)),
		1.0,
		"default master volume should be 1"
	)
	_expect_equal(
		String((defaults.get("display", {}) as Dictionary).get("window_mode", "")),
		"windowed",
		"default window mode should be windowed"
	)
	_expect_equal(
		float((defaults.get("gameplay", {}) as Dictionary).get("mouse_sensitivity", 0.0)),
		0.25,
		"gameplay defaults should be included"
	)

	var normalized_result: Dictionary = SettingsSystem.normalize_settings(
		{
			"audio": {
				"master": 2.0,
				"bgm": -1.0,
				"sfx": 0.4,
			},
			"display": {
				"window_mode": "not-a-mode",
				"resolution": [100, 99999],
				"vsync": "yes",
			},
			"gameplay": {
				"mouse_sensitivity": 0.5,
				"camera": {
					"invert_y": true,
				},
			},
		},
		gameplay_defaults
	)
	_expect_ok(normalized_result, "normalization should succeed")

	var normalized: Dictionary = normalized_result.get("settings", {})
	var audio: Dictionary = normalized.get("audio", {})
	var display: Dictionary = normalized.get("display", {})
	var gameplay: Dictionary = normalized.get("gameplay", {})
	var camera: Dictionary = gameplay.get("camera", {})

	_expect_equal(float(audio.get("master", -1.0)), 1.0, "master volume should clamp to 1")
	_expect_equal(float(audio.get("bgm", -1.0)), 0.0, "bgm volume should clamp to 0")
	_expect_equal(float(audio.get("sfx", -1.0)), 0.4, "sfx volume should be preserved")
	_expect_equal(String(display.get("window_mode", "")), "windowed", "invalid mode should use default")
	_expect_equal((display.get("resolution", []) as Array)[0], 320, "width should clamp to minimum")
	_expect_equal((display.get("resolution", []) as Array)[1], 16384, "height should clamp to maximum")
	_expect_equal(bool(display.get("vsync", false)), true, "invalid vsync should use default")
	_expect_equal(float(gameplay.get("mouse_sensitivity", 0.0)), 0.5, "gameplay override should be preserved")
	_expect_equal(int(camera.get("fov", 0)), 90, "nested gameplay default should be preserved")
	_expect_equal(bool(camera.get("invert_y", false)), true, "nested gameplay extension should be preserved")

	var invalid_defaults: Dictionary = SettingsSystem.normalize_settings(
		{},
		{"position": Vector3(1, 2, 3)}
	)
	_expect_code(
		invalid_defaults,
		"invalid_gameplay_defaults",
		"non-JSON gameplay defaults should be rejected"
	)

	var save_result: Dictionary = SettingsSystem.save_settings(
		normalized,
		gameplay_defaults,
		SETTINGS_PATH
	)
	_expect_ok(save_result, "settings save should succeed")
	_expect_true(
		not FileAccess.file_exists(SettingsSystem.temp_path(SETTINGS_PATH)),
		"settings temp file should not remain"
	)

	var load_result: Dictionary = SettingsSystem.load_settings(
		gameplay_defaults,
		SETTINGS_PATH
	)
	_expect_ok(load_result, "settings load should succeed")
	_expect_equal(String(load_result.get("source", "")), "primary", "settings should load from primary")
	var loaded: Dictionary = load_result.get("settings", {})
	_expect_equal(
		float((loaded.get("gameplay", {}) as Dictionary).get("mouse_sensitivity", 0.0)),
		0.5,
		"gameplay setting should persist"
	)

	var changed := normalized.duplicate(true)
	(changed.get("audio", {}) as Dictionary)["master"] = 0.2
	_expect_ok(
		SettingsSystem.save_settings(changed, gameplay_defaults, SETTINGS_PATH),
		"second settings save should succeed"
	)
	_expect_true(
		FileAccess.file_exists(SettingsSystem.backup_path(SETTINGS_PATH)),
		"settings backup should exist"
	)

	_write_text(SETTINGS_PATH, "{broken-json")
	var recovered: Dictionary = SettingsSystem.load_settings(
		gameplay_defaults,
		SETTINGS_PATH
	)
	_expect_ok(recovered, "broken primary settings should recover")
	_expect_equal(String(recovered.get("source", "")), "backup", "settings should recover from backup")

	_cleanup()
	var missing: Dictionary = SettingsSystem.load_settings(
		gameplay_defaults,
		SETTINGS_PATH
	)
	_expect_ok(missing, "missing settings should fall back to defaults")
	_expect_code(missing, "defaults_used", "missing settings should report defaults_used")
	_expect_equal(String(missing.get("source", "")), "defaults", "missing settings source should be defaults")

	_expect_ok(
		SettingsSystem.save_settings(normalized, gameplay_defaults, SETTINGS_PATH),
		"settings fixture should save before reset"
	)
	var reset: Dictionary = SettingsSystem.reset_settings(
		gameplay_defaults,
		SETTINGS_PATH
	)
	_expect_ok(reset, "reset should succeed")
	_expect_true(not FileAccess.file_exists(SETTINGS_PATH), "reset should remove primary settings")

	var runtime_result: Dictionary = SettingsRuntime.apply_settings(normalized)
	if DisplayServer.get_name() == "headless":
		_expect_code(
			runtime_result,
			"headless_skipped",
			"headless runtime apply should skip display/audio safely"
		)
	else:
		_expect_ok(runtime_result, "runtime settings should apply outside headless")

	_cleanup()
	_finish()


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
		SETTINGS_PATH,
		SettingsSystem.backup_path(SETTINGS_PATH),
		SettingsSystem.temp_path(SETTINGS_PATH),
		SettingsSystem.backup_path(SETTINGS_PATH) + SettingsSystem.TEMP_SUFFIX,
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
	push_error("SETTINGS_SYSTEM_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("SETTINGS_SYSTEM_SMOKE: PASS")
		get_tree().quit(0)
