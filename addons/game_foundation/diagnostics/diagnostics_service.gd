extends Node

signal entry_added(entry: Dictionary)

const RuntimeInfo = preload("res://addons/game_foundation/diagnostics/runtime_info.gd")

const DEFAULT_LOG_PATH: String = "user://logs/runtime.log"
const ROTATED_LOG_SUFFIX: String = ".old"
const DEFAULT_MAX_ENTRIES: int = 200
const DEFAULT_MAX_LOG_BYTES: int = 1024 * 1024
const MAX_CONTEXT_DEPTH: int = 12

@export var log_path: String = DEFAULT_LOG_PATH
@export_range(10, 5000, 10) var max_entries: int = DEFAULT_MAX_ENTRIES
@export_range(4096, 16777216, 4096) var max_log_bytes: int = DEFAULT_MAX_LOG_BYTES

var _app_info: Dictionary = {}
var _paths: Dictionary = {}
var _entries: Array[Dictionary] = []
var _counts: Dictionary = {
	"info": 0,
	"warning": 0,
	"error": 0,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(
	app_info: Dictionary = {},
	paths: Dictionary = {}
) -> Dictionary:
	_app_info = _sanitize_string_dictionary(app_info)
	_paths = _sanitize_string_dictionary(paths)
	return {
		"ok": true,
		"code": "diagnostics_configured",
		"app_info": _app_info.duplicate(true),
		"paths": _paths.duplicate(true),
	}


func set_paths(paths: Dictionary) -> Dictionary:
	_paths = _sanitize_string_dictionary(paths)
	return {
		"ok": true,
		"code": "paths_updated",
		"paths": _paths.duplicate(true),
	}


func log_info(message: String, context: Dictionary = {}) -> Dictionary:
	return _append_entry("info", message, context)


func log_warning(message: String, context: Dictionary = {}) -> Dictionary:
	return _append_entry("warning", message, context)


func log_error(message: String, context: Dictionary = {}) -> Dictionary:
	return _append_entry("error", message, context)


func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func recent_entries(limit: int = 20) -> Array[Dictionary]:
	var safe_limit: int = clampi(limit, 0, max_entries)
	if safe_limit == 0 or _entries.is_empty():
		return []
	var start: int = maxi(0, _entries.size() - safe_limit)
	return _entries.slice(start, _entries.size()).duplicate(true)


func recent_errors(limit: int = 10) -> Array[Dictionary]:
	var safe_limit: int = maxi(0, limit)
	var result: Array[Dictionary] = []
	for index in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		if String(entry.get("level", "")) != "error":
			continue
		result.push_front(entry.duplicate(true))
		if result.size() >= safe_limit:
			break
	return result


func error_summary() -> Dictionary:
	return {
		"info_count": int(_counts.get("info", 0)),
		"warning_count": int(_counts.get("warning", 0)),
		"error_count": int(_counts.get("error", 0)),
		"recent_errors": recent_errors(10),
	}


func build_snapshot() -> Dictionary:
	return {
		"runtime": RuntimeInfo.collect(_app_info),
		"paths": _paths.duplicate(true),
		"errors": error_summary(),
		"recent_entries": recent_entries(20),
		"performance": {
			"fps": Engine.get_frames_per_second(),
		},
	}


func clear_memory() -> void:
	_entries.clear()
	_counts = {
		"info": 0,
		"warning": 0,
		"error": 0,
	}


func clear_log_files() -> Dictionary:
	for path in [log_path, rotated_log_path()]:
		if FileAccess.file_exists(path):
			var error: Error = DirAccess.remove_absolute(path)
			if error != OK:
				return {
					"ok": false,
					"code": "log_remove_failed",
					"path": path,
					"error": error,
				}
	return {
		"ok": true,
		"code": "logs_cleared",
	}


func rotated_log_path() -> String:
	return log_path + ROTATED_LOG_SUFFIX


func _append_entry(
	level: String,
	message: String,
	context: Dictionary
) -> Dictionary:
	if message.strip_edges().is_empty():
		return {
			"ok": false,
			"code": "empty_message",
			"message": "diagnostic log message cannot be empty",
		}
	if not level in ["info", "warning", "error"]:
		return {
			"ok": false,
			"code": "invalid_level",
			"message": "diagnostic log level is not supported",
		}

	var entry: Dictionary = {
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"level": level,
		"message": message,
		"context": _json_safe(context),
	}

	_entries.append(entry)
	while _entries.size() > maxi(10, max_entries):
		_entries.pop_front()

	_counts[level] = int(_counts.get(level, 0)) + 1

	var write_result: Dictionary = _write_entry(entry)
	entry_added.emit(entry.duplicate(true))

	return {
		"ok": bool(write_result.get("ok", false)),
		"code": (
			"logged"
			if bool(write_result.get("ok", false))
			else String(write_result.get("code", "log_write_failed"))
		),
		"entry": entry,
		"log_write": write_result,
	}


func _write_entry(entry: Dictionary) -> Dictionary:
	if not log_path.begins_with("user://"):
		return {
			"ok": false,
			"code": "unsafe_log_path",
			"message": "diagnostic logs must use user://",
		}

	var directory: String = log_path.get_base_dir()
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		return {
			"ok": false,
			"code": "log_directory_failed",
			"error": make_dir_error,
		}

	var rotation_result: Dictionary = _rotate_if_needed()
	if not bool(rotation_result.get("ok", false)):
		return rotation_result

	var file: FileAccess
	if FileAccess.file_exists(log_path):
		file = FileAccess.open(log_path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(log_path, FileAccess.WRITE)

	if file == null:
		return {
			"ok": false,
			"code": "log_open_failed",
			"error": FileAccess.get_open_error(),
		}

	file.store_line(JSON.stringify(entry))
	file.flush()
	file.close()

	return {
		"ok": true,
		"code": "log_written",
		"path": log_path,
	}


func _rotate_if_needed() -> Dictionary:
	if not FileAccess.file_exists(log_path):
		return {
			"ok": true,
			"code": "rotation_not_needed",
		}

	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"code": "log_read_failed",
			"error": FileAccess.get_open_error(),
		}

	var length: int = file.get_length()
	file.close()
	if length < maxi(4096, max_log_bytes):
		return {
			"ok": true,
			"code": "rotation_not_needed",
		}

	var rotated: String = rotated_log_path()
	if FileAccess.file_exists(rotated):
		var remove_error: Error = DirAccess.remove_absolute(rotated)
		if remove_error != OK:
			return {
				"ok": false,
				"code": "old_log_remove_failed",
				"error": remove_error,
			}

	var rename_error: Error = DirAccess.rename_absolute(log_path, rotated)
	if rename_error != OK:
		return {
			"ok": false,
			"code": "log_rotation_failed",
			"error": rename_error,
		}

	return {
		"ok": true,
		"code": "log_rotated",
		"path": rotated,
	}


func _sanitize_string_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key in source.keys():
		if typeof(raw_key) != TYPE_STRING:
			continue
		var value: Variant = source[raw_key]
		if typeof(value) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
			result[String(raw_key)] = value
	return result


func _json_safe(value: Variant, depth: int = 0) -> Variant:
	if depth > MAX_CONTEXT_DEPTH:
		return "<max-depth>"

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			var number: float = float(value)
			if number != number:
				return "<nan>"
			if number == INF:
				return "<inf>"
			if number == -INF:
				return "<-inf>"
			return number
		TYPE_ARRAY:
			var output_array: Array = []
			for item in value as Array:
				output_array.append(_json_safe(item, depth + 1))
			return output_array
		TYPE_DICTIONARY:
			var output_dictionary: Dictionary = {}
			for raw_key in (value as Dictionary).keys():
				output_dictionary[String(raw_key)] = _json_safe(
					(value as Dictionary)[raw_key],
					depth + 1
				)
			return output_dictionary
		_:
			return str(value)
