extends Node

const Foundation = preload("res://addons/game_foundation/foundation.gd")
const FoundationRuntime = preload(
	"res://addons/game_foundation/runtime/foundation_runtime.gd"
)

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var info: Dictionary = Foundation.info()
	if String(info.get("name", "")) != "Godot Game Foundation":
		_fail("Foundation info is unavailable")
	if String(info.get("foundation_version", "")).is_empty():
		_fail("Foundation version is unavailable")
	if not Foundation.capabilities().has("foundation_core"):
		_fail("foundation_core capability is unavailable")
	if not Foundation.capabilities().has("integrated_foundation_runtime"):
		_fail("integrated_foundation_runtime capability is unavailable")

	var runtime := FoundationRuntime.new()
	add_child(runtime)
	var configured: Dictionary = runtime.configure({
		"save": {"enabled": false},
		"settings": {"enabled": false},
		"input": {"enabled": false},
		"flow": {"enabled": false},
		"diagnostics": {"enabled": false},
		"runtime_test": {"enabled": false},
	})
	if not bool(configured.get("ok", false)):
		_fail("FoundationRuntime configure failed")
	var initialized: Dictionary = runtime.initialize()
	if not bool(initialized.get("ok", false)):
		_fail("FoundationRuntime initialize failed")
	runtime.queue_free()

	if _failed:
		get_tree().quit(1)
	else:
		print("FOUNDATION_INTEGRATION_SMOKE: PASS")
		get_tree().quit(0)


func _fail(message: String) -> void:
	_failed = true
	push_error("FOUNDATION_INTEGRATION_SMOKE: " + message)
