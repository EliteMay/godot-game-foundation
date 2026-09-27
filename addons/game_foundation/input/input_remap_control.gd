extends HBoxContainer

signal listening_started(action_name: String)
signal listening_canceled(action_name: String)
signal binding_changed(action_name: String, descriptor: Dictionary, result: Dictionary)
signal rebind_failed(action_name: String, descriptor: Dictionary, result: Dictionary)

const InputSystem = preload(
	"res://addons/game_foundation/input/input_system.gd"
)

var _contract: Dictionary = {}
var _action_name: String = ""
var _display_name: String = ""
var _configured: bool = false
var _listening: bool = false
var _enabled: bool = true
var _replace_all: bool = true
var _preserve_gamepad_device: bool = false
var _axis_threshold: float = 0.5
var _persist: Callable = Callable()
var _binding_formatter: Callable = Callable()
var _labels: Dictionary = {}

var _action_label: Label = null
var _binding_label: Label = null
var _rebind_button: Button = null
var _cancel_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(false)


func configure(
	contract: Dictionary,
	action_name: String,
	display_name: String,
	options: Dictionary = {}
) -> Dictionary:
	if _listening:
		return _error(
			"capture_in_progress",
			"input capture must be canceled before reconfigure"
		)

	var contract_result: Dictionary = InputSystem.validate_contract(contract)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if not contract.has(action_name):
		return _error(
			"unknown_action",
			"action is not declared by the game input contract",
			{"action": action_name}
		)
	if display_name.strip_edges().is_empty():
		return _error(
			"display_name_required",
			"input remap control requires a game-facing display name"
		)

	var persist_variant: Variant = options.get("persist", Callable())
	if typeof(persist_variant) != TYPE_CALLABLE:
		return _error("invalid_persist_callback", "persist must be a Callable")
	var persist_callable: Callable = persist_variant
	if persist_callable != Callable() and not persist_callable.is_valid():
		return _error("invalid_persist_callback", "persist Callable is not valid")

	var formatter_variant: Variant = options.get("binding_formatter", Callable())
	if typeof(formatter_variant) != TYPE_CALLABLE:
		return _error("invalid_binding_formatter", "binding_formatter must be a Callable")
	var formatter_callable: Callable = formatter_variant
	if formatter_callable != Callable() and not formatter_callable.is_valid():
		return _error("invalid_binding_formatter", "binding_formatter Callable is not valid")

	var threshold: float = float(options.get("axis_threshold", 0.5))
	if threshold <= 0.0 or threshold > 1.0:
		return _error(
			"invalid_axis_threshold",
			"axis_threshold must be greater than 0 and at most 1"
		)

	_contract = contract.duplicate(true)
	_action_name = action_name
	_display_name = display_name
	_replace_all = bool(options.get("replace_all", true))
	_preserve_gamepad_device = bool(options.get("preserve_gamepad_device", false))
	_axis_threshold = threshold
	_persist = persist_callable
	_binding_formatter = formatter_callable
	_enabled = bool(options.get("enabled", true))
	_labels = {
		"rebind": String(options.get("rebind_label", "Rebind")),
		"cancel": String(options.get("cancel_label", "Cancel")),
		"listening": String(options.get("listening_label", "Waiting for input…")),
		"unbound": String(options.get("unbound_label", "Unbound")),
	}
	_configured = true

	_build_controls()
	var refresh_result: Dictionary = refresh_binding()
	if not bool(refresh_result.get("ok", false)):
		_configured = false
		_clear_controls()
		return refresh_result

	_update_interaction_state()
	return _success(
		"input_remap_control_configured",
		{
			"action": _action_name,
			"display_name": _display_name,
			"binding_text": binding_text(),
		}
	)


func is_configured() -> bool:
	return _configured


func is_listening() -> bool:
	return _listening


func action_name() -> String:
	return _action_name


func display_name() -> String:
	return _display_name


func action_label_control() -> Label:
	return _action_label


func binding_label_control() -> Label:
	return _binding_label


func rebind_button() -> Button:
	return _rebind_button


func cancel_button() -> Button:
	return _cancel_button


func current_descriptors() -> Array:
	if not _configured:
		return []
	var bindings: Dictionary = InputSystem.capture_bindings(_contract)
	var definition_variant: Variant = bindings.get(_action_name, {})
	if not (definition_variant is Dictionary):
		return []
	var events_variant: Variant = (definition_variant as Dictionary).get("events", [])
	if not (events_variant is Array):
		return []
	return (events_variant as Array).duplicate(true)


