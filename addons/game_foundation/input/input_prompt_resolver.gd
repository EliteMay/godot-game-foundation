extends RefCounted

signal device_changed(device_type: String, device_id: int)

const InputSystem = preload(
	"res://addons/game_foundation/input/input_system.gd"
)

const DEVICE_KEYBOARD_MOUSE: String = "keyboard_mouse"
const DEVICE_GAMEPAD: String = "gamepad"
const DEVICE_UNKNOWN: String = "unknown"
const DEVICE_CURRENT: String = "current"

var _contract: Dictionary = {}
var _configured: bool = false
var _current_device_type: String = DEVICE_KEYBOARD_MOUSE
var _current_device_id: int = -1
var _gamepad_axis_threshold: float = 0.5
var _mouse_motion_threshold: float = 2.0
var _text_overrides: Dictionary = {}
var _icon_key_overrides: Dictionary = {}
var _unbound_text: String = "Unbound"


func configure(contract: Dictionary, options: Dictionary = {}) -> Dictionary:
	var contract_result: Dictionary = InputSystem.validate_contract(contract)
	if not bool(contract_result.get("ok", false)):
		return contract_result

	var initial_device: String = String(
		options.get("initial_device", DEVICE_KEYBOARD_MOUSE)
	)
	var device_result: Dictionary = _validate_device_type(initial_device, true)
	if not bool(device_result.get("ok", false)):
		return device_result

	var axis_threshold: float = float(options.get("gamepad_axis_threshold", 0.5))
	if axis_threshold <= 0.0 or axis_threshold > 1.0:
		return _error(
			"invalid_gamepad_axis_threshold",
			"gamepad_axis_threshold must be greater than 0 and at most 1"
		)

	var mouse_threshold: float = float(options.get("mouse_motion_threshold", 2.0))
	if mouse_threshold < 0.0:
		return _error(
			"invalid_mouse_motion_threshold",
			"mouse_motion_threshold must be 0 or greater"
		)

	var text_overrides_variant: Variant = options.get("text_overrides", {})
	if not (text_overrides_variant is Dictionary):
		return _error("invalid_text_overrides", "text_overrides must be a Dictionary")

	var icon_overrides_variant: Variant = options.get("icon_key_overrides", {})
	if not (icon_overrides_variant is Dictionary):
		return _error(
			"invalid_icon_key_overrides",
			"icon_key_overrides must be a Dictionary"
		)

	_contract = contract.duplicate(true)
	_current_device_type = initial_device
	_current_device_id = int(options.get("initial_device_id", -1))
	if _current_device_type != DEVICE_GAMEPAD:
		_current_device_id = -1
	_gamepad_axis_threshold = axis_threshold
	_mouse_motion_threshold = mouse_threshold
	_text_overrides = (text_overrides_variant as Dictionary).duplicate(true)
	_icon_key_overrides = (icon_overrides_variant as Dictionary).duplicate(true)
	_unbound_text = String(options.get("unbound_text", "Unbound"))
	_configured = true

	return _success(
		"input_prompt_resolver_configured",
		state_snapshot()
	)


func is_configured() -> bool:
	return _configured


func current_device_type() -> String:
	return _current_device_type


func current_device_id() -> int:
	return _current_device_id


func state_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"current_device_type": _current_device_type,
		"current_device_id": _current_device_id,
		"gamepad_axis_threshold": _gamepad_axis_threshold,
		"mouse_motion_threshold": _mouse_motion_threshold,
	}


func set_current_device(device_type: String, device_id: int = -1) -> Dictionary:
	var validation: Dictionary = _validate_device_type(device_type, true)
	if not bool(validation.get("ok", false)):
		return validation

	var normalized_id: int = device_id if device_type == DEVICE_GAMEPAD else -1
	var changed: bool = (
		device_type != _current_device_type
		or normalized_id != _current_device_id
	)
	_current_device_type = device_type
	_current_device_id = normalized_id
	if changed:
		device_changed.emit(_current_device_type, _current_device_id)

	return _success(
		"current_device_set",
		{
			"changed": changed,
			"device_type": _current_device_type,
			"device_id": _current_device_id,
		}
	)


