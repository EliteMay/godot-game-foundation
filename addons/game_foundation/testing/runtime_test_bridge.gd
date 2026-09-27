extends Node

const SCHEMA_VERSION: int = 1
const STATE_ARG_PREFIX: String = "--foundation-test-state="
const SESSION_ARG_PREFIX: String = "--foundation-test-session="

@export_range(0.05, 5.0, 0.05) var capture_interval_seconds: float = 0.20

var _enabled: bool = false
var _output_path: String = ""
var _session_id: String = ""
var _state_provider: Callable
var _elapsed: float = 0.0
var _sequence: int = 0
var _last_error: String = ""


func configure(
	output_path: String,
	session_id: String,
	state_provider: Callable
) -> Dictionary:
	_output_path = output_path.strip_edges()
	_session_id = session_id.strip_edges()
	_state_provider = state_provider
	_enabled = (
		not _output_path.is_empty()
		and not _session_id.is_empty()
		and _state_provider.is_valid()
	)
	set_process(_enabled)

	return {
		"ok": _enabled,
		"enabled": _enabled,
		"output_path": _output_path,
		"session_id": _session_id,
		"code": "ok" if _enabled else "invalid_config",
	}


func configure_from_command_line(state_provider: Callable) -> Dictionary:
	var output_path: String = _find_user_argument(STATE_ARG_PREFIX)
	var session_id: String = _find_user_argument(SESSION_ARG_PREFIX)
	if output_path.is_empty() or session_id.is_empty():
		_enabled = false
		set_process(false)
		return {
			"ok": true,
			"enabled": false,
			"code": "not_requested",
		}

	return configure(output_path, session_id, state_provider)


func is_enabled() -> bool:
	return _enabled


func last_error() -> String:
	return _last_error


func _ready() -> void:
	if _enabled:
		call_deferred("capture_now")


func _process(delta: float) -> void:
	if not _enabled:
		return

	_elapsed += delta
	if _elapsed < capture_interval_seconds:
		return

	_elapsed = 0.0
	capture_now()


func capture_now() -> Dictionary:
	if not _enabled:
		return {"ok": false, "code": "disabled"}
	if not _state_provider.is_valid():
		return _fail("provider_missing")

	var state_variant: Variant = _state_provider.call()
	if not (state_variant is Dictionary):
		return _fail("provider_state_invalid")

	var state: Dictionary = state_variant as Dictionary
	if not _is_json_compatible(state):
		return _fail("provider_state_not_json_compatible")

	_sequence += 1
	var payload: Dictionary = {
		"schemaVersion": SCHEMA_VERSION,
		"sessionId": _session_id,
		"sequence": _sequence,
		"capturedAtUnixMs": int(Time.get_unix_time_from_system() * 1000.0),
		"processId": OS.get_process_id(),
		"gameVersion": String(ProjectSettings.get_setting("application/config/version", "")),
		"state": state,
	}

	var result: Dictionary = _write_payload(payload)
	if bool(result.get("ok", false)):
		_last_error = ""
	return result


func _write_payload(payload: Dictionary) -> Dictionary:
	var parent: String = _output_path.get_base_dir()
	if parent.is_empty():
		return _fail("output_parent_missing")

	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(parent)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return _fail("output_directory_failed")

	var temp_path: String = _output_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("output_open_failed")

	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()

	if FileAccess.file_exists(_output_path):
		var remove_error: Error = DirAccess.remove_absolute(_output_path)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_path)
			return _fail("output_replace_failed")

	var rename_error: Error = DirAccess.rename_absolute(temp_path, _output_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return _fail("output_rename_failed")

	return {
		"ok": true,
		"code": "ok",
		"sequence": _sequence,
		"output_path": _output_path,
	}


func _find_user_argument(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		var value: String = String(argument)
		if value.begins_with(prefix):
			return value.substr(prefix.length()).strip_edges()
	return ""


func _fail(code: String) -> Dictionary:
	_last_error = code
	return {
		"ok": false,
		"code": code,
	}


static func _is_json_compatible(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_json_compatible(item):
					return false
			return true
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value as Dictionary
			for key in dictionary.keys():
				if not (key is String):
					return false
				if not _is_json_compatible(dictionary[key]):
					return false
			return true
		_:
			return false
