extends HBoxContainer

signal value_changed(path: Array, value: Variant, result: Dictionary)
signal update_failed(path: Array, attempted_value: Variant, result: Dictionary)

const TYPE_TOGGLE: String = "toggle"
const TYPE_SLIDER: String = "slider"
const TYPE_LIST: String = "list"
const TYPE_RESOLUTION: String = "resolution"

var _session: Object = null
var _definition: Dictionary = {}
var _setting_path: Array = []
var _control_type: String = ""
var _preview_runtime: bool = true
var _configured: bool = false
var _syncing: bool = false
var _enabled: bool = true

var _label_control: Label = null
var _input_control: Control = null
var _value_label: Label = null
var _choice_values: Array = []


func configure(session: Object, definition: Dictionary) -> Dictionary:
	var session_result: Dictionary = _validate_session(session)
	if not bool(session_result.get("ok", false)):
		return session_result

	var definition_result: Dictionary = _validate_definition(definition)
	if not bool(definition_result.get("ok", false)):
		return definition_result

	_disconnect_session()
	_clear_controls()

	_session = session
	_definition = definition.duplicate(true)
	_setting_path = (definition_result.get("path", []) as Array).duplicate()
	_control_type = String(definition_result.get("type", ""))
	_preview_runtime = bool(definition.get("preview_runtime", true))
	_enabled = bool(definition.get("enabled", true))
	_configured = true

	_build_controls()
	_connect_session()

	var refresh_result: Dictionary = refresh_from_session()
	if not bool(refresh_result.get("ok", false)):
		_disconnect_session()
		_clear_controls()
		_configured = false
		_session = null
		return refresh_result

	_set_interaction_enabled(_enabled and bool(_session.call("is_active")))
	return _success(
		"option_control_configured",
		{
			"type": _control_type,
			"path": _setting_path.duplicate(),
			"value": value(),
		}
	)


func is_configured() -> bool:
	return _configured


func control_type() -> String:
	return _control_type


func setting_path() -> Array:
	return _setting_path.duplicate()


func label_control() -> Label:
	return _label_control


func input_control() -> Control:
	return _input_control


func value_label_control() -> Label:
	return _value_label


func value() -> Variant:
	if not _configured or _session == null:
		return null
	var draft: Dictionary = _session.call("draft_settings")
	var result: Dictionary = _read_path(draft, _setting_path)
	if not bool(result.get("ok", false)):
		return null
	return _copy_value(result.get("value"))


func state_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"type": _control_type,
		"path": _setting_path.duplicate(),
		"label": "" if _label_control == null else _label_control.text,
		"preview_runtime": _preview_runtime,
		"enabled": _enabled and _session != null and bool(_session.call("is_active")),
		"value": value(),
		"choice_count": _choice_values.size(),
	}


func refresh_from_session() -> Dictionary:
	if not _configured or _session == null:
		return _error("control_not_configured", "settings option control is not configured")

	var draft: Dictionary = _session.call("draft_settings")
	var path_result: Dictionary = _read_path(draft, _setting_path)
	if not bool(path_result.get("ok", false)):
		return path_result

	var current_value: Variant = path_result.get("value")
	var value_result: Dictionary = _validate_value(current_value, true)
	if not bool(value_result.get("ok", false)):
		return value_result

	_sync_control(current_value)
	_set_interaction_enabled(_enabled and bool(_session.call("is_active")))
	return _success("option_control_refreshed", {"value": _copy_value(current_value)})


func set_value(candidate: Variant, apply_runtime: bool = true) -> Dictionary:
	if not _configured or _session == null:
		return _error("control_not_configured", "settings option control is not configured")
	if not bool(_session.call("is_active")):
		return _error("session_inactive", "settings edit session is not active")
	if not _enabled:
		return _error("control_disabled", "settings option control is disabled")

	var value_result: Dictionary = _validate_value(candidate, false)
	if not bool(value_result.get("ok", false)):
		return value_result

	var draft: Dictionary = _session.call("draft_settings")
	var write_result: Dictionary = _write_path(
		draft,
		_setting_path,
		value_result.get("value")
	)
	if not bool(write_result.get("ok", false)):
		return write_result

	var update_result: Dictionary = _session.call(
		"set_draft",
		write_result.get("settings", {}) as Dictionary,
		apply_runtime
	)
	if not bool(update_result.get("ok", false)):
		refresh_from_session()
		update_failed.emit(
			_setting_path.duplicate(),
			_copy_value(candidate),
			update_result.duplicate(true)
		)
		return update_result

	refresh_from_session()
	var accepted: Variant = value()
	value_changed.emit(
		_setting_path.duplicate(),
		_copy_value(accepted),
		update_result.duplicate(true)
	)
	return update_result


