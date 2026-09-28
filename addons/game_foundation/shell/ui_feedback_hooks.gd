extends RefCounted

signal motion_changed(motion_scale: float, reduced_motion: bool)
signal feedback_requested(event_id: String, context: Dictionary)
signal feedback_completed(event_id: String, result: Dictionary)
signal feedback_skipped(event_id: String, reason: String, context: Dictionary)

const EVENT_FOCUS: String = "focus"
const EVENT_ACTIVATE: String = "activate"
const EVENT_OPEN: String = "open"
const EVENT_CLOSE: String = "close"

var _motion_scale: float = 1.0
var _feedback_enabled: bool = true
var _feedback_action: Callable = Callable()
var _motion_targets: Array = []


func configure(options: Dictionary = {}) -> Dictionary:
	if options.has("motion_scale") and options.has("reduced_motion"):
		return _error(
			"ambiguous_motion_configuration",
			"use either motion_scale or reduced_motion, not both"
		)

	if options.has("feedback_enabled"):
		if typeof(options.get("feedback_enabled")) != TYPE_BOOL:
			return _error(
				"invalid_feedback_enabled",
				"feedback_enabled must be bool"
			)

	if options.has("feedback_action"):
		var action_variant: Variant = options.get("feedback_action")
		if typeof(action_variant) != TYPE_CALLABLE:
			return _error(
				"invalid_feedback_action",
				"feedback_action must be Callable"
			)
		var action: Callable = action_variant as Callable
		if not action.is_valid():
			return _error(
				"invalid_feedback_action",
				"feedback_action Callable must be valid"
			)

	var targets: Array = []
	if options.has("motion_targets"):
		var targets_variant: Variant = options.get("motion_targets")
		if not (targets_variant is Array):
			return _error(
				"invalid_motion_targets",
				"motion_targets must be an Array"
			)
		targets = targets_variant as Array
		for target in targets:
			var target_result: Dictionary = _validate_motion_target(target)
			if not bool(target_result.get("ok", false)):
				return target_result

	var requested_scale: float = _motion_scale
	if options.has("motion_scale"):
		var scale_result: Dictionary = _normalize_motion_scale(
			options.get("motion_scale")
		)
		if not bool(scale_result.get("ok", false)):
			return scale_result
		requested_scale = float(scale_result.get("motion_scale", 1.0))
	elif options.has("reduced_motion"):
		var reduced_variant: Variant = options.get("reduced_motion")
		if typeof(reduced_variant) != TYPE_BOOL:
			return _error(
				"invalid_reduced_motion",
				"reduced_motion must be bool"
			)
		requested_scale = 0.0 if bool(reduced_variant) else 1.0

	if options.has("feedback_action"):
		_feedback_action = options.get("feedback_action") as Callable
	if options.has("feedback_enabled"):
		_feedback_enabled = bool(options.get("feedback_enabled"))

	for target in targets:
		var register_result: Dictionary = register_motion_target(
			target as Object
		)
		if not bool(register_result.get("ok", false)):
			return register_result

	var motion_result: Dictionary = set_motion_scale(requested_scale)
	if not bool(motion_result.get("ok", false)):
		return motion_result

	return _success(
		"ui_feedback_hooks_configured",
		{"state": state_snapshot()}
	)


func set_motion_scale(value: Variant) -> Dictionary:
	var normalized: Dictionary = _normalize_motion_scale(value)
	if not bool(normalized.get("ok", false)):
		return normalized

	var next_scale: float = float(normalized.get("motion_scale", 1.0))
	var previous_scale: float = _motion_scale
	var applied_targets: Array = []
	_prune_motion_targets()

	for target in _motion_targets:
		var apply_result: Dictionary = _apply_motion_scale(
			target as Object,
			next_scale
		)
		if not bool(apply_result.get("ok", false)):
			for applied_target in applied_targets:
				_apply_motion_scale(
					applied_target as Object,
					previous_scale
				)
			return _error(
				"motion_target_apply_failed",
				"motion preference could not be applied to every target",
				{
					"target": _target_label(target as Object),
					"cause": apply_result,
					"motion_scale": previous_scale,
				}
			)
		applied_targets.append(target)

	_motion_scale = next_scale
	motion_changed.emit(
		_motion_scale,
		is_zero_approx(_motion_scale)
	)
	return _success(
		"motion_scale_changed",
		{"state": state_snapshot()}
	)


func set_reduced_motion(enabled: bool) -> Dictionary:
	return set_motion_scale(0.0 if enabled else 1.0)


func set_feedback_enabled(enabled: bool) -> Dictionary:
	_feedback_enabled = enabled
	return _success(
		"feedback_enabled_changed",
		{"state": state_snapshot()}
	)


func set_feedback_action(action_variant: Variant) -> Dictionary:
	if typeof(action_variant) != TYPE_CALLABLE:
		return _error(
			"invalid_feedback_action",
			"feedback_action must be Callable"
		)
	var action: Callable = action_variant as Callable
	if not action.is_valid():
		return _error(
			"invalid_feedback_action",
			"feedback_action Callable must be valid"
		)
	_feedback_action = action
	return _success(
		"feedback_action_changed",
		{"state": state_snapshot()}
	)


func clear_feedback_action() -> Dictionary:
	_feedback_action = Callable()
	return _success(
		"feedback_action_cleared",
		{"state": state_snapshot()}
	)


