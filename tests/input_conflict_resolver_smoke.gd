extends Node

const InputSystem = preload(
	"res://addons/game_foundation/input/input_system.gd"
)
const InputConflictResolver = preload(
	"res://addons/game_foundation/input/input_conflict_resolver.gd"
)

const ACTION_PRIMARY := "foundation_conflict_primary"
const ACTION_SECONDARY := "foundation_conflict_secondary"
const ACTION_MULTI := "foundation_conflict_multi"
const ACTION_PAD_ANY := "foundation_conflict_pad_any"
const ACTION_PAD_DEVICE := "foundation_conflict_pad_device"
const ACTION_AXIS_POS := "foundation_conflict_axis_pos"
const ACTION_AXIS_NEG := "foundation_conflict_axis_neg"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var contract: Dictionary = {
		ACTION_PRIMARY: {
			"deadzone": 0.5,
			"events": [{"type": "key", "physical_keycode": KEY_A}],
		},
		ACTION_SECONDARY: {
			"deadzone": 0.5,
			"events": [{"type": "key", "physical_keycode": KEY_B}],
		},
		ACTION_MULTI: {
			"deadzone": 0.5,
			"events": [
				{"type": "key", "physical_keycode": KEY_B},
				{"type": "mouse_button", "button_index": MOUSE_BUTTON_MIDDLE},
			],
		},
		ACTION_PAD_ANY: {
			"deadzone": 0.5,
			"events": [{"type": "joypad_button", "button_index": JOY_BUTTON_A, "device": -1}],
		},
		ACTION_PAD_DEVICE: {
			"deadzone": 0.5,
			"events": [{"type": "joypad_button", "button_index": JOY_BUTTON_B, "device": 2}],
		},
		ACTION_AXIS_POS: {
			"deadzone": 0.2,
			"events": [{"type": "joypad_motion", "axis": JOY_AXIS_LEFT_X, "axis_value": 1.0, "device": -1}],
		},
		ACTION_AXIS_NEG: {
			"deadzone": 0.2,
			"events": [{"type": "joypad_motion", "axis": JOY_AXIS_LEFT_X, "axis_value": -1.0, "device": -1}],
		},
	}
	_expect_ok(InputSystem.reset_to_defaults(contract), "input defaults should apply")

	_expect_code(
		InputConflictResolver.validate_policy("merge"),
		"invalid_conflict_policy",
		"unknown policy should be rejected"
	)

	var conflicts: Dictionary = InputConflictResolver.find_conflicts(
		contract,
		ACTION_PRIMARY,
		{"type": "key", "physical_keycode": KEY_B}
	)
	_expect_ok(conflicts, "key conflict detection should succeed")
	_expect_equal(
		int(conflicts.get("conflict_count", 0)),
		2,
		"same keyboard binding should find both conflicting actions"
	)
	_expect_actions(
		conflicts.get("conflicts", []),
		[ACTION_SECONDARY, ACTION_MULTI],
		"keyboard conflicts should identify other actions"
	)

	var own_binding: Dictionary = InputConflictResolver.find_conflicts(
		contract,
		ACTION_PRIMARY,
		{"type": "key", "physical_keycode": KEY_A}
	)
	_expect_equal(
		int(own_binding.get("conflict_count", -1)),
		0,
		"current action should not conflict with itself"
	)

	var reject: Dictionary = InputConflictResolver.rebind_with_policy(
		contract,
		ACTION_PRIMARY,
		{"type": "key", "physical_keycode": KEY_B},
		InputConflictResolver.POLICY_REJECT
	)
	_expect_code(reject, "binding_conflict", "reject policy should block duplicate binding")
	_expect_equal(
		int(_first_descriptor(contract, ACTION_PRIMARY).get("physical_keycode", 0)),
		KEY_A,
		"reject policy should not mutate target binding"
	)

	var allow: Dictionary = InputConflictResolver.rebind_with_policy(
		contract,
		ACTION_PRIMARY,
		{"type": "key", "physical_keycode": KEY_B},
		InputConflictResolver.POLICY_ALLOW
	)
	_expect_ok(allow, "allow policy should apply duplicate binding")
	_expect_equal(
		int(allow.get("conflict_count", 0)),
		2,
		"allow result should still report detected conflicts"
	)
	_expect_equal(
		int(_first_descriptor(contract, ACTION_PRIMARY).get("physical_keycode", 0)),
		KEY_B,
		"allow policy should update target binding"
	)
	_expect_equal(
		int(_first_descriptor(contract, ACTION_SECONDARY).get("physical_keycode", 0)),
		KEY_B,
		"allow policy should leave conflicting action unchanged"
	)

	_expect_ok(InputSystem.reset_to_defaults(contract), "defaults should reset before replace")
	var replace: Dictionary = InputConflictResolver.rebind_with_policy(
		contract,
		ACTION_PRIMARY,
		{"type": "key", "physical_keycode": KEY_B},
		InputConflictResolver.POLICY_REPLACE
	)
	_expect_ok(replace, "replace policy should apply")
	_expect_actions(
		replace.get("displaced_actions", []),
		[ACTION_SECONDARY, ACTION_MULTI],
		"replace policy should report displaced actions"
	)
	_expect_equal(
		(_events_for(contract, ACTION_SECONDARY) as Array).size(),
		0,
		"replace should remove conflicting event from single-binding action"
	)
	var multi_events: Array = _events_for(contract, ACTION_MULTI)
	_expect_equal(multi_events.size(), 1, "replace should preserve unrelated events")
	_expect_equal(
		String((multi_events[0] as Dictionary).get("type", "")),
		"mouse_button",
		"replace should leave non-conflicting mouse binding"
	)

	var wildcard_pad: Dictionary = InputConflictResolver.find_conflicts(
		contract,
		ACTION_PAD_DEVICE,
		{"type": "joypad_button", "button_index": JOY_BUTTON_A, "device": 4}
	)
	_expect_actions(
		wildcard_pad.get("conflicts", []),
		[ACTION_PAD_ANY],
		"device=-1 should overlap a specific gamepad device"
	)

	var specific_devices: Dictionary = InputConflictResolver.descriptors_conflict(
		{"type": "joypad_button", "button_index": JOY_BUTTON_B, "device": 2},
		{"type": "joypad_button", "button_index": JOY_BUTTON_B, "device": 3}
	)
	_expect_ok(specific_devices, "specific device comparison should succeed")
	_expect_equal(
		bool(specific_devices.get("conflict", true)),
		false,
		"different specific devices should not conflict"
	)

	var opposite_axis: Dictionary = InputConflictResolver.descriptors_conflict(
		{"type": "joypad_motion", "axis": JOY_AXIS_LEFT_X, "axis_value": 1.0, "device": -1},
		{"type": "joypad_motion", "axis": JOY_AXIS_LEFT_X, "axis_value": -1.0, "device": 2}
	)
	_expect_ok(opposite_axis, "axis comparison should succeed")
	_expect_equal(
		bool(opposite_axis.get("conflict", true)),
		false,
		"opposite directions on the same axis should not conflict"
	)

	_cleanup()
	_finish()


