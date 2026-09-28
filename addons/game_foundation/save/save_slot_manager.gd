extends RefCounted

const SaveSystem = preload("res://addons/game_foundation/save/save_system.gd")

const DEFAULT_SLOTS_ROOT: String = "user://save_slots"
const SLOT_METADATA_FORMAT: String = "godot-game-foundation-save-slot"
const SLOT_METADATA_SCHEMA_VERSION: int = 1
const MAX_SLOT_ID_LENGTH: int = 64
const MAX_DISPLAY_NAME_LENGTH: int = 128

var _configured: bool = false
var _slots_root: String = DEFAULT_SLOTS_ROOT
var _current_game_schema_version: int = 1
var _migrator: Callable = Callable()


func configure(options: Dictionary = {}) -> Dictionary:
	var root_result: Dictionary = _normalize_root_path(
		String(options.get("slots_root", DEFAULT_SLOTS_ROOT))
	)
	if not bool(root_result.get("ok", false)):
		return root_result

	var game_schema_version: int = int(
		options.get("current_game_schema_version", 1)
	)
	if game_schema_version < 1:
		return _error(
			"invalid_game_schema_version",
			"current_game_schema_version must be 1 or greater"
		)

	var migrator_variant: Variant = options.get("migrator", Callable())
	if typeof(migrator_variant) != TYPE_CALLABLE:
		return _error("invalid_migrator", "migrator must be a Callable")

	_slots_root = String(root_result.get("path", DEFAULT_SLOTS_ROOT))
	_current_game_schema_version = game_schema_version
	_migrator = migrator_variant as Callable
	_configured = true

	return _success("save_slot_manager_configured", {
		"slots_root": _slots_root,
		"current_game_schema_version": _current_game_schema_version,
	})


func is_configured() -> bool:
	return _configured


func slots_root() -> String:
	return _slots_root


func validate_slot_id(slot_id: String) -> Dictionary:
	if slot_id.is_empty() or slot_id.length() > MAX_SLOT_ID_LENGTH:
		return _error(
			"invalid_slot_id",
			"slot_id must contain between 1 and %d characters" % MAX_SLOT_ID_LENGTH
		)

	var regex := RegEx.new()
	var compile_error: Error = regex.compile("^[a-z0-9][a-z0-9_-]{0,63}$")
	if compile_error != OK or regex.search(slot_id) == null:
		return _error(
			"invalid_slot_id",
			"slot_id may only use lowercase a-z, 0-9, underscore, and hyphen"
		)

	return _success("valid_slot_id", {"slot_id": slot_id})


func slot_path(slot_id: String) -> Dictionary:
	var configured_result: Dictionary = _require_configured()
	if not bool(configured_result.get("ok", false)):
		return configured_result

	var id_result: Dictionary = validate_slot_id(slot_id)
	if not bool(id_result.get("ok", false)):
		return id_result

	return _success("slot_path_resolved", {
		"slot_id": slot_id,
		"path": _slots_root + "/" + slot_id + ".json",
	})


func cloud_slot_descriptor(slot_id: String) -> Dictionary:
	var path_result: Dictionary = slot_path(slot_id)
	if not bool(path_result.get("ok", false)):
		return path_result

	var path: String = String(path_result.get("path", ""))
	return _success("cloud_slot_descriptor", {
		"slot_id": slot_id,
		"local_path": path,
		"local_backup_path": SaveSystem.backup_path(path),
		"metadata_format": SLOT_METADATA_FORMAT,
		"metadata_schema_version": SLOT_METADATA_SCHEMA_VERSION,
		"authority": "local_slot_manager",
		"cloud_provider": "external_adapter",
	})


