extends RefCounted

const FORMAT_ID: String = "godot-game-foundation-input-bindings"
const INPUT_SCHEMA_VERSION: int = 1
const DEFAULT_INPUT_PATH: String = "user://input_bindings.json"
const TEMP_SUFFIX: String = ".tmp"
const MAX_ACTIONS: int = 512
const MAX_EVENTS_PER_ACTION: int = 32


static func validate_contract(contract: Dictionary) -> Dictionary:
	if contract.size() > MAX_ACTIONS:
		return _error("too_many_actions", "input contract contains too many actions")

	for raw_action_name in contract.keys():
		if typeof(raw_action_name) != TYPE_STRING:
			return _error("invalid_action_name", "input action names must be String")

		var action_name: String = String(raw_action_name)
		if action_name.is_empty():
			return _error("invalid_action_name", "input action name cannot be empty")

		var definition_variant: Variant = contract[raw_action_name]
		if not (definition_variant is Dictionary):
			return _error(
				"invalid_action_definition",
				"input action definition must be a Dictionary",
				{"action": action_name}
			)

		var definition: Dictionary = definition_variant as Dictionary
		var deadzone_variant: Variant = definition.get("deadzone", 0.5)
		if not _is_number(deadzone_variant):
			return _error(
				"invalid_deadzone",
				"deadzone must be numeric",
				{"action": action_name}
			)

		var deadzone: float = float(deadzone_variant)
		if deadzone < 0.0 or deadzone > 1.0:
			return _error(
				"invalid_deadzone",
				"deadzone must be between 0 and 1",
				{"action": action_name}
			)

		var events_variant: Variant = definition.get("events", [])
		if not (events_variant is Array):
			return _error(
				"invalid_events",
				"events must be an Array",
				{"action": action_name}
			)

		var events: Array = events_variant as Array
		if events.size() > MAX_EVENTS_PER_ACTION:
			return _error(
				"too_many_events",
				"input action contains too many events",
				{"action": action_name}
			)

		for descriptor_variant in events:
			if not (descriptor_variant is Dictionary):
				return _error(
					"invalid_event_descriptor",
					"input event descriptor must be a Dictionary",
					{"action": action_name}
				)

			var event_result: Dictionary = event_from_descriptor(
				descriptor_variant as Dictionary
			)
			if not bool(event_result.get("ok", false)):
				event_result["action"] = action_name
				return event_result

	return _success("valid_contract")


static func reset_to_defaults(contract: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_contract(contract)
	if not bool(validation.get("ok", false)):
		return validation

	for raw_action_name in contract.keys():
		var action_name := StringName(String(raw_action_name))
		var definition: Dictionary = contract[raw_action_name] as Dictionary
		var deadzone: float = float(definition.get("deadzone", 0.5))

		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, deadzone)
		else:
			InputMap.action_set_deadzone(action_name, deadzone)
			InputMap.action_erase_events(action_name)

		var events: Array = definition.get("events", [])
		for descriptor_variant in events:
			var event_result: Dictionary = event_from_descriptor(
				descriptor_variant as Dictionary
			)
			if not bool(event_result.get("ok", false)):
				return event_result
			var event: InputEvent = event_result.get("event")
			InputMap.action_add_event(action_name, event)

	return _success("defaults_applied", {
		"bindings": capture_bindings(contract),
	})


static func rebind_action(
	contract: Dictionary,
	action_name: String,
	event_descriptor: Dictionary,
	replace_all: bool = true
) -> Dictionary:
	var contract_validation: Dictionary = validate_contract(contract)
	if not bool(contract_validation.get("ok", false)):
		return contract_validation
	if not contract.has(action_name):
		return _error(
			"unknown_action",
			"action is not declared by the game input contract",
			{"action": action_name}
		)

	var event_result: Dictionary = event_from_descriptor(event_descriptor)
	if not bool(event_result.get("ok", false)):
		return event_result

	var action := StringName(action_name)
	var definition: Dictionary = contract[action_name] as Dictionary
	if not InputMap.has_action(action):
		InputMap.add_action(action, float(definition.get("deadzone", 0.5)))

	if replace_all:
		InputMap.action_erase_events(action)

	InputMap.action_add_event(action, event_result.get("event"))
	return _success("action_rebound", {
		"action": action_name,
		"bindings": capture_bindings(contract),
	})