func binding_text() -> String:
	if _binding_label == null:
		return ""
	return _binding_label.text


func state_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"action": _action_name,
		"display_name": _display_name,
		"listening": _listening,
		"enabled": _enabled,
		"replace_all": _replace_all,
		"preserve_gamepad_device": _preserve_gamepad_device,
		"axis_threshold": _axis_threshold,
		"binding_text": binding_text(),
		"binding_count": current_descriptors().size(),
	}


func set_control_enabled(enabled: bool) -> void:
	if not enabled and _listening:
		cancel_listening()
	_enabled = enabled
	_update_interaction_state()


func refresh_binding() -> Dictionary:
	if not _configured:
		return _error("control_not_configured", "input remap control is not configured")

	var descriptors: Array = current_descriptors()
	if _binding_label != null and not _listening:
		if descriptors.is_empty():
			_binding_label.text = String(_labels.get("unbound", "Unbound"))
		else:
			var parts: PackedStringArray = PackedStringArray()
			for descriptor_variant in descriptors:
				if descriptor_variant is Dictionary:
					parts.append(_format_descriptor(descriptor_variant as Dictionary))
			_binding_label.text = " / ".join(parts)

	return _success(
		"binding_refreshed",
		{
			"action": _action_name,
			"binding_count": descriptors.size(),
			"binding_text": binding_text(),
		}
	)


func start_listening() -> Dictionary:
	if not _configured:
		return _error("control_not_configured", "input remap control is not configured")
	if not _enabled:
		return _error("control_disabled", "input remap control is disabled")
	if _listening:
		return _success("already_listening", {"action": _action_name})

	_listening = true
	set_process_unhandled_input(true)
	if _binding_label != null:
		_binding_label.text = String(_labels.get("listening", "Waiting for input…"))
	_update_interaction_state()
	if _cancel_button != null:
		_cancel_button.grab_focus()
	listening_started.emit(_action_name)
	return _success("listening_started", {"action": _action_name})


func cancel_listening() -> Dictionary:
	if not _configured:
		return _error("control_not_configured", "input remap control is not configured")
	if not _listening:
		return _success("not_listening", {"action": _action_name})

	_end_listening()
	refresh_binding()
	if _rebind_button != null and not _rebind_button.disabled:
		_rebind_button.grab_focus()
	listening_canceled.emit(_action_name)
	return _success("listening_canceled", {"action": _action_name})


func handle_input_event(event: InputEvent) -> Dictionary:
	if not _configured:
		return _error("control_not_configured", "input remap control is not configured")
	if not _listening:
		return _error("not_listening", "input event capture is not active")

	var descriptor_result: Dictionary = _descriptor_from_capture_event(event)
	if not bool(descriptor_result.get("ok", false)):
		return descriptor_result
	if not bool(descriptor_result.get("accepted", false)):
		return descriptor_result

	var descriptor: Dictionary = (
		(descriptor_result.get("descriptor", {}) as Dictionary).duplicate(true)
	)
	var previous_bindings: Dictionary = InputSystem.capture_bindings(_contract)
	var rebind_result: Dictionary = InputSystem.rebind_action(
		_contract,
		_action_name,
		descriptor,
		_replace_all
	)
	if not bool(rebind_result.get("ok", false)):
		_end_listening()
		refresh_binding()
		rebind_failed.emit(
			_action_name,
			descriptor.duplicate(true),
			rebind_result.duplicate(true)
		)
		return rebind_result

	var persist_result: Dictionary = _success("persistence_not_requested")
	var persisted: bool = false
	if _persist.is_valid():
		persist_result = _call_persist()
		if not bool(persist_result.get("ok", false)):
			var rollback_result: Dictionary = InputSystem.apply_bindings(
				_contract,
				previous_bindings
			)
			_end_listening()
			refresh_binding()
			var failure: Dictionary = _error(
				"binding_persist_failed",
				"input binding changed at runtime but persistence failed; previous runtime bindings were requested again",
				{
					"action": _action_name,
					"persist_result": persist_result,
					"rollback_result": rollback_result,
				}
			)
			rebind_failed.emit(
				_action_name,
				descriptor.duplicate(true),
				failure.duplicate(true)
			)
			return failure
		persisted = true

	_end_listening()
	refresh_binding()
	var result: Dictionary = rebind_result.duplicate(true)
	result["accepted"] = true
	result["persisted"] = persisted
	result["persist_result"] = persist_result
	result["descriptor"] = descriptor.duplicate(true)
	binding_changed.emit(
		_action_name,
		descriptor.duplicate(true),
		result.duplicate(true)
	)
	if _rebind_button != null and not _rebind_button.disabled:
		_rebind_button.grab_focus()
	return result


