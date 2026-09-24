extends Node

const GameFlowService = preload("res://addons/game_foundation/flow/game_flow_service.gd")

var _failed: bool = false
var _pause_events: Array[bool] = []
var _successful_hook_calls: int = 0
var _blocking_hook_calls: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var service := GameFlowService.new()
	add_child(service)
	await get_tree().process_frame

	service.pause_changed.connect(_on_pause_changed)

	var contract := {
		"menu": "res://demo/demo.tscn",
		"gameplay": "res://tests/foundation_smoke.tscn",
	}

	_expect_ok(
		service.validate_scene_contract(contract, "menu"),
		"valid scene contract should pass"
	)
	_expect_code(
		service.validate_scene_contract({"menu": "user://menu.tscn"}, "menu"),
		"invalid_scene_path",
		"scene contract should reject non-res path"
	)
	_expect_code(
		service.validate_scene_contract(contract, "missing"),
		"main_menu_not_declared",
		"main menu id must be declared"
	)

	_expect_ok(
		service.configure_scene_contract(contract, "menu"),
		"scene contract should configure"
	)
	_expect_equal(service.main_menu_id(), "menu", "main menu id should persist")

	var resolved: Dictionary = service.resolve_scene_path("gameplay")
	_expect_ok(resolved, "declared scene should resolve")
	_expect_equal(
		String(resolved.get("path", "")),
		"res://tests/foundation_smoke.tscn",
		"scene resolution should preserve path"
	)
	_expect_code(
		service.resolve_scene_path("unknown"),
		"unknown_scene",
		"unknown scene should be rejected"
	)

	var loaded: Dictionary = service.load_scene("menu")
	_expect_ok(loaded, "declared menu scene should load")
	_expect_true(loaded.get("scene") is PackedScene, "loaded scene should be PackedScene")

	_expect_ok(service.set_paused(true), "pause should succeed")
	_expect_true(get_tree().paused, "SceneTree should be paused")
	_expect_true(service.is_paused(), "service should report paused")
	_expect_equal(_pause_events.size(), 1, "pause signal should fire once")
	if _pause_events.size() >= 1:
		_expect_equal(_pause_events[0], true, "pause signal should report true")

	_expect_ok(service.toggle_pause(), "toggle pause should succeed")
	_expect_true(not get_tree().paused, "SceneTree should resume")
	_expect_true(not service.is_paused(), "service should report resumed")
	_expect_equal(_pause_events.size(), 2, "resume signal should fire")

	_expect_ok(
		service.register_quit_hook(Callable(self, "_successful_quit_hook")),
		"successful quit hook should register"
	)
	_expect_ok(
		service.register_quit_hook(Callable(self, "_successful_quit_hook")),
		"duplicate quit hook registration should be harmless"
	)
	_expect_equal(service.quit_hook_count(), 1, "duplicate hook should not be added twice")

	var safe: Dictionary = service.prepare_safe_quit()
	_expect_ok(safe, "successful hook should allow quit")
	_expect_code(safe, "safe_to_quit", "successful preparation should report safe_to_quit")
	_expect_equal(_successful_hook_calls, 1, "successful hook should run once")

	_expect_ok(
		service.register_quit_hook(Callable(self, "_blocking_quit_hook")),
		"blocking hook should register"
	)
	var blocked: Dictionary = service.prepare_safe_quit()
	_expect_code(blocked, "quit_hook_blocked", "failed hook should block quit")
	_expect_equal(_successful_hook_calls, 2, "first hook should run before blocker")
	_expect_equal(_blocking_hook_calls, 1, "blocking hook should run once")

	_expect_ok(
		service.unregister_quit_hook(Callable(self, "_blocking_quit_hook")),
		"blocking hook should unregister"
	)
	_expect_equal(service.quit_hook_count(), 1, "only successful hook should remain")

	service.clear_quit_hooks()
	_expect_equal(service.quit_hook_count(), 0, "clear should remove quit hooks")

	_expect_ok(service.set_paused(false), "test should leave SceneTree unpaused")
	service.queue_free()
	_finish()


func _on_pause_changed(value: bool) -> void:
	_pause_events.append(value)


func _successful_quit_hook() -> Dictionary:
	_successful_hook_calls += 1
	return {
		"ok": true,
		"code": "flushed",
	}


func _blocking_quit_hook() -> Dictionary:
	_blocking_hook_calls += 1
	return {
		"ok": false,
		"code": "save_failed",
	}


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
	push_error("GAME_FLOW_SMOKE: " + message)


func _finish() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if _failed:
		get_tree().quit(1)
	else:
		print("GAME_FLOW_SMOKE: PASS")
		get_tree().quit(0)