static func apply_bindings(
	contract: Dictionary,
	bindings: Dictionary
) -> Dictionary:
	var contract_validation: Dictionary = validate_contract(contract)
	if not bool(contract_validation.get("ok", false)):
		return contract_validation

	var normalized_result: Dictionary = normalize_bindings(
		contract,
		bindings
	)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	var normalized: Dictionary = normalized_result.get("bindings", {})
	for raw_action_name in contract.keys():
		var action_name: String = String(raw_action_name)
		var action := StringName(action_name)
		var definition: Dictionary = normalized[action_name] as Dictionary
		var deadzone: float = float(definition.get("deadzone", 0.5))

		if not InputMap.has_action(action):
			InputMap.add_action(action, deadzone)
		else:
			InputMap.action_set_deadzone(action, deadzone)
			InputMap.action_erase_events(action)

		var events: Array = definition.get("events", [])
		for descriptor_variant in events:
			var event_result: Dictionary = event_from_descriptor(
				descriptor_variant as Dictionary
			)
			if not bool(event_result.get("ok", false)):
				return event_result
			InputMap.action_add_event(action, event_result.get("event"))

	return _success("bindings_applied", {
		"bindings": capture_bindings(contract),
		"warnings": normalized_result.get("warnings", []),
	})


static func capture_bindings(contract: Dictionary) -> Dictionary:
	var captured: Dictionary = {}
	for raw_action_name in contract.keys():
		var action_name: String = String(raw_action_name)
		var definition: Dictionary = contract[raw_action_name] as Dictionary
		var events: Array = []
		var action := StringName(action_name)

		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action):
				var descriptor_result: Dictionary = descriptor_from_event(event)
				if bool(descriptor_result.get("ok", false)):
					events.append(descriptor_result.get("descriptor"))

		captured[action_name] = {
			"deadzone": (
				InputMap.action_get_deadzone(action)
				if InputMap.has_action(action)
				else float(definition.get("deadzone", 0.5))
			),
			"events": events,
		}

	return captured


static func normalize_bindings(
	contract: Dictionary,
	bindings: Dictionary
) -> Dictionary:
	var contract_validation: Dictionary = validate_contract(contract)
	if not bool(contract_validation.get("ok", false)):
		return contract_validation

	var normalized: Dictionary = {}
	var warnings: Array[String] = []

	for raw_action_name in contract.keys():
		var action_name: String = String(raw_action_name)
		var default_definition: Dictionary = contract[raw_action_name] as Dictionary
		var candidate_variant: Variant = bindings.get(action_name)

		if not (candidate_variant is Dictionary):
			normalized[action_name] = default_definition.duplicate(true)
			if candidate_variant != null:
				warnings.append(action_name + ": invalid definition")
			continue

		var candidate: Dictionary = candidate_variant as Dictionary
		var deadzone: float = float(default_definition.get("deadzone", 0.5))
		var deadzone_variant: Variant = candidate.get("deadzone")
		if _is_number(deadzone_variant):
			var candidate_deadzone: float = float(deadzone_variant)
			if candidate_deadzone >= 0.0 and candidate_deadzone <= 1.0:
				deadzone = candidate_deadzone
			else:
				warnings.append(action_name + ": invalid deadzone")

		var events_variant: Variant = candidate.get("events")
		if not (events_variant is Array):
			normalized[action_name] = default_definition.duplicate(true)
			warnings.append(action_name + ": invalid events")
			continue

		var candidate_events: Array = events_variant as Array
		if candidate_events.size() > MAX_EVENTS_PER_ACTION:
			normalized[action_name] = default_definition.duplicate(true)
			warnings.append(action_name + ": too many events")
			continue

		var normalized_events: Array = []
		var invalid_event: bool = false
		for descriptor_variant in candidate_events:
			if not (descriptor_variant is Dictionary):
				invalid_event = true
				break
			var event_result: Dictionary = event_from_descriptor(
				descriptor_variant as Dictionary
			)
			if not bool(event_result.get("ok", false)):
				invalid_event = true
				break
			normalized_events.append(
				(event_result.get("descriptor") as Dictionary).duplicate(true)
			)

		if invalid_event:
			normalized[action_name] = default_definition.duplicate(true)
			warnings.append(action_name + ": invalid event")
			continue

		normalized[action_name] = {
			"deadzone": deadzone,
			"events": normalized_events,
		}

	return _success("bindings_normalized", {
		"bindings": normalized,
		"warnings": warnings,
	})


static func save_bindings(
	contract: Dictionary,
	path: String = DEFAULT_INPUT_PATH
) -> Dictionary:
	var contract_validation: Dictionary = validate_contract(contract)
	if not bool(contract_validation.get("ok", false)):
		return contract_validation

	var path_result: Dictionary = _validate_path(path)
	if not bool(path_result.get("ok", false)):
		return path_result

	var envelope: Dictionary = {
		"metadata": {
			"format": FORMAT_ID,
			"input_schema_version": INPUT_SCHEMA_VERSION,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
		},
		"bindings": capture_bindings(contract),
	}

	var write_result: Dictionary = _write_atomic(path, envelope)
	if not bool(write_result.get("ok", false)):
		return write_result

	return _success("bindings_saved", {
		"path": path,
		"bindings": envelope["bindings"],
	})


