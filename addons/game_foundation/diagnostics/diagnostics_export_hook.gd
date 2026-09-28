extends RefCounted

const EXPORT_SCHEMA_VERSION: int = 1
const DEFAULT_MAX_RECENT_ENTRIES: int = 20
const MAX_RECENT_ENTRIES: int = 30
const MAX_RECENT_ERRORS: int = 10
const MAX_STRING_LENGTH: int = 1024
const MAX_CONTEXT_DEPTH: int = 5
const MAX_COLLECTION_ITEMS: int = 20
const MAX_PAYLOAD_BYTES: int = 128 * 1024

const REDACTED: String = "<redacted>"
const REDACTED_PATH: String = "<redacted-path>"
const TRUNCATED_SUFFIX: String = "...<truncated>"

const SENSITIVE_KEY_FRAGMENTS: Array[String] = [
	"password",
	"passwd",
	"secret",
	"token",
	"api_key",
	"apikey",
	"authorization",
	"auth_header",
	"cookie",
	"credential",
	"private_key",
	"access_key",
	"refresh_key",
]


static func build_export(
	diagnostics_snapshot: Dictionary,
	runtime_status: Dictionary = {},
	options: Dictionary = {}
) -> Dictionary:
	var max_recent_entries: int = clampi(
		int(
			options.get(
				"max_recent_entries",
				DEFAULT_MAX_RECENT_ENTRIES
			)
		),
		0,
		MAX_RECENT_ENTRIES
	)
	var reason: String = _sanitize_text(
		String(options.get("reason", "manual"))
	)

	var payload: Dictionary = _build_payload(
		diagnostics_snapshot,
		runtime_status,
		max_recent_entries,
		reason
	)
	var json_text: String = JSON.stringify(payload)
	var payload_bytes: int = json_text.to_utf8_buffer().size()
	var trimmed_for_size: bool = false

	if payload_bytes > MAX_PAYLOAD_BYTES:
		trimmed_for_size = true
		payload["recent_entries"] = []
		var errors: Dictionary = (
			payload.get("errors", {}) as Dictionary
		)
		errors["recent_errors"] = []
		payload["errors"] = errors
		json_text = JSON.stringify(payload)
		payload_bytes = json_text.to_utf8_buffer().size()

	if payload_bytes > MAX_PAYLOAD_BYTES:
		return _error(
			"diagnostics_export_too_large",
			"sanitized diagnostics export exceeds the size limit",
			{
				"payload_bytes": payload_bytes,
				"max_payload_bytes": MAX_PAYLOAD_BYTES,
			}
		)

	var handoff: Dictionary = (
		payload.get("handoff", {}) as Dictionary
	)
	handoff["trimmed_for_size"] = trimmed_for_size
	payload["handoff"] = handoff

	for _index in range(4):
		json_text = JSON.stringify(payload)
		payload_bytes = json_text.to_utf8_buffer().size()
		handoff["payload_bytes"] = payload_bytes
		payload["handoff"] = handoff

	json_text = JSON.stringify(payload)
	payload_bytes = json_text.to_utf8_buffer().size()
	if payload_bytes > MAX_PAYLOAD_BYTES:
		return _error(
			"diagnostics_export_too_large",
			"sanitized diagnostics export exceeds the size limit",
			{
				"payload_bytes": payload_bytes,
				"max_payload_bytes": MAX_PAYLOAD_BYTES,
			}
		)

	return _success(
		"diagnostics_export_built",
		{
			"payload": payload,
			"json": json_text,
			"payload_bytes": payload_bytes,
		}
	)