func list_slots() -> Dictionary:
	var configured_result: Dictionary = _require_configured()
	if not bool(configured_result.get("ok", false)):
		return configured_result

	if not DirAccess.dir_exists_absolute(_slots_root):
		return _success("slots_listed", {
			"slots": [],
			"invalid_slots": [],
		})

	var directory := DirAccess.open(_slots_root)
	if directory == null:
		return _error(
			"slots_root_open_failed",
			"save slots directory could not be opened"
		)

	var slots: Array = []
	var invalid_slots: Array = []
	directory.list_dir_begin()
	while true:
		var file_name: String = directory.get_next()
		if file_name.is_empty():
			break
		if directory.current_is_dir():
			continue
		if not file_name.ends_with(".json"):
			continue
		if file_name.begins_with("._"):
			continue

		var slot_id: String = file_name.trim_suffix(".json")
		var id_result: Dictionary = validate_slot_id(slot_id)
		if not bool(id_result.get("ok", false)):
			continue

		var inspected: Dictionary = _inspect_slot(slot_id, true)
		if bool(inspected.get("ok", false)):
			slots.append(inspected.get("slot", {}))
		else:
			invalid_slots.append({
				"slot_id": slot_id,
				"code": String(inspected.get("code", "slot_inspect_failed")),
				"message": String(inspected.get("message", "")),
			})
	directory.list_dir_end()

	slots.sort_custom(Callable(self, "_slot_is_newer"))
	return _success("slots_listed", {
		"slots": slots,
		"invalid_slots": invalid_slots,
	})


