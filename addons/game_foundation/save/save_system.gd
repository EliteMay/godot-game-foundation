extends RefCounted

const FORMAT_ID: String = "godot-game-foundation-save"
const FOUNDATION_SCHEMA_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://save.json"
const BACKUP_SUFFIX: String = ".bak"
const TEMP_SUFFIX: String = ".tmp"
const MAX_VALIDATION_DEPTH: int = 64


static func validate_payload(payload: Dictionary) -> Dictionary:
	return _validate_json_value(payload, "$", 0)


static func save_game(
	payload: Dictionary,
	game_schema_version: int,
	path: String = DEFAULT_SAVE_PATH
) -> Dictionary:
	if game_schema_version < 1:
		return _error("invalid_game_schema_version", "game_schema_version must be 1 or greater")

	var validation: Dictionary = validate_payload(payload)
	if not bool(validation.get("ok", false)):
		return validation

	var path_error: Dictionary = _validate_save_path(path)
	if not bool(path_error.get("ok", false)):
		return path_error

	var envelope: Dictionary = {
		"metadata": {
			"format": FORMAT_ID,
			"foundation_schema_version": FOUNDATION_SCHEMA_VERSION,
			"game_schema_version": game_schema_version,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
		},
		"payload": payload.duplicate(true),
	}

	var write_result: Dictionary = _write_envelope_atomic(path, envelope)
	if not bool(write_result.get("ok", false)):
		return write_result

	return _success("saved", {
		"path": path,
		"backup_path": backup_path(path),
		"game_schema_version": game_schema_version,
	})


static func load_game(
	path: String = DEFAULT_SAVE_PATH,
	current_game_schema_version: int = 1,
	migrator: Callable = Callable()
) -> Dictionary:
	if current_game_schema_version < 1:
		return _error("invalid_game_schema_version", "current_game_schema_version must be 1 or greater")

	var path_error: Dictionary = _validate_save_path(path)
	if not bool(path_error.get("ok", false)):
		return path_error

	var primary: Dictionary = _load_from_path(path, current_game_schema_version, migrator)
	if bool(primary.get("ok", false)):
		var backup_result: Dictionary = _copy_atomic(path, backup_path(path))
		primary["source"] = "primary"
		primary["backup_refreshed"] = bool(backup_result.get("ok", false))
		return primary

	var primary_code: String = String(primary.get("code", "load_failed"))
	if not _should_try_backup(primary_code):
		primary["source"] = "primary"
		return primary

	var backup: Dictionary = _load_from_path(
		backup_path(path),
		current_game_schema_version,
		migrator
	)
	if bool(backup.get("ok", false)):
		backup["source"] = "backup"
		backup["recovered_from_backup"] = true
		backup["primary_error"] = primary_code
		return backup

	primary["source"] = "primary"
	primary["backup_error"] = String(backup.get("code", "backup_load_failed"))
	return primary


static func backup_path(path: String) -> String:
	return path + BACKUP_SUFFIX


static func temp_path(path: String) -> String:
	return path + TEMP_SUFFIX