static func _build_payload(
	snapshot: Dictionary,
	runtime_status: Dictionary,
	max_recent_entries: int,
	reason: String
) -> Dictionary:
	var runtime_info: Dictionary = (
		snapshot.get("runtime", {}) as Dictionary
	)
	var app: Dictionary = (
		runtime_info.get("app", {}) as Dictionary
	)
	var foundation: Dictionary = (
		runtime_info.get("foundation", {}) as Dictionary
	)
	var engine: Dictionary = (
		runtime_info.get("engine", {}) as Dictionary
	)
	var environment: Dictionary = (
		runtime_info.get("runtime", {}) as Dictionary
	)
	var errors: Dictionary = (
		snapshot.get("errors", {}) as Dictionary
	)
	var performance: Dictionary = (
		snapshot.get("performance", {}) as Dictionary
	)

	return {
		"schemaVersion": EXPORT_SCHEMA_VERSION,
		"source": "godot-game-foundation",
		"capture": {
			"timestamp_unix": int(
				Time.get_unix_time_from_system()
			),
			"reason": reason,
		},
		"project": {
			"name": _sanitize_text(
				String(app.get("name", ""))
			),
			"app_version": _sanitize_text(
				String(app.get("version", ""))
			),
			"foundation_version": _sanitize_text(
				String(foundation.get("version", ""))
			),
		},
		"environment": {
			"engine_version": _sanitize_text(
				String(engine.get("version", ""))
			),
			"os": _sanitize_text(
				String(environment.get("os", ""))
			),
			"os_version": _sanitize_text(
				String(environment.get("os_version", ""))
			),
			"display_server": _sanitize_text(
				String(
					environment.get(
						"display_server",
						""
					)
				)
			),
			"headless": bool(
				environment.get("headless", false)
			),
			"debug_build": bool(
				environment.get("debug_build", false)
			),
			"processor_count": int(
				environment.get("processor_count", 0)
			),
		},
		"runtime": _sanitize_runtime_status(
			runtime_status
		),
		"paths": _sanitize_paths(
			snapshot.get("paths", {})
		),
		"errors": {
			"info_count": int(
				errors.get("info_count", 0)
			),
			"warning_count": int(
				errors.get("warning_count", 0)
			),
			"error_count": int(
				errors.get("error_count", 0)
			),
			"recent_errors": _sanitize_entries(
				errors.get("recent_errors", []),
				MAX_RECENT_ERRORS
			),
		},
		"recent_entries": _sanitize_entries(
			snapshot.get("recent_entries", []),
			max_recent_entries
		),
		"performance": {
			"fps": float(
				performance.get("fps", 0.0)
			),
		},
		"handoff": {
			"sanitized": true,
			"remote_eligible": true,
			"contains_binary": false,
			"known_sensitive_fields_redacted": true,
			"home_paths_redacted": true,
			"max_payload_bytes": MAX_PAYLOAD_BYTES,
			"payload_bytes": 0,
			"trimmed_for_size": false,
		},
	}


static func _sanitize_runtime_status(
	status: Dictionary
) -> Dictionary:
	var failure: Dictionary = (
		status.get("runtime_failure", {}) as Dictionary
	)
	var crash_marker: Dictionary = (
		status.get("crash_marker", {}) as Dictionary
	)
	return {
		"configured": bool(
			status.get("configured", false)
		),
		"initialized": bool(
			status.get("initialized", false)
		),
		"runtime_test_mode": bool(
			status.get("runtime_test_mode", false)
		),
		"diagnostics_enabled": bool(
			status.get("diagnostics_enabled", false)
		),
		"save_enabled": bool(
			status.get("save_enabled", false)
		),
		"save_writes_blocked": bool(
			status.get("save_writes_blocked", false)
		),
		"crash_marker_enabled": bool(
			status.get("crash_marker_enabled", false)
		),
		"crash_marker_active": bool(
			crash_marker.get("active", false)
		),
		"previous_session": _sanitize_previous_session(
			crash_marker.get(
				"previous_session",
				{}
			)
		),
		"has_runtime_failure": bool(
			status.get("has_runtime_failure", false)
		),
		"runtime_failure": _sanitize_failure(
			failure
		),
	}


