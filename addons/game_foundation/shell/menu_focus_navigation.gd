extends RefCounted

static func configure_vertical(
	controls: Array,
	wrap: bool = false
) -> Dictionary:
	var validated: Array[Control] = []
	for value in controls:
		if not (value is Control):
			return _error(
				"invalid_focus_control",
				"focus navigation requires Control entries"
			)
		var control: Control = value as Control
		_clear_vertical_links(control)
		validated.append(control)

	var focusable: Array[Control] = []
	for control in validated:
		if is_focusable(control):
			focusable.append(control)

	for index in range(focusable.size()):
		var current: Control = focusable[index]
		var previous: Control = null
		var next: Control = null

		if index > 0:
			previous = focusable[index - 1]
		elif wrap and focusable.size() > 1:
			previous = focusable[focusable.size() - 1]

		if index + 1 < focusable.size():
			next = focusable[index + 1]
		elif wrap and focusable.size() > 1:
			next = focusable[0]

		if is_instance_valid(previous):
			var previous_path: NodePath = current.get_path_to(previous)
			current.focus_neighbor_top = previous_path
			current.focus_previous = previous_path

		if is_instance_valid(next):
			var next_path: NodePath = current.get_path_to(next)
			current.focus_neighbor_bottom = next_path
			current.focus_next = next_path

	return _success(
		"focus_navigation_configured",
		{
			"control_count": validated.size(),
			"focusable_count": focusable.size(),
			"wrap": wrap,
		}
	)


static func is_focusable(control: Control) -> bool:
	if not is_instance_valid(control):
		return false
	if not control.visible:
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true


static func focus_first(controls: Array) -> Dictionary:
	for value in controls:
		if not (value is Control):
			return _error(
				"invalid_focus_control",
				"focus navigation requires Control entries"
			)
		var control: Control = value as Control
		if is_focusable(control):
			control.grab_focus()
			return _success(
				"focus_assigned",
				{"control_path": String(control.get_path())}
			)

	return _error(
		"no_focusable_control",
		"no visible enabled focusable Control is available"
	)


static func _clear_vertical_links(control: Control) -> void:
	control.focus_neighbor_top = NodePath("")
	control.focus_neighbor_bottom = NodePath("")
	control.focus_previous = NodePath("")
	control.focus_next = NodePath("")


static func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"code": code,
	}
	for key in extra:
		result[key] = extra[key]
	return result


static func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
