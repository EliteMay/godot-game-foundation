extends RefCounted

signal state_changed(snapshot: Dictionary)
signal action_requested(action_id: String)
signal action_completed(action_id: String, result: Dictionary)
signal action_failed(action_id: String, result: Dictionary)

const ACTION_RETRY: String = "retry"
const ACTION_MAIN_MENU: String = "main_menu"
const ACTION_SAFE_QUIT: String = "safe_quit"

var _runtime: Object = null
var _retry_action: Callable = Callable()
var _main_menu_action: Callable = Callable()
var _safe_quit_action: Callable = Callable()
var _action_in_progress: bool = false
var _last_action_result: Dictionary = {}


func configure(options: Dictionary) -> Dictionary:
	var runtime_variant: Variant = options.get("runtime")
	if not (runtime_variant is Object):
		return _error(
			"invalid_runtime",
			"runtime must be an Object"
		)

	var runtime: Object = runtime_variant as Object
	for method_name in [
		"runtime_failure_state",
		"initialize",
		"request_quit",
	]:
		if not runtime.has_method(method_name):
			return _error(
				"invalid_runtime",
				"runtime is missing a required recovery method",
				{"method": method_name}
			)

	var retry_result: Dictionary = _read_optional_callable(
		options,
		"retry_action"
	)
	if not bool(retry_result.get("ok", false)):
		return retry_result

	var main_menu_result: Dictionary = _read_optional_callable(
		options,
		"main_menu_action"
	)
	if not bool(main_menu_result.get("ok", false)):
		return main_menu_result

	var quit_result: Dictionary = _read_optional_callable(
		options,
		"safe_quit_action"
	)
	if not bool(quit_result.get("ok", false)):
		return quit_result

	_runtime = runtime
	_retry_action = retry_result.get("callable", Callable()) as Callable
	_main_menu_action = (
		main_menu_result.get("callable", Callable()) as Callable
	)
	_safe_quit_action = (
		quit_result.get("callable", Callable()) as Callable
	)
	_action_in_progress = false
	_last_action_result = {}

	var snapshot: Dictionary = state_snapshot()
	state_changed.emit(snapshot.duplicate(true))
	return _success(
		"recovery_screen_contract_configured",
		{"state": snapshot}
	)


func refresh() -> Dictionary:
	if not is_instance_valid(_runtime):
		return _error(
			"recovery_contract_not_configured",
			"recovery contract has no valid runtime"
		)
	var snapshot: Dictionary = state_snapshot()
	state_changed.emit(snapshot.duplicate(true))
	return _success(
		"recovery_screen_state_refreshed",
		{"state": snapshot}
	)


func perform_action(action_id: String) -> Dictionary:
	if not is_instance_valid(_runtime):
		return _error(
			"recovery_contract_not_configured",
			"recovery contract has no valid runtime"
		)
	if _action_in_progress:
		return _error(
			"recovery_action_in_progress",
			"another recovery action is already running"
		)

	var normalized_action: String = action_id.strip_edges()
	if normalized_action not in [
		ACTION_RETRY,
		ACTION_MAIN_MENU,
		ACTION_SAFE_QUIT,
	]:
		return _error(
			"unknown_recovery_action",
			"recovery action is not supported",
			{"action_id": normalized_action}
		)

	var snapshot_before: Dictionary = state_snapshot()
	if not bool(snapshot_before.get("active", false)):
		return _error(
			"no_active_runtime_failure",
			"there is no active runtime failure to recover from"
		)

	var actions: Dictionary = (
		snapshot_before.get("actions", {}) as Dictionary
	)
	if not bool(actions.get(normalized_action, false)):
		return _error(
			"recovery_action_unavailable",
			"recovery action is not available for the current failure",
			{"action_id": normalized_action}
		)

	_action_in_progress = true
	action_requested.emit(normalized_action)

	var value: Variant = null
	match normalized_action:
		ACTION_RETRY:
			value = (
				_retry_action.call()
				if _retry_action.is_valid()
				else _runtime.call("initialize")
			)
		ACTION_MAIN_MENU:
			value = _perform_main_menu()
		ACTION_SAFE_QUIT:
			value = (
				_safe_quit_action.call()
				if _safe_quit_action.is_valid()
				else _runtime.call("request_quit", 1)
			)

	var result: Dictionary = _normalize_action_result(
		normalized_action,
		value
	)
	_action_in_progress = false
	_last_action_result = result.duplicate(true)

	if bool(result.get("ok", false)):
		action_completed.emit(
			normalized_action,
			result.duplicate(true)
		)
	else:
		action_failed.emit(
			normalized_action,
			result.duplicate(true)
		)

	state_changed.emit(state_snapshot().duplicate(true))
	return result