func _events_for(contract: Dictionary, action_name: String) -> Array:
	var bindings: Dictionary = InputSystem.capture_bindings(contract)
	var definition: Dictionary = bindings.get(action_name, {})
	var events_variant: Variant = definition.get("events", [])
	return (events_variant as Array).duplicate(true)


func _first_descriptor(contract: Dictionary, action_name: String) -> Dictionary:
	var events: Array = _events_for(contract, action_name)
	if events.is_empty() or not (events[0] is Dictionary):
		_fail("binding descriptor missing for " + action_name)
		return {}
	return (events[0] as Dictionary).duplicate(true)


func _expect_actions(actual_variant: Variant, expected: Array, message: String) -> void:
	if not (actual_variant is Array):
		_fail(message + " / actual is not Array")
		return
	var actual: Array[String] = []
	for item in actual_variant as Array:
		if item is Dictionary:
			actual.append(String((item as Dictionary).get("action", "")))
		else:
			actual.append(String(item))
	actual.sort()
	var sorted_expected: Array[String] = []
	for item in expected:
		sorted_expected.append(String(item))
	sorted_expected.sort()
	_expect_equal(actual, sorted_expected, message)


func _cleanup() -> void:
	for action_name in [
		ACTION_PRIMARY,
		ACTION_SECONDARY,
		ACTION_MULTI,
		ACTION_PAD_ANY,
		ACTION_PAD_DEVICE,
		ACTION_AXIS_POS,
		ACTION_AXIS_NEG,
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
		_fail(
			message
			+ " / expected="
			+ str(expected)
			+ " actual="
			+ str(actual)
		)


func _fail(message: String) -> void:
	_failed = true
	push_error("INPUT_CONFLICT_RESOLVER_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("INPUT_CONFLICT_RESOLVER_SMOKE: PASS")
		get_tree().quit(0)
