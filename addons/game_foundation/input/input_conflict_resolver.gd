extends RefCounted

const InputSystem = preload(
	"res://addons/game_foundation/input/input_system.gd"
)

const POLICY_REJECT: String = "reject"
const POLICY_REPLACE: String = "replace"
const POLICY_ALLOW: String = "allow"


static func validate_policy(policy: String) -> Dictionary:
	if policy not in [POLICY_REJECT, POLICY_REPLACE, POLICY_ALLOW]:
		return _error(
			"invalid_conflict_policy",
			"conflict policy must be reject, replace, or allow",
			{"policy": policy}
		)
	return _success("valid_conflict_policy", {"policy": policy})


static func find_conflicts(
	contract: Dictionary,
	action_name: String,
	event_descriptor: Dictionary
) -> Dictionary:
	var contract_result: Dictionary = InputSystem.validate_contract(contract)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if not contract.has(action_name):
		return _error(
			"unknown_action",
			"action is not declared by the game input contract",
			{"action": action_name}
		)

	var descriptor_result: Dictionary = _canonical_descriptor(event_descriptor)
	if not bool(descriptor_result.get("ok", false)):
		return descriptor_result

	var descriptor: Dictionary = (
		(descriptor_result.get("descriptor", {}) as Dictionary).duplicate(true)
	)
	var bindings: Dictionary = InputSystem.capture_bindings(contract)
	var conflicts: Array = _find_conflicts_in_bindings(
		contract,
		bindings,
		action_name,
		descriptor
	)

	return _success(
		"conflicts_found" if not conflicts.is_empty() else "no_conflicts",
		{
			"action": action_name,
			"descriptor": descriptor,
			"conflicts": conflicts,
			"conflict_count": conflicts.size(),
		}
	)


static func rebind_with_policy(
	contract: Dictionary,
	action_name: String,
	event_descriptor: Dictionary,
	policy: String = POLICY_ALLOW,
	replace_all: bool = true
) -> Dictionary:
	var policy_result: Dictionary = validate_policy(policy)
	if not bool(policy_result.get("ok", false)):
		return policy_result

	var contract_result: Dictionary = InputSystem.validate_contract(contract)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if not contract.has(action_name):
		return _error(
			"unknown_action",
			"action is not declared by the game input contract",
			{"action": action_name}
		)

	var descriptor_result: Dictionary = _canonical_descriptor(event_descriptor)
	if not bool(descriptor_result.get("ok", false)):
		return descriptor_result
	var descriptor: Dictionary = (
		(descriptor_result.get("descriptor", {}) as Dictionary).duplicate(true)
	)

	var previous_bindings: Dictionary = InputSystem.capture_bindings(contract)
	var conflicts: Array = _find_conflicts_in_bindings(
		contract,
		previous_bindings,
		action_name,
		descriptor
	)

	if policy == POLICY_REJECT and not conflicts.is_empty():
		return _error(
			"binding_conflict",
			"input binding is already used by another action",
			{
				"action": action_name,
				"policy": policy,
				"descriptor": descriptor,
				"conflicts": conflicts,
				"conflict_count": conflicts.size(),
				"applied": false,
			}
		)

	if policy == POLICY_ALLOW:
		var rebind_result: Dictionary = InputSystem.rebind_action(
			contract,
			action_name,
			descriptor,
			replace_all
		)
		if not bool(rebind_result.get("ok", false)):
			return rebind_result
		return _decorate_result(
			rebind_result,
			action_name,
			descriptor,
			policy,
			conflicts,
			[]
		)

	var proposed: Dictionary = previous_bindings.duplicate(true)
	var displaced_actions: Array[String] = []

	for raw_action_name in contract.keys():
		var other_action: String = String(raw_action_name)
		if other_action == action_name:
			continue
		var definition_variant: Variant = proposed.get(other_action)
		if not (definition_variant is Dictionary):
			continue
		var definition: Dictionary = (definition_variant as Dictionary).duplicate(true)
		var events_variant: Variant = definition.get("events", [])
		if not (events_variant is Array):
			continue

		var filtered: Array = []
		var removed: bool = false
		for existing_variant in events_variant as Array:
			if not (existing_variant is Dictionary):
				filtered.append(existing_variant)
				continue
			var existing: Dictionary = existing_variant as Dictionary
			if _descriptors_overlap(descriptor, existing):
				removed = true
				continue
			filtered.append(existing.duplicate(true))

		if removed:
			definition["events"] = filtered
			proposed[other_action] = definition
			displaced_actions.append(other_action)

	var target_definition_variant: Variant = proposed.get(action_name)
	if not (target_definition_variant is Dictionary):
		return _error(
			"invalid_binding_state",
			"target action binding state is missing",
			{"action": action_name}
		)
	var target_definition: Dictionary = (
		(target_definition_variant as Dictionary).duplicate(true)
	)
	if replace_all:
		target_definition["events"] = [descriptor.duplicate(true)]
	else:
		var target_events: Array = (
			(target_definition.get("events", []) as Array).duplicate(true)
		)
		var already_present: bool = false
		for existing_variant in target_events:
			if (
				existing_variant is Dictionary
				and _descriptors_overlap(
					descriptor,
					existing_variant as Dictionary
				)
			):
				already_present = true
				break
		if not already_present:
			target_events.append(descriptor.duplicate(true))
		target_definition["events"] = target_events
	proposed[action_name] = target_definition

	var apply_result: Dictionary = InputSystem.apply_bindings(contract, proposed)
	if not bool(apply_result.get("ok", false)):
		var rollback_result: Dictionary = InputSystem.apply_bindings(
			contract,
			previous_bindings
		)
		return _error(
			"conflict_replace_failed",
			"failed to apply replacement binding",
			{
				"action": action_name,
				"policy": policy,
				"apply_result": apply_result,
				"rollback_result": rollback_result,
			}
		)

	return _decorate_result(
		apply_result,
		action_name,
		descriptor,
		policy,
		conflicts,
		displaced_actions
	)