func observe_event(event: InputEvent) -> Dictionary:
	var detected_type: String = DEVICE_UNKNOWN
	var detected_id: int = -1

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return _ignored("key_release_or_echo")
		detected_type = DEVICE_KEYBOARD_MOUSE
	elif event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return _ignored("mouse_release")
		detected_type = DEVICE_KEYBOARD_MOUSE
	elif event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if mouse_motion.relative.length() < _mouse_motion_threshold:
			return _ignored("mouse_motion_below_threshold")
		detected_type = DEVICE_KEYBOARD_MOUSE
	elif event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		if not joy_button.pressed:
			return _ignored("joypad_release")
		detected_type = DEVICE_GAMEPAD
		detected_id = joy_button.device
	elif event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		if absf(joy_motion.axis_value) < _gamepad_axis_threshold:
			return _ignored("joypad_axis_below_threshold")
		detected_type = DEVICE_GAMEPAD
		detected_id = joy_motion.device
	else:
		return _ignored("unsupported_event_type")

	var set_result: Dictionary = set_current_device(detected_type, detected_id)
	set_result["accepted"] = true
	return set_result


func resolve_action(action_name: String, options: Dictionary = {}) -> Dictionary:
	if not _configured:
		return _error(
			"resolver_not_configured",
			"input prompt resolver is not configured"
		)
	if not _contract.has(action_name):
		return _error(
			"unknown_action",
			"action is not declared by the game input contract",
			{"action": action_name}
		)

	var requested_device: String = String(
		options.get("device_type", DEVICE_CURRENT)
	)
	if requested_device == DEVICE_CURRENT:
		requested_device = _current_device_type
	var device_result: Dictionary = _validate_device_type(requested_device, true)
	if not bool(device_result.get("ok", false)):
		return device_result

	if requested_device == DEVICE_UNKNOWN:
		requested_device = String(
			options.get("unknown_device_fallback", DEVICE_KEYBOARD_MOUSE)
		)
		var fallback_device_result: Dictionary = _validate_device_type(
			requested_device,
			false
		)
		if not bool(fallback_device_result.get("ok", false)):
			return fallback_device_result

	var bindings: Dictionary = InputSystem.capture_bindings(_contract)
	var definition_variant: Variant = bindings.get(action_name, {})
	if not (definition_variant is Dictionary):
		return _error(
			"invalid_binding_state",
			"action binding state is not a Dictionary",
			{"action": action_name}
		)
	var events_variant: Variant = (definition_variant as Dictionary).get("events", [])
	if not (events_variant is Array):
		return _error(
			"invalid_binding_state",
			"action events are not an Array",
			{"action": action_name}
		)

	var events: Array = events_variant as Array
	if events.is_empty():
		return _empty_prompt(
			"action_unbound",
			action_name,
			requested_device,
			false
		)

	var selected: Dictionary = _select_descriptor(
		events,
		requested_device,
		_current_device_id
	)
	var fallback_used: bool = false
	if selected.is_empty():
		if not bool(options.get("allow_fallback", true)):
			return _empty_prompt(
				"no_binding_for_device",
				action_name,
				requested_device,
				false
			)
		for descriptor_variant in events:
			if descriptor_variant is Dictionary:
				selected = (descriptor_variant as Dictionary).duplicate(true)
				fallback_used = true
				break

	if selected.is_empty():
		return _empty_prompt(
			"action_unbound",
			action_name,
			requested_device,
			false
		)

	var prompt_result: Dictionary = resolve_descriptor(selected)
	if not bool(prompt_result.get("ok", false)):
		return prompt_result

	prompt_result["code"] = "action_prompt_resolved"
	prompt_result["action"] = action_name
	prompt_result["requested_device_type"] = requested_device
	prompt_result["current_device_type"] = _current_device_type
	prompt_result["current_device_id"] = _current_device_id
	prompt_result["fallback_used"] = fallback_used
	prompt_result["available"] = true
	return prompt_result


