extends Node

const FoundationScript = preload("res://addons/game_foundation/foundation.gd")

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var info: Dictionary = FoundationScript.info()
	if String(info.get("name", "")) != "Godot Game Foundation":
		_fail("foundation name is missing")
	if String(info.get("foundation_version", "")).is_empty():
		_fail("foundation version is missing")
	if String(info.get("godot_baseline", "")) != "4.7.2":
		_fail("Godot baseline must be 4.7.2")

	var capabilities: PackedStringArray = FoundationScript.capabilities()
	if not capabilities.has("foundation_core"):
		_fail("foundation_core capability is missing")

	_finish()


func _fail(message: String) -> void:
	_failed = true
	push_error("FOUNDATION_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("FOUNDATION_SMOKE: PASS")
		get_tree().quit(0)
