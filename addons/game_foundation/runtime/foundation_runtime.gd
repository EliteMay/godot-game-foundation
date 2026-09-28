extends Node

signal initialized(result: Dictionary)
signal initialization_failed(
	result: Dictionary,
	state: Dictionary
)
signal runtime_failure_changed(state: Dictionary)
signal save_completed(result: Dictionary)
signal load_completed(result: Dictionary)
signal settings_applied(result: Dictionary)

const Foundation = preload("res://addons/game_foundation/foundation.gd")
const SaveSystem = preload("res://addons/game_foundation/save/save_system.gd")
const AutoSaveService = preload("res://addons/game_foundation/save/auto_save_service.gd")
const SettingsSystem = preload("res://addons/game_foundation/settings/settings_system.gd")
const SettingsRuntime = preload("res://addons/game_foundation/settings/settings_runtime.gd")
const AudioBusContract = preload(
	"res://addons/game_foundation/audio/audio_bus_contract.gd"
)
const SettingsEditSession = preload(
	"res://addons/game_foundation/settings/settings_edit_session.gd"
)
const InputSystem = preload("res://addons/game_foundation/input/input_system.gd")
const GameFlowService = preload("res://addons/game_foundation/flow/game_flow_service.gd")
const DiagnosticsService = preload("res://addons/game_foundation/diagnostics/diagnostics_service.gd")
const RuntimeTestBridge = preload("res://addons/game_foundation/testing/runtime_test_bridge.gd")
const RuntimeFailureState = preload(
	"res://addons/game_foundation/recovery/runtime_failure_state.gd"
)

const DEFAULT_SAVE_CONFIG: Dictionary = {
	"enabled": false,
	"path": SaveSystem.DEFAULT_SAVE_PATH,
	"game_schema_version": 1,
	"autosave_debounce_seconds": 0.5,
}
const DEFAULT_SETTINGS_CONFIG: Dictionary = {
	"enabled": true,
	"path": SettingsSystem.DEFAULT_SETTINGS_PATH,
	"gameplay_defaults": {},
	"audio_bus_map": {
		"master": "Master",
		"bgm": "BGM",
		"sfx": "SFX",
		"ui": "SFX",
		"voice": "SFX",
	},
	"apply_runtime": true,
}
const DEFAULT_INPUT_CONFIG: Dictionary = {
	"enabled": true,
	"path": InputSystem.DEFAULT_INPUT_PATH,
	"contract": {},
}
const DEFAULT_FLOW_CONFIG: Dictionary = {
	"enabled": true,
	"scenes": {},
	"main_menu_id": "",
}
const DEFAULT_DIAGNOSTICS_CONFIG: Dictionary = {
	"enabled": true,
	"log_path": DiagnosticsService.DEFAULT_LOG_PATH,
}
const DEFAULT_RUNTIME_TEST_CONFIG: Dictionary = {
	"enabled": true,
}

var _config: Dictionary = {}
var _adapters: Dictionary = {}
var _configured: bool = false
var _initialized: bool = false
var _save_writes_blocked: bool = false
var _runtime_test_mode: bool = false
var _settings: Dictionary = {}
var _last_save_result: Dictionary = {}
var _last_load_result: Dictionary = {}
var _last_settings_result: Dictionary = {}
var _last_input_result: Dictionary = {}
var _runtime_failure_state: Dictionary = (
	RuntimeFailureState.inactive()
)

var _auto_save_service: Node = null
var _flow_service: Node = null
var _diagnostics_service: Node = null
var _runtime_test_bridge: Node = null


func configure(config: Dictionary = {}, adapters: Dictionary = {}) -> Dictionary:
	if _initialized:
		return _error("already_initialized", "runtime cannot be reconfigured after initialization")

	var normalized: Dictionary = _normalize_config(config)
	var validation: Dictionary = _validate_config(normalized, adapters)
	if not bool(validation.get("ok", false)):
		return validation

	_config = normalized
	_adapters = adapters.duplicate()
	_configured = true
	return _success("configured", {"config": public_config()})