func resolve_descriptor(descriptor: Dictionary) -> Dictionary:
	var event_result: Dictionary = InputSystem.event_from_descriptor(descriptor)
	if not bool(event_result.get("ok", false)):
		return event_result
	var normalized: Dictionary = (
		(event_result.get("descriptor", {}) as Dictionary).duplicate(true)
	)

	var parts: Array[Dictionary] = []
	var descriptor_type: String = String(normalized.get("type", ""))
	if descriptor_type == "key" or descriptor_type == "mouse_button":
		_append_modifier_parts(parts, normalized)

	match descriptor_type:
		"key":
			parts.append(_key_part(normalized, event_result))
		"mouse_button":
			parts.append(_mouse_part(normalized))
		"joypad_button":
			parts.append(_joypad_button_part(normalized))
		"joypad_motion":
			parts.append(_joypad_axis_part(normalized))
		_:
			return _error(
				"unsupported_prompt_descriptor",
				"descriptor type cannot be resolved to an input prompt",
				{"type": descriptor_type}
			)

	var text_parts: PackedStringArray = PackedStringArray()
	var icon_keys: PackedStringArray = PackedStringArray()
	var canonical_icon_keys: PackedStringArray = PackedStringArray()
	for part in parts:
		var canonical_key: String = String(part.get("icon_key", ""))
		var default_text: String = String(part.get("text", ""))
		text_parts.append(_override_text(canonical_key, default_text))
		canonical_icon_keys.append(canonical_key)
		icon_keys.append(_override_icon_key(canonical_key))

	var device_type: String = _descriptor_device_type(normalized)
	return _success(
		"prompt_resolved",
		{
			"text": " + ".join(text_parts),
			"icon_key": "+".join(icon_keys),
			"icon_keys": icon_keys,
			"canonical_icon_key": "+".join(canonical_icon_keys),
			"canonical_icon_keys": canonical_icon_keys,
			"device_type": device_type,
			"device_id": int(normalized.get("device", -1)) if device_type == DEVICE_GAMEPAD else -1,
			"descriptor": normalized,
		}
	)


func format_descriptor_text(descriptor: Dictionary) -> String:
	var result: Dictionary = resolve_descriptor(descriptor)
	if not bool(result.get("ok", false)):
		return ""
	return String(result.get("text", ""))


func icon_keys_for_descriptor(descriptor: Dictionary) -> PackedStringArray:
	var result: Dictionary = resolve_descriptor(descriptor)
	if not bool(result.get("ok", false)):
		return PackedStringArray()
	return result.get("icon_keys", PackedStringArray())


func _select_descriptor(
	events: Array,
	device_type: String,
	preferred_gamepad_id: int
) -> Dictionary:
	var best: Dictionary = {}
	var best_rank: int = 100

	for descriptor_variant in events:
		if not (descriptor_variant is Dictionary):
			continue
		var descriptor: Dictionary = descriptor_variant as Dictionary
		if _descriptor_device_type(descriptor) != device_type:
			continue

		var rank: int = 0
		if device_type == DEVICE_GAMEPAD and preferred_gamepad_id >= 0:
			var descriptor_device: int = int(descriptor.get("device", -1))
			if descriptor_device == preferred_gamepad_id:
				rank = 0
			elif descriptor_device == -1:
				rank = 1
			else:
				rank = 2
		if rank < best_rank:
			best = descriptor.duplicate(true)
			best_rank = rank

	return best


func _descriptor_device_type(descriptor: Dictionary) -> String:
	match String(descriptor.get("type", "")):
		"key", "mouse_button":
			return DEVICE_KEYBOARD_MOUSE
		"joypad_button", "joypad_motion":
			return DEVICE_GAMEPAD
	return DEVICE_UNKNOWN