func set_control_enabled(enabled: bool) -> void:
	_enabled = enabled
	var session_active: bool = (
		_session != null and bool(_session.call("is_active"))
	)
	_set_interaction_enabled(_enabled and session_active)


func _validate_session(session: Object) -> Dictionary:
	if session == null:
		return _error("session_missing", "settings edit session is required")
	for method_name in ["is_active", "draft_settings", "set_draft"]:
		if not session.has_method(method_name):
			return _error(
				"invalid_session",
				"settings edit session is missing method: " + method_name
			)
	if not bool(session.call("is_active")):
		return _error("session_inactive", "settings edit session must be active")
	if not session.has_signal("draft_changed"):
		return _error(
			"invalid_session",
			"settings edit session must expose draft_changed"
			)
	return _success("session_valid")


func _validate_definition(definition: Dictionary) -> Dictionary:
	var path_result: Dictionary = _normalize_path(definition.get("path"))
	if not bool(path_result.get("ok", false)):
		return path_result

	var type_name: String = String(definition.get("type", ""))
	if not type_name in [TYPE_TOGGLE, TYPE_SLIDER, TYPE_LIST, TYPE_RESOLUTION]:
		return _error(
			"invalid_option_type",
			"option type must be toggle, slider, list, or resolution"
		)

	if type_name == TYPE_SLIDER:
		var minimum_variant: Variant = definition.get("min", 0.0)
		var maximum_variant: Variant = definition.get("max", 1.0)
		var step_variant: Variant = definition.get("step", 0.01)
		if not _is_number(minimum_variant) or not _is_number(maximum_variant):
			return _error("invalid_slider_range", "slider min/max must be numeric")
		if not _is_number(step_variant):
			return _error("invalid_slider_step", "slider step must be numeric")
		var minimum: float = float(minimum_variant)
		var maximum: float = float(maximum_variant)
		var step: float = float(step_variant)
		if maximum <= minimum:
			return _error("invalid_slider_range", "slider max must be greater than min")
		if step <= 0.0:
			return _error("invalid_slider_step", "slider step must be greater than zero")

	if type_name == TYPE_LIST or type_name == TYPE_RESOLUTION:
		var choices_result: Dictionary = _normalize_choices(
			definition.get("options", []),
			type_name
		)
		if not bool(choices_result.get("ok", false)):
			return choices_result

	return _success(
		"definition_valid",
		{
			"path": path_result.get("path", []),
			"type": type_name,
		}
	)


func _normalize_path(value: Variant) -> Dictionary:
	var path: Array = []
	if typeof(value) == TYPE_STRING:
		for part in String(value).split(".", false):
			if part.is_empty():
				return _error("invalid_setting_path", "setting path contains an empty segment")
			path.append(part)
	elif value is Array:
		for part in value as Array:
			if typeof(part) != TYPE_STRING or String(part).is_empty():
				return _error(
					"invalid_setting_path",
					"setting path must contain non-empty strings"
				)
			path.append(String(part))
	else:
		return _error(
			"invalid_setting_path",
			"setting path must be a dotted string or string array"
		)

	if path.is_empty():
		return _error("invalid_setting_path", "setting path must not be empty")
	return _success("setting_path_valid", {"path": path})


func _build_controls() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", int(_definition.get("separation", 12)))

	_label_control = Label.new()
	_label_control.name = "OptionLabel"
	_label_control.text = String(
		_definition.get("label", String(_setting_path[_setting_path.size() - 1]))
	)
	_label_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label_control)

	match _control_type:
		TYPE_TOGGLE:
			var toggle := CheckButton.new()
			toggle.name = "Toggle"
			toggle.focus_mode = Control.FOCUS_ALL
			toggle.toggled.connect(_on_toggle_changed)
			_input_control = toggle
			add_child(toggle)
		TYPE_SLIDER:
			var slider := HSlider.new()
			slider.name = "Slider"
			slider.min_value = float(_definition.get("min", 0.0))
			slider.max_value = float(_definition.get("max", 1.0))
			slider.step = float(_definition.get("step", 0.01))
			slider.focus_mode = Control.FOCUS_ALL
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.value_changed.connect(_on_slider_changed)
			_input_control = slider
			add_child(slider)

			_value_label = Label.new()
			_value_label.name = "ValueLabel"
			_value_label.custom_minimum_size.x = float(
				_definition.get("value_label_min_width", 72.0)
			)
			_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_value_label)
		TYPE_LIST, TYPE_RESOLUTION:
			var options := OptionButton.new()
			options.name = "Options"
			options.focus_mode = Control.FOCUS_ALL
			options.fit_to_longest_item = true
			options.item_selected.connect(_on_choice_selected)
			_input_control = options
			add_child(options)
			_populate_choices(options)