func initialize() -> Dictionary:
	if _initialized:
		return _success(
			"already_initialized",
			{"status": status_snapshot()}
		)
	if not _configured:
		var configured: Dictionary = configure()
		if not bool(configured.get("ok", false)):
			return _finish_initialize_failure(
				configured,
				"configure"
			)
	if not is_inside_tree():
		return _finish_initialize_failure(
			_error(
				"not_in_scene_tree",
				"FoundationRuntime must be inside the SceneTree before initialize()"
			),
			"scene_tree"
		)

	var diagnostics_result: Dictionary = _initialize_diagnostics()
	if not bool(diagnostics_result.get("ok", false)):
		return _finish_initialize_failure(
			diagnostics_result,
			"diagnostics"
		)

	var settings_result: Dictionary = _initialize_settings()
	if not bool(settings_result.get("ok", false)):
		return _finish_initialize_failure(
			settings_result,
			"settings"
		)

	var input_result: Dictionary = _initialize_input()
	if not bool(input_result.get("ok", false)):
		return _finish_initialize_failure(
			input_result,
			"input"
		)

	var flow_result: Dictionary = _initialize_flow()
	if not bool(flow_result.get("ok", false)):
		return _finish_initialize_failure(
			flow_result,
			"flow"
		)

	var save_result: Dictionary = _initialize_save()
	if not bool(save_result.get("ok", false)):
		_log_warning(
			"save initialization did not complete",
			save_result
		)

	var runtime_test_result: Dictionary = _initialize_runtime_test()
	if not bool(runtime_test_result.get("ok", false)):
		return _finish_initialize_failure(
			runtime_test_result,
			"runtime_test"
		)

	_register_safe_quit_hook()
	_initialized = true
	_clear_runtime_failure_state()

	var result: Dictionary = _success("initialized", {
		"settings": settings_result,
		"input": input_result,
		"flow": flow_result,
		"save": save_result,
		"runtime_test": runtime_test_result,
		"status": status_snapshot(),
	})
	initialized.emit(result.duplicate(true))
	_log_info("foundation runtime initialized", {
		"foundation_version": Foundation.FOUNDATION_VERSION,
		"runtime_test_mode": _runtime_test_mode,
		"save_writes_blocked": _save_writes_blocked,
	})
	return result


func request_auto_save() -> Dictionary:
	if not _save_enabled():
		return _success("save_disabled")
	if _runtime_test_mode:
		return _success("runtime_test_mode_no_save")
	if _save_writes_blocked:
		return _success("save_preserved_after_load_failure")
	if _auto_save_service == null:
		return _error("autosave_unavailable", "AutoSaveService is not initialized")

	var payload_result: Dictionary = _capture_save_payload()
	if not bool(payload_result.get("ok", false)):
		return payload_result

	var result: Dictionary = _auto_save_service.call(
		"request_save",
		payload_result.get("payload", {}),
		_save_schema_version()
	)
	if not bool(result.get("ok", false)):
		_log_error("autosave request failed", result)
	return result


func save_now() -> Dictionary:
	if not _save_enabled():
		return _success("save_disabled")
	if _runtime_test_mode:
		return _success("runtime_test_mode_no_save")
	if _save_writes_blocked:
		return _success("save_preserved_after_load_failure")

	var payload_result: Dictionary = _capture_save_payload()
	if not bool(payload_result.get("ok", false)):
		_last_save_result = payload_result.duplicate(true)
		save_completed.emit(_last_save_result.duplicate(true))
		return payload_result

	if _auto_save_service == null:
		return _error("autosave_unavailable", "AutoSaveService is not initialized")

	var request_result: Dictionary = _auto_save_service.call(
		"request_save",
		payload_result.get("payload", {}),
		_save_schema_version()
	)
	var result: Dictionary = request_result
	if bool(request_result.get("ok", false)) and String(request_result.get("code", "")) == "autosave_queued":
		result = _auto_save_service.call("flush_pending")

	_last_save_result = result.duplicate(true)
	save_completed.emit(_last_save_result.duplicate(true))

	if bool(result.get("ok", false)):
		_log_info("game state saved", {"code": result.get("code", "saved")})
	else:
		_log_error("game state save failed", result)
	return result