func _append_modifier_parts(parts: Array[Dictionary], descriptor: Dictionary) -> void:
	if bool(descriptor.get("ctrl", false)):
		parts.append({"text": "Ctrl", "icon_key": "key_ctrl"})
	if bool(descriptor.get("alt", false)):
		parts.append({"text": "Alt", "icon_key": "key_alt"})
	if bool(descriptor.get("shift", false)):
		parts.append({"text": "Shift", "icon_key": "key_shift"})
	if bool(descriptor.get("meta", false)):
		parts.append({"text": "Meta", "icon_key": "key_meta"})


func _key_part(descriptor: Dictionary, event_result: Dictionary) -> Dictionary:
	var code: int = int(descriptor.get("physical_keycode", 0))
	if code == 0:
		code = int(descriptor.get("keycode", 0))
	if code == 0:
		var unicode_value: int = int(descriptor.get("unicode", 0))
		if unicode_value > 0:
			code = unicode_value

	var known: Dictionary = _known_key(code)
	if not known.is_empty():
		return known

	if code >= 48 and code <= 57:
		var digit: String = String.chr(code)
		return {"text": digit, "icon_key": "key_" + digit}
	if code >= 65 and code <= 90:
		var letter: String = String.chr(code).to_upper()
		return {"text": letter, "icon_key": "key_" + letter.to_lower()}
	if code >= 97 and code <= 122:
		var lower_letter: String = String.chr(code).to_upper()
		return {
			"text": lower_letter,
			"icon_key": "key_" + lower_letter.to_lower(),
		}

	var event_variant: Variant = event_result.get("event")
	var fallback_text: String = "Key " + str(code)
	if event_variant is InputEvent:
		var as_text: String = (event_variant as InputEvent).as_text()
		if not as_text.strip_edges().is_empty():
			fallback_text = as_text
	return {"text": fallback_text, "icon_key": "key_code_" + str(code)}


func _known_key(code: int) -> Dictionary:
	match code:
		KEY_SPACE:
			return {"text": "Space", "icon_key": "key_space"}
		KEY_ENTER:
			return {"text": "Enter", "icon_key": "key_enter"}
		KEY_ESCAPE:
			return {"text": "Esc", "icon_key": "key_escape"}
		KEY_TAB:
			return {"text": "Tab", "icon_key": "key_tab"}
		KEY_BACKSPACE:
			return {"text": "Backspace", "icon_key": "key_backspace"}
		KEY_DELETE:
			return {"text": "Delete", "icon_key": "key_delete"}
		KEY_INSERT:
			return {"text": "Insert", "icon_key": "key_insert"}
		KEY_HOME:
			return {"text": "Home", "icon_key": "key_home"}
		KEY_END:
			return {"text": "End", "icon_key": "key_end"}
		KEY_PAGEUP:
			return {"text": "Page Up", "icon_key": "key_page_up"}
		KEY_PAGEDOWN:
			return {"text": "Page Down", "icon_key": "key_page_down"}
		KEY_UP:
			return {"text": "Up", "icon_key": "key_up"}
		KEY_DOWN:
			return {"text": "Down", "icon_key": "key_down"}
		KEY_LEFT:
			return {"text": "Left", "icon_key": "key_left"}
		KEY_RIGHT:
			return {"text": "Right", "icon_key": "key_right"}
		KEY_F1:
			return {"text": "F1", "icon_key": "key_f1"}
		KEY_F2:
			return {"text": "F2", "icon_key": "key_f2"}
		KEY_F3:
			return {"text": "F3", "icon_key": "key_f3"}
		KEY_F4:
			return {"text": "F4", "icon_key": "key_f4"}
		KEY_F5:
			return {"text": "F5", "icon_key": "key_f5"}
		KEY_F6:
			return {"text": "F6", "icon_key": "key_f6"}
		KEY_F7:
			return {"text": "F7", "icon_key": "key_f7"}
		KEY_F8:
			return {"text": "F8", "icon_key": "key_f8"}
		KEY_F9:
			return {"text": "F9", "icon_key": "key_f9"}
		KEY_F10:
			return {"text": "F10", "icon_key": "key_f10"}
		KEY_F11:
			return {"text": "F11", "icon_key": "key_f11"}
		KEY_F12:
			return {"text": "F12", "icon_key": "key_f12"}
	return {}


