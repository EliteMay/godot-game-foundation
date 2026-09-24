extends RefCounted

const FORMAT_ID: String = "godot-game-foundation-settings"
const SETTINGS_SCHEMA_VERSION: int = 1
const DEFAULT_SETTINGS_PATH: String = "user://settings.json"
const BACKUP_SUFFIX: String = ".bak"
const TEMP_SUFFIX: String = ".tmp"
const MAX_VALIDATION_DEPTH: int = 64
const MIN_WIDTH: int = 320
const MIN_HEIGHT: int = 200
const MAX_WIDTH: int = 16384
const MAX_HEIGHT: int = 16384


static func default_settings(gameplay_defaults: Dictionary = {}) -> Dictionary:
	var gameplay: Dictionary = {}
	if _is_json_compatible(gameplay_defaults):
		gameplay = gameplay_defaults.duplicate(true)

	return {
		"audio": {
			"master": 1.0,
			"bgm": 1.0,
			"sfx": 1.0,
		},
		"display": {
			"window_mode": "windowed",
			"resolution": [1280, 720],
			"vsync": true,
		},
		"gameplay": gameplay,
	}


static func normalize_settings(
	candidate: Dictionary,
	gameplay_defaults: Dictionary = {}
) -> Dictionary:
	if not _is_json_compatible(gameplay_defaults):
		return _error(
			"invalid_gameplay_defaults",
			"gameplay defaults must be JSON-compatible"
		)

	var normalized: Dictionary = default_settings(gameplay_defaults)
	var warnings: Array[String] = []

	var audio_variant: Variant = candidate.get("audio", {})
	if audio_variant is Dictionary:
		var audio_candidate: Dictionary = audio_variant as Dictionary
		var audio: Dictionary = normalized["audio"] as Dictionary
		audio["master"] = _volume_value(
			audio_candidate.get("master"),
			float(audio["master"])
		)
		audio["bgm"] = _volume_value(
			audio_candidate.get("bgm"),
			float(audio["bgm"])
		)
		audio["sfx"] = _volume_value(
			audio_candidate.get("sfx"),
			float(audio["sfx"])
		)
	else:
		warnings.append("audio_invalid")

	var display_variant: Variant = candidate.get("display", {})
	if display_variant is Dictionary:
		var display_candidate: Dictionary = display_variant as Dictionary
		var display: Dictionary = normalized["display"] as Dictionary

		var mode_variant: Variant = display_candidate.get("window_mode")
		if typeof(mode_variant) == TYPE_STRING:
			var mode: String = String(mode_variant)
			if mode in ["windowed", "fullscreen", "borderless"]:
				display["window_mode"] = mode
			else:
				warnings.append("window_mode_invalid")

		var resolution_variant: Variant = display_candidate.get("resolution")
		if resolution_variant is Array:
			var resolution: Array = resolution_variant as Array
			if resolution.size() == 2 and _is_number(resolution[0]) and _is_number(resolution[1]):
				display["resolution"] = [
					clampi(int(resolution[0]), MIN_WIDTH, MAX_WIDTH),
					clampi(int(resolution[1]), MIN_HEIGHT, MAX_HEIGHT),
				]
			elif not resolution.is_empty():
				warnings.append("resolution_invalid")
		elif resolution_variant != null:
			warnings.append("resolution_invalid")

		var vsync_variant: Variant = display_candidate.get("vsync")
		if typeof(vsync_variant) == TYPE_BOOL:
			display["vsync"] = bool(vsync_variant)
		elif vsync_variant != null:
			warnings.append("vsync_invalid")
	else:
		warnings.append("display_invalid")

	var gameplay_variant: Variant = candidate.get("gameplay", {})
	if gameplay_variant is Dictionary:
		var gameplay_candidate: Dictionary = gameplay_variant as Dictionary
		if _is_json_compatible(gameplay_candidate):
			normalized["gameplay"] = _deep_merge(
				gameplay_defaults.duplicate(true),
				gameplay_candidate
			)
		else:
			warnings.append("gameplay_invalid")
	elif gameplay_variant != null:
		warnings.append("gameplay_invalid")

	return _success("normalized", {
		"settings": normalized,
		"warnings": warnings,
	})


