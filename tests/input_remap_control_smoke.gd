extends Node

const InputSystem = preload(
	"res://addons/game_foundation/input/input_system.gd"
)
const InputRemapControl = preload(
	"res://addons/game_foundation/input/input_remap_control.gd"
)

const ACTION_JUMP := "foundation_remap_jump"
const ACTION_FIRE := "foundation_remap_fire"
const ACTION_PAD := "foundation_remap_pad"
const ACTION_AXIS := "foundation_remap_axis"

var _failed: bool = false
var _persist_calls: int = 0
var _fail_persist: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var contract: Dictionary = {
		ACTION_JUMP: {
			"deadzone": 0.5,
			"events": [{"type": "key", "physical_keycode": KEY_SPACE}],
		},
		ACTION_FIRE: {
			"deadzone": 0.5,
			"events": [{"type": "mouse_button", "button_index": MOUSE_BUTTON_LEFT}],
		},
		ACTION_PAD: {
			"deadzone": 0.5,
			"events": [{"type": "joypad_button", "button_index": JOY_BUTTON_A, "device": -1}],
		},
		ACTION_AXIS: {
			"deadzone": 0.2,
			"events": [{"type": "joypad_motion", "axis": JOY_AXIS_LEFT_X, "axis_value": 1.0, "device": -1}],
		},
	}

	_expect_ok(InputSystem.reset_to_defaults(contract), "input defaults should apply")

	var root := VBoxContainer.new()
	add_child(root)

	var jump := InputRemapControl.new()
	root.add_child(jump)
	_expect_ok(
		jump.configure(
			contract,
			ACTION_JUMP,
			"Jump",
			{
				"persist": Callable(self, "_persist"),
				"rebind_label": "Change",
				"listening_label": "Press something",
			}
		),
		"jump remap control should configure"
	)
	_expect_equal(jump.action_name(), ACTION_JUMP, "internal action name should remain game contract name")
	_expect_equal(jump.display_name(), "Jump", "display name should be separate from action name")
	_expect_equal(jump.action_label_control().text, "Jump", "game-facing label should use display name")
	_expect_equal(jump.rebind_button().text, "Change", "rebind label should be configurable")
	_expect_true(not jump.binding_text().is_empty(), "current binding text should be visible")

	_expect_ok(jump.start_listening(), "jump capture should start")
	_expect_true(jump.is_listening(), "jump control should be listening")
	_expect_equal(jump.binding_text(), "Press something", "listening label should replace binding text")
	_expect_true(jump.rebind_button().disabled, "rebind button should disable while listening")
	_expect_true(jump.cancel_button().visible, "cancel button should be visible while listening")

	var released := InputEventKey.new()
	released.physical_keycode = KEY_Z
	released.pressed = false
	var released_result: Dictionary = jump.handle_input_event(released)
	_expect_code(released_result, "input_ignored", "key release should be ignored")
	_expect_true(jump.is_listening(), "ignored release should keep capture active")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.pressed = true
	_expect_ok(jump.handle_input_event(key), "keyboard rebind should succeed")
	_expect_true(not jump.is_listening(), "successful rebind should stop listening")
	_expect_equal(_persist_calls, 1, "successful rebind should call persistence")
	var jump_descriptor: Dictionary = _first_descriptor(contract, ACTION_JUMP)
	_expect_equal(int(jump_descriptor.get("physical_keycode", 0)), KEY_Z, "jump should be rebound to Z")

	var fire := InputRemapControl.new()
	root.add_child(fire)
	_expect_ok(
		fire.configure(contract, ACTION_FIRE, "Fire", {"persist": Callable(self, "_persist")}),
		"mouse remap control should configure"
	)
	_expect_ok(fire.start_listening(), "mouse capture should start")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	_expect_ok(fire.handle_input_event(mouse), "mouse button rebind should succeed")
	var fire_descriptor: Dictionary = _first_descriptor(contract, ACTION_FIRE)
	_expect_equal(
		int(fire_descriptor.get("button_index", 0)),
		MOUSE_BUTTON_RIGHT,
		"fire should use right mouse button"
	)

	var pad := InputRemapControl.new()
	root.add_child(pad)
	_expect_ok(
		pad.configure(contract, ACTION_PAD, "Controller Action", {"persist": Callable(self, "_persist")}),
		"joypad button remap should configure"
	)
	_expect_ok(pad.start_listening(), "joypad button capture should start")
	var joy_button := InputEventJoypadButton.new()
	joy_button.button_index = JOY_BUTTON_B
	joy_button.device = 3
	joy_button.pressed = true
	_expect_ok(pad.handle_input_event(joy_button), "joypad button rebind should succeed")
	var pad_descriptor: Dictionary = _first_descriptor(contract, ACTION_PAD)
	_expect_equal(int(pad_descriptor.get("button_index", -1)), JOY_BUTTON_B, "joypad button should update")
	_expect_equal(int(pad_descriptor.get("device", 99)), -1, "captured gamepad should be device-agnostic by default")

	var axis := InputRemapControl.new()
	root.add_child(axis)
	_expect_ok(
		axis.configure(
			contract,
			ACTION_AXIS,
			"Move Right",
			{"persist": Callable(self, "_persist"), "axis_threshold": 0.6}
		),
		"joypad axis remap should configure"
	)
	_expect_ok(axis.start_listening(), "axis capture should start")
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_RIGHT_X
	drift.axis_value = 0.2
	drift.device = 2
	_expect_code(
		axis.handle_input_event(drift),
		"input_ignored",
		"axis drift below threshold should be ignored"
	)
	_expect_true(axis.is_listening(), "ignored axis drift should keep capture active")
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_RIGHT_X
	motion.axis_value = -0.8
	motion.device = 2
	_expect_ok(axis.handle_input_event(motion), "joypad axis rebind should succeed")
	var axis_descriptor: Dictionary = _first_descriptor(contract, ACTION_AXIS)
	_expect_equal(int(axis_descriptor.get("axis", -1)), JOY_AXIS_RIGHT_X, "axis should update")
	_expect_equal(float(axis_descriptor.get("axis_value", 0.0)), -1.0, "axis direction should normalize")
	_expect_equal(int(axis_descriptor.get("device", 99)), -1, "axis should be device-agnostic by default")

	_expect_ok(jump.start_listening(), "cancel capture should start")
	_expect_ok(jump.cancel_listening(), "capture cancel should succeed")
	_expect_true(not jump.is_listening(), "cancel should stop listening")
	_expect_equal(
		int(_first_descriptor(contract, ACTION_JUMP).get("physical_keycode", 0)),
		KEY_Z,
		"cancel should preserve current binding"
	)

	_fail_persist = true
	_expect_ok(jump.start_listening(), "persist failure capture should start")
	var x_key := InputEventKey.new()
	x_key.physical_keycode = KEY_X
	x_key.pressed = true
	var failure: Dictionary = jump.handle_input_event(x_key)
	_expect_code(failure, "binding_persist_failed", "persist failure should be surfaced")
	_expect_equal(
		int(_first_descriptor(contract, ACTION_JUMP).get("physical_keycode", 0)),
		KEY_Z,
		"persist failure should roll runtime binding back"
	)
	_fail_persist = false

	_expect_code(
		jump.configure(contract, ACTION_JUMP, ""),
		"display_name_required",
		"display name must be explicit"
	)

	root.queue_free()
	_cleanup()
	_finish()