func _mouse_part(descriptor: Dictionary) -> Dictionary:
	match int(descriptor.get("button_index", 0)):
		MOUSE_BUTTON_LEFT:
			return {"text": "Mouse Left", "icon_key": "mouse_left"}
		MOUSE_BUTTON_RIGHT:
			return {"text": "Mouse Right", "icon_key": "mouse_right"}
		MOUSE_BUTTON_MIDDLE:
			return {"text": "Mouse Middle", "icon_key": "mouse_middle"}
		MOUSE_BUTTON_WHEEL_UP:
			return {"text": "Wheel Up", "icon_key": "mouse_wheel_up"}
		MOUSE_BUTTON_WHEEL_DOWN:
			return {"text": "Wheel Down", "icon_key": "mouse_wheel_down"}
		MOUSE_BUTTON_WHEEL_LEFT:
			return {"text": "Wheel Left", "icon_key": "mouse_wheel_left"}
		MOUSE_BUTTON_WHEEL_RIGHT:
			return {"text": "Wheel Right", "icon_key": "mouse_wheel_right"}
	var index: int = int(descriptor.get("button_index", 0))
	return {
		"text": "Mouse " + str(index),
		"icon_key": "mouse_button_" + str(index),
	}


func _joypad_button_part(descriptor: Dictionary) -> Dictionary:
	match int(descriptor.get("button_index", -1)):
		JOY_BUTTON_A:
			return {"text": "Gamepad South", "icon_key": "gamepad_south"}
		JOY_BUTTON_B:
			return {"text": "Gamepad East", "icon_key": "gamepad_east"}
		JOY_BUTTON_X:
			return {"text": "Gamepad West", "icon_key": "gamepad_west"}
		JOY_BUTTON_Y:
			return {"text": "Gamepad North", "icon_key": "gamepad_north"}
		JOY_BUTTON_BACK:
			return {"text": "Gamepad Back", "icon_key": "gamepad_back"}
		JOY_BUTTON_GUIDE:
			return {"text": "Gamepad Guide", "icon_key": "gamepad_guide"}
		JOY_BUTTON_START:
			return {"text": "Gamepad Start", "icon_key": "gamepad_start"}
		JOY_BUTTON_LEFT_STICK:
			return {"text": "Left Stick Press", "icon_key": "gamepad_left_stick_press"}
		JOY_BUTTON_RIGHT_STICK:
			return {"text": "Right Stick Press", "icon_key": "gamepad_right_stick_press"}
		JOY_BUTTON_LEFT_SHOULDER:
			return {"text": "Left Shoulder", "icon_key": "gamepad_left_shoulder"}
		JOY_BUTTON_RIGHT_SHOULDER:
			return {"text": "Right Shoulder", "icon_key": "gamepad_right_shoulder"}
		JOY_BUTTON_DPAD_UP:
			return {"text": "D-Pad Up", "icon_key": "gamepad_dpad_up"}
		JOY_BUTTON_DPAD_DOWN:
			return {"text": "D-Pad Down", "icon_key": "gamepad_dpad_down"}
		JOY_BUTTON_DPAD_LEFT:
			return {"text": "D-Pad Left", "icon_key": "gamepad_dpad_left"}
		JOY_BUTTON_DPAD_RIGHT:
			return {"text": "D-Pad Right", "icon_key": "gamepad_dpad_right"}
	var index: int = int(descriptor.get("button_index", -1))
	return {
		"text": "Gamepad Button " + str(index),
		"icon_key": "gamepad_button_" + str(index),
	}


