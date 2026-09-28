extends RefCounted

const DEFAULT_BUS_MAP: Dictionary = {
	"master": "Master",
	"bgm": "BGM",
	"sfx": "SFX",
	"ui": "SFX",
	"voice": "SFX",
}

const SETTINGS_VOLUME_KEYS: Array[String] = [
	"master",
	"bgm",
	"sfx",
]


static func normalize(value: Variant = {}) -> Dictionary:
	if value == null:
		value = {}
	if not (value is Dictionary):
		return _error(
			"invalid_audio_bus_map",
			"audio bus map must be a Dictionary"
		)

	var source: Dictionary = value as Dictionary
	var normalized: Dictionary = {
		"master": "Master",
		"bgm": "BGM",
		"sfx": "SFX",
	}

	for key_variant in source.keys():
		if typeof(key_variant) != TYPE_STRING:
			return _error(
				"invalid_audio_bus_key",
				"audio bus map keys must be non-empty Strings"
			)
		var logical_name: String = String(key_variant).strip_edges()
		if logical_name.is_empty():
			return _error(
				"invalid_audio_bus_key",
				"audio bus map keys cannot be empty"
			)

		var bus_variant: Variant = source[key_variant]
		if typeof(bus_variant) != TYPE_STRING:
			return _error(
				"invalid_audio_bus_name",
				"audio bus names must be non-empty Strings",
				{"bus_key": logical_name}
			)
		var bus_name: String = String(bus_variant).strip_edges()
		if bus_name.is_empty():
			return _error(
				"invalid_audio_bus_name",
				"audio bus names cannot be empty",
				{"bus_key": logical_name}
			)
		normalized[logical_name] = bus_name

	if not source.has("ui"):
		normalized["ui"] = String(normalized.get("sfx", "SFX"))
	if not source.has("voice"):
		normalized["voice"] = String(normalized.get("sfx", "SFX"))

	return _success(
		"audio_bus_map_normalized",
		{"bus_map": normalized}
	)


static func resolve_bus(value: Variant, logical_name: String) -> Dictionary:
	var normalized_result: Dictionary = normalize(value)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	var key: String = logical_name.strip_edges()
	if key.is_empty():
		return _error(
			"invalid_audio_bus_key",
			"logical audio bus key cannot be empty"
		)

	var bus_map: Dictionary = normalized_result.get("bus_map", {})
	if not bus_map.has(key):
		return _error(
			"unknown_audio_bus_key",
			"logical audio bus key is not declared",
			{"bus_key": key}
		)

	return _success(
		"audio_bus_resolved",
		{
			"bus_key": key,
			"bus_name": String(bus_map.get(key, "")),
			"bus_map": bus_map.duplicate(true),
		}
	)


static func settings_bus_map(value: Variant) -> Dictionary:
	var normalized_result: Dictionary = normalize(value)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	var bus_map: Dictionary = normalized_result.get("bus_map", {})
	var settings_map: Dictionary = {}
	for key in SETTINGS_VOLUME_KEYS:
		settings_map[key] = String(bus_map.get(key, ""))

	return _success(
		"settings_audio_bus_map_resolved",
		{
			"bus_map": settings_map,
			"full_bus_map": bus_map.duplicate(true),
		}
	)


static func one_shot_bus_map(value: Variant) -> Dictionary:
	var normalized_result: Dictionary = normalize(value)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	var bus_map: Dictionary = normalized_result.get("bus_map", {})
	return _success(
		"one_shot_audio_bus_map_resolved",
		{
			"bus_map": {
				"sfx": String(bus_map.get("sfx", "")),
				"ui": String(bus_map.get("ui", "")),
				"voice": String(bus_map.get("voice", "")),
			},
			"full_bus_map": bus_map.duplicate(true),
		}
	)


static func inspect_audio_server(value: Variant) -> Dictionary:
	var normalized_result: Dictionary = normalize(value)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result

	var bus_map: Dictionary = normalized_result.get("bus_map", {})
	var existing: Array[String] = []
	var missing: Array[String] = []
	var visited: Dictionary = {}

	for logical_name_variant in bus_map.keys():
		var logical_name: String = String(logical_name_variant)
		var bus_name: String = String(bus_map.get(logical_name, ""))
		if visited.has(bus_name):
			continue
		visited[bus_name] = true
		if AudioServer.get_bus_index(bus_name) >= 0:
			existing.append(bus_name)
		else:
			missing.append(bus_name)

	return _success(
		"audio_bus_server_inspected",
		{
			"bus_map": bus_map.duplicate(true),
			"existing_buses": existing,
			"missing_buses": missing,
		}
	)


static func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "code": code}
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
