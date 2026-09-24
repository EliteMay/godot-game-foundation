extends Node

signal save_completed(result: Dictionary)

const SaveSystemScript = preload("res://addons/game_foundation/save/save_system.gd")

@export var save_path: String = SaveSystemScript.DEFAULT_SAVE_PATH
@export_range(0.0, 60.0, 0.05) var debounce_seconds: float = 0.5

var _timer: Timer
var _pending_payload: Dictionary = {}
var _pending_game_schema_version: int = 1
var _has_pending_save: bool = false


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


func request_save(payload: Dictionary, game_schema_version: int) -> Dictionary:
	var validation: Dictionary = SaveSystemScript.validate_payload(payload)
	if not bool(validation.get("ok", false)):
		return validation
	if game_schema_version < 1:
		return {
			"ok": false,
			"code": "invalid_game_schema_version",
			"message": "game_schema_version must be 1 or greater",
		}

	_pending_payload = payload.duplicate(true)
	_pending_game_schema_version = game_schema_version
	_has_pending_save = true

	if not is_instance_valid(_timer):
		return {
			"ok": false,
			"code": "service_not_ready",
			"message": "AutoSaveService must be inside the SceneTree before request_save",
		}

	if debounce_seconds <= 0.0:
		return flush_pending()

	_timer.start(debounce_seconds)
	return {
		"ok": true,
		"code": "autosave_queued",
	}


func flush_pending() -> Dictionary:
	if not _has_pending_save:
		return {
			"ok": true,
			"code": "nothing_pending",
		}

	if is_instance_valid(_timer):
		_timer.stop()

	var result: Dictionary = SaveSystemScript.save_game(
		_pending_payload,
		_pending_game_schema_version,
		save_path
	)
	if bool(result.get("ok", false)):
		_pending_payload.clear()
		_has_pending_save = false

	save_completed.emit(result)
	return result


func has_pending_save() -> bool:
	return _has_pending_save


func _on_timer_timeout() -> void:
	flush_pending()
