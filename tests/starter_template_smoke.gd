extends Node

const Foundation = preload("res://addons/game_foundation/foundation.gd")

const MANIFEST_PATH := "res://foundation-template.json"

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	if manifest.is_empty():
		_finish()
		return

	_expect_equal(int(manifest.get("schemaVersion", 0)), 1, "starter manifest schemaVersion must be 1")
	_expect_equal(String(manifest.get("foundationVersion", "")), Foundation.FOUNDATION_VERSION, "starter manifest version must match Foundation version")
	_expect_equal(String(manifest.get("godotBaseline", "")), Foundation.GODOT_BASELINE, "starter manifest Godot baseline must match Foundation baseline")
	_expect_equal(String(manifest.get("sourceRepository", "")), "EliteMay/godot-game-foundation", "starter source repository must remain explicit")

	var files_variant: Variant = manifest.get("starterFiles", [])
	if not (files_variant is Array):
		_fail("starterFiles must be an Array")
	else:
		var targets: Dictionary = {}
		for item_variant in files_variant as Array:
			if not (item_variant is Dictionary):
				_fail("starterFiles entry must be a Dictionary")
				continue
			var item: Dictionary = item_variant as Dictionary
			var source: String = String(item.get("source", ""))
			var target: String = String(item.get("target", ""))
			if not _safe_relative_path(source):
				_fail("unsafe starter source path: " + source)
			if not _safe_relative_path(target):
				_fail("unsafe starter target path: " + target)
			if targets.has(target):
				_fail("duplicate starter target: " + target)
			targets[target] = true
			if not FileAccess.file_exists("res://" + source):
				_fail("starter source is missing: " + source)

		for required_target in [
			"project.godot",
			"README.md",
			"docs/ROADMAP.md",
			"scenes/main.tscn",
			"scripts/main.gd",
			"tests/foundation_integration_smoke.gd",
			"tests/foundation_integration_smoke.tscn",
		]:
			if not targets.has(required_target):
				_fail("starter target is missing: " + required_target)

	var managed_variant: Variant = manifest.get("managedPaths", [])
	if not (managed_variant is Array):
		_fail("managedPaths must be an Array")
	else:
		var managed: Array = managed_variant as Array
		if managed.is_empty():
			_fail("managedPaths cannot be empty")
		for path_variant in managed:
			var managed_path: String = String(path_variant)
			if not _safe_relative_path(managed_path):
				_fail("unsafe managed path: " + managed_path)
				continue
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + managed_path)):
				_fail("managed path is missing: " + managed_path)

	_finish()


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("manifest is missing: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("manifest could not be opened")
		return {}
	var parser := JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not (parser.data is Dictionary):
		_fail("manifest JSON is invalid")
		return {}
	return parser.data as Dictionary


func _safe_relative_path(value: String) -> bool:
	if value.is_empty():
		return false
	if value.begins_with("/") or value.begins_with("\\"):
		return false
	if value.contains(".."):
		return false
	if value.contains("\\"):
		return false
	return true


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail(message + " / expected=" + str(expected) + " actual=" + str(actual))


func _fail(message: String) -> void:
	_failed = true
	push_error("STARTER_TEMPLATE_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("STARTER_TEMPLATE_SMOKE: PASS")
		get_tree().quit(0)
