extends RefCounted

const SHELL_MAIN_MENU: String = "main_menu"
const SHELL_PAUSE_MENU: String = "pause_menu"
const SHELL_RECOVERY_SCREEN: String = "recovery_screen"

const DEFAULT_CONTRACTS: Dictionary = {
	SHELL_MAIN_MENU: {
		"continue": {
			"key": "GF_MAIN_MENU_CONTINUE",
			"fallback": "Continue",
			"context": "",
		},
		"new_game": {
			"key": "GF_MAIN_MENU_NEW_GAME",
			"fallback": "New Game",
			"context": "",
		},
		"options": {
			"key": "GF_MAIN_MENU_OPTIONS",
			"fallback": "Options",
			"context": "",
		},
		"quit": {
			"key": "GF_MAIN_MENU_QUIT",
			"fallback": "Quit",
			"context": "",
		},
	},
	SHELL_PAUSE_MENU: {
		"resume": {
			"key": "GF_PAUSE_MENU_RESUME",
			"fallback": "Resume",
			"context": "",
		},
		"options": {
			"key": "GF_PAUSE_MENU_OPTIONS",
			"fallback": "Options",
			"context": "",
		},
		"main_menu": {
			"key": "GF_PAUSE_MENU_MAIN_MENU",
			"fallback": "Main Menu",
			"context": "",
		},
		"quit": {
			"key": "GF_PAUSE_MENU_QUIT",
			"fallback": "Quit",
			"context": "",
		},
	},
	SHELL_RECOVERY_SCREEN: {
		"title": {
			"key": "GF_RECOVERY_TITLE",
			"fallback": "Recovery needed",
			"context": "",
		},
		"retry": {
			"key": "GF_RECOVERY_RETRY",
			"fallback": "Retry",
			"context": "",
		},
		"main_menu": {
			"key": "GF_RECOVERY_MAIN_MENU",
			"fallback": "Main Menu",
			"context": "",
		},
		"safe_quit": {
			"key": "GF_RECOVERY_SAFE_QUIT",
			"fallback": "Quit",
			"context": "",
		},
		"save_protected": {
			"key": "GF_RECOVERY_SAVE_PROTECTED",
			"fallback": "Save data is protected from overwrite.",
			"context": "",
		},
		"diagnostics_available": {
			"key": "GF_RECOVERY_DIAGNOSTICS_AVAILABLE",
			"fallback": "Diagnostics are available.",
			"context": "",
		},
	},
}


static func default_entries(shell_id: String) -> Dictionary:
	if not DEFAULT_CONTRACTS.has(shell_id):
		return {}
	return (DEFAULT_CONTRACTS[shell_id] as Dictionary).duplicate(true)


static func normalize_entries(
	shell_id: String,
	overrides_variant: Variant = {}
) -> Dictionary:
	if not DEFAULT_CONTRACTS.has(shell_id):
		return _error(
			"unknown_shell",
			"translation shell id is not supported",
			{"shell_id": shell_id}
		)
	if not (overrides_variant is Dictionary):
		return _error(
			"invalid_translation_entries",
			"translation entries must be a Dictionary"
		)

	var entries: Dictionary = default_entries(shell_id)
	var overrides: Dictionary = overrides_variant as Dictionary

	for raw_action_id in overrides.keys():
		if typeof(raw_action_id) != TYPE_STRING:
			return _error(
				"invalid_translation_action_id",
				"translation action ids must be String"
			)

		var action_id: String = String(raw_action_id)
		if not entries.has(action_id):
			return _error(
				"unknown_translation_action",
				"translation action id is not supported by this shell",
				{
					"shell_id": shell_id,
					"action_id": action_id,
				}
			)

		var base_entry: Dictionary = (
			entries[action_id] as Dictionary
		).duplicate(true)
		var override_variant: Variant = overrides[raw_action_id]

		if typeof(override_variant) == TYPE_STRING:
			base_entry["key"] = String(override_variant).strip_edges()
		elif override_variant is Dictionary:
			var override: Dictionary = override_variant as Dictionary
			for field in override.keys():
				if typeof(field) != TYPE_STRING:
					return _error(
						"invalid_translation_entry",
						"translation entry field names must be String",
						{"action_id": action_id}
					)
				var field_name: String = String(field)
				if field_name not in ["key", "fallback", "context"]:
					return _error(
						"unknown_translation_entry_field",
						"translation entry field is not supported",
						{
							"action_id": action_id,
							"field": field_name,
						}
					)
				if typeof(override[field]) != TYPE_STRING:
					return _error(
						"invalid_translation_entry",
						"translation entry values must be String",
						{
							"action_id": action_id,
							"field": field_name,
						}
					)
				base_entry[field_name] = String(override[field])
		else:
			return _error(
				"invalid_translation_entry",
				"translation entry must be a String key or Dictionary",
				{"action_id": action_id}
			)

		var validation: Dictionary = _validate_entry(action_id, base_entry)
		if not bool(validation.get("ok", false)):
			return validation
		entries[action_id] = base_entry

	for action_id in entries.keys():
		var validation: Dictionary = _validate_entry(
			String(action_id),
			entries[action_id] as Dictionary
		)
		if not bool(validation.get("ok", false)):
			return validation

	return _success(
		"translation_entries_normalized",
		{
			"shell_id": shell_id,
			"entries": entries,
		}
	)


static func resolve_labels(
	shell_id: String,
	overrides_variant: Variant = {}
) -> Dictionary:
	var normalized: Dictionary = normalize_entries(
		shell_id,
		overrides_variant
	)
	if not bool(normalized.get("ok", false)):
		return normalized

	var entries: Dictionary = (
		normalized.get("entries", {}) as Dictionary
	)
	var labels: Dictionary = {}
	var sources: Dictionary = {}

	for action_id in entries.keys():
		var entry: Dictionary = entries[action_id] as Dictionary
		var key: String = String(entry.get("key", ""))
		var context: String = String(entry.get("context", ""))
		var fallback: String = String(entry.get("fallback", ""))
		var translated: String = String(
			TranslationServer.translate(
				StringName(key),
				StringName(context)
			)
		)

		if translated == key:
			labels[action_id] = fallback
			sources[action_id] = "fallback"
		else:
			labels[action_id] = translated
			sources[action_id] = "translation"

	return _success(
		"translation_labels_resolved",
		{
			"shell_id": shell_id,
			"locale": TranslationServer.get_locale(),
			"entries": entries,
			"labels": labels,
			"sources": sources,
		}
	)


static func _validate_entry(
	action_id: String,
	entry: Dictionary
) -> Dictionary:
	var key: String = String(entry.get("key", "")).strip_edges()
	if key.is_empty():
		return _error(
			"invalid_translation_key",
			"translation key cannot be empty",
			{"action_id": action_id}
		)

	for field in ["fallback", "context"]:
		if typeof(entry.get(field, "")) != TYPE_STRING:
			return _error(
				"invalid_translation_entry",
				"translation entry values must be String",
				{
					"action_id": action_id,
					"field": field,
				}
			)

	entry["key"] = key
	return _success("translation_entry_valid")


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
