extends Node

const DiagnosticsService = preload("res://addons/game_foundation/diagnostics/diagnostics_service.gd")
const DiagnosticsOverlay = preload("res://addons/game_foundation/diagnostics/diagnostics_overlay.gd")
const RuntimeInfo = preload("res://addons/game_foundation/diagnostics/runtime_info.gd")

const TEST_DIR := "user://game_foundation_diagnostics_tests"
const LOG_PATH := TEST_DIR + "/runtime.log"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()

	var runtime: Dictionary = RuntimeInfo.collect({
		"name": "Diagnostics Test",
		"version": "1.2.3",
		"foundation_version": "0.6.0-dev",
	})
	_expect_equal(
		String((runtime.get("app", {}) as Dictionary).get("name", "")),
		"Diagnostics Test",
		"runtime info should include app name"
	)
	_expect_true(
		not String((runtime.get("engine", {}) as Dictionary).get("version", "")).is_empty(),
		"runtime info should include Godot version"
	)
	_expect_true(
		not String((runtime.get("runtime", {}) as Dictionary).get("os", "")).is_empty(),
		"runtime info should include OS name"
	)

	var service := DiagnosticsService.new()
	service.log_path = LOG_PATH
	service.max_entries = 10
	add_child(service)
	await get_tree().process_frame

	_expect_ok(
		service.configure(
			{
				"name": "Diagnostics Test",
				"version": "1.2.3",
				"foundation_version": "0.6.0-dev",
			},
			{
				"save": "user://save.json",
				"settings": "user://settings.json",
				"input": "user://input_bindings.json",
				"log": LOG_PATH,
			}
		),
		"diagnostics should configure"
	)

	_expect_ok(
		service.log_info("started", {"scene": "test"}),
		"info log should succeed"
	)
	_expect_ok(
		service.log_warning("low capacity", {"remaining": 2}),
		"warning log should succeed"
	)
	_expect_ok(
		service.log_error(
			"save failed",
			{
				"code": "disk",
				"position": Vector3(1, 2, 3),
			}
		),
		"error log should succeed"
	)

	_expect_true(FileAccess.file_exists(LOG_PATH), "diagnostic log file should exist")
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		_fail("diagnostic log file could not be opened")
	else:
		var text: String = file.get_as_text()
		file.close()
		_expect_true(text.contains("started"), "log file should contain info message")
		_expect_true(text.contains("save failed"), "log file should contain error message")
		_expect_true(text.contains("(1.0, 2.0, 3.0)"), "unsupported context types should be sanitized")

	var summary: Dictionary = service.error_summary()
	_expect_equal(int(summary.get("info_count", 0)), 1, "info count should be tracked")
	_expect_equal(int(summary.get("warning_count", 0)), 1, "warning count should be tracked")
	_expect_equal(int(summary.get("error_count", 0)), 1, "error count should be tracked")
	var errors: Array = summary.get("recent_errors", [])
	_expect_equal(errors.size(), 1, "recent errors should include logged error")

	var snapshot: Dictionary = service.build_snapshot()
	var paths: Dictionary = snapshot.get("paths", {})
	_expect_equal(
		String(paths.get("save", "")),
		"user://save.json",
		"snapshot should expose configured save path"
	)
	_expect_equal(
		String(paths.get("settings", "")),
		"user://settings.json",
		"snapshot should expose configured settings path"
	)

	var overlay := DiagnosticsOverlay.new()
	add_child(overlay)
	await get_tree().process_frame

	_expect_ok(
		overlay.bind_service(service),
		"debug overlay should bind diagnostics service"
	)
	overlay.set_overlay_visible(true)
	overlay.refresh_now()
	var rendered: String = overlay.rendered_text()
	_expect_true(rendered.contains("Diagnostics Test"), "overlay should show app name")
	_expect_true(rendered.contains("user://save.json"), "overlay should show save path")
	_expect_true(rendered.contains("error=1"), "overlay should show error count")
	_expect_true(rendered.contains("save failed"), "overlay should show recent error")

	overlay.toggle_overlay()
	_expect_true(not overlay.visible, "overlay toggle should hide overlay")
	overlay.toggle_overlay()
	_expect_true(overlay.visible, "overlay toggle should show overlay")

	service.clear_memory()
	var cleared: Dictionary = service.error_summary()
	_expect_equal(int(cleared.get("error_count", -1)), 0, "clear_memory should reset error count")
	_expect_equal(service.entries().size(), 0, "clear_memory should remove in-memory entries")

	_expect_ok(service.clear_log_files(), "diagnostic log files should clear")
	_expect_true(not FileAccess.file_exists(LOG_PATH), "primary diagnostic log should be removed")

	overlay.queue_free()
	service.queue_free()
	_cleanup()
	_finish()


func _cleanup() -> void:
	for path in [LOG_PATH, LOG_PATH + ".old"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR)


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


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
	push_error("DIAGNOSTICS_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("DIAGNOSTICS_SMOKE: PASS")
		get_tree().quit(0)