func _clear_controls() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_label_control = null
	_input_control = null
	_value_label = null
	_choice_values.clear()


func _connect_session() -> void:
	if _session == null:
		return
	var draft_callable := Callable(self, "_on_session_draft_changed")
	if not _session.is_connected("draft_changed", draft_callable):
		_session.connect("draft_changed", draft_callable)
	if _session.has_signal("canceled"):
		var canceled_callable := Callable(self, "_on_session_canceled")
		if not _session.is_connected("canceled", canceled_callable):
			_session.connect("canceled", canceled_callable)


func _disconnect_session() -> void:
	if _session == null:
		return
	var draft_callable := Callable(self, "_on_session_draft_changed")
	if _session.has_signal("draft_changed") and _session.is_connected("draft_changed", draft_callable):
		_session.disconnect("draft_changed", draft_callable)
	var canceled_callable := Callable(self, "_on_session_canceled")
	if _session.has_signal("canceled") and _session.is_connected("canceled", canceled_callable):
		_session.disconnect("canceled", canceled_callable)


func _populate_choices(options: OptionButton) -> void:
	options.clear()
	_choice_values.clear()
	var normalized: Dictionary = _normalize_choices(
		_definition.get("options", []),
		_control_type
	)
	if not bool(normalized.get("ok", false)):
		return

	for entry in normalized.get("choices", []) as Array:
		var choice: Dictionary = entry as Dictionary
		options.add_item(String(choice.get("label", "")))
		_choice_values.append(_copy_value(choice.get("value")))


func _normalize_choices(value: Variant, type_name: String) -> Dictionary:
	if not (value is Array) or (value as Array).is_empty():
		return _error(
			"options_required",
			"list and resolution controls require at least one option"
		)

	var choices: Array = []
	for raw in value as Array:
		if type_name == TYPE_RESOLUTION:
			var resolution_value: Variant = raw
			var label: String = ""
			if raw is Dictionary:
				resolution_value = (raw as Dictionary).get("value")
				label = String((raw as Dictionary).get("label", ""))
			var resolution_result: Dictionary = _normalize_resolution(resolution_value)
			if not bool(resolution_result.get("ok", false)):
				return resolution_result
			var resolution: Array = resolution_result.get("value", [])
			if label.is_empty():
				label = "%d × %d" % [int(resolution[0]), int(resolution[1])]
			choices.append({"label": label, "value": resolution})
		else:
			if not (raw is Dictionary):
				return _error(
					"invalid_list_option",
					"list options must be { label, value } dictionaries"
				)
			var raw_choice: Dictionary = raw as Dictionary
			var list_label: String = String(raw_choice.get("label", ""))
			if list_label.is_empty() or not raw_choice.has("value"):
				return _error(
					"invalid_list_option",
					"list options require label and value"
				)
			choices.append(
				{
					"label": list_label,
					"value": _copy_value(raw_choice.get("value")),
				}
			)

	return _success("options_valid", {"choices": choices})


func _validate_value(candidate: Variant, allow_fallback_choice: bool) -> Dictionary:
	match _control_type:
		TYPE_TOGGLE:
			if typeof(candidate) != TYPE_BOOL:
				return _error("invalid_toggle_value", "toggle value must be bool")
			return _success("value_valid", {"value": bool(candidate)})
		TYPE_SLIDER:
			if not _is_number(candidate):
				return _error("invalid_slider_value", "slider value must be numeric")
			var minimum: float = float(_definition.get("min", 0.0))
			var maximum: float = float(_definition.get("max", 1.0))
			var numeric: float = float(candidate)
			if numeric < minimum or numeric > maximum:
				return _error(
					"slider_value_out_of_range",
					"slider value is outside the configured range"
				)
			return _success("value_valid", {"value": numeric})
		TYPE_RESOLUTION:
			var resolution_result: Dictionary = _normalize_resolution(candidate)
			if not bool(resolution_result.get("ok", false)):
				return resolution_result
			var normalized_resolution: Array = resolution_result.get("value", [])
			if _find_choice_index(normalized_resolution) < 0 and not allow_fallback_choice:
				return _error(
					"value_not_in_options",
					"resolution value is not in configured options"
				)
			return _success("value_valid", {"value": normalized_resolution})
		TYPE_LIST:
			if _find_choice_index(candidate) < 0 and not allow_fallback_choice:
				return _error(
					"value_not_in_options",
					"list value is not in configured options"
				)
			return _success("value_valid", {"value": _copy_value(candidate)})
	return _error("invalid_option_type", "option control type is invalid")