func load_now() -> Dictionary:
	if not _save_enabled():
		var disabled := _success("save_disabled")
		_last_load_result = disabled.duplicate(true)
		load_completed.emit(_last_load_result.duplicate(true))
		return disabled

	var save_config: Dictionary = _section("save", DEFAULT_SAVE_CONFIG)
	var migrator: Callable = _adapter_callable("migrate_save_state")
	var result: Dictionary = SaveSystem.load_game(
		String(save_config.get("path", SaveSystem.DEFAULT_SAVE_PATH)),
		_save_schema_version(),
		migrator
	)

	if bool(result.get("ok", false)):
		var payload_variant: Variant = result.get("payload", {})
		if not (payload_variant is Dictionary):
			var invalid := _error("invalid_payload", "loaded save payload must be a Dictionary")
			_block_save_writes(invalid)
			return _record_load_result(invalid)

		var restored: Dictionary = _restore_save_payload(payload_variant as Dictionary)
		if not bool(restored.get("ok", false)):
			_block_save_writes(restored)
			return _record_load_result(restored)

		_save_writes_blocked = false
		var loaded: Dictionary = result.duplicate(true)
		loaded["restore"] = restored
		return _record_load_result(loaded)

	var code: String = String(result.get("code", "load_failed"))
	var backup_error: String = String(result.get("backup_error", "not_found"))
	if code == "not_found" and backup_error == "not_found":
		_save_writes_blocked = false
		return _record_load_result(_success("new_game"))

	_block_save_writes(result)
	return _record_load_result(result)


func save_settings(settings: Dictionary) -> Dictionary:
	if not _settings_enabled():
		return _success("settings_disabled")

	var settings_config: Dictionary = _section("settings", DEFAULT_SETTINGS_CONFIG)
	var result: Dictionary = SettingsSystem.save_settings(
		settings,
		settings_config.get("gameplay_defaults", {}),
		String(settings_config.get("path", SettingsSystem.DEFAULT_SETTINGS_PATH))
	)
	if not bool(result.get("ok", false)):
		_log_error("settings save failed", result)
		return result

	_settings = (result.get("settings", {}) as Dictionary).duplicate(true)
	var applied: Dictionary = _apply_loaded_settings()
	result["runtime_apply"] = applied
	_last_settings_result = result.duplicate(true)
	settings_applied.emit(_last_settings_result.duplicate(true))
	return result


func begin_settings_edit_session() -> Dictionary:
	if not _initialized:
		return _error(
			"runtime_not_initialized",
			"FoundationRuntime must be initialized before editing settings"
		)
	if not _settings_enabled():
		return _error("settings_disabled", "settings are disabled for this runtime")

	var settings_config: Dictionary = _section(
		"settings",
		DEFAULT_SETTINGS_CONFIG
	)
	var session := SettingsEditSession.new()
	var configured: Dictionary = session.configure(
		_settings,
		settings_config.get("gameplay_defaults", {}),
		Callable(self, "_apply_settings_preview"),
		Callable(self, "_persist_settings_from_edit_session")
	)
	if not bool(configured.get("ok", false)):
		return configured

	return _success(
		"settings_edit_session_started",
		{
			"session": session,
			"settings": session.draft_settings(),
		}
	)


func restore_input_bindings() -> Dictionary:
	if not _input_enabled():
		return _success("input_disabled")

	var input_config: Dictionary = _section("input", DEFAULT_INPUT_CONFIG)
	var result: Dictionary = InputSystem.restore_bindings(
		input_config.get("contract", {}),
		String(input_config.get("path", InputSystem.DEFAULT_INPUT_PATH))
	)
	_last_input_result = result.duplicate(true)
	if not bool(result.get("ok", false)):
		_log_error("input bindings restore failed", result)
	return result


func save_input_bindings() -> Dictionary:
	if not _input_enabled():
		return _success("input_disabled")

	var input_config: Dictionary = _section("input", DEFAULT_INPUT_CONFIG)
	var result: Dictionary = InputSystem.save_bindings(
		input_config.get("contract", {}),
		String(input_config.get("path", InputSystem.DEFAULT_INPUT_PATH))
	)
	_last_input_result = result.duplicate(true)
	if not bool(result.get("ok", false)):
		_log_error("input bindings save failed", result)
	return result


func request_quit(exit_code: int = 0) -> Dictionary:
	if _flow_service != null:
		return _flow_service.call("request_quit", exit_code)

	var save_result: Dictionary = _safe_quit_save()
	if save_result.has("ok") and not bool(save_result.get("ok", false)):
		return save_result
	get_tree().quit(exit_code)
	return _success("quit_requested", {"exit_code": exit_code})


func diagnostics_snapshot() -> Dictionary:
	if _diagnostics_service == null:
		return {}
	return _diagnostics_service.call("build_snapshot")


