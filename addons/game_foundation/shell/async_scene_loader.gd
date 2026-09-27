extends Node

signal load_started(scene_id: String, path: String)
signal load_progress(scene_id: String, progress: float)
signal load_completed(scene_id: String, path: String, scene: PackedScene)
signal load_failed(scene_id: String, path: String, result: Dictionary)

const MAX_SCENE_ID_LENGTH: int = 128

var _scene_resolver: Callable = Callable()
var _active_scene_id: String = ""
var _active_path: String = ""
var _progress: float = 0.0
var _loaded_scene_id: String = ""
var _loaded_path: String = ""
var _loaded_scene: PackedScene = null
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func configure(scene_resolver: Callable) -> Dictionary:
	if is_loading():
		return _error(
			"load_in_progress",
			"scene resolver cannot change while a load is active"
		)
	if not scene_resolver.is_valid():
		return _error(
			"invalid_scene_resolver",
			"scene resolver must be a valid Callable"
		)

	_scene_resolver = scene_resolver
	return _success("scene_resolver_configured")


func request_scene(scene_id: String) -> Dictionary:
	if not is_inside_tree():
		return _error(
			"not_in_scene_tree",
			"AsyncSceneLoader must be inside the SceneTree before loading"
		)
	if not _scene_resolver.is_valid():
		return _error(
			"scene_resolver_not_configured",
			"configure a scene resolver before requesting a scene"
		)
	if scene_id.is_empty() or scene_id.length() > MAX_SCENE_ID_LENGTH:
		return _error(
			"invalid_scene_id",
			"scene id must be a non-empty String within the supported length"
		)

	if is_loading():
		if scene_id == _active_scene_id:
			return _error(
				"duplicate_request",
				"the requested scene is already loading",
				{
					"scene_id": _active_scene_id,
					"path": _active_path,
				}
			)
		return _error(
			"loader_busy",
			"another scene is already loading",
			{
				"active_scene_id": _active_scene_id,
				"active_path": _active_path,
			}
		)

	var resolved_variant: Variant = _scene_resolver.call(scene_id)
	if not (resolved_variant is Dictionary):
		return _error(
			"invalid_resolver_result",
			"scene resolver must return a Dictionary"
		)

	var resolved: Dictionary = resolved_variant as Dictionary
	if not bool(resolved.get("ok", false)):
		var failure: Dictionary = resolved.duplicate(true)
		if not failure.has("code"):
			failure["code"] = "scene_resolve_failed"
		if not failure.has("message"):
			failure["message"] = "scene resolver rejected the scene"
		return failure

	var path: String = String(resolved.get("path", ""))
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		return _error(
			"invalid_scene_path",
			"resolved scene path must be a res:// .tscn path",
			{
				"scene_id": scene_id,
				"path": path,
			}
		)

	var request_error: Error = ResourceLoader.load_threaded_request(
		path,
		"PackedScene"
	)
	if request_error != OK:
		var request_failure := _error(
			"threaded_request_failed",
			"ResourceLoader.load_threaded_request failed",
			{
				"scene_id": scene_id,
				"path": path,
				"error": request_error,
			}
		)
		_last_result = request_failure.duplicate(true)
		load_failed.emit(scene_id, path, request_failure.duplicate(true))
		return request_failure

	_active_scene_id = scene_id
	_active_path = path
	_progress = 0.0
	_last_result = {}
	_loaded_scene_id = ""
	_loaded_path = ""
	_loaded_scene = null
	set_process(true)
	load_started.emit(scene_id, path)

	return _success(
		"load_started",
		{
			"scene_id": scene_id,
			"path": path,
		}
	)


func is_loading() -> bool:
	return not _active_path.is_empty()


func progress() -> float:
	return _progress


func loaded_scene() -> PackedScene:
	return _loaded_scene


func loaded_scene_id() -> String:
	return _loaded_scene_id


func loaded_path() -> String:
	return _loaded_path


func take_loaded_scene() -> PackedScene:
	var scene: PackedScene = _loaded_scene
	_loaded_scene = null
	_loaded_scene_id = ""
	_loaded_path = ""
	return scene


func clear_loaded_scene() -> void:
	_loaded_scene = null
	_loaded_scene_id = ""
	_loaded_path = ""


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


func status_snapshot() -> Dictionary:
	return {
		"loading": is_loading(),
		"scene_id": _active_scene_id,
		"path": _active_path,
		"progress": _progress,
		"has_loaded_scene": _loaded_scene != null,
		"loaded_scene_id": _loaded_scene_id,
		"loaded_path": _loaded_path,
		"last_code": String(_last_result.get("code", "")),
	}


func _process(_delta: float) -> void:
	if not is_loading():
		set_process(false)
		return

	var progress_values: Array = []
	var status: ResourceLoader.ThreadLoadStatus = (
		ResourceLoader.load_threaded_get_status(
			_active_path,
			progress_values
		)
	)

	if not progress_values.is_empty():
		var next_progress: float = clampf(
			float(progress_values[0]),
			0.0,
			1.0
		)
		if not is_equal_approx(next_progress, _progress):
			_progress = next_progress
			load_progress.emit(_active_scene_id, _progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			_complete_current_request()
		ResourceLoader.THREAD_LOAD_FAILED:
			_fail_current_request(
				"threaded_load_failed",
				"background scene loading failed"
			)
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail_current_request(
				"invalid_threaded_resource",
				"background scene request became invalid"
			)
		_:
			_fail_current_request(
				"unknown_threaded_status",
				"background scene loader returned an unknown status",
				{"status": int(status)}
			)


func _complete_current_request() -> void:
	var scene_id: String = _active_scene_id
	var path: String = _active_path
	var resource: Resource = ResourceLoader.load_threaded_get(path)

	if not (resource is PackedScene):
		_fail_current_request(
			"loaded_resource_not_scene",
			"loaded resource is not a PackedScene"
		)
		return

	_progress = 1.0
	load_progress.emit(scene_id, _progress)

	_loaded_scene_id = scene_id
	_loaded_path = path
	_loaded_scene = resource as PackedScene

	var result := _success(
		"load_completed",
		{
			"scene_id": scene_id,
			"path": path,
		}
	)
	_last_result = result.duplicate(true)
	_clear_active_request()
	load_completed.emit(scene_id, path, _loaded_scene)


func _fail_current_request(
	code: String,
	message: String,
	extra: Dictionary = {}
) -> void:
	var scene_id: String = _active_scene_id
	var path: String = _active_path
	var details: Dictionary = {
		"scene_id": scene_id,
		"path": path,
	}
	for key in extra:
		details[key] = extra[key]

	var result: Dictionary = _error(code, message, details)
	_last_result = result.duplicate(true)
	_clear_active_request()
	load_failed.emit(scene_id, path, result.duplicate(true))


func _clear_active_request() -> void:
	_active_scene_id = ""
	_active_path = ""
	set_process(false)


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