static func _sanitize_previous_session(
	value: Variant
) -> Dictionary:
	if not (value is Dictionary):
		return {
			"marker_found": false,
			"possible_unclean_exit": false,
			"reason": "unavailable",
		}

	var source: Dictionary = value as Dictionary
	var result: Dictionary = {
		"marker_found": bool(
			source.get("marker_found", false)
		),
		"possible_unclean_exit": bool(
			source.get(
				"possible_unclean_exit",
				false
			)
		),
		"reason": _sanitize_text(
			String(source.get("reason", ""))
		),
	}
	if source.has("marker_valid"):
		result["marker_valid"] = bool(
			source.get("marker_valid", false)
		)
	if source.has("previous_started_at_unix"):
		result["previous_started_at_unix"] = int(
			source.get(
				"previous_started_at_unix",
				0
			)
		)
	if source.has("app_version"):
		result["app_version"] = _sanitize_text(
			String(source.get("app_version", ""))
		)
	if source.has("foundation_version"):
		result["foundation_version"] = (
			_sanitize_text(
				String(
					source.get(
						"foundation_version",
						""
					)
				)
			)
		)
	return result


static func _sanitize_failure(
	failure: Dictionary
) -> Dictionary:
	if not bool(failure.get("active", false)):
		return {
			"active": false,
		}
	return {
		"active": true,
		"kind": _sanitize_text(
			String(failure.get("kind", ""))
		),
		"stage": _sanitize_text(
			String(failure.get("stage", ""))
		),
		"code": _sanitize_text(
			String(failure.get("code", ""))
		),
		"message": _sanitize_text(
			String(failure.get("message", ""))
		),
		"retry_supported": bool(
			failure.get("retry_supported", false)
		),
		"save_writes_blocked": bool(
			failure.get("save_writes_blocked", false)
		),
		"diagnostics_available": bool(
			failure.get("diagnostics_available", false)
		),
	}


static func _sanitize_paths(
	paths_variant: Variant
) -> Dictionary:
	if not (paths_variant is Dictionary):
		return {}
	var paths: Dictionary = paths_variant as Dictionary
	var result: Dictionary = {}
	var keys: Array = paths.keys()
	keys.sort()
	var count: int = 0
	for raw_key in keys:
		if count >= MAX_COLLECTION_ITEMS:
			break
		var key: String = _sanitize_text(
			String(raw_key)
		)
		var path_value: String = String(
			paths[raw_key]
		)
		result[key] = _sanitize_path(path_value)
		count += 1
	return result


static func _sanitize_path(value: String) -> String:
	var trimmed: String = value.strip_edges()
	if (
		trimmed.begins_with("user://")
		or trimmed.begins_with("res://")
	):
		return _truncate_text(trimmed)
	if trimmed.is_empty():
		return ""
	return REDACTED_PATH


static func _sanitize_entries(
	entries_variant: Variant,
	limit: int
) -> Array:
	if not (entries_variant is Array):
		return []
	var entries: Array = entries_variant as Array
	var safe_limit: int = clampi(
		limit,
		0,
		MAX_RECENT_ENTRIES
	)
	if safe_limit == 0:
		return []
	var start: int = maxi(
		0,
		entries.size() - safe_limit
	)
	var result: Array = []
	for index in range(start, entries.size()):
		var entry_variant: Variant = entries[index]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = (
			entry_variant as Dictionary
		)
		result.append({
			"timestamp_unix": int(
				entry.get("timestamp_unix", 0)
			),
			"level": _sanitize_level(
				String(entry.get("level", ""))
			),
			"message": _sanitize_text(
				String(entry.get("message", ""))
			),
			"context": _sanitize_value(
				entry.get("context", {}),
				0,
				""
			),
		})
	return result


static func _sanitize_level(value: String) -> String:
	var normalized: String = value.to_lower()
	if normalized in ["info", "warning", "error"]:
		return normalized
	return "unknown"


