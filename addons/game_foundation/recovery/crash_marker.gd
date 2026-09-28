extends RefCounted

const SCHEMA_VERSION: int = 1
const DEFAULT_MARKER_PATH: String = (
	"user://foundation_session_marker.json"
)
const MAX_MARKER_BYTES: int = 16 * 1024
const MAX_METADATA_LENGTH: int = 128

var _path: String = DEFAULT_MARKER_PATH
var _app_version: String = ""
var _foundation_version: String = ""
var _session_id: String = ""
var _active: bool = false
var _started_at_unix: int = 0
var _previous_session: Dictionary = {
	"marker_found": false,
	"possible_unclean_exit": false,
	"reason": "no_marker",
}


static func validate_marker_path(path: String) -> Dictionary:
	var normalized: String = path.strip_edges()
	if normalized.is_empty():
		return _error_static(
			"empty_crash_marker_path",
			"crash marker path cannot be empty"
		)
	if not normalized.begins_with("user://"):
		return _error_static(
			"unsafe_crash_marker_path",
			"crash marker path must use user://"
		)
	if normalized.ends_with("/"):
		return _error_static(
			"invalid_crash_marker_path",
			"crash marker path must point to a file"
		)
	return {
		"ok": true,
		"code": "crash_marker_path_valid",
		"path": normalized,
	}


func configure(options: Dictionary = {}) -> Dictionary:
	var path_result: Dictionary = validate_marker_path(
		String(
			options.get(
				"path",
				DEFAULT_MARKER_PATH
			)
		)
	)
	if not bool(path_result.get("ok", false)):
		return path_result

	_path = String(path_result.get("path", DEFAULT_MARKER_PATH))
	_app_version = _bounded_metadata(
		String(options.get("app_version", ""))
	)
	_foundation_version = _bounded_metadata(
		String(options.get("foundation_version", ""))
	)

	return _success(
		"crash_marker_configured",
		{
			"path": _path,
		}
	)


func begin_session() -> Dictionary:
	if _active:
		return _success(
			"crash_marker_session_already_active",
			{
				"state": snapshot(),
			}
		)

	_previous_session = _inspect_existing_marker()
	_session_id = _make_session_id()
	_started_at_unix = int(
		Time.get_unix_time_from_system()
	)

	var marker: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"state": "running",
		"session_id": _session_id,
		"started_at_unix": _started_at_unix,
		"app_version": _app_version,
		"foundation_version": _foundation_version,
	}
	var write_result: Dictionary = _write_marker(marker)
	if not bool(write_result.get("ok", false)):
		return _error(
			String(
				write_result.get(
					"code",
					"crash_marker_write_failed"
				)
			),
			String(
				write_result.get(
					"message",
					"crash marker could not be written"
				)
			),
			{
				"previous_session": (
					_previous_session.duplicate(true)
				),
			}
		)

	_active = true
	return _success(
		"crash_marker_session_started",
		{
			"previous_session": (
				_previous_session.duplicate(true)
			),
			"state": snapshot(),
		}
	)


func mark_clean() -> Dictionary:
	if not _active:
		return _success(
			"crash_marker_session_inactive",
			{
				"state": snapshot(),
			}
		)

	if not FileAccess.file_exists(_path):
		_active = false
		return _success(
			"crash_marker_already_missing",
			{
				"state": snapshot(),
			}
		)

	var marker_result: Dictionary = _read_marker()
	if not bool(marker_result.get("ok", false)):
		return _error(
			"crash_marker_cleanup_ownership_unknown",
			"crash marker could not be validated before cleanup",
			{
				"marker_error": String(
					marker_result.get(
						"code",
						"marker_invalid"
					)
				),
				"state": snapshot(),
			}
		)

	var marker: Dictionary = (
		marker_result.get("marker", {}) as Dictionary
	)
	if String(marker.get("session_id", "")) != _session_id:
		_active = false
		return _success(
			"crash_marker_replaced_by_other_session",
			{
				"removed": false,
				"state": snapshot(),
			}
		)

	var remove_error: Error = DirAccess.remove_absolute(_path)
	if remove_error != OK:
		return _error(
			"crash_marker_remove_failed",
			"crash marker could not be removed",
			{
				"error": int(remove_error),
				"state": snapshot(),
			}
		)

	_active = false
	return _success(
		"crash_marker_session_clean",
		{
			"removed": true,
			"state": snapshot(),
		}
	)


func snapshot() -> Dictionary:
	return {
		"configured": not _path.is_empty(),
		"active": _active,
		"path": _path,
		"started_at_unix": _started_at_unix,
		"previous_session": (
			_previous_session.duplicate(true)
		),
	}


func previous_session() -> Dictionary:
	return _previous_session.duplicate(true)