static func _load_from_path(
	path: String,
	current_game_schema_version: int,
	migrator: Callable
) -> Dictionary:
	var read_result: Dictionary = _read_envelope(path)
	if not bool(read_result.get("ok", false)):
		return read_result

	var envelope_variant: Variant = read_result.get("envelope", {})
	if not (envelope_variant is Dictionary):
		return _error("invalid_envelope", "save root must be a Dictionary")

	var envelope: Dictionary = envelope_variant as Dictionary
	var metadata_variant: Variant = envelope.get("metadata")
	if not (metadata_variant is Dictionary):
		return _error("invalid_metadata", "metadata must be a Dictionary")

	var metadata: Dictionary = metadata_variant as Dictionary
	if String(metadata.get("format", "")) != FORMAT_ID:
		return _error("unsupported_format", "save format is not supported")

	if not metadata.has("foundation_schema_version"):
		return _error("missing_foundation_schema_version", "foundation schema version is missing")
	if not metadata.has("game_schema_version"):
		return _error("missing_game_schema_version", "game schema version is missing")
	if not envelope.has("payload"):
		return _error("missing_payload", "payload is missing")

	var foundation_schema_version: int = int(metadata.get("foundation_schema_version", 0))
	var saved_game_schema_version: int = int(metadata.get("game_schema_version", 0))

	if foundation_schema_version < FOUNDATION_SCHEMA_VERSION:
		return _error("foundation_schema_too_old", "foundation schema requires an internal migration")
	if foundation_schema_version > FOUNDATION_SCHEMA_VERSION:
		return _error("foundation_schema_too_new", "save was written by a newer Foundation schema")
	if saved_game_schema_version < 1:
		return _error("invalid_saved_game_schema_version", "saved game schema version is invalid")
	if saved_game_schema_version > current_game_schema_version:
		return _error("game_schema_too_new", "save belongs to a newer game schema")

	var payload_variant: Variant = envelope.get("payload")
	if not (payload_variant is Dictionary):
		return _error("invalid_payload", "payload must be a Dictionary")

	var payload: Dictionary = (payload_variant as Dictionary).duplicate(true)
	var validation: Dictionary = validate_payload(payload)
	if not bool(validation.get("ok", false)):
		return _error(
			"invalid_payload",
			"saved payload is not JSON-compatible",
			{"validation": validation}
		)

	var migrated: bool = false
	if saved_game_schema_version < current_game_schema_version:
		if not migrator.is_valid():
			return _error(
				"migration_required",
				"save uses an older game schema and no migrator was provided",
				{
					"saved_game_schema_version": saved_game_schema_version,
					"current_game_schema_version": current_game_schema_version,
				}
			)

		var migrated_variant: Variant = migrator.call(
			payload.duplicate(true),
			saved_game_schema_version,
			current_game_schema_version
		)
		if not (migrated_variant is Dictionary):
			return _error("migration_failed", "migrator must return a Dictionary payload")

		payload = (migrated_variant as Dictionary).duplicate(true)
		var migrated_validation: Dictionary = validate_payload(payload)
		if not bool(migrated_validation.get("ok", false)):
			return _error(
				"migration_invalid_payload",
				"migrated payload is not JSON-compatible",
				{"validation": migrated_validation}
			)
		migrated = true

	return _success("loaded", {
		"path": path,
		"payload": payload,
		"saved_game_schema_version": saved_game_schema_version,
		"game_schema_version": current_game_schema_version,
		"foundation_schema_version": foundation_schema_version,
		"migrated": migrated,
	})


static func _write_envelope_atomic(path: String, envelope: Dictionary) -> Dictionary:
	var directory: String = path.get_base_dir()
	if directory.is_empty():
		return _error("invalid_path", "save path must include a directory")

	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		return _error(
			"directory_create_failed",
			"save directory could not be created",
			{"error": make_dir_error}
		)

	var temp: String = temp_path(path)
	var text: String = JSON.stringify(envelope, "\t")

	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _error(
			"temp_open_failed",
			"temporary save file could not be opened",
			{"error": FileAccess.get_open_error()}
		)

	file.store_string(text)
	file.flush()
	file.close()

	var temp_validation: Dictionary = _read_envelope(temp)
	if not bool(temp_validation.get("ok", false)):
		_remove_if_exists(temp)
		return _error(
			"temp_validation_failed",
			"temporary save file failed read-back validation",
			{"validation": temp_validation}
		)

	if FileAccess.file_exists(path):
		var previous: Dictionary = _read_envelope(path)
		if bool(previous.get("ok", false)):
			var backup_result: Dictionary = _copy_atomic(path, backup_path(path))
			if not bool(backup_result.get("ok", false)):
				_remove_if_exists(temp)
				return _error(
					"backup_write_failed",
					"existing valid save could not be backed up",
					{"backup": backup_result}
				)

	var rename_error: Error = DirAccess.rename_absolute(temp, path)
	if rename_error != OK:
		_remove_if_exists(temp)
		return _error(
			"atomic_replace_failed",
			"temporary save could not replace the primary save",
			{"error": rename_error}
		)

	return _success("atomic_write_complete", {"path": path})