func _joypad_axis_part(descriptor: Dictionary) -> Dictionary:
	var axis: int = int(descriptor.get("axis", -1))
	var value: float = float(descriptor.get("axis_value", 0.0))
	var positive: bool = value >= 0.0

	match axis:
		JOY_AXIS_LEFT_X:
			return (
				{"text": "Left Stick Right", "icon_key": "gamepad_left_stick_right"}
				if positive
				else {"text": "Left Stick Left", "icon_key": "gamepad_left_stick_left"}
			)
		JOY_AXIS_LEFT_Y:
			return (
				{"text": "Left Stick Down", "icon_key": "gamepad_left_stick_down"}
				if positive
				else {"text": "Left Stick Up", "icon_key": "gamepad_left_stick_up"}
			)
		JOY_AXIS_RIGHT_X:
			return (
				{"text": "Right Stick Right", "icon_key": "gamepad_right_stick_right"}
				if positive
				else {"text": "Right Stick Left", "icon_key": "gamepad_right_stick_left"}
			)
		JOY_AXIS_RIGHT_Y:
			return (
				{"text": "Right Stick Down", "icon_key": "gamepad_right_stick_down"}
				if positive
				else {"text": "Right Stick Up", "icon_key": "gamepad_right_stick_up"}
			)
		JOY_AXIS_TRIGGER_LEFT:
			return {"text": "Left Trigger", "icon_key": "gamepad_left_trigger"}
		JOY_AXIS_TRIGGER_RIGHT:
			return {"text": "Right Trigger", "icon_key": "gamepad_right_trigger"}

	var direction: String = "positive" if positive else "negative"
	return {
		"text": "Gamepad Axis " + str(axis) + " " + direction.capitalize(),
		"icon_key": "gamepad_axis_" + str(axis) + "_" + direction,
	}


func _override_text(canonical_key: String, default_text: String) -> String:
	if _text_overrides.has(canonical_key):
		return String(_text_overrides[canonical_key])
	return default_text


func _override_icon_key(canonical_key: String) -> String:
	if _icon_key_overrides.has(canonical_key):
		return String(_icon_key_overrides[canonical_key])
	return canonical_key


func _empty_prompt(
	code: String,
	action_name: String,
	requested_device: String,
	fallback_used: bool
) -> Dictionary:
	return _success(
		code,
		{
			"action": action_name,
			"available": false,
			"text": _unbound_text,
			"icon_key": "",
			"icon_keys": PackedStringArray(),
			"canonical_icon_key": "",
			"canonical_icon_keys": PackedStringArray(),
			"descriptor": {},
			"requested_device_type": requested_device,
			"current_device_type": _current_device_type,
			"current_device_id": _current_device_id,
			"fallback_used": fallback_used,
		}
	)


func _validate_device_type(
	device_type: String,
	allow_unknown: bool
) -> Dictionary:
	var allowed: Array[String] = [DEVICE_KEYBOARD_MOUSE, DEVICE_GAMEPAD]
	if allow_unknown:
		allowed.append(DEVICE_UNKNOWN)
	if device_type not in allowed:
		return _error(
			"invalid_device_type",
			"device type must be keyboard_mouse, gamepad"
			+ (", or unknown" if allow_unknown else ""),
			{"device_type": device_type}
		)
	return _success("valid_device_type")


func _ignored(reason: String) -> Dictionary:
	return _success(
		"input_ignored",
		{
			"accepted": false,
			"reason": reason,
			"device_type": _current_device_type,
			"device_id": _current_device_id,
		}
	)


func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "code": code}
	for key in extra:
		result[key] = extra[key]
	return result


func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": false, "code": code, "message": message}
	for key in extra:
		result[key] = extra[key]
	return result