func _normalize_resolution(value: Variant) -> Dictionary:
	if not (value is Array):
		return _error("invalid_resolution_value", "resolution value must be [width, height]")
	var resolution: Array = value as Array
	if resolution.size() != 2 or not _is_number(resolution[0]) or not _is_number(resolution[1]):
		return _error("invalid_resolution_value", "resolution value must contain two numbers")
	var width: int = int(resolution[0])
	var height: int = int(resolution[1])
	if width <= 0 or height <= 0:
		return _error("invalid_resolution_value", "resolution dimensions must be positive")
	return _success("resolution_valid", {"value": [width, height]})


func _sync_control(current_value: Variant) -> void:
	if _input_control == null:
		return
	_syncing = true
	match _control_type:
		TYPE_TOGGLE:
			(_input_control as CheckButton).button_pressed = bool(current_value)
		TYPE_SLIDER:
			(_input_control as HSlider).value = float(current_value)
			_update_slider_label(float(current_value))
		TYPE_LIST, TYPE_RESOLUTION:
			var choice_index: int = _find_choice_index(current_value)
			if choice_index < 0:
				choice_index = _append_fallback_choice(current_value)
			(_input_control as OptionButton).select(choice_index)
	_syncing = false


func _append_fallback_choice(current_value: Variant) -> int:
	var options := _input_control as OptionButton
	var label: String = str(current_value)
	if _control_type == TYPE_RESOLUTION:
		var result: Dictionary = _normalize_resolution(current_value)
		if bool(result.get("ok", false)):
			var resolution: Array = result.get("value", [])
			label = "%d × %d" % [int(resolution[0]), int(resolution[1])]
	options.add_item(label)
	_choice_values.append(_copy_value(current_value))
	return _choice_values.size() - 1


func _find_choice_index(candidate: Variant) -> int:
	for index in range(_choice_values.size()):
		if _choice_values[index] == candidate:
			return index
	return -1


func _update_slider_label(numeric: float) -> void:
	if _value_label == null:
		return
	var decimals: int = clampi(int(_definition.get("decimals", 2)), 0, 6)
	var multiplier: float = float(_definition.get("display_multiplier", 1.0))
	var suffix: String = String(_definition.get("suffix", ""))
	_value_label.text = ("%.*f" % [decimals, numeric * multiplier]) + suffix


func _set_interaction_enabled(enabled: bool) -> void:
	if _input_control == null:
		return
	if _input_control is BaseButton:
		(_input_control as BaseButton).disabled = not enabled
	elif _input_control is Slider:
		(_input_control as Slider).editable = enabled
		_input_control.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


func _on_toggle_changed(pressed: bool) -> void:
	if _syncing:
		return
	set_value(pressed, _preview_runtime)


func _on_slider_changed(numeric: float) -> void:
	if _syncing:
		return
	_update_slider_label(numeric)
	set_value(numeric, _preview_runtime)


func _on_choice_selected(index: int) -> void:
	if _syncing:
		return
	if index < 0 or index >= _choice_values.size():
		return
	set_value(_choice_values[index], _preview_runtime)


func _on_session_draft_changed(_settings: Dictionary) -> void:
	refresh_from_session()


func _on_session_canceled(_result: Dictionary) -> void:
	refresh_from_session()
	_set_interaction_enabled(false)


func _read_path(root: Dictionary, path: Array) -> Dictionary:
	var current: Variant = root
	for segment_variant in path:
		if not (current is Dictionary):
			return _error("setting_path_missing", "setting path crosses a non-dictionary value")
		var segment: String = String(segment_variant)
		var current_dictionary: Dictionary = current as Dictionary
		if not current_dictionary.has(segment):
			return _error(
				"setting_path_missing",
				"setting path does not exist: " + ".".join(path)
			)
		current = current_dictionary[segment]
	return _success("setting_value_found", {"value": _copy_value(current)})


func _write_path(root: Dictionary, path: Array, new_value: Variant) -> Dictionary:
	var updated: Dictionary = root.duplicate(true)
	var cursor: Dictionary = updated
	for index in range(path.size() - 1):
		var segment: String = String(path[index])
		if not cursor.has(segment) or not (cursor[segment] is Dictionary):
			return _error(
				"setting_path_missing",
				"setting path does not exist: " + ".".join(path)
			)
		cursor = cursor[segment] as Dictionary

	var final_segment: String = String(path[path.size() - 1])
	if not cursor.has(final_segment):
		return _error(
			"setting_path_missing",
			"setting path does not exist: " + ".".join(path)
		)
	cursor[final_segment] = _copy_value(new_value)
	return _success("setting_value_written", {"settings": updated})


func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


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
