extends Node

const FoundationRuntime = preload("res://addons/game_foundation/runtime/foundation_runtime.gd")

const SAVE_PATH := "user://tests/foundation_runtime_smoke_save.json"
const SETTINGS_PATH := "user://tests/foundation_runtime_smoke_settings.json"
const INPUT_PATH := "user://tests/foundation_runtime_smoke_input.json"
const LOG_PATH := "user://tests/foundation_runtime_smoke.log"

var _failed: bool = false
var _game_state: Dictionary = {"score": 0}
var _applied_gameplay_settings: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()

	var runtime := FoundationRuntime.new()
	add_child(runtime)

	var configured: Dictionary = runtime.configure(
		{
			"app": {
				"name": "Foundation Runtime Smoke",
				"version": "1.0.0",
			},
			"save": {
				"enabled": true,
				"path": SAVE_PATH,
				"game_schema_version": 1,
				"autosave_debounce_seconds": 1.0,
			},
			"settings": {
				"enabled": true,
				"path": SETTINGS_PATH,
				"gameplay_defaults": {
					"look_sensitivity": 1.0,
				},
				"apply_runtime": false,
			},
			"input": {
				"enabled": true,
				"path": INPUT_PATH,
				"contract": {
					"foundation_runtime_smoke_action": {
						"deadzone": 0.5,
						"events": [
							{
								"type": "key",
								"physical_keycode": KEY_F9,
							},
						],
					},
				},
			},
			"flow": {
				"enabled": true,
				"scenes": {
					"demo": "res://demo/demo.tscn",
				},
				"main_menu_id": "demo",
			},
			"diagnostics": {
				"enabled": true,
				"log_path": LOG_PATH,
			},
			"runtime_test": {
				"enabled": false,
			},
		},
		{
			"capture_save_state": Callable(self, "_capture_save_state"),
			"restore_save_state": Callable(self, "_restore_save_state"),
			"apply_gameplay_settings": Callable(self, "_apply_gameplay_settings"),
		}
	)
	_expect_ok(configured, "configure")

	var initialized: Dictionary = runtime.initialize()
	_expect_ok(initialized, "initialize")
	_expect_equal(
		String((initialized.get("save", {}) as Dictionary).get("code", "")),
		"new_game",
		"first runtime start should be a new game"
	)
	_expect_true(
		InputMap.has_action(&"foundation_runtime_smoke_action"),
		"input contract should be restored/applied"
	)
	_expect_equal(
		float(_applied_gameplay_settings.get("look_sensitivity", 0.0)),
		1.0,
		"gameplay settings adapter should receive defaults"
	)
	_expect_true(
		runtime.flow_service() != null,
		"flow service should be available"
	)
	if runtime.flow_service() != null:
		_expect_equal(
			int(runtime.flow_service().call("quit_hook_count")),
			1,
			"save-enabled runtime should register one safe quit hook"
		)

	var diagnostics: Dictionary = runtime.diagnostics_snapshot()
	var runtime_info: Dictionary = diagnostics.get("runtime", {})
	var app_info: Dictionary = runtime_info.get("app", {})
	_expect_equal(
		String(app_info.get("name", "")),
		"Foundation Runtime Smoke",
		"diagnostics should include configured app info"
	)

	_game_state = {"score": 10}
	var queued: Dictionary = runtime.request_auto_save()
	_expect_ok(queued, "request_auto_save")
	_expect_equal(
		String(queued.get("code", "")),
		"autosave_queued",
		"debounced autosave should remain pending"
	)

	_game_state = {"score": 20}
	var saved: Dictionary = runtime.save_now()
	_expect_ok(saved, "save_now")
	_expect_true(
		FileAccess.file_exists(SAVE_PATH),
		"save_now should materialize the primary save"
	)

	_game_state = {"score": 0}
	var loaded: Dictionary = runtime.load_now()
	_expect_ok(loaded, "load_now")
	_expect_equal(
		int(_game_state.get("score", -1)),
		20,
		"explicit save must not be overwritten by an older pending autosave"
	)

	var settings_result: Dictionary = runtime.save_settings({
		"audio": {
			"master": 1.0,
			"bgm": 1.0,
			"sfx": 1.0,
		},
		"display": {
			"window_mode": "windowed",
			"resolution": [960, 540],
			"vsync": true,
		},
		"gameplay": {
			"look_sensitivity": 1.5,
		},
	})
	_expect_ok(settings_result, "save_settings")
	_expect_equal(
		float(_applied_gameplay_settings.get("look_sensitivity", 0.0)),
		1.5,
		"gameplay settings adapter should receive updated values"
	)

	var edit_start: Dictionary = runtime.begin_settings_edit_session()
	_expect_ok(edit_start, "begin_settings_edit_session")
	var edit_session: RefCounted = edit_start.get("session") as RefCounted
	_expect_true(edit_session != null, "settings edit session should be returned")
	if edit_session != null:
		var preview_settings: Dictionary = runtime.current_settings()
		(preview_settings.get("gameplay", {}) as Dictionary)["look_sensitivity"] = 2.0
		_expect_ok(
			edit_session.call("set_draft", preview_settings),
			"settings edit preview"
		)
		_expect_equal(
			float(_applied_gameplay_settings.get("look_sensitivity", 0.0)),
			2.0,
			"settings edit preview should apply runtime gameplay values"
		)
		_expect_equal(
			float(
				(runtime.current_settings().get("gameplay", {}) as Dictionary)
				.get("look_sensitivity", 0.0)
			),
			1.5,
			"preview should not replace committed runtime settings"
		)
		_expect_ok(edit_session.call("cancel"), "settings edit cancel")
		_expect_equal(
			float(_applied_gameplay_settings.get("look_sensitivity", 0.0)),
			1.5,
			"cancel should restore runtime gameplay values"
		)

	var apply_start: Dictionary = runtime.begin_settings_edit_session()
	_expect_ok(apply_start, "begin apply settings edit session")
	var apply_session: RefCounted = apply_start.get("session") as RefCounted
	_expect_true(apply_session != null, "apply settings edit session should be returned")
	if apply_session != null:
		var apply_settings: Dictionary = runtime.current_settings()
		(apply_settings.get("gameplay", {}) as Dictionary)["look_sensitivity"] = 1.75
		_expect_ok(
			apply_session.call("set_draft", apply_settings),
			"settings edit apply preview"
		)
		_expect_ok(apply_session.call("apply"), "settings edit apply")
		_expect_equal(
			float(
				(runtime.current_settings().get("gameplay", {}) as Dictionary)
				.get("look_sensitivity", 0.0)
			),
			1.75,
			"Apply should advance committed runtime settings"
		)
		var post_apply: Dictionary = apply_session.call("draft_settings")
		(post_apply.get("gameplay", {}) as Dictionary)["look_sensitivity"] = 2.5
		_expect_ok(
			apply_session.call("set_draft", post_apply),
			"post-apply preview"
		)
		_expect_ok(apply_session.call("cancel"), "post-apply cancel")
		_expect_equal(
			float(_applied_gameplay_settings.get("look_sensitivity", 0.0)),
			1.75,
			"Cancel after Apply should restore the latest committed baseline"
		)

	var input_saved: Dictionary = runtime.save_input_bindings()
	_expect_ok(input_saved, "save_input_bindings")
	_expect_true(
		FileAccess.file_exists(INPUT_PATH),
		"input bindings should be persisted"
	)

	var status: Dictionary = runtime.status_snapshot()
	_expect_true(bool(status.get("initialized", false)), "runtime should report initialized")
	_expect_true(not bool(status.get("save_writes_blocked", true)), "normal load should not block writes")
	_expect_true(not bool(status.get("runtime_test_mode", true)), "smoke run should not be test-bridge mode")

	runtime.queue_free()
	await get_tree().process_frame

	for path in [SAVE_PATH + ".bak", SAVE_PATH + ".tmp", SAVE_PATH + ".bak.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var broken_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if broken_file == null:
		_fail("could not create corrupt save fixture")
	else:
		broken_file.store_string("{ broken json")
		broken_file.close()

	var protected_runtime := FoundationRuntime.new()
	add_child(protected_runtime)
	var protected_config: Dictionary = protected_runtime.configure(
		{
			"save": {
				"enabled": true,
				"path": SAVE_PATH,
				"game_schema_version": 1,
			},
			"settings": {"enabled": false},
			"input": {"enabled": false},
			"flow": {"enabled": false},
			"diagnostics": {"enabled": false},
			"runtime_test": {"enabled": false},
		},
		{
			"capture_save_state": Callable(self, "_capture_save_state"),
			"restore_save_state": Callable(self, "_restore_save_state"),
		}
	)
	_expect_ok(protected_config, "protected runtime configure")
	var protected_initialized: Dictionary = protected_runtime.initialize()
	_expect_ok(protected_initialized, "protected runtime initialize")
	_expect_true(
		protected_runtime.is_save_write_blocked(),
		"corrupt unrecoverable save should block future writes"
	)

	_game_state = {"score": 999}
	var blocked_save: Dictionary = protected_runtime.save_now()
	_expect_ok(blocked_save, "blocked save should preserve the existing file without crashing")
	_expect_equal(
		String(blocked_save.get("code", "")),
		"save_preserved_after_load_failure",
		"blocked save should report preservation instead of overwriting"
	)
	var preserved_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if preserved_file == null:
		_fail("corrupt primary should remain available for recovery")
	else:
		_expect_equal(
			preserved_file.get_as_text(),
			"{ broken json",
			"blocked runtime must not overwrite the corrupt primary"
		)
		preserved_file.close()

	protected_runtime.queue_free()
	await get_tree().process_frame
	_cleanup()
	_finish()


func _capture_save_state() -> Dictionary:
	return _game_state.duplicate(true)


func _restore_save_state(payload: Dictionary) -> Dictionary:
	_game_state = payload.duplicate(true)
	return {
		"ok": true,
		"code": "restored",
	}


func _apply_gameplay_settings(settings: Dictionary) -> Dictionary:
	_applied_gameplay_settings = settings.duplicate(true)
	return {
		"ok": true,
		"code": "applied",
	}


func _cleanup() -> void:
	for path in [
		SAVE_PATH,
		SAVE_PATH + ".bak",
		SAVE_PATH + ".tmp",
		SAVE_PATH + ".bak.tmp",
		SETTINGS_PATH,
		SETTINGS_PATH + ".bak",
		SETTINGS_PATH + ".tmp",
		SETTINGS_PATH + ".bak.tmp",
		INPUT_PATH,
		INPUT_PATH + ".tmp",
		LOG_PATH,
		LOG_PATH + ".old",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _expect_ok(result: Dictionary, label: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(label + " failed / " + str(result))


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
	push_error("FOUNDATION_RUNTIME_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("FOUNDATION_RUNTIME_SMOKE: PASS")
		get_tree().quit(0)
