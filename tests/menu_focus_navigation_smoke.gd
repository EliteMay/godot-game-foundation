extends Node

const MenuFocusNavigation = preload(
	"res://addons/game_foundation/shell/menu_focus_navigation.gd"
)

var _failed: bool = false
var _press_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var actions := VBoxContainer.new()
	add_child(actions)

	var first := Button.new()
	first.name = "First"
	first.text = "First"
	actions.add_child(first)

	var disabled := Button.new()
	disabled.name = "Disabled"
	disabled.text = "Disabled"
	disabled.disabled = true
	actions.add_child(disabled)

	var hidden := Button.new()
	hidden.name = "Hidden"
	hidden.text = "Hidden"
	hidden.hide()
	actions.add_child(hidden)

	var last := Button.new()
	last.name = "Last"
	last.text = "Last"
	actions.add_child(last)
	last.pressed.connect(_on_last_pressed)

	await get_tree().process_frame

	var configure_result: Dictionary = MenuFocusNavigation.configure_vertical(
		[first, disabled, hidden, last]
	)
	_expect_ok(configure_result, "linear focus navigation should configure")
	_expect_equal(
		int(configure_result.get("focusable_count", -1)),
		2,
		"disabled and hidden controls should be skipped"
	)
	_expect_equal(
		first.focus_neighbor_bottom,
		first.get_path_to(last),
		"down navigation should skip unavailable controls"
	)
	_expect_equal(
		last.focus_neighbor_top,
		last.get_path_to(first),
		"up navigation should skip unavailable controls"
	)
	_expect_equal(
		String(first.focus_neighbor_top),
		"",
		"non-modal baseline should not trap focus at the first control"
	)
	_expect_equal(
		String(last.focus_neighbor_bottom),
		"",
		"non-modal baseline should not trap focus at the last control"
	)

	_expect_ok(
		MenuFocusNavigation.focus_first([disabled, hidden, first, last]),
		"focus_first should select the first available control"
	)
	await get_tree().process_frame
	_expect_true(
		get_viewport().gui_get_focus_owner() == first,
		"focus_first should assign GUI focus"
	)

	await _send_ui_action("ui_down")
	_expect_true(
		get_viewport().gui_get_focus_owner() == last,
		"ui_down should follow the generated focus graph"
	)
	await _send_ui_action("ui_accept")
	_expect_equal(
		_press_count,
		1,
		"ui_accept should activate a focused Button without mouse input"
	)

	disabled.disabled = false
	hidden.show()
	_expect_ok(
		MenuFocusNavigation.configure_vertical(
			[first, disabled, hidden, last]
		),
		"focus graph should refresh when availability changes"
	)
	_expect_equal(
		first.focus_neighbor_bottom,
		first.get_path_to(disabled),
		"refreshed graph should include newly enabled controls"
	)
	_expect_equal(
		disabled.focus_neighbor_bottom,
		disabled.get_path_to(hidden),
		"refreshed graph should preserve visual order"
	)

	actions.queue_free()
	_finish()


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


func _on_last_pressed() -> void:
	_press_count += 1


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
	push_error("MENU_FOCUS_NAVIGATION_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("MENU_FOCUS_NAVIGATION_SMOKE: PASS")
		get_tree().quit(0)
