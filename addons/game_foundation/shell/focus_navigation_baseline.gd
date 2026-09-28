extends RefCounted

const MenuFocusNavigation = preload(
	"res://addons/game_foundation/shell/menu_focus_navigation.gd"
)

static func required_ui_actions() -> PackedStringArray:
	return PackedStringArray([
		"ui_up",
		"ui_down",
		"ui_accept",
	])


static func validate_input_actions(
	options: Dictionary = {}
) -> Dictionary:
	var required_actions: PackedStringArray = PackedStringArray(
		options.get("required_actions", required_ui_actions())
	)
	var require_keyboard: bool = bool(
		options.get("require_keyboard", true)
	)
	var require_gamepad: bool = bool(
		options.get("require_gamepad", true)
	)
	var coverage: Dictionary = {}
	var missing_actions: Array[String] = []
	var missing_keyboard: Array[String] = []
	var missing_gamepad: Array[String] = []

	for action_name in required_actions:
		if not InputMap.has_action(action_name):
			missing_actions.append(action_name)
			coverage[action_name] = {
				"exists": false,
				"keyboard": false,
				"gamepad": false,
			}
			continue

		var has_keyboard: bool = false
		var has_gamepad: bool = false
		for event in InputMap.action_get_events(action_name):
			if event is InputEventKey:
				has_keyboard = true
			elif (
				event is InputEventJoypadButton
				or event is InputEventJoypadMotion
			):
				has_gamepad = true

		coverage[action_name] = {
			"exists": true,
			"keyboard": has_keyboard,
			"gamepad": has_gamepad,
		}

		if require_keyboard and not has_keyboard:
			missing_keyboard.append(action_name)
		if require_gamepad and not has_gamepad:
			missing_gamepad.append(action_name)

	var ok: bool = (
		missing_actions.is_empty()
		and missing_keyboard.is_empty()
		and missing_gamepad.is_empty()
	)
	if not ok:
		return _error(
			"focus_navigation_input_incomplete",
			"required semantic UI actions or device bindings are missing",
			{
				"coverage": coverage,
				"missing_actions": missing_actions,
				"missing_keyboard": missing_keyboard,
				"missing_gamepad": missing_gamepad,
			}
		)

	return _success(
		"focus_navigation_input_ready",
		{
			"coverage": coverage,
			"required_actions": Array(required_actions),
		}
	)


static func configure_vertical(
	controls: Array,
	wrap: bool = false
) -> Dictionary:
	var input_result: Dictionary = validate_input_actions()
	if not bool(input_result.get("ok", false)):
		return input_result

	var navigation_result: Dictionary = (
		MenuFocusNavigation.configure_vertical(controls, wrap)
	)
	if not bool(navigation_result.get("ok", false)):
		return navigation_result

	return _success(
		"focus_navigation_baseline_configured",
		{
			"navigation": navigation_result,
			"input": input_result,
		}
	)


static func focus_first(controls: Array) -> Dictionary:
	var input_result: Dictionary = validate_input_actions()
	if not bool(input_result.get("ok", false)):
		return input_result

	var focus_result: Dictionary = MenuFocusNavigation.focus_first(controls)
	if not bool(focus_result.get("ok", false)):
		return focus_result

	return _success(
		"focus_navigation_initial_focus_assigned",
		{
			"focus": focus_result,
			"input": input_result,
		}
	)


static func repair_focus(
	controls: Array,
	options: Dictionary = {}
) -> Dictionary:
	var validated: Dictionary = _validated_controls(controls)
	if not bool(validated.get("ok", false)):
		return validated

	var control_list: Array = validated.get("controls", [])
	var focusable: Array = validated.get("focusable", [])
	if focusable.is_empty():
		return _error(
			"no_focusable_control",
			"no visible enabled focusable Control is available"
		)

	var preserve_external_focus: bool = bool(
		options.get("preserve_external_focus", true)
	)
	var preferred: Control = null
	var preferred_variant: Variant = options.get("preferred")
	if preferred_variant is Control:
		preferred = preferred_variant as Control

	var first_focusable: Control = focusable[0] as Control
	var viewport: Viewport = first_focusable.get_viewport()
	var owner: Control = viewport.gui_get_focus_owner()
	if is_instance_valid(owner):
		for control in focusable:
			if owner == control:
				return _success(
					"focus_navigation_focus_valid",
					{"control_path": String(owner.get_path())}
				)

		if preserve_external_focus:
			var belongs_to_controls: bool = false
			for control in control_list:
				if owner == control or control.is_ancestor_of(owner):
					belongs_to_controls = true
					break
			if not belongs_to_controls:
				return _success(
					"focus_navigation_external_focus_preserved",
					{"control_path": String(owner.get_path())}
				)

	if (
		is_instance_valid(preferred)
		and focusable.has(preferred)
	):
		preferred.grab_focus()
		return _success(
			"focus_navigation_focus_repaired",
			{
				"control_path": String(preferred.get_path()),
				"strategy": "preferred",
			}
		)

	var focus_result: Dictionary = MenuFocusNavigation.focus_first(controls)
	if not bool(focus_result.get("ok", false)):
		return focus_result

	return _success(
		"focus_navigation_focus_repaired",
		{
			"control_path": String(
				focus_result.get("control_path", "")
			),
			"strategy": "first_focusable",
		}
	)


static func snapshot(controls: Array) -> Dictionary:
	var validated: Dictionary = _validated_controls(controls)
	if not bool(validated.get("ok", false)):
		return validated

	var control_list: Array = validated.get("controls", [])
	var focusable: Array = validated.get("focusable", [])
	var input_result: Dictionary = validate_input_actions()

	var focusable_paths: Array[String] = []
	for control in focusable:
		focusable_paths.append(String(control.get_path()))

	var focused_path: String = ""
	if not control_list.is_empty():
		var first_control: Control = control_list[0] as Control
		var owner: Control = first_control.get_viewport().gui_get_focus_owner()
		if is_instance_valid(owner):
			focused_path = String(owner.get_path())

	return _success(
		"focus_navigation_snapshot",
		{
			"control_count": control_list.size(),
			"focusable_count": focusable.size(),
			"focusable_paths": focusable_paths,
			"focused_path": focused_path,
			"input_ready": bool(input_result.get("ok", false)),
			"input": input_result,
		}
	)


static func is_focusable(control: Control) -> bool:
	return MenuFocusNavigation.is_focusable(control)


static func _validated_controls(controls: Array) -> Dictionary:
	var validated: Array[Control] = []
	var focusable: Array[Control] = []
	for value in controls:
		if not (value is Control):
			return _error(
				"invalid_focus_control",
				"focus navigation requires Control entries"
			)
		var control: Control = value as Control
		validated.append(control)
		if is_focusable(control):
			focusable.append(control)

	return _success(
		"focus_controls_valid",
		{
			"controls": validated,
			"focusable": focusable,
		}
	)


static func _success(
	code: String,
	extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"code": code,
	}
	for key in extra:
		result[key] = extra[key]
	return result


static func _error(
	code: String,
	message: String,
	extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"code": code,
		"message": message,
	}
	for key in extra:
		result[key] = extra[key]
	return result
