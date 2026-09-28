extends RefCounted

const AUTOMATIC_LOCALE: String = "automatic"
const MAX_LOCALE_LENGTH: int = 64


static func apply_from_settings(
	settings: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	var preference_variant: Variant = settings.get("locale", AUTOMATIC_LOCALE)
	if typeof(preference_variant) != TYPE_STRING:
		return _error(
			"invalid_locale_setting",
			"settings.locale must be a String"
		)

	return apply_preference(String(preference_variant), options)


static func apply_preference(
	preference: String,
	options: Dictionary = {}
) -> Dictionary:
	var resolved: Dictionary = resolve_preference(preference, options)
	if not bool(resolved.get("ok", false)):
		return resolved

	var locale: String = String(resolved.get("locale", ""))
	TranslationServer.set_locale(locale)
	var applied_locale: String = TranslationServer.get_locale()

	return _success(
		"locale_applied",
		{
			"preference": String(resolved.get("preference", preference)),
			"locale": applied_locale,
			"automatic": bool(resolved.get("automatic", false)),
			"system_locale": String(resolved.get("system_locale", "")),
			"loaded_translation_available": (
				TranslationServer.has_translation_for_locale(
					applied_locale,
					false
				)
			),
			"loaded_locales": Array(TranslationServer.get_loaded_locales()),
		}
	)


static func resolve_preference(
	preference: String,
	options: Dictionary = {}
) -> Dictionary:
	var normalized_preference: String = preference.strip_edges()
	if normalized_preference.is_empty():
		return _error(
			"invalid_locale_preference",
			"locale preference cannot be empty"
		)
	if normalized_preference.length() > MAX_LOCALE_LENGTH:
		return _error(
			"invalid_locale_preference",
			"locale preference is too long"
		)

	var automatic: bool = normalized_preference == AUTOMATIC_LOCALE
	var system_locale: String = ""
	var requested_locale: String = normalized_preference
	if automatic:
		system_locale = String(
			options.get("system_locale", OS.get_locale_language())
		).strip_edges()
		if system_locale.is_empty():
			return _error(
				"system_locale_unavailable",
				"automatic locale could not resolve a system language"
			)
		requested_locale = system_locale

	var standardized: String = TranslationServer.standardize_locale(
		requested_locale,
		false
	)
	if standardized.is_empty():
		return _error(
			"invalid_locale_preference",
			"locale preference could not be standardized",
			{"preference": normalized_preference}
		)

	return _success(
		"locale_resolved",
		{
			"preference": normalized_preference,
			"locale": standardized,
			"automatic": automatic,
			"system_locale": system_locale,
		}
	)


static func _success(code: String, extra: Dictionary = {}) -> Dictionary:
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
