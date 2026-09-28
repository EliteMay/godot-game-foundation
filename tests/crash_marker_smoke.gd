extends Node

const CrashMarker = preload(
	"res://addons/game_foundation/recovery/crash_marker.gd"
)
const FoundationRuntime = preload(
	"res://addons/game_foundation/runtime/foundation_runtime.gd"
)

const TEST_DIR: String = (
	"user://game_foundation_crash_marker_tests"
)
const MARKER_PATH: String = TEST_DIR + "/session.json"
const RUNTIME_MARKER_PATH: String = (
	TEST_DIR + "/runtime_session.json"
)
const SAVE_BLOCK_MARKER_PATH: String = (
	TEST_DIR + "/save_block_session.json"
)
const SAVE_PATH: String = TEST_DIR + "/save.json"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_marker_lifecycle()
	_test_corrupt_marker_detection()
	await _test_runtime_integration()
	await _test_safe_quit_ordering()
	_cleanup()
	_finish()


func _test_marker_lifecycle() -> void:
	var first := CrashMarker.new()
	_expect_ok(
		first.configure({
			"path": MARKER_PATH,
			"app_version": "1.0.0",
			"foundation_version": "0.16.0-dev",
		}),
		"first crash marker should configure"
	)
	var first_start: Dictionary = first.begin_session()
	_expect_ok(
		first_start,
		"first crash marker should start"
	)
	var first_previous: Dictionary = (
		first_start.get(
			"previous_session",
			{}
		) as Dictionary
	)
	_expect_true(
		not bool(
			first_previous.get(
				"possible_unclean_exit",
				true
			)
		),
		"first session should not report a previous unclean exit"
	)
	_expect_true(
		FileAccess.file_exists(MARKER_PATH),
		"active session should leave a marker file"
	)

	var second := CrashMarker.new()
	_expect_ok(
		second.configure({
			"path": MARKER_PATH,
			"app_version": "1.0.1",
			"foundation_version": "0.16.0-dev",
		}),
		"second crash marker should configure"
	)
	var second_start: Dictionary = second.begin_session()
	_expect_ok(
		second_start,
		"second crash marker should start"
	)
	var second_previous: Dictionary = (
		second_start.get(
			"previous_session",
			{}
		) as Dictionary
	)
	_expect_true(
		bool(
			second_previous.get(
				"possible_unclean_exit",
				false
			)
		),
		"existing active marker should mean possible unclean exit"
	)
	_expect_equal(
		String(
			second_previous.get(
				"reason",
				""
			)
		),
		"active_marker_present",
		"valid stale marker should have explicit reason"
	)
	_expect_equal(
		String(
			second_previous.get(
				"app_version",
				""
			)
		),
		"1.0.0",
		"previous marker should retain bounded version metadata"
	)

	var first_clean: Dictionary = first.mark_clean()
	_expect_ok(
		first_clean,
		"older session cleanup should not fail"
	)
	_expect_equal(
		String(
			first_clean.get(
				"code",
				""
			)
		),
		"crash_marker_replaced_by_other_session",
		"older session must not delete a newer session marker"
	)
	_expect_true(
		FileAccess.file_exists(MARKER_PATH),
		"newer session marker must survive older cleanup"
	)

	_expect_ok(
		second.mark_clean(),
		"current session cleanup should succeed"
	)
	_expect_true(
		not FileAccess.file_exists(MARKER_PATH),
		"clean session should remove its marker"
	)

	var invalid_path: Dictionary = (
		CrashMarker.validate_marker_path(
			"C:\\Users\\Example\\marker.json"
		)
	)
	_expect_true(
		not bool(invalid_path.get("ok", true)),
		"crash marker must reject absolute paths"
	)


func _test_corrupt_marker_detection() -> void:
	_write_text(MARKER_PATH, "{broken-json")

	var marker := CrashMarker.new()
	_expect_ok(
		marker.configure({
			"path": MARKER_PATH,
		}),
		"marker should configure over corrupt previous file"
	)
	var started: Dictionary = marker.begin_session()
	_expect_ok(
		started,
		"marker should replace corrupt previous evidence with current marker"
	)
	var previous: Dictionary = (
		started.get(
			"previous_session",
			{}
		) as Dictionary
	)
	_expect_true(
		bool(previous.get("marker_found", false)),
		"corrupt marker should still count as marker evidence"
	)
	_expect_true(
		bool(
			previous.get(
				"possible_unclean_exit",
				false
			)
		),
		"corrupt marker should remain possible unclean evidence"
	)
	_expect_true(
		not bool(previous.get("marker_valid", true)),
		"corrupt marker should not be treated as valid"
	)
	_expect_equal(
		String(previous.get("reason", "")),
		"crash_marker_invalid_json",
		"corrupt marker should preserve validation reason"
	)
	_expect_ok(
		marker.mark_clean(),
		"current marker should still clean after corrupt previous evidence"
	)