func create_slot(
	slot_id: String,
	payload: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	var configured_result: Dictionary = _require_configured()
	if not bool(configured_result.get("ok", false)):
		return configured_result

	var path_result: Dictionary = slot_path(slot_id)
	if not bool(path_result.get("ok", false)):
		return path_result
	var path: String = String(path_result.get("path", ""))

	if _slot_artifacts_exist(path):
		return _error(
			"slot_already_exists",
			"slot or recovery artifacts already exist",
			{"slot_id": slot_id}
		)

	var presentation: Dictionary = _normalize_presentation(options, slot_id)
	if not bool(presentation.get("ok", false)):
		return presentation

	var now: int = int(Time.get_unix_time_from_system())
	var slot_metadata: Dictionary = _build_slot_metadata(
		slot_id,
		String(presentation.get("display_name", slot_id)),
		presentation.get("summary", {}) as Dictionary,
		now,
		now
	)

	var save_result: Dictionary = SaveSystem.save_game(
		payload,
		_current_game_schema_version,
		path,
		{"slot": slot_metadata}
	)
	if not bool(save_result.get("ok", false)):
		_cleanup_slot_artifacts(path)
		return save_result

	return _success("slot_created", {
		"slot_id": slot_id,
		"path": path,
		"slot": slot_metadata.duplicate(true),
		"save": save_result,
	})


func save_slot(
	slot_id: String,
	payload: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	var configured_result: Dictionary = _require_configured()
	if not bool(configured_result.get("ok", false)):
		return configured_result

	var current: Dictionary = _inspect_slot(slot_id, false)
	if not bool(current.get("ok", false)):
		return _error(
			"slot_not_writable",
			"slot primary must be healthy before it can be overwritten",
			{
				"slot_id": slot_id,
				"cause": current,
			}
		)

	var current_slot: Dictionary = current.get("slot", {}) as Dictionary
	var presentation: Dictionary = _normalize_presentation(
		options,
		String(current_slot.get("display_name", slot_id)),
		current_slot.get("summary", {}) as Dictionary
	)
	if not bool(presentation.get("ok", false)):
		return presentation

	var path_result: Dictionary = slot_path(slot_id)
	if not bool(path_result.get("ok", false)):
		return path_result
	var path: String = String(path_result.get("path", ""))

	var now: int = int(Time.get_unix_time_from_system())
	var slot_metadata: Dictionary = _build_slot_metadata(
		slot_id,
		String(presentation.get("display_name", slot_id)),
		presentation.get("summary", {}) as Dictionary,
		int(current_slot.get("created_at_unix", now)),
		now
	)

	var save_result: Dictionary = SaveSystem.save_game(
		payload,
		_current_game_schema_version,
		path,
		{"slot": slot_metadata}
	)
	if not bool(save_result.get("ok", false)):
		return save_result

	return _success("slot_saved", {
		"slot_id": slot_id,
		"path": path,
		"slot": slot_metadata.duplicate(true),
		"save": save_result,
	})


func load_slot(slot_id: String) -> Dictionary:
	var configured_result: Dictionary = _require_configured()
	if not bool(configured_result.get("ok", false)):
		return configured_result

	var path_result: Dictionary = slot_path(slot_id)
	if not bool(path_result.get("ok", false)):
		return path_result
	var path: String = String(path_result.get("path", ""))

	var load_result: Dictionary = SaveSystem.load_game(
		path,
		_current_game_schema_version,
		_migrator
	)
	if not bool(load_result.get("ok", false)):
		return load_result

	var metadata_variant: Variant = load_result.get("metadata", {})
	if not (metadata_variant is Dictionary):
		return _error("invalid_slot_metadata", "loaded slot metadata is missing")

	var slot_result: Dictionary = _validate_slot_metadata(
		slot_id,
		metadata_variant as Dictionary
	)
	if not bool(slot_result.get("ok", false)):
		return slot_result

	return _success("slot_loaded", {
		"slot_id": slot_id,
		"slot": slot_result.get("slot", {}),
		"payload": (load_result.get("payload", {}) as Dictionary).duplicate(true),
		"source": String(load_result.get("source", "primary")),
		"recovered_from_backup": bool(
			load_result.get("recovered_from_backup", false)
		),
		"migrated": bool(load_result.get("migrated", false)),
		"save": load_result,
	})


func continue_latest() -> Dictionary:
	var listed: Dictionary = list_slots()
	if not bool(listed.get("ok", false)):
		return listed

	var failures: Array = []
	for slot_variant in listed.get("slots", []) as Array:
		if not (slot_variant is Dictionary):
			continue
		var slot: Dictionary = slot_variant as Dictionary
		var slot_id: String = String(slot.get("slot_id", ""))
		var loaded: Dictionary = load_slot(slot_id)
		if bool(loaded.get("ok", false)):
			loaded["code"] = "continue_slot_loaded"
			loaded["continue_slot"] = slot.duplicate(true)
			loaded["skipped_slots"] = failures
			return loaded
		failures.append({
			"slot_id": slot_id,
			"code": String(loaded.get("code", "slot_load_failed")),
		})

	return _error(
		"no_loadable_slots",
		"no healthy save slot could be loaded",
		{
			"skipped_slots": failures,
			"invalid_slots": listed.get("invalid_slots", []),
		}
	)


func create_new_game(
	payload: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	var configured_result: Dictionary = _require_configured()
	if not bool(configured_result.get("ok", false)):
		return configured_result

	var requested_slot_id: String = String(options.get("slot_id", ""))
	var slot_id: String = requested_slot_id
	if slot_id.is_empty():
		slot_id = _generate_slot_id()

	var create_options: Dictionary = options.duplicate(true)
	create_options.erase("slot_id")
	var created: Dictionary = create_slot(slot_id, payload, create_options)
	if not bool(created.get("ok", false)):
		return created

	created["code"] = "new_game_slot_created"
	created["new_game"] = true
	return created


func delete_slot(slot_id: String) -> Dictionary:
	var configured_result: Dictionary = _require_configured()
	if not bool(configured_result.get("ok", false)):
		return configured_result

	var path_result: Dictionary = slot_path(slot_id)
	if not bool(path_result.get("ok", false)):
		return path_result
	var path: String = String(path_result.get("path", ""))

	if not FileAccess.file_exists(path):
		return _error(
			"slot_not_found",
			"slot primary does not exist",
			{"slot_id": slot_id}
		)

	var tombstone_path: String = (
		_slots_root
		+ "/._deleting_"
		+ slot_id
		+ "_"
		+ str(Time.get_ticks_usec())
		+ ".json"
	)
	var rename_error: Error = DirAccess.rename_absolute(path, tombstone_path)
	if rename_error != OK:
		return _error(
			"slot_delete_prepare_failed",
			"slot could not be moved out of the active namespace",
			{"error": rename_error}
		)

	var cleanup_paths: Array[String] = [
		tombstone_path,
		SaveSystem.backup_path(path),
		SaveSystem.temp_path(path),
		SaveSystem.backup_path(path) + SaveSystem.TEMP_SUFFIX,
	]
	var failed_paths: Array[String] = []
	for cleanup_path in cleanup_paths:
		if not FileAccess.file_exists(cleanup_path):
			continue
		var remove_error: Error = DirAccess.remove_absolute(cleanup_path)
		if remove_error != OK:
			failed_paths.append(cleanup_path)

	if not failed_paths.is_empty():
		return _error(
			"slot_delete_cleanup_incomplete",
			"slot left the active namespace but recovery artifacts remain",
			{
				"slot_id": slot_id,
				"failed_paths": failed_paths,
			}
		)

	return _success("slot_deleted", {"slot_id": slot_id})


func _inspect_slot(slot_id: String, allow_backup: bool) -> Dictionary:
	var path_result: Dictionary = slot_path(slot_id)
	if not bool(path_result.get("ok", false)):
		return path_result
	var path: String = String(path_result.get("path", ""))

	var inspected: Dictionary = SaveSystem.inspect_game(path, allow_backup)
	if not bool(inspected.get("ok", false)):
		return inspected

	var metadata_variant: Variant = inspected.get("metadata", {})
	if not (metadata_variant is Dictionary):
		return _error("invalid_slot_metadata", "slot save metadata is missing")

	var slot_result: Dictionary = _validate_slot_metadata(
		slot_id,
		metadata_variant as Dictionary
	)
	if not bool(slot_result.get("ok", false)):
		return slot_result

	return _success("slot_inspected", {
		"slot_id": slot_id,
		"slot": slot_result.get("slot", {}),
		"source": String(inspected.get("source", "primary")),
		"recovered_from_backup": bool(
			inspected.get("recovered_from_backup", false)
		),
	})


func _validate_slot_metadata(
	expected_slot_id: String,
	save_metadata: Dictionary
) -> Dictionary:
	var slot_variant: Variant = save_metadata.get("slot")
	if not (slot_variant is Dictionary):
		return _error("invalid_slot_metadata", "slot metadata is missing")

	var slot: Dictionary = slot_variant as Dictionary
	if String(slot.get("format", "")) != SLOT_METADATA_FORMAT:
		return _error("invalid_slot_metadata_format", "slot metadata format is not supported")
	if int(slot.get("metadata_schema_version", 0)) != SLOT_METADATA_SCHEMA_VERSION:
		return _error("unsupported_slot_metadata_schema", "slot metadata schema is not supported")

	var slot_id: String = String(slot.get("slot_id", ""))
	var id_result: Dictionary = validate_slot_id(slot_id)
	if not bool(id_result.get("ok", false)):
		return id_result
	if slot_id != expected_slot_id:
		return _error(
			"slot_id_mismatch",
			"slot metadata does not match its file identity",
			{
				"expected": expected_slot_id,
				"actual": slot_id,
			}
		)

	var display_name: String = String(slot.get("display_name", "")).strip_edges()
	if display_name.is_empty() or display_name.length() > MAX_DISPLAY_NAME_LENGTH:
		return _error("invalid_slot_display_name", "slot display name is invalid")

	var created_at_unix: int = int(slot.get("created_at_unix", 0))
	var updated_at_unix: int = int(slot.get("updated_at_unix", 0))
	if created_at_unix <= 0 or updated_at_unix <= 0:
		return _error("invalid_slot_timestamp", "slot timestamps must be positive")
	if updated_at_unix < created_at_unix:
		return _error("invalid_slot_timestamp", "slot updated time cannot precede creation")

	var slot_game_schema: int = int(slot.get("game_schema_version", 0))
	var envelope_game_schema: int = int(save_metadata.get("game_schema_version", 0))
	if slot_game_schema < 1 or slot_game_schema != envelope_game_schema:
		return _error(
			"slot_schema_mismatch",
			"slot metadata game schema must match the save envelope"
		)

	var summary_variant: Variant = slot.get("summary", {})
	if not (summary_variant is Dictionary):
		return _error("invalid_slot_summary", "slot summary must be a Dictionary")
	var summary: Dictionary = summary_variant as Dictionary
	var summary_validation: Dictionary = SaveSystem.validate_payload(summary)
	if not bool(summary_validation.get("ok", false)):
		return _error(
			"invalid_slot_summary",
			"slot summary must be JSON-compatible",
			{"validation": summary_validation}
		)

	return _success("valid_slot_metadata", {
		"slot": {
			"format": SLOT_METADATA_FORMAT,
			"metadata_schema_version": SLOT_METADATA_SCHEMA_VERSION,
			"slot_id": slot_id,
			"display_name": display_name,
			"created_at_unix": created_at_unix,
			"updated_at_unix": updated_at_unix,
			"game_schema_version": slot_game_schema,
			"summary": summary.duplicate(true),
		}
	})


func _normalize_presentation(
	options: Dictionary,
	default_display_name: String,
	default_summary: Dictionary = {}
) -> Dictionary:
	var display_name: String = String(
		options.get("display_name", default_display_name)
	).strip_edges()
	if display_name.is_empty() or display_name.length() > MAX_DISPLAY_NAME_LENGTH:
		return _error(
			"invalid_slot_display_name",
			"display_name must be between 1 and %d characters" % MAX_DISPLAY_NAME_LENGTH
		)

	var summary_variant: Variant = options.get("summary", default_summary)
	if not (summary_variant is Dictionary):
		return _error("invalid_slot_summary", "summary must be a Dictionary")
	var summary: Dictionary = (summary_variant as Dictionary).duplicate(true)
	var summary_validation: Dictionary = SaveSystem.validate_payload(summary)
	if not bool(summary_validation.get("ok", false)):
		return _error(
			"invalid_slot_summary",
			"summary must be JSON-compatible",
			{"validation": summary_validation}
		)

	return _success("valid_slot_presentation", {
		"display_name": display_name,
		"summary": summary,
	})


func _build_slot_metadata(
	slot_id: String,
	display_name: String,
	summary: Dictionary,
	created_at_unix: int,
	updated_at_unix: int
) -> Dictionary:
	return {
		"format": SLOT_METADATA_FORMAT,
		"metadata_schema_version": SLOT_METADATA_SCHEMA_VERSION,
		"slot_id": slot_id,
		"display_name": display_name,
		"created_at_unix": created_at_unix,
		"updated_at_unix": updated_at_unix,
		"game_schema_version": _current_game_schema_version,
		"summary": summary.duplicate(true),
	}


func _generate_slot_id() -> String:
	var base: String = "slot_" + str(int(Time.get_unix_time_from_system()))
	var candidate: String = base
	var suffix: int = 2
	while true:
		var path: String = _slots_root + "/" + candidate + ".json"
		if not _slot_artifacts_exist(path):
			return candidate
		candidate = base + "_" + str(suffix)
		suffix += 1


func _slot_artifacts_exist(path: String) -> bool:
	return (
		FileAccess.file_exists(path)
		or FileAccess.file_exists(SaveSystem.backup_path(path))
		or FileAccess.file_exists(SaveSystem.temp_path(path))
		or FileAccess.file_exists(
			SaveSystem.backup_path(path) + SaveSystem.TEMP_SUFFIX
		)
	)


func _cleanup_slot_artifacts(path: String) -> void:
	for cleanup_path in [
		path,
		SaveSystem.backup_path(path),
		SaveSystem.temp_path(path),
		SaveSystem.backup_path(path) + SaveSystem.TEMP_SUFFIX,
	]:
		if FileAccess.file_exists(cleanup_path):
			DirAccess.remove_absolute(cleanup_path)


func _normalize_root_path(path: String) -> Dictionary:
	var normalized: String = path.strip_edges()
	while normalized.ends_with("/"):
		normalized = normalized.left(normalized.length() - 1)

	if normalized.is_empty() or not normalized.begins_with("user://"):
		return _error("unsafe_slots_root", "slots_root must use user://")
	if normalized.contains("\\") or normalized.contains(".."):
		return _error("unsafe_slots_root", "slots_root contains unsafe path segments")
	if normalized == "user:/":
		return _error("unsafe_slots_root", "slots_root must be a child directory")

	return _success("valid_slots_root", {"path": normalized})


func _slot_is_newer(left: Dictionary, right: Dictionary) -> bool:
	var left_updated: int = int(left.get("updated_at_unix", 0))
	var right_updated: int = int(right.get("updated_at_unix", 0))
	if left_updated == right_updated:
		return String(left.get("slot_id", "")) < String(right.get("slot_id", ""))
	return left_updated > right_updated


func _require_configured() -> Dictionary:
	if not _configured:
		return _error(
			"save_slot_manager_not_configured",
			"configure() must be called before using save slots"
		)
	return _success("configured")


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
