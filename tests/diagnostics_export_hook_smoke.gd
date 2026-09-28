extends Node

const DiagnosticsExportHook = preload(
	"res://addons/game_foundation/diagnostics/diagnostics_export_hook.gd"
)
const FoundationRuntime = preload(
	"res://addons/game_foundation/runtime/foundation_runtime.gd"
)

const TEST_DIR: String = (
	"user://game_foundation_diagnostics_export_tests"
)
const LOG_PATH: String = TEST_DIR + "/runtime.log"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_direct_sanitization()
	await _test_runtime_integration()
	_cleanup()
	_finish()


func _test_direct_sanitization() -> void:
	var long_message: String = "x".repeat(4000)
	var snapshot: Dictionary = {
		"runtime": {
			"app": {
				"name": "Diagnostics Export Test",
				"version": "1.0.0",
			},
			"foundation": {
				"version": "0.16.0-dev",
			},
			"engine": {
				"version": "4.7.2.stable",
			},
			"runtime": {
				"os": "Windows",
				"os_version": "11",
				"display_server": "windows",
				"headless": false,
				"debug_build": true,
				"processor_count": 8,
			},
		},
		"paths": {
			"save": "user://save.json",
			"settings": (
				"C:\\Users\\Example\\private\\settings.json"
			),
			"resource": "res://game/main.tscn",
		},
		"errors": {
			"info_count": 3,
			"warning_count": 2,
			"error_count": 1,
			"recent_errors": [
				{
					"timestamp_unix": 1,
					"level": "error",
					"message": (
						"Bearer should-never-leave-runtime"
					),
					"context": {
						"password": "plain-password",
						"file_path": (
							"C:\\Users\\Example\\private.txt"
						),
						"safe_code": "disk_error",
					},
				},
			],
		},
		"recent_entries": [
			{
				"timestamp_unix": 2,
				"level": "info",
				"message": long_message,
				"context": {
					"token": "TOP_SECRET_TOKEN",
					"nested": {
						"api_key": "TOP_SECRET_API_KEY",
						"safe": "visible",
					},
				},
			},
		],
		"performance": {
			"fps": 60.0,
		},
	}
	var status: Dictionary = {
		"configured": true,
		"initialized": true,
		"runtime_test_mode": false,
		"diagnostics_enabled": true,
		"save_enabled": true,
		"save_writes_blocked": true,
		"crash_marker_enabled": true,
		"crash_marker": {
			"active": true,
			"path": "user://foundation_session_marker.json",
			"previous_session": {
				"marker_found": true,
				"marker_valid": true,
				"possible_unclean_exit": true,
				"reason": "active_marker_present",
				"previous_started_at_unix": 123456,
				"app_version": "0.9.0",
				"foundation_version": "0.15.0-dev",
			},
			"session_id": "must-not-export",
		},
		"has_runtime_failure": true,
		"runtime_failure": {
			"active": true,
			"kind": "initialization",
			"stage": "settings",
			"code": "settings_load_failed",
			"message": "sk-proj-private-value",
			"retry_supported": false,
			"save_writes_blocked": true,
			"diagnostics_available": true,
		},
		"last_load": {
			"payload": {
				"private_game_data": "TOP_SECRET_GAME_DATA",
			},
		},
		"last_settings": {
			"settings": {
				"private_setting": "TOP_SECRET_SETTING",
			},
		},
	}

	var result: Dictionary = DiagnosticsExportHook.build_export(
		snapshot,
		status,
		{"reason": "game_dev_hub_share"}
	)
	_expect_ok(
		result,
		"direct diagnostics export should build"
	)

	var payload: Dictionary = (
		result.get("payload", {}) as Dictionary
	)
	var json_text: String = String(
		result.get("json", "")
	)
	var parsed: Variant = JSON.parse_string(json_text)
	_expect_true(
		parsed is Dictionary,
		"diagnostics export JSON should parse"
	)

	_expect_equal(
		int(payload.get("schemaVersion", 0)),
		1,
		"export should declare schema version"
	)
	_expect_equal(
		String(
			(
				payload.get("paths", {}) as Dictionary
			).get("save", "")
		),
		"user://save.json",
		"virtual user path should remain shareable"
	)
	_expect_equal(
		String(
			(
				payload.get("paths", {}) as Dictionary
			).get("resource", "")
		),
		"res://game/main.tscn",
		"virtual resource path should remain shareable"
	)
	_expect_equal(
		String(
			(
				payload.get("paths", {}) as Dictionary
			).get("settings", "")
		),
		DiagnosticsExportHook.REDACTED_PATH,
		"absolute path should be redacted"
	)

	_expect_not_contains(
		json_text,
		"plain-password",
		"password value must not be exported"
	)
	_expect_not_contains(
		json_text,
		"TOP_SECRET_TOKEN",
		"token value must not be exported"
	)
	_expect_not_contains(
		json_text,
		"TOP_SECRET_API_KEY",
		"nested API key value must not be exported"
	)
	_expect_not_contains(
		json_text,
		"TOP_SECRET_GAME_DATA",
		"last_load payload must not be exported"
	)
	_expect_not_contains(
		json_text,
		"TOP_SECRET_SETTING",
		"settings payload must not be exported"
	)
	_expect_not_contains(
		json_text,
		"should-never-leave-runtime",
		"Bearer message must be redacted"
	)
	_expect_not_contains(
		json_text,
		"C:\\Users\\Example",
		"absolute Windows path must not be exported"
	)
	_expect_true(
		json_text.contains(
			DiagnosticsExportHook.REDACTED
		),
		"export should leave explicit redaction markers"
	)
	_expect_true(
		json_text.contains("visible"),
		"safe nested context should remain useful"
	)
	_expect_true(
		not json_text.contains(long_message),
		"oversized message should be truncated"
	)

	var exported_runtime: Dictionary = (
		payload.get("runtime", {}) as Dictionary
	)
	_expect_true(
		bool(
			exported_runtime.get(
				"crash_marker_enabled",
				false
			)
		),
		"export should include crash marker enablement"
	)
	var previous_session: Dictionary = (
		exported_runtime.get(
			"previous_session",
			{}
		) as Dictionary
	)
	_expect_true(
		bool(
			previous_session.get(
				"possible_unclean_exit",
				false
			)
		),
		"export should include previous-session possibility"
	)
	_expect_equal(
		String(
			previous_session.get(
				"reason",
				""
			)
		),
		"active_marker_present",
		"export should include previous-session reason"
	)
	_expect_not_contains(
		json_text,
		"must-not-export",
		"current crash marker session id must not be exported"
	)
	_expect_not_contains(
		json_text,
		"foundation_session_marker.json",
		"crash marker path must not be exported"
	)

	var handoff: Dictionary = (
		payload.get("handoff", {}) as Dictionary
	)
	_expect_true(
		bool(handoff.get("sanitized", false)),
		"handoff should declare sanitization"
	)
	_expect_true(
		bool(
			handoff.get(
				"known_sensitive_fields_redacted",
				false
			)
		),
		"handoff should record known-field redaction"
	)
	_expect_true(
		int(result.get("payload_bytes", 0))
			<= DiagnosticsExportHook.MAX_PAYLOAD_BYTES,
		"export should respect payload size limit"
	)
	_expect_equal(
		int(handoff.get("payload_bytes", -1)),
		int(result.get("payload_bytes", -2)),
		"handoff byte count should match export result"
	)


