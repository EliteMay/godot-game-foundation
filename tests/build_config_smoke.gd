extends Node

const Foundation = preload("res://addons/game_foundation/foundation.gd")

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var app_version: String = String(
		ProjectSettings.get_setting("application/config/version", "")
	)
	_expect_true(
		not app_version.is_empty(),
		"application/config/version must be set"
	)
	_expect_equal(
		app_version,
		Foundation.FOUNDATION_VERSION,
		"foundation harness app version must match Foundation version"
	)

	var config := ConfigFile.new()
	var load_error: Error = config.load("res://export_presets.cfg")
	if load_error != OK:
		_fail("export_presets.cfg could not be loaded / error=" + str(load_error))
		_finish()
		return

	_expect_equal(
		String(config.get_value("preset.0", "name", "")),
		"Windows Desktop",
		"Windows export preset name should remain stable for CI"
	)
	_expect_equal(
		String(config.get_value("preset.0", "platform", "")),
		"Windows Desktop",
		"Windows export preset platform should be Windows Desktop"
	)
	_expect_true(
		bool(config.get_value("preset.0", "runnable", false)),
		"Windows export preset should be runnable"
	)

	var export_path: String = String(
		config.get_value("preset.0", "export_path", "")
	)
	_expect_true(
		export_path.ends_with(".exe"),
		"Windows export path should end with .exe"
	)
	_expect_equal(
		String(
			config.get_value(
				"preset.0.options",
				"binary_format/architecture",
				""
			)
		),
		"x86_64",
		"Windows starter build should target x86_64"
	)
	_expect_true(
		bool(
			config.get_value(
				"preset.0.options",
				"binary_format/embed_pck",
				false
			)
		),
		"Windows starter build should embed PCK into the executable"
	)
	_expect_true(
		bool(
			config.get_value(
				"preset.0.options",
				"application/modify_resources",
				false
			)
		),
		"Windows executable metadata should be enabled"
	)
	_expect_true(
		not String(
			config.get_value(
				"preset.0.options",
				"application/product_name",
				""
			)
		).is_empty(),
		"Windows product name should be configured"
	)
	_expect_true(
		not String(
			config.get_value(
				"preset.0.options",
				"application/file_description",
				""
			)
		).is_empty(),
		"Windows file description should be configured"
	)

	var file_version: String = String(
		config.get_value(
			"preset.0.options",
			"application/file_version",
			""
		)
	)
	var product_version: String = String(
		config.get_value(
			"preset.0.options",
			"application/product_version",
			""
		)
	)

	if not file_version.is_empty():
		_expect_equal(
			file_version,
			app_version,
			"explicit file version should match project app version"
		)
	if not product_version.is_empty():
		_expect_equal(
			product_version,
			app_version,
			"explicit product version should match project app version"
		)

	_expect_true(
		not bool(
			config.get_value(
				"preset.0.options",
				"codesign/enable",
				true
			)
		),
		"Foundation harness CI build should remain unsigned until credentials are configured"
	)

	_finish()


func _expect_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
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
	push_error("BUILD_CONFIG_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("BUILD_CONFIG_SMOKE: PASS")
		get_tree().quit(0)
