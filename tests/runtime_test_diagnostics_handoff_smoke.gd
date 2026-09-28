extends Node

const FoundationRuntime = preload(
	"res://addons/game_foundation/runtime/foundation_runtime.gd"
)
const CrashMarker = preload(
	"res://addons/game_foundation/recovery/crash_marker.gd"
)

const MARKER_PATH: String = (
	"user://tests/runtime_test_diagnostics_handoff_crash.json"
)
const LOG_PATH: String = (
	"user://tests/runtime_test_diagnostics_handoff.log"
)
const STATE_ARG_PREFIX: String = "--foundation-test-state="
const SESSION_ARG_PREFIX: String = "--foundation-test-session="

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()

	var stale_marker := CrashMarker.new()
	_expect_ok(
		stale_marker.configure({
			"path": MARKER_PATH,
			"app_version": "0.0.9",
			"foundation_version": "0.15.0-dev",
		}),
		"stale marker configure"
	)
	_expect_ok(
		stale_marker.begin_session(),
		"stale marker begin"
	)

	var runtime := FoundationRuntime.new()
	add_child(runtime)
	_expect_ok(
		runtime.configure(
			{
				"app": {
					"name": "Diagnostics Handoff Smoke",
					"version": "1.0.0",
				},
				"save": {"enabled": false},
				"settings": {"enabled": false},
				"input": {"enabled": false},
				"flow": {"enabled": false},
				"diagnostics": {
					"enabled": true,
					"log_path": LOG_PATH,
				},
				"runtime_test": {"enabled": true},
				"crash_marker": {
					"enabled": true,
					"path": MARKER_PATH,
				},
			},
			{
				"runtime_test_state": Callable(
					self,
					"_runtime_test_state"
				),
			}
		),
		"runtime configure"
	)

	var initialized: Dictionary = runtime.initialize()
	_expect_ok(initialized, "runtime initialize")
	var runtime_test: Dictionary = (
		initialized.get("runtime_test", {}) as Dictionary
	)
	_expect_true(
		bool(runtime_test.get("enabled", false)),
		"runtime test bridge should be enabled by command line"
	)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var output_path: String = _find_argument(
		STATE_ARG_PREFIX
	)
	if output_path.is_empty():
		_fail("state output argument is missing")
		runtime.queue_free()
		await get_tree().process_frame
		_cleanup()
		_finish()
		return

	var file := FileAccess.open(
		output_path,
		FileAccess.READ
	)
	if file == null:
		_fail("runtime bridge output was not created")
		runtime.queue_free()
		await get_tree().process_frame
		_cleanup()
		_finish()
		return

	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		_fail("runtime bridge output is not valid JSON")
	else:
		var envelope: Dictionary = parsed as Dictionary
		_expect_equal(
			int(envelope.get("schemaVersion", 0)),
			2,
			"bridge schema should expose diagnostics transport"
		)
		_expect_equal(
			String(envelope.get("sessionId", "")),
			_find_argument(SESSION_ARG_PREFIX),
			"bridge session should match command line"
		)
		var state: Dictionary = (
			envelope.get("state", {}) as Dictionary
		)
		_expect_true(
			bool(state.get("ready", false)),
			"game telemetry state should be preserved"
		)

		var diagnostics: Dictionary = (
			envelope.get(
				"foundationDiagnostics",
				{}
			) as Dictionary
		)
		_expect_equal(
			String(diagnostics.get("source", "")),
			"godot-game-foundation",
			"sanitized Foundation diagnostics should be attached"
		)
		var handoff: Dictionary = (
			diagnostics.get("handoff", {}) as Dictionary
		)
		_expect_true(
			bool(handoff.get("sanitized", false)),
			"attached diagnostics must be sanitized"
		)
		_expect_true(
			bool(
				handoff.get(
					"remote_eligible",
					false
				)
			),
			"attached diagnostics must be remote eligible"
		)
		var diagnostics_runtime: Dictionary = (
			diagnostics.get("runtime", {}) as Dictionary
		)
		var previous: Dictionary = (
			diagnostics_runtime.get(
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
			"previous-session crash evidence should reach the bridge"
		)
		_expect_true(
			not json_text.contains("session_id"),
			"current crash marker session id must not leak"
		)
		_expect_true(
			not json_text.contains(MARKER_PATH),
			"crash marker path must not leak"
		)

	runtime.queue_free()
	await get_tree().process_frame
	_cleanup()
	_finish()


func _runtime_test_state() -> Dictionary:
	return {
		"ready": true,
		"player": {
			"position": [0.0, 0.0, 0.0],
			"yaw": 0.0,
			"pitch": 0.0,
		},
	}


func _find_argument(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		var value: String = String(argument)
		if value.begins_with(prefix):
			return value.substr(prefix.length()).strip_edges()
	return ""


func _cleanup() -> void:
	for path in [
		MARKER_PATH,
		MARKER_PATH + ".tmp",
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
		"RUNTIME_TEST_DIAGNOSTICS_HANDOFF_SMOKE: "
		+ message
	)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print(
			"RUNTIME_TEST_DIAGNOSTICS_HANDOFF_SMOKE: PASS"
		)
		get_tree().quit(0)
