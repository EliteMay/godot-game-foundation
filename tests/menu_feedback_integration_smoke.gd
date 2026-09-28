extends Node

const UIFeedbackHooks = preload(
	"res://addons/game_foundation/shell/ui_feedback_hooks.gd"
)
const MainMenuScene = preload(
	"res://addons/game_foundation/shell/main_menu_shell.tscn"
)
const PauseMenuScene = preload(
	"res://addons/game_foundation/shell/pause_menu_shell.tscn"
)

class FakeFlowService:
	extends Node

	var paused: bool = false
	var quit_calls: int = 0

	func set_paused(value: bool) -> Dictionary:
		paused = value
		get_tree().paused = value
		return {
			"ok": true,
			"code": "pause_changed",
			"paused": paused,
		}

	func is_paused() -> bool:
		return paused

	func go_to_main_menu() -> Dictionary:
		return {
			"ok": true,
			"code": "main_menu_changed",
		}

	func main_menu_id() -> String:
		return ""

	func request_quit(_exit_code: int = 0) -> Dictionary:
		quit_calls += 1
		return {
			"ok": true,
			"code": "quit_requested",
		}


var _failed: bool = false
var _new_game_calls: int = 0
var _events: Array[Dictionary] = []
var _reject_feedback: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var flow := FakeFlowService.new()
	add_child(flow)

	var hooks := UIFeedbackHooks.new()
	_expect_ok(
		hooks.configure({
			"feedback_action": Callable(self, "_on_feedback"),
		}),
		"feedback hooks should configure for menu integration"
	)

	var main_menu := MainMenuScene.instantiate()
	add_child(main_menu)
	await get_tree().process_frame
	_expect_ok(
		main_menu.configure({
			"flow_service": flow,
			"new_game_action": Callable(self, "_new_game"),
			"show_quit": false,
			"feedback_hooks": hooks,
		}),
		"main menu should accept feedback hooks"
	)
	await get_tree().process_frame
	_expect_event(
		"focus",
		"main_menu",
		"new_game",
		"initial main menu focus should request feedback"
	)
	_expect_true(
		bool(
			main_menu.state_snapshot().get(
				"feedback_hooks_configured",
				false
			)
		),
		"main menu snapshot should expose feedback hook wiring"
	)

	_reject_feedback = true
	await _send_ui_action("ui_accept")
	_reject_feedback = false
	_expect_equal(
		_new_game_calls,
		1,
		"ui_accept should still run the main menu action when feedback fails"
	)
	_expect_event(
		"activate",
		"main_menu",
		"new_game",
		"main menu activation should request feedback"
	)

	_expect_ok(
		main_menu.deactivate_menu(),
		"main menu should deactivate"
	)
	_expect_event(
		"close",
		"main_menu",
		"",
		"main menu close should request feedback"
	)
	_expect_ok(
		main_menu.activate_menu(),
		"main menu should activate"
	)
	_expect_event(
		"open",
		"main_menu",
		"",
		"main menu open should request feedback"
	)

	main_menu.queue_free()
	await get_tree().process_frame

	var pause_menu := PauseMenuScene.instantiate()
	add_child(pause_menu)
	await get_tree().process_frame
	_expect_ok(
		pause_menu.configure({
			"flow_service": flow,
			"show_quit": false,
			"feedback_hooks": hooks,
		}),
		"pause menu should accept feedback hooks"
	)
	_expect_ok(
		pause_menu.open_menu(),
		"pause menu should open"
	)
	_expect_event(
		"open",
		"pause_menu",
		"",
		"pause menu open should request feedback"
	)
	await get_tree().process_frame
	_expect_event(
		"focus",
		"pause_menu",
		"resume",
		"pause menu initial focus should request feedback"
	)

	await _send_ui_action("ui_accept")
	_expect_true(
		not flow.paused,
		"ui_accept on Resume should still close and unpause"
	)
	_expect_event(
		"activate",
		"pause_menu",
		"resume",
		"pause menu Resume activation should request feedback"
	)
	_expect_event(
		"close",
		"pause_menu",
		"",
		"pause menu close should request feedback"
	)

	_expect_ok(
		hooks.set_feedback_enabled(false),
		"feedback should be disableable without changing menu behavior"
	)
	var event_count_before: int = _events.size()
	_expect_ok(
		pause_menu.open_menu(),
		"pause menu should still open when feedback is disabled"
	)
	await get_tree().process_frame
	_expect_equal(
		_events.size(),
		event_count_before,
		"disabled feedback should suppress open/focus callback handling"
	)
	_expect_ok(
		pause_menu.close_menu(),
		"pause menu should still close when feedback is disabled"
	)

	pause_menu.queue_free()
	flow.queue_free()
	get_tree().paused = false
	_finish()


func _new_game() -> Dictionary:
	_new_game_calls += 1
	return {
		"ok": true,
		"code": "new_game_started",
	}


func _on_feedback(
	event_id: String,
	context: Dictionary
) -> Dictionary:
	_events.append({
		"event_id": event_id,
		"surface": String(context.get("surface", "")),
		"action_id": String(context.get("action_id", "")),
	})
	if _reject_feedback:
		return {
			"ok": false,
			"code": "feedback_test_rejected",
		}
	return {
		"ok": true,
		"code": "feedback_recorded",
	}


func _expect_event(
	event_id: String,
	surface: String,
	action_id: String,
	message: String
) -> void:
	for event in _events:
		if (
			String(event.get("event_id", "")) == event_id
			and String(event.get("surface", "")) == surface
			and String(event.get("action_id", "")) == action_id
		):
			return
	_fail(
		message
		+ " / event="
		+ event_id
		+ " surface="
		+ surface
		+ " action="
		+ action_id
	)


func _send_ui_action(action_name: String) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action_name
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame

	var released := InputEventAction.new()
	released.action = action_name
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame


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
	push_error("MENU_FEEDBACK_INTEGRATION_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("MENU_FEEDBACK_INTEGRATION_SMOKE: PASS")
		get_tree().quit(0)