func _test_runtime_integration() -> void:
	var runtime := FoundationRuntime.new()
	add_child(runtime)
	await get_tree().process_frame

	_expect_ok(
		runtime.configure({
			"app": {
				"name": "Runtime Export Integration",
				"version": "9.9.9",
			},
			"save": {"enabled": false},
			"settings": {"enabled": false},
			"input": {"enabled": false},
			"flow": {"enabled": false},
			"diagnostics": {
				"enabled": true,
				"log_path": LOG_PATH,
			},
			"runtime_test": {"enabled": false},
		}),
		"runtime should configure for diagnostics export"
	)
	_expect_ok(
		runtime.initialize(),
		"runtime should initialize for diagnostics export"
	)

	var diagnostics: Node = runtime.diagnostics_service()
	_expect_true(
		is_instance_valid(diagnostics),
		"runtime should expose diagnostics service"
	)
	if is_instance_valid(diagnostics):
		_expect_ok(
			diagnostics.call(
				"log_error",
				"runtime export smoke",
				{
					"authorization": (
						"Bearer TOP_SECRET_AUTH"
					),
					"safe_code": "smoke",
				}
			),
			"runtime diagnostic log should succeed"
		)

	var export_result: Dictionary = runtime.diagnostics_export({
		"reason": "game_dev_hub_share",
	})
	_expect_ok(
		export_result,
		"FoundationRuntime should expose sanitized export"
	)

	var payload: Dictionary = (
		export_result.get("payload", {}) as Dictionary
	)
	_expect_equal(
		String(
			(
				payload.get("project", {}) as Dictionary
			).get("name", "")
		),
		"Runtime Export Integration",
		"runtime export should include project identity"
	)
	_expect_true(
		bool(
			(
				payload.get("runtime", {}) as Dictionary
			).get("initialized", false)
		),
		"runtime export should include safe runtime state"
	)
	_expect_not_contains(
		String(export_result.get("json", "")),
		"TOP_SECRET_AUTH",
		"runtime export must redact authorization context"
	)

	runtime.queue_free()
	await get_tree().process_frame


func _cleanup() -> void:
	for path in [
		LOG_PATH,
		LOG_PATH + ".old",
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


func _expect_not_contains(
	text_value: String,
	needle: String,
	message: String
) -> void:
	if text_value.contains(needle):
		_fail(
			message
			+ " / leaked="
			+ needle
		)


func _fail(message: String) -> void:
	_failed = true
	push_error(
		"DIAGNOSTICS_EXPORT_HOOK_SMOKE: "
		+ message
	)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print(
			"DIAGNOSTICS_EXPORT_HOOK_SMOKE: PASS"
		)
		get_tree().quit(0)
