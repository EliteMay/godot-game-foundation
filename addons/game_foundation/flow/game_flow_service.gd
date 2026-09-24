extends Node

signal pause_changed(is_paused: bool)
signal scene_change_started(scene_id: String, path: String)
signal scene_change_failed(scene_id: String, path: String, error: int)
signal safe_quit_blocked(result: Dictionary)

const MAX_SCENES: int = 256
const MAX_QUIT_HOOKS: int = 64

var _scene_map: Dictionary = {}
var _main_menu_id: String = ""
var _quit_hooks: Array[Callable] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure_scene_contract(
	scene_map: Dictionary,
	main_menu_id: String = ""
) -> Dictionary:
	var validation: Dictionary = validate_scene_contract(
		scene_map,
		main_menu_id
	)
	if not bool(validation.get("ok", false)):
		return validation

	_scene_map = scene_map.duplicate(true)
	_main_menu_id = main_menu_id
	return _success("scene_contract_configured", {
		"scene_count": _scene_map.size(),
		"main_menu_id": _main_menu_id,
	})


func validate_scene_contract(
	scene_map: Dictionary,
	main_menu_id: String = ""
) -> Dictionary:
	if scene_map.size() > MAX_SCENES:
		return _error("too_many_scenes", "scene contract contains too many scenes")

	for raw_id in scene_map.keys():
		if typeof(raw_id) != TYPE_STRING:
			return _error("invalid_scene_id", "scene ids must be String")

		var scene_id: String = String(raw_id)
		if scene_id.is_empty():
			return _error("invalid_scene_id", "scene id cannot be empty")

		var path_variant: Variant = scene_map[raw_id]
		if typeof(path_variant) != TYPE_STRING:
			return _error(
				"invalid_scene_path",
				"scene path must be String",
				{"scene_id": scene_id}
			)

		var path: String = String(path_variant)
		if not path.begins_with("res://") or not path.ends_with(".tscn"):
			return _error(
				"invalid_scene_path",
				"scene path must be a res:// .tscn path",
				{"scene_id": scene_id, "path": path}
			)

	if not main_menu_id.is_empty() and not scene_map.has(main_menu_id):
		return _error(
			"main_menu_not_declared",
			"main menu id must exist in the scene contract",
			{"main_menu_id": main_menu_id}
		)

	return _success("valid_scene_contract")


func scene_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for raw_id in _scene_map.keys():
		ids.append(String(raw_id))
	return ids


func resolve_scene_path(scene_id: String) -> Dictionary:
	if scene_id.is_empty():
		return _error("invalid_scene_id", "scene id cannot be empty")
	if not _scene_map.has(scene_id):
		return _error(
			"unknown_scene",
			"scene id is not declared by the game",
			{"scene_id": scene_id}
		)

	return _success("scene_resolved", {
		"scene_id": scene_id,
		"path": String(_scene_map[scene_id]),
	})


func load_scene(scene_id: String) -> Dictionary:
	var resolved: Dictionary = resolve_scene_path(scene_id)
	if not bool(resolved.get("ok", false)):
		return resolved

	var path: String = String(resolved.get("path", ""))
	var resource: Resource = load(path)
	if not (resource is PackedScene):
		return _error(
			"scene_load_failed",
			"scene could not be loaded as PackedScene",
			{"scene_id": scene_id, "path": path}
		)

	return _success("scene_loaded", {
		"scene_id": scene_id,
		"path": path,
		"scene": resource,
	})


func change_scene(scene_id: String) -> Dictionary:
	if get_tree() == null:
		return _error("not_in_scene_tree", "GameFlowService is not inside a SceneTree")

	var loaded: Dictionary = load_scene(scene_id)
	if not bool(loaded.get("ok", false)):
		return loaded

	var path: String = String(loaded.get("path", ""))
	set_paused(false)
	scene_change_started.emit(scene_id, path)

	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		scene_change_failed.emit(scene_id, path, error)
		return _error(
			"scene_change_failed",
			"SceneTree.change_scene_to_file failed",
			{"scene_id": scene_id, "path": path, "error": error}
		)

	return _success("scene_change_requested", {
		"scene_id": scene_id,
		"path": path,
	})


