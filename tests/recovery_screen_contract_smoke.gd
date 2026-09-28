extends Node

const RecoveryScreenContract = preload(
	"res://addons/game_foundation/recovery/recovery_screen_contract.gd"
)
const RecoveryScreenScene = preload(
	"res://addons/game_foundation/recovery/recovery_screen.tscn"
)

class FakeFlow:
	extends RefCounted

	var main_menu_calls: int = 0
	var configured_main_menu_id: String = "main"

	func main_menu_id() -> String:
		return configured_main_menu_id

	func go_to_main_menu() -> Dictionary:
		main_menu_calls += 1
		return {
			"ok": true,
			"code": "main_menu_requested",
		}


class FakeRuntime:
	extends RefCounted

	var state: Dictionary = {}
	var initialize_calls: int = 0
	var quit_calls: int = 0
	var flow := FakeFlow.new()

	func runtime_failure_state() -> Dictionary:
		return state.duplicate(true)

	func initialize() -> Dictionary:
		initialize_calls += 1
		if bool(state.get("retry_supported", false)):
			state = {
				"active": false,
				"kind": "",
				"stage": "",
				"code": "",
				"message": "",
				"retry_supported": false,
				"save_writes_blocked": false,
				"diagnostics_available": false,
			}
			return {
				"ok": true,
				"code": "initialized",
			}
		return {
			"ok": false,
			"code": "retry_not_supported",
			"message": "Retry is not supported.",
		}

	func request_quit(exit_code: int = 0) -> Dictionary:
		quit_calls += 1
		return {
			"ok": true,
			"code": "quit_requested",
			"exit_code": exit_code,
		}

	func flow_service() -> Object:
		return flow


var _failed: bool = false
var _recovery_success_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_contract_actions()
	await _test_optional_screen()
	_finish()


func _test_contract_actions() -> void:
	var runtime := FakeRuntime.new()
	runtime.state = _active_failure(false)

	var contract := RecoveryScreenContract.new()
	_expect_ok(
		contract.configure({"runtime": runtime}),
		"contract should configure"
	)

	var snapshot: Dictionary = contract.state_snapshot()
	var actions: Dictionary = snapshot.get("actions", {}) as Dictionary
	_expect_true(
		not bool(actions.get("retry", true)),
		"retry should be hidden when runtime marks it unsafe"
	)
	_expect_true(
		bool(actions.get("main_menu", false)),
		"main menu should be available from configured flow"
	)
	_expect_true(
		bool(actions.get("safe_quit", false)),
		"safe quit should be available from runtime"
	)
	_expect_equal(
		actions.size(),
		3,
		"recovery contract must not expose implicit reset/delete actions"
	)

	_expect_code(
		contract.perform_action(
			RecoveryScreenContract.ACTION_RETRY
		),
		"recovery_action_unavailable",
		"unsafe retry should be rejected"
	)

	_expect_ok(
		contract.perform_action(
			RecoveryScreenContract.ACTION_MAIN_MENU
		),
		"main menu recovery should run"
	)
	_expect_equal(
		runtime.flow.main_menu_calls,
		1,
		"main menu flow should run once"
	)

	_expect_ok(
		contract.perform_action(
			RecoveryScreenContract.ACTION_SAFE_QUIT
		),
		"safe quit recovery should run"
	)
	_expect_equal(
		runtime.quit_calls,
		1,
		"safe quit should call runtime request_quit"
	)


func _test_optional_screen() -> void:
	var runtime := FakeRuntime.new()
	runtime.state = _active_failure(true)

	var screen := RecoveryScreenScene.instantiate()
	add_child(screen)
	await get_tree().process_frame

	screen.recovery_succeeded.connect(
		_on_recovery_succeeded
	)
	_expect_ok(
		screen.configure({
			"runtime": runtime,
			"labels": {
				"title": "Recovery Test",
			},
		}),
		"recovery screen should configure"
	)
	_expect_ok(
		screen.open_screen(),
		"recovery screen should open for active failure"
	)
	await get_tree().process_frame

	_expect_true(
		screen.visible,
		"recovery screen should become visible"
	)
	_expect_equal(
		String(
			screen.get_node(
				"Center/Panel/Margin/Content/Title"
			).text
		),
		"Recovery Test",
		"screen should apply title override"
	)
	_expect_equal(
		String(
			screen.get_node(
				"Center/Panel/Margin/Content/Summary"
			).text
		),
		"Runtime initialization failed for smoke test.",
		"screen should show failure summary"
	)

	var hint_text: String = String(
		screen.get_node(
			"Center/Panel/Margin/Content/StateHint"
		).text
	)
	_expect_true(
		hint_text.contains(
			"Save data is protected from overwrite."
		),
		"screen should explain save protection"
	)
	_expect_true(
		hint_text.contains("Diagnostics are available."),
		"screen should expose diagnostics availability"
	)

	var retry_button: Button = screen.action_button(
		RecoveryScreenContract.ACTION_RETRY
	)
	var main_button: Button = screen.action_button(
		RecoveryScreenContract.ACTION_MAIN_MENU
	)
	var quit_button: Button = screen.action_button(
		RecoveryScreenContract.ACTION_SAFE_QUIT
	)
	_expect_true(
		retry_button.visible and not retry_button.disabled,
		"retry button should be available"
	)
	_expect_true(
		main_button.visible and not main_button.disabled,
		"main menu button should be available"
	)
	_expect_true(
		quit_button.visible and not quit_button.disabled,
		"safe quit button should be available"
	)
	_expect_equal(
		screen.focused_action_id(),
		RecoveryScreenContract.ACTION_RETRY,
		"retry should receive initial focus when available"
	)

	_expect_ok(
		screen.request_action(
			RecoveryScreenContract.ACTION_RETRY
		),
		"safe retry should succeed"
	)
	await get_tree().process_frame
	_expect_equal(
		runtime.initialize_calls,
		1,
		"retry should call runtime initialize once"
	)
	_expect_true(
		not screen.visible,
		"successful retry should close the recovery screen"
	)
	_expect_equal(
		_recovery_success_count,
		1,
		"successful retry should emit recovery_succeeded"
	)

	var reopen: Dictionary = screen.open_screen()
	_expect_true(
		not bool(reopen.get("ok", true)),
		"screen must not open without an active failure"
	)
	_expect_code(
		reopen,
		"no_active_runtime_failure",
		"inactive runtime should return a clear open error"
	)

	screen.queue_free()
	await get_tree().process_frame


func _active_failure(retry_supported: bool) -> Dictionary:
	return {
		"active": true,
		"kind": "initialization",
		"stage": "settings",
		"code": "settings_load_failed",
		"message": (
			"Runtime initialization failed for smoke test."
		),
		"retry_supported": retry_supported,
		"save_writes_blocked": true,
		"diagnostics_available": true,
	}


func _on_recovery_succeeded(
	_result: Dictionary
) -> void:
	_recovery_success_count += 1


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


func _expect_code(
	result: Dictionary,
	expected: String,
	message: String
) -> void:
	if String(result.get("code", "")) != expected:
		_fail(
			message
			+ " / expected="
			+ expected
			+ " actual="
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
		"RECOVERY_SCREEN_CONTRACT_SMOKE: "
		+ message
	)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print(
			"RECOVERY_SCREEN_CONTRACT_SMOKE: PASS"
		)
		get_tree().quit(0)