static func _copy_atomic(source: String, destination: String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return _error("source_not_found", "source file does not exist")

	var temp_destination: String = destination + TEMP_SUFFIX
	_remove_if_exists(temp_destination)

	var copy_error: Error = DirAccess.copy_absolute(source, temp_destination)
	if copy_error != OK:
		return _error("backup_copy_failed", "file copy failed", {"error": copy_error})

	var copied_validation: Dictionary = _read_envelope(temp_destination)
	if not bool(copied_validation.get("ok", false)):
		_remove_if_exists(temp_destination)
		return _error(
			"backup_validation_failed",
			"copied backup failed validation",
			{"validation": copied_validation}
		)

	var rename_error: Error = DirAccess.rename_absolute(temp_destination, destination)
	if rename_error != OK:
		_remove_if_exists(temp_destination)
		return _error("backup_replace_failed", "backup replacement failed", {"error": rename_error})

	return _success("backup_written", {"path": destination})


static func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("not_found", "save file does not exist", {"path": path})

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error(
			"read_failed",
			"save file could not be opened",
			{"path": path, "error": FileAccess.get_open_error()}
		)

	var text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return _error(
			"parse_error",
			"save JSON could not be parsed",
			{
				"path": path,
				"line": parser.get_error_line(),
				"message": parser.get_error_message(),
			}
		)

	var data: Variant = parser.data
	if not (data is Dictionary):
		return _error("invalid_envelope", "save root must be a Dictionary", {"path": path})

	return _success("read", {"envelope": data})


static func _validate_save_path(path: String) -> Dictionary:
	if path.is_empty():
		return _error("invalid_path", "save path is empty")
	if not path.begins_with("user://"):
		return _error("unsafe_path", "runtime saves must use user://")
	if path.ends_with("/") or path.ends_with("\\"):
		return _error("invalid_path", "save path must point to a file")
	return _success("valid_path")


static func _validate_json_value(value: Variant, path: String, depth: int) -> Dictionary:
	if depth > MAX_VALIDATION_DEPTH:
		return _error(
			"payload_too_deep",
			"payload nesting exceeds the supported depth",
			{"path": path}
		)

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return _success("valid")
		TYPE_FLOAT:
			var number: float = float(value)
			if number != number or number == INF or number == -INF:
				return _error(
					"invalid_number",
					"payload contains NaN or Infinity",
					{"path": path}
				)
			return _success("valid")
		TYPE_ARRAY:
			var array_value: Array = value as Array
			for index in range(array_value.size()):
				var item_result: Dictionary = _validate_json_value(
					array_value[index],
					"%s[%d]" % [path, index],
					depth + 1
				)
				if not bool(item_result.get("ok", false)):
					return item_result
			return _success("valid")
		TYPE_DICTIONARY:
			var dictionary_value: Dictionary = value as Dictionary
			for key in dictionary_value.keys():
				if typeof(key) != TYPE_STRING:
					return _error(
						"non_string_key",
						"Dictionary keys must be String",
						{"path": path}
					)
				var child_result: Dictionary = _validate_json_value(
					dictionary_value[key],
					"%s.%s" % [path, String(key)],
					depth + 1
				)
				if not bool(child_result.get("ok", false)):
					return child_result
			return _success("valid")
		_:
			return _error(
				"unsupported_type",
				"payload contains a non-JSON-compatible value",
				{"path": path, "type": type_string(typeof(value))}
			)


static func _should_try_backup(code: String) -> bool:
	return code in [
		"not_found",
		"read_failed",
		"parse_error",
		"invalid_envelope",
		"invalid_metadata",
		"missing_foundation_schema_version",
		"missing_game_schema_version",
		"missing_payload",
		"unsupported_format",
		"invalid_saved_game_schema_version",
		"invalid_payload",
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