func go_to_main_menu() -> Dictionary:
	if _main_menu_id.is_empty():
		return _error(
			"main_menu_not_configured",
			"game did not configure a main menu scene id"
		)
	return change_scene(_main_menu_id)


func main_menu_id() -> String:
	return _main_menu_id


func set_paused(value: bool) -> Dictionary:
	if get_tree() == null:
		return _error("not_in_scene_tree", "GameFlowService is not inside a SceneTree")

	if get_tree().paused == value:
		return _success("pause_unchanged", {"paused": value})

	get_tree().paused = value
	pause_changed.emit(value)
	return _success("pause_changed", {"paused": value})


func toggle_pause() -> Dictionary:
	if get_tree() == null:
		return _error("not_in_scene_tree", "GameFlowService is not inside a SceneTree")
	return set_paused(not get_tree().paused)


func is_paused() -> bool:
	return get_tree() != null and get_tree().paused


func register_quit_hook(hook: Callable) -> Dictionary:
	if not hook.is_valid():
		return _error("invalid_quit_hook", "quit hook must be a valid Callable")
	if _quit_hooks.size() >= MAX_QUIT_HOOKS:
		return _error("too_many_quit_hooks", "too many safe quit hooks are registered")
	if _quit_hooks.has(hook):
		return _success("quit_hook_already_registered", {
			"hook_count": _quit_hooks.size(),
		})

	_quit_hooks.append(hook)
	return _success("quit_hook_registered", {
		"hook_count": _quit_hooks.size(),
	})


func unregister_quit_hook(hook: Callable) -> Dictionary:
	var index: int = _quit_hooks.find(hook)
	if index < 0:
		return _success("quit_hook_not_registered", {
			"hook_count": _quit_hooks.size(),
		})

	_quit_hooks.remove_at(index)
	return _success("quit_hook_unregistered", {
		"hook_count": _quit_hooks.size(),
	})


func clear_quit_hooks() -> void:
	_quit_hooks.clear()


func quit_hook_count() -> int:
	return _quit_hooks.size()


func prepare_safe_quit() -> Dictionary:
	for index in range(_quit_hooks.size()):
		var hook: Callable = _quit_hooks[index]
		if not hook.is_valid():
			var invalid := _error(
				"quit_hook_invalid",
				"registered quit hook is no longer valid",
				{"hook_index": index}
			)
			safe_quit_blocked.emit(invalid)
			return invalid

		var value: Variant = hook.call()
		if typeof(value) == TYPE_BOOL and not bool(value):
			var bool_failure := _error(
				"quit_hook_blocked",
				"quit hook returned false",
				{"hook_index": index}
			)
			safe_quit_blocked.emit(bool_failure)
			return bool_failure

		if value is Dictionary:
			var result: Dictionary = value as Dictionary
			if result.has("ok") and not bool(result.get("ok", false)):
				var hook_failure := _error(
					"quit_hook_blocked",
					"quit hook reported failure",
					{
						"hook_index": index,
						"hook_result": result,
					}
				)
				safe_quit_blocked.emit(hook_failure)
				return hook_failure

	return _success("safe_to_quit", {
		"hook_count": _quit_hooks.size(),
	})


func request_quit(exit_code: int = 0) -> Dictionary:
	if get_tree() == null:
		return _error("not_in_scene_tree", "GameFlowService is not inside a SceneTree")

	var preparation: Dictionary = prepare_safe_quit()
	if not bool(preparation.get("ok", false)):
		return preparation

	get_tree().quit(exit_code)
	return _success("quit_requested", {
		"exit_code": exit_code,
	})


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
