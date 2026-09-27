extends Node

signal state_changed(state: Dictionary)
signal progress_changed(scene_id: String, progress: float, state: Dictionary)

const PHASE_IDLE: String = "idle"
const PHASE_LOADING: String = "loading"
const PHASE_LOADED: String = "loaded"
const PHASE_FAILED: String = "failed"

var _loader: Node = null
var _phase: String = PHASE_IDLE
var _scene_id: String = ""
var _path: String = ""
var _progress: float = 0.0
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(loader: Node) -> Dictionary:
	if not is_instance_valid(loader):
		return _error(
			"invalid_loader",
			"loading contract requires a valid loader Node"
		)

	var validation: Dictionary = _validate_loader_contract(loader)
	if not bool(validation.get("ok", false)):
		return validation

	if (
		is_instance_valid(_loader)
		and _loader != loader
		and _loader.has_method("is_loading")
		and bool(_loader.call("is_loading"))
	):
		return _error(
			"load_in_progress",
			"loading contract cannot switch loaders while the current loader is active"
		)

	_disconnect_loader()
	_loader = loader
	_connect_loader()
	_sync_from_loader()

	return _success(
		"loading_contract_configured",
		{"state": status_snapshot()}
	)


func request_scene(scene_id: String) -> Dictionary:
	if not is_instance_valid(_loader):
		return _error(
			"loader_not_configured",
			"configure a loader before requesting a scene"
		)

	var result_variant: Variant = _loader.call("request_scene", scene_id)
	if not (result_variant is Dictionary):
		var invalid_result := _error(
			"invalid_loader_result",
			"loader request_scene must return a Dictionary"
		)
		if _phase != PHASE_LOADING:
			_apply_failure(scene_id, "", invalid_result)
		return invalid_result

	var result: Dictionary = (result_variant as Dictionary).duplicate(true)
	if not bool(result.get("ok", false)) and _phase != PHASE_LOADING:
		_apply_failure(
			String(result.get("scene_id", scene_id)),
			String(result.get("path", "")),
			result
		)
	return result


func reset_state() -> Dictionary:
	if (
		is_instance_valid(_loader)
		and _loader.has_method("is_loading")
		and bool(_loader.call("is_loading"))
	):
		return _error(
			"load_in_progress",
			"loading state cannot reset while the loader is active"
		)

	_phase = PHASE_IDLE
	_scene_id = ""
	_path = ""
	_progress = 0.0
	_last_result = {}
	_emit_state()
	return _success("loading_state_reset", {"state": status_snapshot()})


func status_snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"scene_id": _scene_id,
		"path": _path,
		"progress": _progress,
		"last_code": String(_last_result.get("code", "")),
		"last_message": String(_last_result.get("message", "")),
	}


func phase() -> String:
	return _phase


func progress() -> float:
	return _progress


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


func _validate_loader_contract(loader: Node) -> Dictionary:
	for signal_name in [
		"load_started",
		"load_progress",
		"load_completed",
		"load_failed",
	]:
		if not loader.has_signal(signal_name):
			return _error(
				"invalid_loader_contract",
				"loader is missing required signal",
				{"signal": signal_name}
			)

	for method_name in [
		"request_scene",
		"is_loading",
		"status_snapshot",
		"last_result",
	]:
		if not loader.has_method(method_name):
			return _error(
				"invalid_loader_contract",
				"loader is missing required method",
				{"method": method_name}
			)

	return _success("loader_contract_valid")


func _connect_loader() -> void:
	_connect_loader_signal("load_started", Callable(self, "_on_load_started"))
	_connect_loader_signal("load_progress", Callable(self, "_on_load_progress"))
	_connect_loader_signal("load_completed", Callable(self, "_on_load_completed"))
	_connect_loader_signal("load_failed", Callable(self, "_on_load_failed"))


func _connect_loader_signal(signal_name: String, callback: Callable) -> void:
	if not _loader.is_connected(signal_name, callback):
		_loader.connect(signal_name, callback)