func _test_runtime_integration() -> void:
	var stale := CrashMarker.new()
	_expect_ok(
		stale.configure({
			"path": RUNTIME_MARKER_PATH,
			"app_version": "previous-runtime",
			"foundation_version": "0.16.0-dev",
		}),
		"stale runtime marker should configure"
	)
	_expect_ok(
		stale.begin_session(),
		"stale runtime marker should start"
	)

	var runtime := FoundationRuntime.new()
	add_child(runtime)
	await get_tree().process_frame

	_expect_ok(
		runtime.configure({
			"app": {
				"name": "Crash Marker Runtime Test",
				"version": "2.0.0",
			},
			"save": {"enabled": false},
			"settings": {"enabled": false},
			"input": {"enabled": false},
			"flow": {
				"enabled": true,
				"scenes": {},
				"main_menu_id": "",
			},
			"diagnostics": {"enabled": false},
			"runtime_test": {"enabled": false},
			"crash_marker": {
				"enabled": true,
				"path": RUNTIME_MARKER_PATH,
			},
		}),
		"runtime should configure with crash marker"
	)
	_expect_ok(
		runtime.initialize(),
		"runtime should initialize with crash marker"
	)

	var state: Dictionary = runtime.crash_marker_snapshot()
	_expect_true(
		bool(state.get("active", false)),
		"runtime crash marker should become active"
	)
	var previous: Dictionary = (
		state.get(
			"previous_session",
			{}
		) as Dictionary
	)
	_expect_true(
		bool(
			previous.get(
				"possible_unclean_exit",
				false
			)
		),
		"runtime should expose previous possible unclean session"
	)

	var status: Dictionary = runtime.status_snapshot()
	_expect_true(
		bool(
			status.get(
				"crash_marker_enabled",
				false
			)
		),
		"runtime status should expose crash marker enablement"
	)

	var flow: Node = runtime.flow_service()
	_expect_true(
		is_instance_valid(flow),
		"flow service should be available"
	)
	if is_instance_valid(flow):
		_expect_ok(
			flow.call("prepare_safe_quit"),
			"safe quit preparation should clean marker"
		)
	_expect_true(
		not FileAccess.file_exists(
			RUNTIME_MARKER_PATH
		),
		"safe quit hook should remove current marker"
	)

	runtime.queue_free()
	await get_tree().process_frame


func _test_safe_quit_ordering() -> void:
	var runtime := FoundationRuntime.new()
	add_child(runtime)
	await get_tree().process_frame

	_expect_ok(
		runtime.configure(
			{
				"app": {
					"name": "Crash Marker Save Order Test",
					"version": "3.0.0",
				},
				"save": {
					"enabled": true,
					"path": SAVE_PATH,
					"game_schema_version": 1,
				},
				"settings": {"enabled": false},
				"input": {"enabled": false},
				"flow": {
					"enabled": true,
					"scenes": {},
					"main_menu_id": "",
				},
				"diagnostics": {"enabled": false},
				"runtime_test": {"enabled": false},
				"crash_marker": {
					"enabled": true,
					"path": SAVE_BLOCK_MARKER_PATH,
				},
			},
			{
				"capture_save_state": Callable(
					self,
					"_capture_invalid_save"
				),
				"restore_save_state": Callable(
					self,
					"_restore_save_ok"
				),
			}
		),
		"runtime should configure for safe quit ordering"
	)
	_expect_ok(
		runtime.initialize(),
		"runtime should initialize before safe quit ordering test"
	)
	_expect_true(
		FileAccess.file_exists(
			SAVE_BLOCK_MARKER_PATH
		),
		"marker should exist before blocked safe quit"
	)

	var flow: Node = runtime.flow_service()
	_expect_true(
		is_instance_valid(flow),
		"flow service should exist for ordering test"
	)
	if is_instance_valid(flow):
		var blocked: Dictionary = flow.call(
			"prepare_safe_quit"
		)
		_expect_true(
			not bool(blocked.get("ok", true)),
			"save failure should block safe quit preparation"
		)

	_expect_true(
		FileAccess.file_exists(
			SAVE_BLOCK_MARKER_PATH
		),
		"marker must remain when an earlier save hook blocks quit"
	)

	runtime.queue_free()
	await get_tree().process_frame
	_expect_true(
		not FileAccess.file_exists(
			SAVE_BLOCK_MARKER_PATH
		),
		"clean runtime teardown should remove its marker"
	)


func _capture_invalid_save() -> Variant:
	return "invalid-save-payload"


func _restore_save_ok(
	_payload: Dictionary
) -> Dictionary:
	return {
		"ok": true,
		"code": "restored",
	}


func _write_text(
	path: String,
	text_value: String
) -> void:
	var directory: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(
		path,
		FileAccess.WRITE
	)
	if file == null:
		_fail("test fixture could not write " + path)
		return
	file.store_string(text_value)
	file.flush()
	file.close()


func _cleanup() -> void:
	for path in [
		MARKER_PATH,
		RUNTIME_MARKER_PATH,
		SAVE_BLOCK_MARKER_PATH,
		SAVE_PATH,
		SAVE_PATH + ".bak",
		SAVE_PATH + ".tmp",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR)


func _expect_ok(
	result: Dictionary,
	message: String
) -> void:
	if not bool(result.get("ok", false)):
		_fail(
			message
			+ " / code="
			+ String(result.get("code", ""))
		)


func _expect_true(
	value: bool,
	message: String
) -> void:
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
	push_error(
		"CRASH_MARKER_SMOKE: "
		+ message
	)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("CRASH_MARKER_SMOKE: PASS")
		get_tree().quit(0)