static func save_settings(
	settings: Dictionary,
	gameplay_defaults: Dictionary = {},
	path: String = DEFAULT_SETTINGS_PATH
) -> Dictionary:
	var path_result: Dictionary = _validate_settings_path(path)
	if not bool(path_result.get("ok", false)):
		return path_result

	var normalized_result: Dictionary = normalize_settings(
		settings,
		gameplay_defaults
	)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	var normalized: Dictionary = normalized_result.get("settings", {})
	var envelope: Dictionary = {
		"metadata": {
			"format": FORMAT_ID,
			"settings_schema_version": SETTINGS_SCHEMA_VERSION,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
		},
		"settings": normalized,
	}

	var write_result: Dictionary = _write_envelope_atomic(path, envelope)
	if not bool(write_result.get("ok", false)):
		return write_result

	return _success("saved", {
		"path": path,
		"settings": normalized,
		"warnings": normalized_result.get("warnings", []),
	})


static func load_settings(
	gameplay_defaults: Dictionary = {},
	path: String = DEFAULT_SETTINGS_PATH
) -> Dictionary:
	if not _is_json_compatible(gameplay_defaults):
		return _error(
			"invalid_gameplay_defaults",
			"gameplay defaults must be JSON-compatible"
		)

	var path_result: Dictionary = _validate_settings_path(path)
	if not bool(path_result.get("ok", false)):
		return path_result

	var primary: Dictionary = _load_from_path(path, gameplay_defaults)
	if bool(primary.get("ok", false)):
		var backup_result: Dictionary = _copy_atomic(path, backup_path(path))
		primary["source"] = "primary"
		primary["backup_refreshed"] = bool(backup_result.get("ok", false))
		return primary

	var primary_code: String = String(primary.get("code", "load_failed"))
	if _should_try_backup(primary_code):
		var backup: Dictionary = _load_from_path(
			backup_path(path),
			gameplay_defaults
		)
		if bool(backup.get("ok", false)):
			backup["source"] = "backup"
			backup["recovered_from_backup"] = true
			backup["primary_error"] = primary_code
			return backup

	return _success("defaults_used", {
		"source": "defaults",
		"settings": default_settings(gameplay_defaults),
		"warning": primary_code,
	})


static func reset_settings(
	gameplay_defaults: Dictionary = {},
	path: String = DEFAULT_SETTINGS_PATH
) -> Dictionary:
	if not _is_json_compatible(gameplay_defaults):
		return _error(
			"invalid_gameplay_defaults",
			"gameplay defaults must be JSON-compatible"
		)

	var path_result: Dictionary = _validate_settings_path(path)
	if not bool(path_result.get("ok", false)):
		return path_result

	_remove_if_exists(path)
	_remove_if_exists(backup_path(path))
	_remove_if_exists(temp_path(path))
	_remove_if_exists(backup_path(path) + TEMP_SUFFIX)

	return _success("reset", {
		"settings": default_settings(gameplay_defaults),
	})


static func backup_path(path: String) -> String:
	return path + BACKUP_SUFFIX


static func temp_path(path: String) -> String:
	return path + TEMP_SUFFIX


static func _load_from_path(
	path: String,
	gameplay_defaults: Dictionary
) -> Dictionary:
	var read_result: Dictionary = _read_envelope(path)
	if not bool(read_result.get("ok", false)):
		return read_result

	var envelope_variant: Variant = read_result.get("envelope", {})
	if not (envelope_variant is Dictionary):
		return _error("invalid_envelope", "settings root must be a Dictionary")

	var envelope: Dictionary = envelope_variant as Dictionary
	var metadata_variant: Variant = envelope.get("metadata")
	if not (metadata_variant is Dictionary):
		return _error("invalid_metadata", "settings metadata must be a Dictionary")

	var metadata: Dictionary = metadata_variant as Dictionary
	if String(metadata.get("format", "")) != FORMAT_ID:
		return _error("unsupported_format", "settings format is not supported")

	var schema_version: int = int(metadata.get("settings_schema_version", 0))
	if schema_version < SETTINGS_SCHEMA_VERSION:
		return _error("settings_schema_too_old", "settings schema requires migration")
	if schema_version > SETTINGS_SCHEMA_VERSION:
		return _error("settings_schema_too_new", "settings file was written by a newer schema")

	var settings_variant: Variant = envelope.get("settings")
	if not (settings_variant is Dictionary):
		return _error("invalid_settings", "settings must be a Dictionary")

	var normalized_result: Dictionary = normalize_settings(
		settings_variant as Dictionary,
		gameplay_defaults
	)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	return _success("loaded", {
		"path": path,
		"settings": normalized_result.get("settings", {}),
		"warnings": normalized_result.get("warnings", []),
		"settings_schema_version": schema_version,
	})