func state_snapshot() -> Dictionary:
	var failure: Dictionary = _failure_state()
	var active: bool = bool(failure.get("active", false))
	var retry_available: bool = (
		active
		and bool(failure.get("retry_supported", false))
	)
	var main_menu_available: bool = (
		active
		and _main_menu_available()
	)
	var safe_quit_available: bool = (
		active
		and (
			_safe_quit_action.is_valid()
			or (
				is_instance_valid(_runtime)
				and _runtime.has_method("request_quit")
			)
		)
	)

	return {
		"configured": is_instance_valid(_runtime),
		"active": active,
		"failure": failure,
		"actions": {
			ACTION_RETRY: retry_available,
			ACTION_MAIN_MENU: main_menu_available,
			ACTION_SAFE_QUIT: safe_quit_available,
		},
		"action_in_progress": _action_in_progress,
		"last_action_result": _last_action_result.duplicate(true),
	}


func _failure_state() -> Dictionary:
	if (
		not is_instance_valid(_runtime)
		or not _runtime.has_method("runtime_failure_state")
	):
		return {}
	var value: Variant = _runtime.call("runtime_failure_state")
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _main_menu_available() -> bool:
	if _main_menu_action.is_valid():
		return true
	var flow: Object = _flow_service()
	if not is_instance_valid(flow):
		return false
	if not flow.has_method("main_menu_id"):
		return false
	if not flow.has_method("go_to_main_menu"):
		return false
	return not String(flow.call("main_menu_id")).strip_edges().is_empty()


func _perform_main_menu() -> Variant:
	if _main_menu_action.is_valid():
		return _main_menu_action.call()
	var flow: Object = _flow_service()
	if not is_instance_valid(flow):
		return _error(
			"recovery_main_menu_unavailable",
			"main menu recovery action is unavailable"
		)
	return flow.call("go_to_main_menu")


func _flow_service() -> Object:
	if (
		not is_instance_valid(_runtime)
		or not _runtime.has_method("flow_service")
	):
		return null
	var value: Variant = _runtime.call("flow_service")
	if value is Object:
		return value as Object
	return null


func _read_optional_callable(
	options: Dictionary,
	key: String
) -> Dictionary:
	if not options.has(key):
		return _success(
			"optional_callable_not_configured",
			{"callable": Callable()}
		)
	var value: Variant = options.get(key)
	if typeof(value) != TYPE_CALLABLE:
		return _error(
			"invalid_recovery_action",
			key + " must be a Callable"
		)
	var action: Callable = value as Callable
	if not action.is_valid():
		return _error(
			"invalid_recovery_action",
			key + " Callable must be valid"
		)
	return _success(
		"optional_callable_configured",
		{"callable": action}
	)


func _normalize_action_result(
	action_id: String,
	value: Variant
) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		result = (value as Dictionary).duplicate(true)
		if not result.has("ok"):
			result["ok"] = true
		if not result.has("code"):
			result["code"] = (
				"recovery_action_completed"
				if bool(result.get("ok", false))
				else "recovery_action_failed"
			)
	elif typeof(value) == TYPE_BOOL:
		result = (
			_success("recovery_action_completed")
			if bool(value)
			else _error(
				"recovery_action_failed",
				"recovery action returned false"
			)
		)
	elif value == null:
		result = _success("recovery_action_completed")
	else:
		result = _success(
			"recovery_action_completed",
			{"value": value}
		)

	result["action_id"] = action_id
	return result


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