func _persist() -> Dictionary:
	_persist_calls += 1
	if _fail_persist:
		return {"ok": false, "code": "test_persist_failure"}
	return {"ok": true, "code": "test_persisted"}


func _first_descriptor(contract: Dictionary, action_name: String) -> Dictionary:
	var bindings: Dictionary = InputSystem.capture_bindings(contract)
	var definition: Dictionary = bindings.get(action_name, {})
	var events: Array = definition.get("events", [])
	if events.is_empty() or not (events[0] is Dictionary):
		_fail("binding descriptor missing for " + action_name)
		return {}
	return (events[0] as Dictionary).duplicate(true)


func _cleanup() -> void:
	for action_name in [ACTION_JUMP, ACTION_FIRE, ACTION_PAD, ACTION_AXIS]:
		if InputMap.has_action(StringName(action_name)):
			InputMap.erase_action(StringName(action_name))


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


func _expect_code(result: Dictionary, expected: String, message: String) -> void:
	if String(result.get("code", "")) != expected:
		_fail(message + " / expected=" + expected + " actual=" + String(result.get("code", "")))


func _expect_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail(message + " / expected=" + str(expected) + " actual=" + str(actual))


func _fail(message: String) -> void:
	_failed = true
	push_error("INPUT_REMAP_CONTROL_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("INPUT_REMAP_CONTROL_SMOKE: PASS")
		get_tree().quit(0)
