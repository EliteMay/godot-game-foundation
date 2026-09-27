extends Node

const InputSystem = preload(
	"res://addons/game_foundation/input/input_system.gd"
)
const InputPromptResolver = preload(
	"res://addons/game_foundation/input/input_prompt_resolver.gd"
)

const ACTION_JUMP := "foundation_prompt_jump"
const ACTION_INTERACT := "foundation_prompt_interact"
const ACTION_AXIS := "foundation_prompt_axis"
const ACTION_GAMEPAD_ONLY := "foundation_prompt_gamepad_only"
const ACTION_UNBOUND := "foundation_prompt_unbound"

var _failed: bool = false
var _device_changes: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var contract: Dictionary = {
		ACTION_JUMP: {
			"deadzone": 0.5,
			"events": [
				{"type": "key", "physical_keycode": KEY_W},
				{"type": "joypad_button", "button_index": JOY_BUTTON_A, "device": -1},
			],
		},
		ACTION_INTERACT: {
			"deadzone": 0.5,
			"events": [
				{
					"type": "mouse_button",
					"button_index": MOUSE_BUTTON_LEFT,
					"ctrl": true,
				},
			],
		},
		ACTION_AXIS: {
			"deadzone": 0.2,
			"events": [
				{
					"type": "joypad_motion",
					"axis": JOY_AXIS_LEFT_X,
					"axis_value": 1.0,
					"device": -1,
				},
			],
		},
		ACTION_GAMEPAD_ONLY: {
			"deadzone": 0.5,
			"events": [
				{"type": "joypad_button", "button_index": JOY_BUTTON_B, "device": -1},
			],
		},
		ACTION_UNBOUND: {
			"deadzone": 0.5,
			"events": [],
		},
	}
	_expect_ok(InputSystem.reset_to_defaults(contract), "input defaults should apply")

	var resolver := InputPromptResolver.new()
	resolver.device_changed.connect(_on_device_changed)
	_expect_ok(
		resolver.configure(
			contract,
			{
				"gamepad_axis_threshold": 0.6,
				"mouse_motion_threshold": 3.0,
			}
		),
		"resolver should configure"
	)
	_expect_equal(
		resolver.current_device_type(),
		InputPromptResolver.DEVICE_KEYBOARD_MOUSE,
		"default device should be keyboard/mouse"
	)

	var keyboard_prompt: Dictionary = resolver.resolve_action(ACTION_JUMP)
	_expect_ok(keyboard_prompt, "keyboard jump prompt should resolve")
	_expect_equal(String(keyboard_prompt.get("text", "")), "W", "keyboard text should be W")
	_expect_equal(
		String(keyboard_prompt.get("icon_key", "")),
		"key_w",
		"keyboard icon key should be stable"
	)
	_expect_equal(
		String(keyboard_prompt.get("device_type", "")),
		InputPromptResolver.DEVICE_KEYBOARD_MOUSE,
		"keyboard prompt should report keyboard/mouse device"
	)

	var drift := InputEventJoypadMotion.new()
	drift.device = 2
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.2
	_expect_code(
		resolver.observe_event(drift),
		"input_ignored",
		"small gamepad drift should not switch current device"
	)
	_expect_equal(
		resolver.current_device_type(),
		InputPromptResolver.DEVICE_KEYBOARD_MOUSE,
		"ignored drift should keep keyboard/mouse device"
	)

	var gamepad_press := InputEventJoypadButton.new()
	gamepad_press.device = 2
	gamepad_press.button_index = JOY_BUTTON_A
	gamepad_press.pressed = true
	_expect_ok(resolver.observe_event(gamepad_press), "gamepad press should be observed")
	_expect_equal(
		resolver.current_device_type(),
		InputPromptResolver.DEVICE_GAMEPAD,
		"gamepad press should switch current device"
	)
	_expect_equal(resolver.current_device_id(), 2, "current gamepad device id should be tracked")
	_expect_equal(_device_changes, 1, "meaningful device change should emit signal")

	var gamepad_prompt: Dictionary = resolver.resolve_action(ACTION_JUMP)
	_expect_ok(gamepad_prompt, "gamepad jump prompt should resolve")
	_expect_equal(
		String(gamepad_prompt.get("text", "")),
		"Gamepad South",
		"generic gamepad text should avoid controller-brand assumptions"
	)
	_expect_equal(
		String(gamepad_prompt.get("icon_key", "")),
		"gamepad_south",
		"gamepad south icon key should be stable"
	)
	_expect_equal(
		bool(gamepad_prompt.get("fallback_used", true)),
		false,
		"gamepad binding should not require fallback"
	)

	var tiny_mouse := InputEventMouseMotion.new()
	tiny_mouse.relative = Vector2(1.0, 1.0)
	_expect_code(
		resolver.observe_event(tiny_mouse),
		"input_ignored",
		"small mouse motion should not steal current device"
	)
	_expect_equal(
		resolver.current_device_type(),
		InputPromptResolver.DEVICE_GAMEPAD,
		"ignored mouse motion should keep gamepad device"
	)

	var mouse_move := InputEventMouseMotion.new()
	mouse_move.relative = Vector2(4.0, 0.0)
	_expect_ok(resolver.observe_event(mouse_move), "meaningful mouse motion should switch device")
	_expect_equal(
		resolver.current_device_type(),
		InputPromptResolver.DEVICE_KEYBOARD_MOUSE,
		"mouse motion should switch to keyboard/mouse"
	)

	var mouse_prompt: Dictionary = resolver.resolve_action(ACTION_INTERACT)
	_expect_ok(mouse_prompt, "mouse prompt should resolve")
	_expect_equal(
		String(mouse_prompt.get("text", "")),
		"Ctrl + Mouse Left",
		"modifier text should be included"
	)
	_expect_string_array(
		mouse_prompt.get("icon_keys", PackedStringArray()),
		PackedStringArray(["key_ctrl", "mouse_left"]),
		"modifier and mouse icon keys should be separated"
	)

	var axis_prompt: Dictionary = resolver.resolve_action(
		ACTION_AXIS,
		{"device_type": InputPromptResolver.DEVICE_GAMEPAD}
	)
	_expect_ok(axis_prompt, "gamepad axis prompt should resolve")
	_expect_equal(
		String(axis_prompt.get("text", "")),
		"Left Stick Right",
		"axis direction should resolve to semantic text"
	)
	_expect_equal(
		String(axis_prompt.get("icon_key", "")),
		"gamepad_left_stick_right",
		"axis prompt should expose semantic icon key"
	)

	var no_keyboard: Dictionary = resolver.resolve_action(
		ACTION_GAMEPAD_ONLY,
		{
			"device_type": InputPromptResolver.DEVICE_KEYBOARD_MOUSE,
			"allow_fallback": false,
		}
	)
	_expect_code(
		no_keyboard,
		"no_binding_for_device",
		"device-specific resolve should surface missing binding without fallback"
	)
	_expect_equal(
		bool(no_keyboard.get("available", true)),
		false,
		"missing device binding should not be available"
	)

	var fallback_prompt: Dictionary = resolver.resolve_action(
		ACTION_GAMEPAD_ONLY,
		{"device_type": InputPromptResolver.DEVICE_KEYBOARD_MOUSE}
	)
	_expect_ok(fallback_prompt, "fallback prompt should resolve")
	_expect_equal(
		bool(fallback_prompt.get("fallback_used", false)),
		true,
		"cross-device fallback should be reported"
	)
	_expect_equal(
		String(fallback_prompt.get("device_type", "")),
		InputPromptResolver.DEVICE_GAMEPAD,
		"fallback should report the actual selected device"
	)

	var unbound: Dictionary = resolver.resolve_action(ACTION_UNBOUND)
	_expect_code(unbound, "action_unbound", "unbound action should be explicit")
	_expect_equal(String(unbound.get("text", "")), "Unbound", "unbound text should be stable")
	_expect_equal(bool(unbound.get("available", true)), false, "unbound action should be unavailable")

	var key_descriptor: Dictionary = {
		"type": "key",
		"physical_keycode": KEY_K,
		"shift": true,
		"ctrl": true,
	}
	var key_combo: Dictionary = resolver.resolve_descriptor(key_descriptor)
	_expect_ok(key_combo, "keyboard combo should resolve")
	_expect_equal(
		String(key_combo.get("text", "")),
		"Ctrl + Shift + K",
		"keyboard combo text should be ordered"
	)
	_expect_string_array(
		key_combo.get("icon_keys", PackedStringArray()),
		PackedStringArray(["key_ctrl", "key_shift", "key_k"]),
		"keyboard combo should expose one icon key per part"
	)

	var overridden := InputPromptResolver.new()
	_expect_ok(
		overridden.configure(
			contract,
			{
				"initial_device": InputPromptResolver.DEVICE_GAMEPAD,
				"text_overrides": {"gamepad_south": "Confirm"},
				"icon_key_overrides": {"gamepad_south": "xbox_a"},
			}
		),
		"override resolver should configure"
	)
	var override_prompt: Dictionary = overridden.resolve_action(ACTION_JUMP)
	_expect_equal(
		String(override_prompt.get("text", "")),
		"Confirm",
		"text override should replace generic text"
	)
	_expect_equal(
		String(override_prompt.get("icon_key", "")),
		"xbox_a",
		"icon key override should adapt to external icon packs without bundling assets"
	)
	_expect_equal(
		String(override_prompt.get("canonical_icon_key", "")),
		"gamepad_south",
		"canonical icon key should remain available"
	)
	_expect_equal(
		overridden.format_descriptor_text(
			{"type": "joypad_button", "button_index": JOY_BUTTON_A, "device": -1}
		),
		"Confirm",
		"formatter helper should integrate with Input Remap Control"
	)

	_cleanup()
	_finish()


func _on_device_changed(_device_type: String, _device_id: int) -> void:
	_device_changes += 1


func _cleanup() -> void:
	for action_name in [
		ACTION_JUMP,
		ACTION_INTERACT,
		ACTION_AXIS,
		ACTION_GAMEPAD_ONLY,
		ACTION_UNBOUND,
	]:
		if InputMap.has_action(StringName(action_name)):
			InputMap.erase_action(StringName(action_name))


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


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail(message + " / expected=" + str(expected) + " actual=" + str(actual))


func _expect_string_array(
	actual_variant: Variant,
	expected: PackedStringArray,
	message: String
) -> void:
	var actual := PackedStringArray(actual_variant)
	if actual != expected:
		_fail(message + " / expected=" + str(expected) + " actual=" + str(actual))


func _fail(message: String) -> void:
	_failed = true
	push_error("INPUT_PROMPT_RESOLVER_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("INPUT_PROMPT_RESOLVER_SMOKE: PASS")
		get_tree().quit(0)