func _inspect_existing_marker() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {
			"marker_found": false,
			"possible_unclean_exit": false,
			"reason": "no_marker",
		}

	var read_result: Dictionary = _read_marker()
	if not bool(read_result.get("ok", false)):
		return {
			"marker_found": true,
			"marker_valid": false,
			"possible_unclean_exit": true,
			"reason": String(
				read_result.get(
					"code",
					"marker_invalid"
				)
			),
		}

	var marker: Dictionary = (
		read_result.get("marker", {}) as Dictionary
	)
	return {
		"marker_found": true,
		"marker_valid": true,
		"possible_unclean_exit": true,
		"reason": "active_marker_present",
		"previous_started_at_unix": int(
			marker.get("started_at_unix", 0)
		),
		"app_version": _bounded_metadata(
			String(marker.get("app_version", ""))
		),
		"foundation_version": _bounded_metadata(
			String(
				marker.get(
					"foundation_version",
					""
				)
			)
		),
	}


func _write_marker(marker: Dictionary) -> Dictionary:
	var directory: String = _path.get_base_dir()
	var make_dir_error: Error = (
		DirAccess.make_dir_recursive_absolute(directory)
	)
	if (
		make_dir_error != OK
		and make_dir_error != ERR_ALREADY_EXISTS
	):
		return _error(
			"crash_marker_directory_failed",
			"crash marker directory could not be created",
			{"error": int(make_dir_error)}
		)

	var text_value: String = JSON.stringify(marker)
	if text_value.to_utf8_buffer().size() > MAX_MARKER_BYTES:
		return _error(
			"crash_marker_too_large",
			"crash marker exceeds size limit"
		)

	var file: FileAccess = FileAccess.open(
		_path,
		FileAccess.WRITE
	)
	if file == null:
		return _error(
			"crash_marker_open_failed",
			"crash marker could not be opened for writing",
			{
				"error": int(FileAccess.get_open_error()),
			}
		)

	file.store_string(text_value)
	file.flush()
	file.close()

	var verification: Dictionary = _read_marker()
	if not bool(verification.get("ok", false)):
		return _error(
			"crash_marker_verify_failed",
			"crash marker verification failed",
			{
				"verification_code": String(
					verification.get(
						"code",
						"marker_invalid"
					)
				),
			}
		)

	var stored: Dictionary = (
		verification.get("marker", {}) as Dictionary
	)
	if String(stored.get("session_id", "")) != _session_id:
		return _error(
			"crash_marker_verify_failed",
			"crash marker session id did not round-trip"
		)

	return _success("crash_marker_written")


func _read_marker() -> Dictionary:
	var file: FileAccess = FileAccess.open(
		_path,
		FileAccess.READ
	)
	if file == null:
		return _error(
			"crash_marker_read_failed",
			"crash marker could not be opened",
			{
				"error": int(FileAccess.get_open_error()),
			}
		)

	var length: int = file.get_length()
	if length < 1 or length > MAX_MARKER_BYTES:
		file.close()
		return _error(
			"crash_marker_invalid_size",
			"crash marker size is invalid",
			{
				"bytes": length,
			}
		)

	var text_value: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error: Error = parser.parse(text_value)
	if parse_error != OK:
		return _error(
			"crash_marker_invalid_json",
			"crash marker is not valid JSON",
			{
				"error": int(parse_error),
				"error_line": parser.get_error_line(),
				"error_message": (
					parser.get_error_message()
				),
			}
		)

	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return _error(
			"crash_marker_invalid_json",
			"crash marker is not a JSON object"
		)

	var marker: Dictionary = parsed as Dictionary
	var validation: Dictionary = _validate_marker(marker)
	if not bool(validation.get("ok", false)):
		return validation

	return _success(
		"crash_marker_read",
		{
			"marker": marker.duplicate(true),
		}
	)


func _validate_marker(marker: Dictionary) -> Dictionary:
	if int(marker.get("schema_version", 0)) != SCHEMA_VERSION:
		return _error(
			"crash_marker_schema_mismatch",
			"crash marker schema is unsupported"
		)
	if String(marker.get("state", "")) != "running":
		return _error(
			"crash_marker_state_invalid",
			"crash marker state is invalid"
		)

	var session_id: String = String(
		marker.get("session_id", "")
	).strip_edges()
	if session_id.is_empty():
		return _error(
			"crash_marker_session_id_missing",
			"crash marker session id is missing"
		)

	if int(marker.get("started_at_unix", 0)) <= 0:
		return _error(
			"crash_marker_started_at_invalid",
			"crash marker start time is invalid"
		)

	return _success("crash_marker_valid")


func _make_session_id() -> String:
	return "%d-%d-%d" % [
		int(
			Time.get_unix_time_from_system()
			* 1000.0
		),
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]


func _bounded_metadata(value: String) -> String:
	var normalized: String = value.strip_edges()
	if normalized.length() <= MAX_METADATA_LENGTH:
		return normalized
	return normalized.substr(0, MAX_METADATA_LENGTH)


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


static func _error_static(
	code: String,
	message: String
) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
