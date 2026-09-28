extends Node

const FocusNavigationBaseline = preload(
	"res://addons/game_foundation/shell/focus_navigation_baseline.gd"
)

var _failed: bool = false
var _press_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var input_result: Dictionary = (
		FocusNavigationBaseline.validate_input_actions()
	)
	_expect_ok(
		input_result,
		"Godot semantic UI baseline should include keyboard and gamepad coverage"
	)
	var coverage: Dictionary = input_result.get("coverage", {}) as Dictionary
	for action_name in FocusNavigationBaseline.REQUIRED_UI_ACTIONS:
		var action_coverage: Dictionary = coverage.get(
			action_name,
			{}
		) as Dictionary
		_expect_true(
			bool(action_coverage.get("keyboard", false)),
			action_name + " should expose a keyboard binding"
		)
		_expect_true(
			bool(action_coverage.get("gamepad", false)),
			action_name + " should expose a gamepad binding"
		)

	var actions := VBoxContainer.new()
	actions.name = "Actions"
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

	var last := Button.new()
	last.name = "Last"
	last.text = "Last"
	last.pressed.connect(_on_last_pressed)
	actions.add_child(last)

	var external := Button.new()
	external.name = "External"
	external.text = "External"
	add_child(external)

	await get_tree().process_frame

	var configure_result: Dictionary = (
		FocusNavigationBaseline.configure_vertical(
			[first, disabled, last]
		)
	)
	_expect_ok(
		configure_result,
		"focus baseline should configure the vertical graph"
	)
	_expect_equal(
		first.focus_neighbor_bottom,
		first.get_path_to(last),
		"focus graph should skip disabled controls"
	)

	_expect_ok(
		FocusNavigationBaseline.focus_first(
			[disabled, first, last]
		),
		"focus baseline should assign initial focus"
	)
	await get_tree().process_frame
	_expect_true(
		get_viewport().gui_get_focus_owner() == first,
		"initial focus should select the first available control"
	)

	await _send_ui_action("ui_down")
	_expect_true(
		get_viewport().gui_get_focus_owner() == last,
		"semantic ui_down should move focus without a mouse"
	)
	await _send_ui_action("ui_up")
	_expect_true(
		get_viewport().gui_get_focus_owner() == first,
		"semantic ui_up should move focus back"
	)
	await _send_ui_action("ui_down")
	await _send_ui_action("ui_accept")
	_expect_equal(
		_press_count,
		1,
		"semantic ui_accept should activate the focused button"
	)

	last.disabled = true
	var repair_result: Dictionary = FocusNavigationBaseline.repair_focus(
		[first, disabled, last]
	)
	_expect_ok(
		repair_result,
		"focus baseline should repair focus after availability changes"
	)
	await get_tree().process_frame
	_expect_true(
		get_viewport().gui_get_focus_owner() == first,
		"repair should move focus away from a newly disabled control"
	)

	external.grab_focus()
	await get_tree().process_frame
	var preserve_result: Dictionary = FocusNavigationBaseline.repair_focus(
		[first, disabled, last]
	)
	_expect_code(
		preserve_result,
		"focus_navigation_external_focus_preserved",
		"baseline should not steal valid external focus"
	)
	_expect_true(
		get_viewport().gui_get_focus_owner() == external,
		"external focus should remain untouched"
	)

	external.release_focus()
	await get_tree().process_frame
	var missing_focus_result: Dictionary = (
		FocusNavigationBaseline.repair_focus(
			[first, disabled, last]
		)
	)
	_expect_code(
		missing_focus_result,
		"focus_navigation_focus_repaired",
		"baseline should recover when GUI focus is lost"
	)
	await get_tree().process_frame
	_expect_true(
		get_viewport().gui_get_focus_owner() == first,
		"lost focus should recover to the first available control"
	)

	var snapshot: Dictionary = FocusNavigationBaseline.snapshot(
		[first, disabled, last]
	)
	_expect_ok(snapshot, "focus baseline snapshot should build")
	_expect_equal(
		int(snapshot.get("focusable_count", -1)),
		1,
		"snapshot should expose current focusable count"
	)
	_expect_true(
		bool(snapshot.get("input_ready", false)),
		"snapshot should expose semantic input readiness"
	)

	actions.queue_free()
	external.queue_free()
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
	push_error("FOCUS_NAVIGATION_BASELINE_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("FOCUS_NAVIGATION_BASELINE_SMOKE: PASS")
		get_tree().quit(0)