func status_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"initialized": _initialized,
		"foundation_version": Foundation.FOUNDATION_VERSION,
		"save_enabled": _save_enabled(),
		"save_writes_blocked": _save_writes_blocked,
		"runtime_test_mode": _runtime_test_mode,
		"settings_enabled": _settings_enabled(),
		"input_enabled": _input_enabled(),
		"flow_enabled": _flow_enabled(),
		"diagnostics_enabled": _diagnostics_enabled(),
		"has_runtime_failure": has_runtime_failure(),
		"runtime_failure": runtime_failure_state(),
		"last_save": _last_save_result.duplicate(true),
		"last_load": _last_load_result.duplicate(true),
		"last_settings": _last_settings_result.duplicate(true),
		"last_input": _last_input_result.duplicate(true),
	}


func public_config() -> Dictionary:
	var result: Dictionary = _config.duplicate(true)
	return result


func current_settings() -> Dictionary:
	return _settings.duplicate(true)


func flow_service() -> Node:
	return _flow_service


func diagnostics_service() -> Node:
	return _diagnostics_service


func runtime_test_bridge() -> Node:
	return _runtime_test_bridge


func is_runtime_test_mode() -> bool:
	return _runtime_test_mode


func is_save_write_blocked() -> bool:
	return _save_writes_blocked


func has_runtime_failure() -> bool:
	return bool(_runtime_failure_state.get("active", false))


func runtime_failure_state() -> Dictionary:
	return _runtime_failure_state.duplicate(true)


func _initialize_diagnostics() -> Dictionary:
	if not _diagnostics_enabled():
		return _success("diagnostics_disabled")

	var diagnostics_config: Dictionary = _section("diagnostics", DEFAULT_DIAGNOSTICS_CONFIG)
	_diagnostics_service = DiagnosticsService.new()
	_diagnostics_service.set(
		"log_path",
		String(diagnostics_config.get("log_path", DiagnosticsService.DEFAULT_LOG_PATH))
	)
	add_child(_diagnostics_service)

	var paths: Dictionary = {
		"save": String(_section("save", DEFAULT_SAVE_CONFIG).get("path", SaveSystem.DEFAULT_SAVE_PATH)),
		"settings": String(_section("settings", DEFAULT_SETTINGS_CONFIG).get("path", SettingsSystem.DEFAULT_SETTINGS_PATH)),
		"input": String(_section("input", DEFAULT_INPUT_CONFIG).get("path", InputSystem.DEFAULT_INPUT_PATH)),
		"log": String(diagnostics_config.get("log_path", DiagnosticsService.DEFAULT_LOG_PATH)),
	}
	var app_info: Dictionary = _section("app", {
		"name": String(ProjectSettings.get_setting("application/config/name", "Game")),
		"version": String(ProjectSettings.get_setting("application/config/version", "")),
	})
	app_info["foundation_version"] = Foundation.FOUNDATION_VERSION
	return _diagnostics_service.call("configure", app_info, paths)


func _initialize_settings() -> Dictionary:
	if not _settings_enabled():
		return _success("settings_disabled")

	var settings_config: Dictionary = _section("settings", DEFAULT_SETTINGS_CONFIG)
	var result: Dictionary = SettingsSystem.load_settings(
		settings_config.get("gameplay_defaults", {}),
		String(settings_config.get("path", SettingsSystem.DEFAULT_SETTINGS_PATH))
	)
	if not bool(result.get("ok", false)):
		_log_error("settings load failed", result)
		return result

	_settings = (result.get("settings", {}) as Dictionary).duplicate(true)
	var applied: Dictionary = _apply_loaded_settings()
	result["runtime_apply"] = applied
	_last_settings_result = result.duplicate(true)
	settings_applied.emit(_last_settings_result.duplicate(true))
	return result


func _apply_loaded_settings() -> Dictionary:
	return _apply_settings_value(_settings)


func _apply_settings_preview(settings: Dictionary) -> Dictionary:
	var settings_config: Dictionary = _section(
		"settings",
		DEFAULT_SETTINGS_CONFIG
	)
	var normalized_result: Dictionary = SettingsSystem.normalize_settings(
		settings,
		settings_config.get("gameplay_defaults", {})
	)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	return _apply_settings_value(
		normalized_result.get("settings", {}) as Dictionary
	)


