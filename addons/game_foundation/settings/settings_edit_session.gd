extends RefCounted

signal draft_changed(settings: Dictionary)
signal applied(result: Dictionary)
signal canceled(result: Dictionary)
signal reset(result: Dictionary)

const SettingsSystem = preload(
	"res://addons/game_foundation/settings/settings_system.gd"
)

var _configured: bool = false
var _active: bool = false
var _gameplay_defaults: Dictionary = {}
var _baseline_settings: Dictionary = {}
var _draft_settings: Dictionary = {}
var _runtime_preview_settings: Dictionary = {}
var _preview_apply: Callable = Callable()
var _persist: Callable = Callable()


func configure(
	initial_settings: Dictionary,
	gameplay_defaults: Dictionary = {},
	preview_apply: Callable = Callable(),
	persist: Callable = Callable()
) -> Dictionary:
	if _active:
		return _error(
			"session_active",
			"active settings edit session must be canceled before reconfigure"
		)
	if not preview_apply.is_valid():
		return _error(
			"preview_apply_missing",
			"settings edit session requires a runtime preview callable"
		)
	if not persist.is_valid():
		return _error(
			"persist_missing",
			"settings edit session requires a persistence callable"
		)

	var normalized_result: Dictionary = SettingsSystem.normalize_settings(
		initial_settings,
		gameplay_defaults
	)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	_gameplay_defaults = gameplay_defaults.duplicate(true)
	_baseline_settings = (
		(normalized_result.get("settings", {}) as Dictionary).duplicate(true)
	)
	_draft_settings = _baseline_settings.duplicate(true)
	_runtime_preview_settings = _baseline_settings.duplicate(true)
	_preview_apply = preview_apply
	_persist = persist
	_configured = true
	_active = true

	return _success(
		"session_started",
		{
			"settings": _draft_settings.duplicate(true),
			"has_changes": false,
		}
	)


func is_active() -> bool:
	return _active


func has_changes() -> bool:
	return _configured and _draft_settings != _baseline_settings


func baseline_settings() -> Dictionary:
	return _baseline_settings.duplicate(true)


func draft_settings() -> Dictionary:
	return _draft_settings.duplicate(true)


func state_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"active": _active,
		"has_changes": has_changes(),
		"baseline": _baseline_settings.duplicate(true),
		"draft": _draft_settings.duplicate(true),
		"runtime_preview": _runtime_preview_settings.duplicate(true),
	}


func set_draft(
	candidate: Dictionary,
	apply_runtime: bool = true
) -> Dictionary:
	if not _active:
		return _error("session_inactive", "settings edit session is not active")

	var normalized_result: Dictionary = SettingsSystem.normalize_settings(
		candidate,
		_gameplay_defaults
	)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	var normalized: Dictionary = (
		(normalized_result.get("settings", {}) as Dictionary).duplicate(true)
	)
	if apply_runtime and normalized != _runtime_preview_settings:
		var preview_result: Dictionary = _apply_preview_with_rollback(normalized)
		if not bool(preview_result.get("ok", false)):
			return preview_result

	_draft_settings = normalized
	draft_changed.emit(_draft_settings.duplicate(true))

	return _success(
		"draft_updated",
		{
			"settings": _draft_settings.duplicate(true),
			"has_changes": has_changes(),
			"runtime_previewed": apply_runtime,
			"warnings": normalized_result.get("warnings", []),
		}
	)


func reset_to_defaults(apply_runtime: bool = true) -> Dictionary:
	if not _active:
		return _error("session_inactive", "settings edit session is not active")

	var defaults: Dictionary = SettingsSystem.default_settings(_gameplay_defaults)
	var result: Dictionary = set_draft(defaults, apply_runtime)
	if not bool(result.get("ok", false)):
		return result

	result["code"] = "draft_reset"
	reset.emit(result.duplicate(true))
	return result