func _unhandled_input(event: InputEvent) -> void:
	if not _listening:
		return
	var result: Dictionary = handle_input_event(event)
	if bool(result.get("accepted", false)):
		get_viewport().set_input_as_handled()


func _descriptor_from_capture_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return _ignored("key_release_or_echo")
	elif event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return _ignored("mouse_release")
	elif event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return _ignored("joypad_release")
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < _axis_threshold:
			return _ignored("joypad_axis_below_threshold")
	else:
		return _ignored("unsupported_event_type")

	var descriptor_result: Dictionary = InputSystem.descriptor_from_event(event)
	if not bool(descriptor_result.get("ok", false)):
		return descriptor_result
	var descriptor: Dictionary = (
		(descriptor_result.get("descriptor", {}) as Dictionary).duplicate(true)
	)

	var descriptor_type: String = String(descriptor.get("type", ""))
	if descriptor_type == "joypad_button" or descriptor_type == "joypad_motion":
		if not _preserve_gamepad_device:
			descriptor["device"] = -1
	if descriptor_type == "joypad_motion":
		var axis_value: float = float(descriptor.get("axis_value", 0.0))
		descriptor["axis_value"] = 1.0 if axis_value >= 0.0 else -1.0

	return _success(
		"input_accepted",
		{
			"accepted": true,
			"descriptor": descriptor,
		}
	)


func _format_descriptor(descriptor: Dictionary) -> String:
	if _binding_formatter.is_valid():
		var value: Variant = _binding_formatter.call(descriptor.duplicate(true))
		if typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty():
			return String(value)

	var event_result: Dictionary = InputSystem.event_from_descriptor(descriptor)
	if bool(event_result.get("ok", false)):
		var event_variant: Variant = event_result.get("event")
		if event_variant is InputEvent:
			var text: String = (event_variant as InputEvent).as_text()
			if not text.strip_edges().is_empty():
				return text

	return String(descriptor.get("type", "input"))


func _call_persist() -> Dictionary:
	var value: Variant = _persist.call()
	if value is Dictionary:
		var result: Dictionary = (value as Dictionary).duplicate(true)
		if not result.has("ok"):
			result["ok"] = true
		if not result.has("code"):
			result["code"] = (
				"bindings_persisted"
				if bool(result.get("ok", false))
				else "bindings_persist_failed"
			)
		return result
	if typeof(value) == TYPE_BOOL:
		return (
			_success("bindings_persisted")
			if bool(value)
			else _error("bindings_persist_failed", "persist callback returned false")
		)
	if value == null:
		return _success("bindings_persisted")
	return _error(
		"invalid_persist_result",
		"persist callback must return Dictionary, bool, or null"
	)


func _build_controls() -> void:
	_clear_controls()
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 12)

	_action_label = Label.new()
	_action_label.name = "ActionLabel"
	_action_label.text = _display_name
	_action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_label)

	_binding_label = Label.new()
	_binding_label.name = "BindingLabel"
	_binding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_binding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_binding_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_binding_label)

	_rebind_button = Button.new()
	_rebind_button.name = "RebindButton"
	_rebind_button.text = String(_labels.get("rebind", "Rebind"))
	_rebind_button.focus_mode = Control.FOCUS_ALL
	_rebind_button.pressed.connect(_on_rebind_pressed)
	add_child(_rebind_button)

	_cancel_button = Button.new()
	_cancel_button.name = "CancelButton"
	_cancel_button.text = String(_labels.get("cancel", "Cancel"))
	_cancel_button.focus_mode = Control.FOCUS_ALL
	_cancel_button.pressed.connect(_on_cancel_pressed)
	add_child(_cancel_button)


func _clear_controls() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_action_label = null
	_binding_label = null
	_rebind_button = null
	_cancel_button = null


func _update_interaction_state() -> void:
	if _rebind_button != null:
		_rebind_button.disabled = not _enabled or _listening
	if _cancel_button != null:
		_cancel_button.visible = _listening
		_cancel_button.disabled = not _enabled


func _end_listening() -> void:
	_listening = false
	set_process_unhandled_input(false)
	_update_interaction_state()


func _on_rebind_pressed() -> void:
	start_listening()


func _on_cancel_pressed() -> void:
	cancel_listening()


func _ignored(reason: String) -> Dictionary:
	return _success(
		"input_ignored",
		{
			"accepted": false,
			"reason": reason,
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
