extends Node

const InputSystem = preload("res://addons/game_foundation/input/input_system.gd")

const TEST_DIR := "user://game_foundation_input_tests"
const INPUT_PATH := TEST_DIR + "/bindings.json"

const ACTION_JUMP := "foundation_test_jump"
const ACTION_FIRE := "foundation_test_fire"
const ACTION_MOVE := "foundation_test_move_axis"
const ACTION_PAD := "foundation_test_pad_button"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()

	var contract := {
		ACTION_JUMP: {
			"deadzone": 0.5,
			"events": [
				{
					"type": "key",
					"physical_keycode": KEY_SPACE,
				},
			],
		},
		ACTION_FIRE: {
			"deadzone": 0.5,
			"events": [
				{
					"type": "mouse_button",
					"button_index": MOUSE_BUTTON_LEFT,
				},
			],
		},
		ACTION_MOVE: {
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
		ACTION_PAD: {
			"deadzone": 0.5,
			"events": [
				{
					"type": "joypad_button",
					"button_index": JOY_BUTTON_A,
					"device": -1,
				},
			],
		},
	}

	_expect_ok(
		InputSystem.validate_contract(contract),
		"valid input contract should pass"
	)

	_expect_code(
		InputSystem.validate_contract({
			"broken": {
				"events": [
					{
						"type": "mouse_button",
						"button_index": 0,
					},
				],
			},
		}),
		"invalid_mouse_button",
		"invalid event descriptor should fail contract validation"
	)

	_expect_ok(
		InputSystem.reset_to_defaults(contract),
		"default input bindings should apply"
	)
	_expect_true(InputMap.has_action(ACTION_JUMP), "jump action should exist")
	_expect_true(InputMap.has_action(ACTION_FIRE), "fire action should exist")
	_expect_true(InputMap.has_action(ACTION_MOVE), "gamepad motion action should exist")
	_expect_true(InputMap.has_action(ACTION_PAD), "gamepad button action should exist")

	var defaults: Dictionary = InputSystem.capture_bindings(contract)
	_expect_event_type(defaults, ACTION_JUMP, "key", "jump default should be keyboard")
	_expect_event_type(defaults, ACTION_FIRE, "mouse_button", "fire default should be mouse")
	_expect_event_type(defaults, ACTION_MOVE, "joypad_motion", "motion default should serialize")
	_expect_event_type(defaults, ACTION_PAD, "joypad_button", "gamepad button should serialize")

	var jump_events: Array = (
		(defaults.get(ACTION_JUMP, {}) as Dictionary).get("events", [])
		as Array
	)
	_expect_equal(
		int((jump_events[0] as Dictionary).get("physical_keycode", 0)),
		KEY_SPACE,
		"default jump should use Space"
	)

	_expect_ok(
		InputSystem.rebind_action(
			contract,
			ACTION_JUMP,
			{
				"type": "key",
				"physical_keycode": KEY_Z,
			}
		),
		"jump rebind should succeed"
	)
	var rebound: Dictionary = InputSystem.capture_bindings(contract)
	var rebound_events: Array = (
		(rebound.get(ACTION_JUMP, {}) as Dictionary).get("events", [])
		as Array
	)
	_expect_equal(
		int((rebound_events[0] as Dictionary).get("physical_keycode", 0)),
		KEY_Z,
		"jump should be rebound to Z"
	)

	_expect_ok(
		InputSystem.save_bindings(contract, INPUT_PATH),
		"input bindings should save"
	)
	_expect_true(FileAccess.file_exists(INPUT_PATH), "input bindings file should exist")
	_expect_true(
		not FileAccess.file_exists(INPUT_PATH + InputSystem.TEMP_SUFFIX),
		"input temp file should not remain"
	)

	_expect_ok(
		InputSystem.rebind_action(
			contract,
			ACTION_JUMP,
			{
				"type": "key",
				"physical_keycode": KEY_X,
			}
		),
		"second rebind should succeed"
	)

	var restored: Dictionary = InputSystem.restore_bindings(
		contract,
		INPUT_PATH
	)
	_expect_ok(restored, "saved input bindings should restore")
	_expect_code(restored, "bindings_restored", "restore should report bindings_restored")
	_expect_equal(String(restored.get("source", "")), "file", "restore source should be file")

	var after_restore: Dictionary = InputSystem.capture_bindings(contract)
	var restored_events: Array = (
		(after_restore.get(ACTION_JUMP, {}) as Dictionary).get("events", [])
		as Array
	)
	_expect_equal(
		int((restored_events[0] as Dictionary).get("physical_keycode", 0)),
		KEY_Z,
		"restore should bring Z binding back"
	)

	_expect_ok(
		InputSystem.reset_to_defaults(contract),
		"reset to defaults should succeed"
	)
	var reset_bindings: Dictionary = InputSystem.capture_bindings(contract)
	var reset_events: Array = (
		(reset_bindings.get(ACTION_JUMP, {}) as Dictionary).get("events", [])
		as Array
	)
	_expect_equal(
		int((reset_events[0] as Dictionary).get("physical_keycode", 0)),
		KEY_SPACE,
		"reset should restore Space"
	)

	_write_text(INPUT_PATH, "{broken-json")
	var fallback: Dictionary = InputSystem.restore_bindings(
		contract,
		INPUT_PATH
	)
	_expect_ok(fallback, "broken input file should safely fall back")
	_expect_code(fallback, "defaults_applied", "broken input should apply defaults")
	_expect_equal(String(fallback.get("source", "")), "defaults", "fallback source should be defaults")

	_cleanup()
	var missing: Dictionary = InputSystem.restore_bindings(
		contract,
		INPUT_PATH
	)
	_expect_ok(missing, "missing input file should apply defaults")
	_expect_code(missing, "defaults_applied", "missing file should report defaults")
	_expect_equal(String(missing.get("source", "")), "defaults", "missing source should be defaults")

	_cleanup()
	_finish()


func _expect_event_type(
	bindings: Dictionary,
	action_name: String,
	expected_type: String,
	message: String
) -> void:
	var definition_variant: Variant = bindings.get(action_name, {})
	if not (definition_variant is Dictionary):
		_fail(message + " / action definition missing")
		return
	var events_variant: Variant = (definition_variant as Dictionary).get("events", [])
	if not (events_variant is Array):
		_fail(message + " / events missing")
		return
	var events: Array = events_variant as Array
	if events.is_empty() or not (events[0] is Dictionary):
		_fail(message + " / first event missing")
		return
	_expect_equal(
		String((events[0] as Dictionary).get("type", "")),
		expected_type,
		message
	)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("test fixture could not open " + path)
		return
	file.store_string(text)
	file.flush()
	file.close()


func _cleanup() -> void:
	for action_name in [ACTION_JUMP, ACTION_FIRE, ACTION_MOVE, ACTION_PAD]:
		if InputMap.has_action(StringName(action_name)):
			InputMap.erase_action(StringName(action_name))

	for path in [INPUT_PATH, INPUT_PATH + InputSystem.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR)


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
	push_error("INPUT_SYSTEM_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("INPUT_SYSTEM_SMOKE: PASS")
		get_tree().quit(0)