func apply() -> Dictionary:
	if not _active:
		return _error("session_inactive", "settings edit session is not active")

	if _draft_settings != _runtime_preview_settings:
		var preview_result: Dictionary = _apply_preview_with_rollback(_draft_settings)
		if not bool(preview_result.get("ok", false)):
			return preview_result

	var persist_result: Dictionary = _call_settings_callback(
		_persist,
		_draft_settings,
		"settings_persisted",
		"settings_persist_failed"
	)
	if not bool(persist_result.get("ok", false)):
		return _error(
			"apply_persist_failed",
			"settings draft could not be persisted",
			{
				"persist_result": persist_result,
				"settings": _draft_settings.duplicate(true),
			}
		)

	var committed: Dictionary = _draft_settings.duplicate(true)
	var persisted_settings_variant: Variant = persist_result.get("settings")
	if persisted_settings_variant is Dictionary:
		var normalized_persisted: Dictionary = SettingsSystem.normalize_settings(
			persisted_settings_variant as Dictionary,
			_gameplay_defaults
		)
		if bool(normalized_persisted.get("ok", false)):
			committed = (
				(normalized_persisted.get("settings", {}) as Dictionary).duplicate(true)
			)

	_baseline_settings = committed.duplicate(true)
	_draft_settings = committed.duplicate(true)
	_runtime_preview_settings = committed.duplicate(true)

	var result: Dictionary = _success(
		"applied",
		{
			"settings": committed.duplicate(true),
			"persist_result": persist_result,
			"has_changes": false,
		}
	)
	applied.emit(result.duplicate(true))
	return result


func cancel() -> Dictionary:
	if not _active:
		return _error("session_inactive", "settings edit session is not active")

	if _runtime_preview_settings != _baseline_settings:
		var restore_result: Dictionary = _call_settings_callback(
			_preview_apply,
			_baseline_settings,
			"runtime_restored",
			"runtime_restore_failed"
		)
		if not bool(restore_result.get("ok", false)):
			return _error(
				"cancel_restore_failed",
				"runtime settings could not be restored to the session baseline",
				{"restore_result": restore_result}
			)
		_runtime_preview_settings = _baseline_settings.duplicate(true)

	_draft_settings = _baseline_settings.duplicate(true)
	_active = false
	var result: Dictionary = _success(
		"canceled",
		{"settings": _baseline_settings.duplicate(true)}
	)
	canceled.emit(result.duplicate(true))
	return result


func _apply_preview_with_rollback(settings: Dictionary) -> Dictionary:
	var previous_runtime: Dictionary = _runtime_preview_settings.duplicate(true)
	var preview_result: Dictionary = _call_settings_callback(
		_preview_apply,
		settings,
		"runtime_preview_applied",
		"runtime_preview_failed"
	)
	if bool(preview_result.get("ok", false)):
		_runtime_preview_settings = settings.duplicate(true)
		return preview_result

	var rollback_result: Dictionary = _call_settings_callback(
		_preview_apply,
		previous_runtime,
		"runtime_preview_rolled_back",
		"runtime_preview_rollback_failed"
	)
	if bool(rollback_result.get("ok", false)):
		_runtime_preview_settings = previous_runtime.duplicate(true)

	return _error(
		"preview_apply_failed",
		"settings preview failed and the previous runtime state was requested again",
		{
			"preview_result": preview_result,
			"rollback_result": rollback_result,
		}
	)


func _call_settings_callback(
	callback: Callable,
	settings: Dictionary,
	success_code: String,
	failure_code: String
) -> Dictionary:
	var value: Variant = callback.call(settings.duplicate(true))
	if value is Dictionary:
		var result: Dictionary = (value as Dictionary).duplicate(true)
		if not result.has("ok"):
			result["ok"] = true
		if not result.has("code"):
			result["code"] = (
				success_code
				if bool(result.get("ok", false))
				else failure_code
			)
		return result

	if typeof(value) == TYPE_BOOL:
		if bool(value):
			return _success(success_code)
		return _error(failure_code, "settings callback returned false")

	if value == null:
		return _success(success_code)

	return _error(
		"invalid_callback_result",
		"settings callback must return Dictionary, bool, or null"
	)


func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"code": code,
	}
	for key in extra:
		result[key] = extra[key]
	return result


func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"code": code,
		"message": message,
	}
	for key in extra:
		result[key] = extra[key]
	return result
