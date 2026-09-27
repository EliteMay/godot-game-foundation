extends Control

const Foundation = preload("res://addons/game_foundation/foundation.gd")
const FoundationRuntime = preload(
	"res://addons/game_foundation/runtime/foundation_runtime.gd"
)

@onready var title_label: Label = $Content/Title
@onready var foundation_label: Label = $Content/Foundation

var foundation_runtime: Node = null


func _ready() -> void:
	title_label.text = String(
		ProjectSettings.get_setting("application/config/name", "Game")
	)

	foundation_runtime = FoundationRuntime.new()
	add_child(foundation_runtime)

	var configured: Dictionary = foundation_runtime.call("configure", {
		"app": {
			"name": String(
				ProjectSettings.get_setting("application/config/name", "Game")
			),
			"version": String(
				ProjectSettings.get_setting("application/config/version", "")
			),
		},
		"save": {
			"enabled": false,
		},
		"settings": {
			"enabled": true,
			"apply_runtime": false,
		},
		"input": {
			"enabled": false,
		},
		"flow": {
			"enabled": false,
		},
		"diagnostics": {
			"enabled": true,
		},
		"runtime_test": {
			"enabled": false,
		},
	})

	var initialized: Dictionary = {}
	if bool(configured.get("ok", false)):
		initialized = foundation_runtime.call("initialize")

	var runtime_state: String = (
		"Runtime ready"
		if bool(initialized.get("ok", false))
		else "Runtime setup error"
	)
	foundation_label.text = (
		"Godot Game Foundation "
		+ Foundation.FOUNDATION_VERSION
		+ " / "
		+ runtime_state
	)