static func descriptors_conflict(
	first: Dictionary,
	second: Dictionary
) -> Dictionary:
	var first_result: Dictionary = _canonical_descriptor(first)
	if not bool(first_result.get("ok", false)):
		return first_result
	var second_result: Dictionary = _canonical_descriptor(second)
	if not bool(second_result.get("ok", false)):
		return second_result

	var first_descriptor: Dictionary = first_result.get("descriptor", {})
	var second_descriptor: Dictionary = second_result.get("descriptor", {})
	return _success(
		"descriptor_comparison",
		{
			"conflict": _descriptors_overlap(
				first_descriptor,
				second_descriptor
			),
			"first": first_descriptor.duplicate(true),
			"second": second_descriptor.duplicate(true),
		}
	)


static func _find_conflicts_in_bindings(
	contract: Dictionary,
	bindings: Dictionary,
	action_name: String,
	descriptor: Dictionary
) -> Array:
	var conflicts: Array = []
	for raw_action_name in contract.keys():
		var other_action: String = String(raw_action_name)
		if other_action == action_name:
			continue
		var definition_variant: Variant = bindings.get(other_action)
		if not (definition_variant is Dictionary):
			continue
		var events_variant: Variant = (
			(definition_variant as Dictionary).get("events", [])
		)
		if not (events_variant is Array):
			continue

		var event_index: int = 0
		for existing_variant in events_variant as Array:
			if existing_variant is Dictionary:
				var existing: Dictionary = existing_variant as Dictionary
				if _descriptors_overlap(descriptor, existing):
					conflicts.append(
						{
							"action": other_action,
							"event_index": event_index,
							"descriptor": existing.duplicate(true),
						}
					)
			event_index += 1
	return conflicts


static func _descriptors_overlap(
	first_raw: Dictionary,
	second_raw: Dictionary
) -> bool:
	var first_result: Dictionary = _canonical_descriptor(first_raw)
	var second_result: Dictionary = _canonical_descriptor(second_raw)
	if not bool(first_result.get("ok", false)) or not bool(second_result.get("ok", false)):
		return false

	var first: Dictionary = first_result.get("descriptor", {})
	var second: Dictionary = second_result.get("descriptor", {})
	var first_type: String = String(first.get("type", ""))
	var second_type: String = String(second.get("type", ""))
	if first_type != second_type:
		return false

	match first_type:
		"key":
			return (
				int(first.get("keycode", 0)) == int(second.get("keycode", 0))
				and int(first.get("physical_keycode", 0)) == int(second.get("physical_keycode", 0))
				and int(first.get("unicode", 0)) == int(second.get("unicode", 0))
				and _modifiers_match(first, second)
			)
		"mouse_button":
			return (
				int(first.get("button_index", 0)) == int(second.get("button_index", 0))
				and _modifiers_match(first, second)
			)
		"joypad_button":
			return (
				int(first.get("button_index", -1)) == int(second.get("button_index", -2))
				and _devices_overlap(
					int(first.get("device", -1)),
					int(second.get("device", -1))
				)
			)
		"joypad_motion":
			return (
				int(first.get("axis", -1)) == int(second.get("axis", -2))
				and _axis_direction(float(first.get("axis_value", 0.0)))
					== _axis_direction(float(second.get("axis_value", 0.0)))
				and _devices_overlap(
					int(first.get("device", -1)),
					int(second.get("device", -1))
				)
			)
	return false


static func _canonical_descriptor(descriptor: Dictionary) -> Dictionary:
	var result: Dictionary = InputSystem.event_from_descriptor(descriptor)
	if not bool(result.get("ok", false)):
		return result
	var normalized_variant: Variant = result.get("descriptor", {})
	if not (normalized_variant is Dictionary):
		return _error(
			"invalid_event_descriptor",
			"input system did not return a normalized descriptor"
		)
	return _success(
		"descriptor_canonicalized",
		{"descriptor": (normalized_variant as Dictionary).duplicate(true)}
	)


static func _modifiers_match(first: Dictionary, second: Dictionary) -> bool:
	return (
		bool(first.get("shift", false)) == bool(second.get("shift", false))
		and bool(first.get("ctrl", false)) == bool(second.get("ctrl", false))
		and bool(first.get("alt", false)) == bool(second.get("alt", false))
		and bool(first.get("meta", false)) == bool(second.get("meta", false))
	)


static func _devices_overlap(first: int, second: int) -> bool:
	return first == -1 or second == -1 or first == second


static func _axis_direction(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0


static func _decorate_result(
	base: Dictionary,
	action_name: String,
	descriptor: Dictionary,
	policy: String,
	conflicts: Array,
	displaced_actions: Array[String]
) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	result["ok"] = true
	result["code"] = "binding_rebound"
	result["action"] = action_name
	result["descriptor"] = descriptor.duplicate(true)
	result["policy"] = policy
	result["conflicts"] = conflicts.duplicate(true)
	result["conflict_count"] = conflicts.size()
	result["displaced_actions"] = displaced_actions.duplicate()
	result["applied"] = true
	return result


static func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "code": code}
	for key in extra:
		result[key] = extra[key]
	return result


static func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": false, "code": code, "message": message}
	for key in extra:
		result[key] = extra[key]
	return result