static func restore_bindings(
	contract: Dictionary,
	path: String = DEFAULT_INPUT_PATH
) -> Dictionary:
	var contract_validation: Dictionary = validate_contract(contract)
	if not bool(contract_validation.get("ok", false)):
		return contract_validation

	var path_result: Dictionary = _validate_path(path)
	if not bool(path_result.get("ok", false)):
		return path_result

	if not FileAccess.file_exists(path):
		var defaults_result: Dictionary = reset_to_defaults(contract)
		if not bool(defaults_result.get("ok", false)):
			return defaults_result
		defaults_result["code"] = "defaults_applied"
		defaults_result["source"] = "defaults"
		return defaults_result

	var read_result: Dictionary = _read_envelope(path)
	if not bool(read_result.get("ok", false)):
		var fallback_result: Dictionary = reset_to_defaults(contract)
		if not bool(fallback_result.get("ok", false)):
			return fallback_result
		fallback_result["code"] = "defaults_applied"
		fallback_result["source"] = "defaults"
		fallback_result["warning"] = String(read_result.get("code", "load_failed"))
		return fallback_result

	var envelope: Dictionary = read_result.get("envelope", {})
	var metadata_variant: Variant = envelope.get("metadata")
	if not (metadata_variant is Dictionary):
		return _fallback_defaults(contract, "invalid_metadata")

	var metadata: Dictionary = metadata_variant as Dictionary
	if String(metadata.get("format", "")) != FORMAT_ID:
		return _fallback_defaults(contract, "unsupported_format")

	var schema_version: int = int(metadata.get("input_schema_version", 0))
	if schema_version != INPUT_SCHEMA_VERSION:
		return _fallback_defaults(contract, "unsupported_schema")

	var bindings_variant: Variant = envelope.get("bindings")
	if not (bindings_variant is Dictionary):
		return _fallback_defaults(contract, "invalid_bindings")

	var apply_result: Dictionary = apply_bindings(
		contract,
		bindings_variant as Dictionary
	)
	if not bool(apply_result.get("ok", false)):
		return _fallback_defaults(
			contract,
			String(apply_result.get("code", "invalid_bindings"))
		)

	apply_result["code"] = "bindings_restored"
	apply_result["source"] = "file"
	return apply_result


static func descriptor_from_event(event: InputEvent) -> Dictionary:
	var descriptor: Dictionary = {}

	if event is InputEventKey:
		var key_event := event as InputEventKey
		descriptor = {
			"type": "key",
			"keycode": int(key_event.keycode),
			"physical_keycode": int(key_event.physical_keycode),
			"unicode": int(key_event.unicode),
			"shift": key_event.shift_pressed,
			"ctrl": key_event.ctrl_pressed,
			"alt": key_event.alt_pressed,
			"meta": key_event.meta_pressed,
		}
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		descriptor = {
			"type": "mouse_button",
			"button_index": int(mouse_event.button_index),
			"shift": mouse_event.shift_pressed,
			"ctrl": mouse_event.ctrl_pressed,
			"alt": mouse_event.alt_pressed,
			"meta": mouse_event.meta_pressed,
		}
	elif event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		descriptor = {
			"type": "joypad_button",
			"button_index": int(joy_button.button_index),
			"device": joy_button.device,
		}
	elif event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		descriptor = {
			"type": "joypad_motion",
			"axis": int(joy_motion.axis),
			"axis_value": joy_motion.axis_value,
			"device": joy_motion.device,
		}
	else:
		return _error(
			"unsupported_event_type",
			"input event type is not supported",
			{"type": event.get_class()}
		)

	return _success("event_serialized", {"descriptor": descriptor})