func _disconnect_loader() -> void:
	if not is_instance_valid(_loader):
		_loader = null
		return

	_disconnect_loader_signal("load_started", Callable(self, "_on_load_started"))
	_disconnect_loader_signal("load_progress", Callable(self, "_on_load_progress"))
	_disconnect_loader_signal("load_completed", Callable(self, "_on_load_completed"))
	_disconnect_loader_signal("load_failed", Callable(self, "_on_load_failed"))
	_loader = null


func _disconnect_loader_signal(signal_name: String, callback: Callable) -> void:
	if _loader.has_signal(signal_name) and _loader.is_connected(signal_name, callback):
		_loader.disconnect(signal_name, callback)


func _sync_from_loader() -> void:
	if not is_instance_valid(_loader):
		return

	var snapshot_variant: Variant = _loader.call("status_snapshot")
	if not (snapshot_variant is Dictionary):
		_phase = PHASE_IDLE
		_scene_id = ""
		_path = ""
		_progress = 0.0
		_last_result = {}
		_emit_state()
		return

	var snapshot: Dictionary = snapshot_variant as Dictionary
	if bool(snapshot.get("loading", false)):
		_phase = PHASE_LOADING
		_scene_id = String(snapshot.get("scene_id", ""))
		_path = String(snapshot.get("path", ""))
		_progress = clampf(float(snapshot.get("progress", 0.0)), 0.0, 1.0)
		_last_result = {}
		_emit_state()
		return

	if bool(snapshot.get("has_loaded_scene", false)):
		_phase = PHASE_LOADED
		_scene_id = String(snapshot.get("loaded_scene_id", ""))
		_path = String(snapshot.get("loaded_path", ""))
		_progress = 1.0
		_last_result = _read_loader_result()
		_emit_state()
		return

	var result: Dictionary = _read_loader_result()
	if not result.is_empty() and not bool(result.get("ok", false)):
		_apply_failure(
			String(result.get("scene_id", "")),
			String(result.get("path", "")),
			result
		)
		return

	_phase = PHASE_IDLE
	_scene_id = ""
	_path = ""
	_progress = 0.0
	_last_result = {}
	_emit_state()


func _on_load_started(scene_id: String, path: String) -> void:
	_phase = PHASE_LOADING
	_scene_id = scene_id
	_path = path
	_progress = 0.0
	_last_result = {}
	_emit_state()


func _on_load_progress(scene_id: String, value: float) -> void:
	var next_progress: float = clampf(value, 0.0, 1.0)
	if scene_id != _scene_id:
		_scene_id = scene_id
	if is_equal_approx(next_progress, _progress):
		return

	_progress = next_progress
	var state: Dictionary = status_snapshot()
	progress_changed.emit(_scene_id, _progress, state.duplicate(true))
	state_changed.emit(state)


func _on_load_completed(
	scene_id: String,
	path: String,
	_scene: PackedScene
) -> void:
	_phase = PHASE_LOADED
	_scene_id = scene_id
	_path = path
	_progress = 1.0
	_last_result = _read_loader_result()
	_emit_state()


func _on_load_failed(
	scene_id: String,
	path: String,
	result: Dictionary
) -> void:
	_apply_failure(scene_id, path, result)


func _apply_failure(
	scene_id: String,
	path: String,
	result: Dictionary
) -> void:
	_phase = PHASE_FAILED
	_scene_id = scene_id
	_path = path
	_progress = 0.0
	_last_result = result.duplicate(true)
	_emit_state()


func _read_loader_result() -> Dictionary:
	if not is_instance_valid(_loader) or not _loader.has_method("last_result"):
		return {}

	var value: Variant = _loader.call("last_result")
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _emit_state() -> void:
	state_changed.emit(status_snapshot())


func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"code": code,
	}
	for key in extra:
		result[key] = extra[key]
	return result


func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"code": code,
		"message": message,
	}
	for key in extra:
		result[key] = extra[key]
	return result