static func _write_envelope_atomic(path: String, envelope: Dictionary) -> Dictionary:
	var directory: String = path.get_base_dir()
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		return _error(
			"directory_create_failed",
			"settings directory could not be created",
			{"error": make_dir_error}
		)

	var temp: String = temp_path(path)
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _error(
			"temp_open_failed",
			"temporary settings file could not be opened",
			{"error": FileAccess.get_open_error()}
		)

	file.store_string(JSON.stringify(envelope, "\t"))
	file.flush()
	file.close()

	var temp_validation: Dictionary = _read_envelope(temp)
	if not bool(temp_validation.get("ok", false)):
		_remove_if_exists(temp)
		return _error(
			"temp_validation_failed",
			"temporary settings file failed validation"
		)

	if FileAccess.file_exists(path):
		var previous: Dictionary = _read_envelope(path)
		if bool(previous.get("ok", false)):
			var backup_result: Dictionary = _copy_atomic(path, backup_path(path))
			if not bool(backup_result.get("ok", false)):
				_remove_if_exists(temp)
				return _error(
					"backup_write_failed",
					"existing settings could not be backed up",
					{"backup": backup_result}
				)

	var rename_error: Error = DirAccess.rename_absolute(temp, path)
	if rename_error != OK:
		_remove_if_exists(temp)
		return _error(
			"atomic_replace_failed",
			"temporary settings could not replace the primary file",
			{"error": rename_error}
		)

	return _success("atomic_write_complete", {"path": path})


static func _copy_atomic(source: String, destination: String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return _error("source_not_found", "source settings file does not exist")

	var temp_destination: String = destination + TEMP_SUFFIX
	_remove_if_exists(temp_destination)

	var copy_error: Error = DirAccess.copy_absolute(source, temp_destination)
	if copy_error != OK:
		return _error(
			"backup_copy_failed",
			"settings backup copy failed",
			{"error": copy_error}
		)

	var copied_validation: Dictionary = _read_envelope(temp_destination)
	if not bool(copied_validation.get("ok", false)):
		_remove_if_exists(temp_destination)
		return _error(
			"backup_validation_failed",
			"settings backup failed validation"
		)

	var rename_error: Error = DirAccess.rename_absolute(
		temp_destination,
		destination
	)
	if rename_error != OK:
		_remove_if_exists(temp_destination)
		return _error(
			"backup_replace_failed",
			"settings backup replacement failed",
			{"error": rename_error}
		)

	return _success("backup_written", {"path": destination})


static func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("not_found", "settings file does not exist", {"path": path})

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error(
			"read_failed",
			"settings file could not be opened",
			{"path": path, "error": FileAccess.get_open_error()}
		)

	var text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return _error(
			"parse_error",
			"settings JSON could not be parsed",
			{
				"path": path,
				"line": parser.get_error_line(),
				"message": parser.get_error_message(),
			}
		)

	if not (parser.data is Dictionary):
		return _error(
			"invalid_envelope",
			"settings root must be a Dictionary",
			{"path": path}
		)

	return _success("read", {"envelope": parser.data})


static func _validate_settings_path(path: String) -> Dictionary:
	if path.is_empty():
		return _error("invalid_path", "settings path is empty")
	if not path.begins_with("user://"):
		return _error("unsafe_path", "runtime settings must use user://")
	if path.ends_with("/") or path.ends_with("\\"):
		return _error("invalid_path", "settings path must point to a file")
	return _success("valid_path")


static func _volume_value(value: Variant, fallback: float) -> float:
	if not _is_number(value):
		return fallback
	return clampf(float(value), 0.0, 1.0)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _deep_merge(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true)
	for key in overlay.keys():
		if typeof(key) != TYPE_STRING:
			continue

		var overlay_value: Variant = overlay[key]
		var base_value: Variant = merged.get(key)
		if overlay_value is Dictionary and base_value is Dictionary:
			merged[key] = _deep_merge(
				base_value as Dictionary,
				overlay_value as Dictionary
			)
		else:
			merged[key] = overlay_value
	return merged


static func _is_json_compatible(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_VALIDATION_DEPTH:
		return false

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			var number: float = float(value)
			return number == number and number != INF and number != -INF
		TYPE_ARRAY:
			for item in value as Array:
				if not _is_json_compatible(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value as Dictionary
			for key in dictionary.keys():
				if typeof(key) != TYPE_STRING:
					return false
				if not _is_json_compatible(dictionary[key], depth + 1):
					return false
			return true
		_:
			return false


static func _should_try_backup(code: String) -> bool:
	return code in [
		"not_found",
		"read_failed",
		"parse_error",
		"invalid_envelope",
		"invalid_metadata",
		"invalid_settings",
		"unsupported_format",
	]


static func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"code": code,
	}
	for key in extra:
		result[key] = extra[key]
	return result


static func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"code": code,
		"message": message,
	}
	for key in extra:
		result[key] = extra[key]
	return result
