extends Node

const SettingsSystem = preload(
	"res://addons/game_foundation/settings/settings_system.gd"
)
const SettingsRuntime = preload(
	"res://addons/game_foundation/settings/settings_runtime.gd"
)
const LocaleSettingAdapter = preload(
	"res://addons/game_foundation/localization/locale_setting_adapter.gd"
)

var _failed: bool = false
var _original_locale: String = ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_original_locale = TranslationServer.get_locale()

	var defaults: Dictionary = SettingsSystem.default_settings()
	_expect_equal(
		String(defaults.get("locale", "")),
		LocaleSettingAdapter.AUTOMATIC_LOCALE,
		"default settings should follow system locale automatically"
	)

	var normalized: Dictionary = SettingsSystem.normalize_settings(
		{"locale": "en-US"}
	)
	_expect_ok(normalized, "explicit locale should normalize")
	_expect_equal(
		String(
			(normalized.get("settings", {}) as Dictionary)
			.get("locale", "")
		),
		"en-US",
		"settings persistence should preserve the user preference"
	)

	var invalid_type: Dictionary = SettingsSystem.normalize_settings(
		{"locale": 123}
	)
	_expect_ok(invalid_type, "invalid locale type should fall back safely")
	_expect_equal(
		String(
			(invalid_type.get("settings", {}) as Dictionary)
			.get("locale", "")
		),
		LocaleSettingAdapter.AUTOMATIC_LOCALE,
		"invalid locale type should fall back to automatic"
	)
	_expect_true(
		(invalid_type.get("warnings", []) as Array).has(
			"locale_invalid"
		),
		"invalid locale type should report a warning"
	)

	var resolved_explicit: Dictionary = LocaleSettingAdapter.resolve_preference(
		"en-US"
	)
	_expect_ok(resolved_explicit, "explicit locale should resolve")
	_expect_equal(
		String(resolved_explicit.get("locale", "")),
		"en_US",
		"Godot locale normalization should be preserved"
	)

	var resolved_automatic: Dictionary = LocaleSettingAdapter.resolve_preference(
		"automatic",
		{"system_locale": "ja-JP"}
	)
	_expect_ok(resolved_automatic, "automatic locale should resolve")
	_expect_true(
		bool(resolved_automatic.get("automatic", false)),
		"automatic mode should be reported"
	)
	_expect_equal(
		String(resolved_automatic.get("locale", "")),
		"ja_JP",
		"automatic locale should use the supplied system language"
	)

	var applied: Dictionary = LocaleSettingAdapter.apply_from_settings(
		{"locale": "en-US"}
	)
	_expect_ok(applied, "explicit locale should apply")
	_expect_equal(
		TranslationServer.get_locale(),
		"en_US",
		"TranslationServer should receive the explicit locale"
	)

	var runtime_result: Dictionary = SettingsRuntime.apply_settings(
		{
			"locale": "ja-JP",
			"audio": {
				"master": 1.0,
				"bgm": 1.0,
				"sfx": 1.0,
			},
			"display": {
				"window_mode": "windowed",
				"resolution": [960, 540],
				"vsync": true,
			},
		}
	)
	_expect_ok(runtime_result, "SettingsRuntime should apply locale in headless mode")
	_expect_equal(
		String(
			(runtime_result.get("locale", {}) as Dictionary)
			.get("locale", "")
		),
		"ja_JP",
		"SettingsRuntime should expose applied locale"
	)
	_expect_equal(
		TranslationServer.get_locale(),
		"ja_JP",
		"SettingsRuntime should apply locale before headless visual skip"
	)

	var invalid_empty: Dictionary = LocaleSettingAdapter.apply_preference("   ")
	_expect_code(
		invalid_empty,
		"invalid_locale_preference",
		"empty locale should be rejected"
	)

	TranslationServer.set_locale(_original_locale)
	_finish()


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


func _expect_code(
	result: Dictionary,
	expected: String,
	message: String
) -> void:
	if String(result.get("code", "")) != expected:
		_fail(
			message
			+ " / expected="
			+ expected
			+ " actual="
			+ String(result.get("code", ""))
		)


func _expect_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _expect_equal(
	actual: Variant,
	expected: Variant,
	message: String
) -> void:
	if actual != expected:
		_fail(
			message
			+ " / expected="
			+ str(expected)
			+ " actual="
			+ str(actual)
		)


func _fail(message: String) -> void:
	_failed = true
	push_error("LOCALE_SETTING_ADAPTER_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("LOCALE_SETTING_ADAPTER_SMOKE: PASS")
		get_tree().quit(0)
