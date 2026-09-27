extends Node

const MainMenuScene = preload(
	"res://addons/game_foundation/shell/main_menu_shell.tscn"
)

class FakeFlowService:
	extends Node

	var quit_calls: int = 0
	var block_quit: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

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
var _new_game_calls: int = 0
var _continue_calls: int = 0
var _options_calls: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var flow := FakeFlowService.new()
	add_child(flow)

	var shell := MainMenuScene.instantiate()
	add_child(shell)
	await get_tree().process_frame

	_expect_ok(
		shell.configure({
			"flow_service": flow,
			"new_game_action": Callable(self, "_new_game"),
			"continue_action": Callable(self, "_continue_game"),
			"options_action": Callable(self, "_open_options"),
			"continue_available": false,
			"labels": {
				"continue": "Resume Save",
				"new_game": "Start",
				"options": "Settings",
				"quit": "Exit",
			},
		}),
		"main menu should configure against action slots and Game Flow"
	)
	_expect_equal(
		shell.action_button("new_game").text,
		"Start",
		"game should be able to replace action labels"
	)
	_expect_true(
		shell.action_button("continue").visible,
		"configured continue slot should remain visible"
	)
	_expect_true(
		shell.action_button("continue").disabled,
		"continue should be disabled when no resumable state exists"
	)

	await get_tree().process_frame
	_expect_true(
		get_viewport().gui_get_focus_owner() == shell.action_button("new_game"),
		"first-use menu should focus New Game when Continue is disabled"
	)

	_expect_code(
		shell.request_action("continue"),
		"action_unavailable",
		"disabled Continue must not invoke the game action"
	)
	_expect_equal(_continue_calls, 0, "unavailable Continue should not call the game")

	_expect_code(
		shell.request_action("new_game"),
		"new_game_started",
		"New Game should preserve the game-provided result"
	)
	_expect_equal(_new_game_calls, 1, "New Game should run once")

	_expect_code(
		shell.set_continue_available(true),
		"continue_availability_changed",
		"game should be able to refresh Continue availability"
	)
	_expect_code(
		shell.focus_initial_action(),
		"initial_focus_assigned",
		"menu should expose a reusable initial-focus action"
	)
	_expect_true(
		get_viewport().gui_get_focus_owner() == shell.action_button("continue"),
		"returning-user menu should prefer available Continue"
	)

	_expect_code(
		shell.request_action("continue"),
		"continue_started",
		"available Continue should invoke the game action"
	)
	_expect_equal(_continue_calls, 1, "Continue should run once")

	_expect_code(
		shell.request_action("options"),
		"options_opened",
		"Options should preserve the game-provided result"
	)
	_expect_equal(_options_calls, 1, "Options should run once")

	flow.block_quit = true
	_expect_code(
		shell.request_action("quit"),
		"quit_hook_blocked",
		"blocked safe quit should be surfaced"
	)
	_expect_true(shell.is_active(), "blocked quit should keep menu active")

	flow.block_quit = false
	_expect_code(
		shell.request_action("quit"),
		"quit_requested",
		"successful quit should preserve Game Flow result"
	)
	_expect_equal(flow.quit_calls, 2, "quit should route through Game Flow")

	_expect_code(
		shell.deactivate_menu(),
		"main_menu_deactivated",
		"menu should be able to deactivate without owning scene transitions"
	)
	_expect_true(not shell.visible, "deactivated menu should be hidden")
	_expect_code(
		shell.request_action("new_game"),
		"menu_not_active",
		"inactive menu should reject actions"
	)

	_expect_code(
		shell.activate_menu(),
		"main_menu_activated",
		"menu should reactivate"
	)
	await get_tree().process_frame
	_expect_true(
		get_viewport().gui_get_focus_owner() == shell.action_button("continue"),
		"reactivating should restore initial focus policy"
	)

	var minimal_shell := MainMenuScene.instantiate()
	add_child(minimal_shell)
	await get_tree().process_frame
	_expect_ok(
		minimal_shell.configure({
			"flow_service": flow,
			"new_game_action": Callable(self, "_new_game"),
			"show_quit": false,
		}),
		"optional action slots should be removable"
	)
	_expect_true(
		not minimal_shell.action_button("continue").visible,
		"unconfigured Continue slot should be hidden"
	)
	_expect_true(
		not minimal_shell.action_button("options").visible,
		"unconfigured Options slot should be hidden"
	)
	_expect_true(
		not minimal_shell.action_button("quit").visible,
		"Quit should hide when the game disables it"
	)

	minimal_shell.queue_free()
	shell.queue_free()
	flow.queue_free()
	_finish()


func _new_game() -> Dictionary:
	_new_game_calls += 1
	return {
		"ok": true,
		"code": "new_game_started",
	}


func _continue_game() -> Dictionary:
	_continue_calls += 1
	return {
		"ok": true,
		"code": "continue_started",
	}


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
	push_error("MAIN_MENU_SHELL_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("MAIN_MENU_SHELL_SMOKE: PASS")
		get_tree().quit(0)