func _apply_settings_value(settings: Dictionary) -> Dictionary:
	var settings_config: Dictionary = _section("settings", DEFAULT_SETTINGS_CONFIG)
	var runtime_result: Dictionary = _success("runtime_apply_disabled")
	if bool(settings_config.get("apply_runtime", true)):
		runtime_result = SettingsRuntime.apply_settings(
			settings,
			settings_config.get("audio_bus_map", {})
		)
		if not bool(runtime_result.get("ok", false)):
			_log_warning("common runtime settings apply failed", runtime_result)

	var gameplay_apply: Callable = _adapter_callable("apply_gameplay_settings")
	var gameplay_result: Dictionary = _success("gameplay_settings_not_used")
	if gameplay_apply.is_valid():
		var gameplay_variant: Variant = settings.get("gameplay", {})
		var value: Variant = gameplay_apply.call(
			gameplay_variant if gameplay_variant is Dictionary else {}
		)
		gameplay_result = _normalize_adapter_result(
			value,
			"gameplay_settings_applied",
			"gameplay_settings_apply_failed"
		)
		if not bool(gameplay_result.get("ok", false)):
			_log_error("gameplay settings apply failed", gameplay_result)

	return {
		"ok": bool(runtime_result.get("ok", false)) and bool(gameplay_result.get("ok", false)),
		"code": "settings_applied",
		"common": runtime_result,
		"gameplay": gameplay_result,
	}


func _persist_settings_from_edit_session(settings: Dictionary) -> Dictionary:
	var settings_config: Dictionary = _section(
		"settings",
		DEFAULT_SETTINGS_CONFIG
	)
	var result: Dictionary = SettingsSystem.save_settings(
		settings,
		settings_config.get("gameplay_defaults", {}),
		String(
			settings_config.get(
				"path",
				SettingsSystem.DEFAULT_SETTINGS_PATH
			)
		)
	)
	if not bool(result.get("ok", false)):
		_log_error("settings edit session persistence failed", result)
		return result

	_settings = (result.get("settings", {}) as Dictionary).duplicate(true)
	result["runtime_apply"] = _success("settings_session_preview_committed")
	_last_settings_result = result.duplicate(true)
	settings_applied.emit(_last_settings_result.duplicate(true))
	return result


func _initialize_input() -> Dictionary:
	if not _input_enabled():
		return _success("input_disabled")
	return restore_input_bindings()


func _initialize_flow() -> Dictionary:
	if not _flow_enabled():
		return _success("flow_disabled")

	var flow_config: Dictionary = _section("flow", DEFAULT_FLOW_CONFIG)
	_flow_service = GameFlowService.new()
	add_child(_flow_service)
	return _flow_service.call(
		"configure_scene_contract",
		flow_config.get("scenes", {}),
		String(flow_config.get("main_menu_id", ""))
	)


func _initialize_save() -> Dictionary:
	if not _save_enabled():
		return _success("save_disabled")

	var save_config: Dictionary = _section("save", DEFAULT_SAVE_CONFIG)
	_auto_save_service = AutoSaveService.new()
	_auto_save_service.set(
		"save_path",
		String(save_config.get("path", SaveSystem.DEFAULT_SAVE_PATH))
	)
	_auto_save_service.set(
		"debounce_seconds",
		maxf(0.0, float(save_config.get("autosave_debounce_seconds", 0.5)))
	)
	add_child(_auto_save_service)

	return load_now()


func _initialize_runtime_test() -> Dictionary:
	var runtime_config: Dictionary = _section("runtime_test", DEFAULT_RUNTIME_TEST_CONFIG)
	if not bool(runtime_config.get("enabled", true)):
		return _success("runtime_test_disabled")

	var provider: Callable = _adapter_callable("runtime_test_state")
	if not provider.is_valid():
		return _success("runtime_test_provider_not_configured")

	_runtime_test_bridge = RuntimeTestBridge.new()
	var result: Dictionary = _runtime_test_bridge.call(
		"configure_from_command_line",
		provider
	)
	if not bool(result.get("ok", false)):
		_runtime_test_bridge.free()
		_runtime_test_bridge = null
		return result

	if bool(result.get("enabled", false)):
		_runtime_test_mode = true
		add_child(_runtime_test_bridge)
	else:
		_runtime_test_bridge.free()
		_runtime_test_bridge = null

	return result


func _register_safe_quit_hook() -> void:
	if _flow_service == null or not _save_enabled():
		return
	_flow_service.call("register_quit_hook", Callable(self, "_safe_quit_save"))


func _safe_quit_save() -> Dictionary:
	return save_now()