static func event_from_descriptor(descriptor: Dictionary) -> Dictionary:
	var event_type: String = String(descriptor.get("type", ""))
	var event: InputEvent

	match event_type:
		"key":
			var key_event := InputEventKey.new()
			key_event.keycode = int(descriptor.get("keycode", 0))
			key_event.physical_keycode = int(descriptor.get("physical_keycode", 0))
			key_event.unicode = int(descriptor.get("unicode", 0))
			_apply_modifiers(key_event, descriptor)
			event = key_event
		"mouse_button":
			var mouse_event := InputEventMouseButton.new()
			var button_index: int = int(descriptor.get("button_index", 0))
			if button_index <= 0:
				return _error(
					"invalid_mouse_button",
					"mouse button_index must be greater than 0"
				)
			mouse_event.button_index = button_index
			_apply_modifiers(mouse_event, descriptor)
			event = mouse_event
		"joypad_button":
			var joy_button := InputEventJoypadButton.new()
			var joy_button_index: int = int(descriptor.get("button_index", -1))
			if joy_button_index < 0:
				return _error(
					"invalid_joypad_button",
					"joypad button_index must be 0 or greater"
				)
			joy_button.button_index = joy_button_index
			joy_button.device = int(descriptor.get("device", -1))
			event = joy_button
		"joypad_motion":
			var joy_motion := InputEventJoypadMotion.new()
			var axis: int = int(descriptor.get("axis", -1))
			var axis_value: float = float(descriptor.get("axis_value", 0.0))
			if axis < 0:
				return _error(
					"invalid_joypad_axis",
					"joypad axis must be 0 or greater"
				)
			if axis_value < -1.0 or axis_value > 1.0:
				return _error(
					"invalid_joypad_axis_value",
					"joypad axis_value must be between -1 and 1"
				)
			joy_motion.axis = axis
			joy_motion.axis_value = axis_value
			joy_motion.device = int(descriptor.get("device", -1))
			event = joy_motion
		_:
			return _error(
				"unsupported_event_descriptor",
				"input event descriptor type is not supported",
				{"type": event_type}
			)

	var roundtrip: Dictionary = descriptor_from_event(event)
	if not bool(roundtrip.get("ok", false)):
		return roundtrip
	return _success("event_deserialized", {
		"event": event,
		"descriptor": roundtrip.get("descriptor"),
	})


static func _apply_modifiers(
	event: InputEventWithModifiers,
	descriptor: Dictionary
) -> void:
	event.shift_pressed = bool(descriptor.get("shift", false))
	event.ctrl_pressed = bool(descriptor.get("ctrl", false))
	event.alt_pressed = bool(descriptor.get("alt", false))
	event.meta_pressed = bool(descriptor.get("meta", false))


static func _fallback_defaults(
	contract: Dictionary,
	warning: String
) -> Dictionary:
	var result: Dictionary = reset_to_defaults(contract)
	if bool(result.get("ok", false)):
		result["code"] = "defaults_applied"
		result["source"] = "defaults"
		result["warning"] = warning
	return result


static func _write_atomic(path: String, envelope: Dictionary) -> Dictionary:
	var directory: String = path.get_base_dir()
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		return _error(
			"directory_create_failed",
			"input settings directory could not be created",
			{"error": make_dir_error}
		)

	var temp: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _error(
			"temp_open_failed",
			"temporary input settings file could not be opened",
			{"error": FileAccess.get_open_error()}
		)

	file.store_string(JSON.stringify(envelope, "\t"))
	file.flush()
	file.close()

	var temp_validation: Dictionary = _read_envelope(temp)
	if not bool(temp_validation.get("ok", false)):
		_remove_if_exists(temp)
		return _error(
			"temp_validation_failed",
			"temporary input settings file failed validation"
		)

	var rename_error: Error = DirAccess.rename_absolute(temp, path)
	if rename_error != OK:
		_remove_if_exists(temp)
		return _error(
			"atomic_replace_failed",
			"temporary input settings could not replace the primary file",
			{"error": rename_error}
		)

	return _success("atomic_write_complete", {"path": path})


static func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("not_found", "input settings file does not exist")

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error(
			"read_failed",
			"input settings file could not be opened",
			{"error": FileAccess.get_open_error()}
		)

	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()

	if parse_error != OK:
		return _error(
			"parse_error",
			"input settings JSON could not be parsed",
			{
				"line": parser.get_error_line(),
				"message": parser.get_error_message(),
			}
		)

	if not (parser.data is Dictionary):
		return _error(
			"invalid_envelope",
			"input settings root must be a Dictionary"
		)

	return _success("read", {"envelope": parser.data})


static func _validate_path(path: String) -> Dictionary:
	if path.is_empty():
		return _error("invalid_path", "input settings path is empty")
	if not path.begins_with("user://"):
		return _error("unsafe_path", "runtime input settings must use user://")
	if path.ends_with("/") or path.ends_with("\\"):
		return _error("invalid_path", "input settings path must point to a file")
	return _success("valid_path")


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"code": code,
	}
	for key in extra:
		result[key] = extra[key]
	return result


static func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"code": code,
		"message": message,
	}
	for key in extra:
		result[key] = extra[key]
	return result