static func _sanitize_value(
	value: Variant,
	depth: int,
	parent_key: String
) -> Variant:
	if depth > MAX_CONTEXT_DEPTH:
		return "<max-depth>"
	if _is_sensitive_key(parent_key):
		return REDACTED

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
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
		TYPE_STRING:
			var text_value: String = String(value)
			if _is_path_key(parent_key):
				return _sanitize_path(text_value)
			return _sanitize_text(text_value)
		TYPE_ARRAY:
			var output_array: Array = []
			var source_array: Array = value as Array
			var item_count: int = mini(
				source_array.size(),
				MAX_COLLECTION_ITEMS
			)
			for index in range(item_count):
				output_array.append(
					_sanitize_value(
						source_array[index],
						depth + 1,
						parent_key
					)
				)
			if source_array.size() > item_count:
				output_array.append("<truncated-items>")
			return output_array
		TYPE_DICTIONARY:
			var source_dictionary: Dictionary = (
				value as Dictionary
			)
			var output_dictionary: Dictionary = {}
			var keys: Array = source_dictionary.keys()
			keys.sort_custom(
				func(left: Variant, right: Variant) -> bool:
					return String(left) < String(right)
			)
			var item_count: int = 0
			for raw_key in keys:
				if item_count >= MAX_COLLECTION_ITEMS:
					output_dictionary[
						"<truncated-items>"
					] = true
					break
				var key: String = _truncate_text(
					String(raw_key)
				)
				output_dictionary[key] = _sanitize_value(
					source_dictionary[raw_key],
					depth + 1,
					key
				)
				item_count += 1
			return output_dictionary
		_:
			return _sanitize_text(str(value))


static func _sanitize_text(value: String) -> String:
	var result: String = value
	if _looks_sensitive_text(result):
		return REDACTED

	for home in _home_paths():
		if not home.is_empty():
			result = result.replace(
				home,
				"<home>"
			)
			result = result.replace(
				home.replace("\\", "/"),
				"<home>"
			)
	return _truncate_text(result)


static func _truncate_text(value: String) -> String:
	if value.length() <= MAX_STRING_LENGTH:
		return value
	return (
		value.substr(
			0,
			MAX_STRING_LENGTH - TRUNCATED_SUFFIX.length()
		)
		+ TRUNCATED_SUFFIX
	)


static func _is_sensitive_key(key: String) -> bool:
	var normalized: String = (
		key.to_lower()
		.replace("-", "_")
		.replace(" ", "_")
	)
	for fragment in SENSITIVE_KEY_FRAGMENTS:
		if normalized.contains(fragment):
			return true
	return false


static func _is_path_key(key: String) -> bool:
	var normalized: String = key.to_lower()
	return (
		normalized.contains("path")
		or normalized.ends_with("_dir")
		or normalized.contains("directory")
	)


static func _looks_sensitive_text(
	value: String
) -> bool:
	var normalized: String = value.strip_edges()
	var lower: String = normalized.to_lower()
	return (
		lower.begins_with("bearer ")
		or lower.contains("authorization: bearer ")
		or lower.contains("api_key=")
		or lower.contains("apikey=")
		or lower.contains("access_token=")
		or lower.contains("refresh_token=")
		or normalized.begins_with("sk-proj-")
		or normalized.begins_with("sk-")
		or normalized.begins_with("ghp_")
		or normalized.begins_with("github_pat_")
		or _contains_absolute_path(normalized)
	)


static func _contains_absolute_path(
	value: String
) -> bool:
	if (
		value.begins_with("user://")
		or value.begins_with("res://")
	):
		return false
	if (
		value.begins_with("/")
		or value.contains(" /home/")
		or value.contains(" /Users/")
		or value.begins_with("\\\\")
	):
		return true

	for index in range(maxi(0, value.length() - 2)):
		var first: String = value.substr(index, 1)
		var second: String = value.substr(index + 1, 1)
		var third: String = value.substr(index + 2, 1)
		var is_letter: bool = (
			first.to_lower() != first.to_upper()
		)
		if (
			is_letter
			and second == ":"
			and third in ["/", "\\"]
		):
			return true
	return false


static func _home_paths() -> Array[String]:
	var result: Array[String] = []
	for key in [
		"HOME",
		"USERPROFILE",
	]:
		var value: String = OS.get_environment(key)
		if not value.is_empty() and not result.has(value):
			result.append(value)

	var drive: String = OS.get_environment("HOMEDRIVE")
	var home_path: String = OS.get_environment("HOMEPATH")
	var combined: String = drive + home_path
	if (
		not combined.is_empty()
		and not result.has(combined)
	):
		result.append(combined)
	return result


static func _success(
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


static func _error(
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