func _capture_save_payload() -> Dictionary:
	var capture: Callable = _adapter_callable("capture_save_state")
	if not capture.is_valid():
		return _error("save_capture_adapter_missing", "capture_save_state adapter is required")

	var value: Variant = capture.call()
	if not (value is Dictionary):
		return _error("save_payload_invalid", "capture_save_state must return a Dictionary")

	var payload: Dictionary = (value as Dictionary).duplicate(true)
	var validation: Dictionary = SaveSystem.validate_payload(payload)
	if not bool(validation.get("ok", false)):
		return validation
	return _success("save_payload_captured", {"payload": payload})


func _restore_save_payload(payload: Dictionary) -> Dictionary:
	var restore: Callable = _adapter_callable("restore_save_state")
	if not restore.is_valid():
		return _error("save_restore_adapter_missing", "restore_save_state adapter is required")

	var value: Variant = restore.call(payload.duplicate(true))
	return _normalize_adapter_result(value, "save_state_restored", "save_state_restore_failed")


func _normalize_adapter_result(
	value: Variant,
	success_code: String,
	failure_code: String
) -> Dictionary:
	if value is Dictionary:
		var result: Dictionary = (value as Dictionary).duplicate(true)
		if not result.has("ok"):
			result["ok"] = true
		if not result.has("code"):
			result["code"] = success_code if bool(result.get("ok", false)) else failure_code
		return result
	if typeof(value) == TYPE_BOOL:
		return (
			_success(success_code)
			if bool(value)
			else _error(failure_code, failure_code)
		)
	if value == null:
		return _success(success_code)
	return _error(failure_code, "adapter returned an unsupported result type")


func _block_save_writes(result: Dictionary) -> void:
	_save_writes_blocked = true
	_log_error("save load/restore failed; writes are blocked to preserve existing data", result)


func _record_load_result(result: Dictionary) -> Dictionary:
	_last_load_result = result.duplicate(true)
	load_completed.emit(_last_load_result.duplicate(true))
	if bool(result.get("ok", false)):
		_log_info("game state load completed", {
			"code": result.get("code", "loaded"),
			"source": result.get("source", ""),
		})
	else:
		_log_error("game state load failed", result)
	return result


func _finish_initialize_failure(
	result: Dictionary,
	stage: String
) -> Dictionary:
	_runtime_failure_state = (
		RuntimeFailureState.initialization_failure(
			stage,
			result,
			{
				"save_writes_blocked": _save_writes_blocked,
				"diagnostics_available": (
					_diagnostics_service != null
				),
			}
		)
	)

	var recorded: Dictionary = result.duplicate(true)
	recorded["runtime_failure"] = (
		_runtime_failure_state.duplicate(true)
	)

	_log_error(
		"foundation runtime initialization failed",
		{
			"stage": stage,
			"code": recorded.get(
				"code",
				"initialization_failed"
			),
			"runtime_failure": _runtime_failure_state,
		}
	)
	initialization_failed.emit(
		recorded.duplicate(true),
		_runtime_failure_state.duplicate(true)
	)
	runtime_failure_changed.emit(
		_runtime_failure_state.duplicate(true)
	)
	return recorded


func _clear_runtime_failure_state() -> void:
	if not has_runtime_failure():
		return
	_runtime_failure_state = RuntimeFailureState.inactive()
	runtime_failure_changed.emit(
		_runtime_failure_state.duplicate(true)
	)


func _normalize_config(source: Dictionary) -> Dictionary:
	var app_defaults: Dictionary = {
		"name": String(ProjectSettings.get_setting("application/config/name", "Game")),
		"version": String(ProjectSettings.get_setting("application/config/version", "")),
	}
	var settings_section: Dictionary = _merge_section(
		DEFAULT_SETTINGS_CONFIG,
		source.get("settings", {})
	)
	var audio_bus_variant: Variant = settings_section.get("audio_bus_map", {})
	if audio_bus_variant is Dictionary:
		var bus_result: Dictionary = AudioBusContract.normalize(audio_bus_variant)
		if bool(bus_result.get("ok", false)):
			settings_section["audio_bus_map"] = (
				bus_result.get("bus_map", {}) as Dictionary
			).duplicate(true)

	return {
		"app": _merge_section(app_defaults, source.get("app", {})),
		"save": _merge_section(DEFAULT_SAVE_CONFIG, source.get("save", {})),
		"settings": settings_section,
		"input": _merge_section(DEFAULT_INPUT_CONFIG, source.get("input", {})),
		"flow": _merge_section(DEFAULT_FLOW_CONFIG, source.get("flow", {})),
		"diagnostics": _merge_section(DEFAULT_DIAGNOSTICS_CONFIG, source.get("diagnostics", {})),
		"runtime_test": _merge_section(DEFAULT_RUNTIME_TEST_CONFIG, source.get("runtime_test", {})),
	}


