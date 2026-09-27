extends Node

const PauseMenuScene = preload(
	"res://addons/game_foundation/shell/pause_menu_shell.tscn"
)

class FakeFlowService:
	extends Node

	var main_menu_calls: int = 0
	var quit_calls: int = 0
	var block_quit: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func set_paused(value: bool) -> Dictionary:
		get_tree().paused = value
		return {
			"ok": true,
			"code": "pause_changed",
			"paused": value,
		}

	func is_paused() -> bool:
		return get_tree() != null and get_tree().paused

	func main_menu_id() -> String:
		return "menu"

	func go_to_main_menu() -> Dictionary:
		main_menu_calls += 1
		get_tree().paused = false
		return {
			"ok": true,
			"code": "scene_change_requested",
			"scene_id": "menu",
		}

	func request_quit(_exit_code: int = 0) -> Dictionary:
		quit_calls += 1
		if block_quit:
			return {
				"ok": false,
				"code": "quit_hook_blocked",
			}
		return {
			"ok": true,
			"code": "quit_requested",
		}


var _failed: bool = false
var _options_calls: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var flow := FakeFlowService.new()
	add_child(flow)

	var previous_focus := Button.new()
	previous_focus.name = "PreviousFocus"
	previous_focus.text = "Before pause"
	previous_focus.focus_mode = Control.FOCUS_ALL
	add_child(previous_focus)

	var shell := PauseMenuScene.instantiate()
	add_child(shell)
	await get_tree().process_frame

	_expect_ok(
		shell.configure({
			"flow_service": flow,
			"options_action": Callable(self, "_open_options"),
			"labels": {
				"resume": "Continue",
				"options": "Settings",
				"main_menu": "Menu",
				"quit": "Exit",
			},
		}),
		"pause shell should configure against Game Flow contract"
	)
	_expect_equal(
		shell.action_button("resume").text,
		"Continue",
		"game should be able to replace action labels"
	)

	previous_focus.grab_focus()
	await get_tree().process_frame
	_expect_true(
		get_viewport().gui_get_focus_owner() == previous_focus,
		"fixture should own focus before opening pause menu"
	)

	_expect_code(
		shell.open_menu(),
		"pause_menu_opened",
		"pause menu should open"
	)
	await get_tree().process_frame
	_expect_true(flow.is_paused(), "opening pause menu should pause the tree")
	_expect_true(shell.visible, "pause menu should become visible")
	_expect_true(
		get_viewport().gui_get_focus_owner() == shell.action_button("resume"),
		"pause menu should move focus to its initial action"
	)

	_expect_code(
		shell.request_action("options"),
		"action_completed",
		"options action should call the game-provided contract"
	)
	_expect_equal(
		_options_calls,
		1,
		"options action should run exactly once"
	)
	_expect_true(
		flow.is_paused(),
		"opening options from pause menu should keep gameplay paused"
	)

	_expect_code(
		shell.request_action("resume"),
		"pause_menu_closed",
		"resume should close pause menu"
	)
	await get_tree().process_frame
	_expect_true(not flow.is_paused(), "resume should unpause the tree")
	_expect_true(not shell.visible, "resume should hide pause menu")
	_expect_true(
		get_viewport().gui_get_focus_owner() == previous_focus,
		"closing pause menu should restore the previous focus owner"
	)

	_expect_ok(shell.open_menu(), "pause menu should reopen")
	await get_tree().process_frame
	flow.block_quit = true
	_expect_code(
		shell.request_action("quit"),
		"quit_hook_blocked",
		"blocked safe quit should be surfaced"
	)
	_expect_true(
		shell.is_open(),
		"blocked quit should leave pause menu open"
	)
	_expect_true(
		flow.is_paused(),
		"blocked quit should keep gameplay paused"
	)

	flow.block_quit = false
	_expect_code(
		shell.request_action("quit"),
		"quit_requested",
		"successful safe quit should use Game Flow contract"
	)
	_expect_equal(flow.quit_calls, 2, "quit contract should record both attempts")

	_expect_code(
		shell.request_action("main_menu"),
		"scene_change_requested",
		"main menu action should use Game Flow contract"
	)
	_expect_equal(
		flow.main_menu_calls,
		1,
		"main menu contract should run exactly once"
	)
	_expect_true(
		not shell.visible,
		"main menu action should hide the pause shell"
	)
	_expect_true(
		not flow.is_paused(),
		"main menu transition should leave the tree unpaused"
	)

	shell.queue_free()
	previous_focus.queue_free()
	flow.queue_free()
	get_tree().paused = false
	_finish()


func _open_options() -> Dictionary:
	_options_calls += 1
	return {
		"ok": true,
		"code": "options_opened",
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
	push_error("PAUSE_MENU_SHELL_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("PAUSE_MENU_SHELL_SMOKE: PASS")
		get_tree().quit(0)