func register_motion_target(target: Object) -> Dictionary:
	var validation: Dictionary = _validate_motion_target(target)
	if not bool(validation.get("ok", false)):
		return validation

	_prune_motion_targets()
	for existing in _motion_targets:
		if existing == target:
			return _success(
				"motion_target_already_registered",
				{
					"target": _target_label(target),
					"state": state_snapshot(),
				}
			)

	var apply_result: Dictionary = _apply_motion_scale(
		target,
		_motion_scale
	)
	if not bool(apply_result.get("ok", false)):
		return apply_result

	_motion_targets.append(target)
	return _success(
		"motion_target_registered",
		{
			"target": _target_label(target),
			"state": state_snapshot(),
		}
	)


func unregister_motion_target(target: Object) -> Dictionary:
	_prune_motion_targets()
	for index in range(_motion_targets.size() - 1, -1, -1):
		if _motion_targets[index] == target:
			_motion_targets.remove_at(index)
			return _success(
				"motion_target_unregistered",
				{
					"target": _target_label(target),
					"state": state_snapshot(),
				}
			)
	return _success(
		"motion_target_not_registered",
		{"state": state_snapshot()}
	)


func request_feedback(
	event_id: String,
	context: Dictionary = {}
) -> Dictionary:
	var normalized_event: String = event_id.strip_edges()
	if normalized_event.is_empty():
		return _error(
			"invalid_feedback_event",
			"feedback event id must not be empty"
		)

	var safe_context: Dictionary = context.duplicate(true)
	if not _feedback_enabled:
		feedback_skipped.emit(
			normalized_event,
			"disabled",
			safe_context.duplicate(true)
		)
		return _success(
			"feedback_skipped",
			{
				"event_id": normalized_event,
				"reason": "disabled",
			}
		)

	if not _feedback_action.is_valid():
		feedback_skipped.emit(
			normalized_event,
			"no_handler",
			safe_context.duplicate(true)
		)
		return _success(
			"feedback_skipped",
			{
				"event_id": normalized_event,
				"reason": "no_handler",
			}
		)

	feedback_requested.emit(
		normalized_event,
		safe_context.duplicate(true)
	)
	var value: Variant = _feedback_action.call(
		normalized_event,
		safe_context.duplicate(true)
	)
	var result: Dictionary = _normalize_feedback_result(
		normalized_event,
		value
	)
	feedback_completed.emit(
		normalized_event,
		result.duplicate(true)
	)
	return result


func state_snapshot() -> Dictionary:
	_prune_motion_targets()
	return {
		"motion_scale": _motion_scale,
		"reduced_motion": is_zero_approx(_motion_scale),
		"feedback_enabled": _feedback_enabled,
		"feedback_action_configured": _feedback_action.is_valid(),
		"motion_target_count": _motion_targets.size(),
	}


func _validate_motion_target(target_variant: Variant) -> Dictionary:
	if not (target_variant is Object):
		return _error(
			"invalid_motion_target",
			"motion target must be an Object"
		)
	var target: Object = target_variant as Object
	if not is_instance_valid(target):
		return _error(
			"invalid_motion_target",
			"motion target must be valid"
		)
	if not target.has_method("set_motion_scale"):
		return _error(
			"invalid_motion_target",
			"motion target must implement set_motion_scale(value)"
		)
	return _success("motion_target_valid")


func _apply_motion_scale(
	target: Object,
	value: float
) -> Dictionary:
	if not is_instance_valid(target):
		return _error(
			"invalid_motion_target",
			"motion target is no longer valid"
		)
	var result_variant: Variant = target.call(
		"set_motion_scale",
		value
	)
	if result_variant is Dictionary:
		var result: Dictionary = (
			result_variant as Dictionary
		).duplicate(true)
		if bool(result.get("ok", false)):
			return result
		return _error(
			"motion_target_rejected",
			"motion target rejected motion_scale",
			{"result": result}
		)
	if result_variant is bool and not bool(result_variant):
		return _error(
			"motion_target_rejected",
			"motion target rejected motion_scale"
		)
	return _success("motion_target_applied")


func _normalize_motion_scale(value: Variant) -> Dictionary:
	if not _is_number(value):
		return _error(
			"invalid_motion_scale",
			"motion_scale must be numeric"
		)
	var scale: float = float(value)
	if scale < 0.0 or scale > 1.0:
		return _error(
			"invalid_motion_scale",
			"motion_scale must be between 0.0 and 1.0"
		)
	return _success(
		"motion_scale_valid",
		{"motion_scale": scale}
	)


func _normalize_feedback_result(
	event_id: String,
	value: Variant
) -> Dictionary:
	if value is Dictionary:
		var result: Dictionary = (
			value as Dictionary
		).duplicate(true)
		if not result.has("ok"):
			result["ok"] = true
		if not result.has("code"):
			result["code"] = (
				"feedback_handled"
				if bool(result.get("ok", false))
				else "feedback_failed"
			)
		result["event_id"] = event_id
		return result

	if value is bool:
		if bool(value):
			return _success(
				"feedback_handled",
				{"event_id": event_id}
			)
		return _error(
			"feedback_failed",
			"feedback handler returned false",
			{"event_id": event_id}
		)

	return _success(
		"feedback_handled",
		{
			"event_id": event_id,
			"value": value,
		}
	)


func _prune_motion_targets() -> void:
	for index in range(_motion_targets.size() - 1, -1, -1):
		var target_variant: Variant = _motion_targets[index]
		if (
			not (target_variant is Object)
			or not is_instance_valid(target_variant as Object)
		):
			_motion_targets.remove_at(index)


func _target_label(target: Object) -> String:
	if target is Node:
		var node: Node = target as Node
		if node.is_inside_tree():
			return String(node.get_path())
		return node.name
	return target.get_class()


func _is_number(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		or typeof(value) == TYPE_FLOAT
	)


func _success(
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


func _error(
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