func _validate_config(config: Dictionary, adapters: Dictionary) -> Dictionary:
	for section_name in [
		"app",
		"save",
		"settings",
		"input",
		"flow",
		"diagnostics",
		"runtime_test",
	]:
		if not (config.get(section_name, {}) is Dictionary):
			return _error("invalid_config_section", section_name + " must be a Dictionary")

	var save_config: Dictionary = config.get("save", {})
	if bool(save_config.get("enabled", false)):
		if int(save_config.get("game_schema_version", 0)) < 1:
			return _error("invalid_game_schema_version", "save.game_schema_version must be 1 or greater")
		if not _callable_from(adapters, "capture_save_state").is_valid():
			return _error("save_capture_adapter_missing", "capture_save_state adapter is required when save is enabled")
		if not _callable_from(adapters, "restore_save_state").is_valid():
			return _error("save_restore_adapter_missing", "restore_save_state adapter is required when save is enabled")

	var settings_config: Dictionary = config.get("settings", {})
	if not (settings_config.get("gameplay_defaults", {}) is Dictionary):
		return _error("invalid_gameplay_defaults", "settings.gameplay_defaults must be a Dictionary")
	var audio_bus_result: Dictionary = AudioBusContract.normalize(
		settings_config.get("audio_bus_map", {})
	)
	if not bool(audio_bus_result.get("ok", false)):
		return audio_bus_result

	var input_config: Dictionary = config.get("input", {})
	if bool(input_config.get("enabled", true)):
		var contract_variant: Variant = input_config.get("contract", {})
		if not (contract_variant is Dictionary):
			return _error("invalid_input_contract", "input.contract must be a Dictionary")
		var contract_result: Dictionary = InputSystem.validate_contract(contract_variant as Dictionary)
		if not bool(contract_result.get("ok", false)):
			return contract_result

	var flow_config: Dictionary = config.get("flow", {})
	if not (flow_config.get("scenes", {}) is Dictionary):
		return _error("invalid_scene_contract", "flow.scenes must be a Dictionary")

	return _success("valid_config")


func _merge_section(defaults: Dictionary, value: Variant) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			result[key] = (value as Dictionary)[key]
	return result


func _section(name: String, defaults: Dictionary) -> Dictionary:
	var value: Variant = _config.get(name, defaults)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return defaults.duplicate(true)


func _adapter_callable(name: String) -> Callable:
	return _callable_from(_adapters, name)


func _callable_from(source: Dictionary, name: String) -> Callable:
	var value: Variant = source.get(name, Callable())
	if typeof(value) == TYPE_CALLABLE:
		return value
	return Callable()


func _save_schema_version() -> int:
	return maxi(1, int(_section("save", DEFAULT_SAVE_CONFIG).get("game_schema_version", 1)))


func _save_enabled() -> bool:
	return bool(_section("save", DEFAULT_SAVE_CONFIG).get("enabled", false))


func _settings_enabled() -> bool:
	return bool(_section("settings", DEFAULT_SETTINGS_CONFIG).get("enabled", true))


func _input_enabled() -> bool:
	return bool(_section("input", DEFAULT_INPUT_CONFIG).get("enabled", true))


func _flow_enabled() -> bool:
	return bool(_section("flow", DEFAULT_FLOW_CONFIG).get("enabled", true))


func _diagnostics_enabled() -> bool:
	return bool(_section("diagnostics", DEFAULT_DIAGNOSTICS_CONFIG).get("enabled", true))


func _log_info(message: String, context: Dictionary = {}) -> void:
	if _diagnostics_service != null:
		_diagnostics_service.call("log_info", message, context)


func _log_warning(message: String, context: Dictionary = {}) -> void:
	if _diagnostics_service != null:
		_diagnostics_service.call("log_warning", message, context)


func _log_error(message: String, context: Dictionary = {}) -> void:
	if _diagnostics_service != null:
		_diagnostics_service.call("log_error", message, context)


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
