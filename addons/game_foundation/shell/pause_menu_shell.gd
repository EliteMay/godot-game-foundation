extends Control

signal menu_opened
signal menu_closed(reason: String)
signal action_requested(action_id: String)
signal action_completed(action_id: String, result: Dictionary)
signal action_failed(action_id: String, result: Dictionary)

const ACTION_RESUME: String = "resume"
const ACTION_OPTIONS: String = "options"
const ACTION_MAIN_MENU: String = "main_menu"
const ACTION_QUIT: String = "quit"

@export var resume_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/ResumeButton"
)
@export var options_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/OptionsButton"
)
@export var main_menu_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/MainMenuButton"
)
@export var quit_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/QuitButton"
)

var _flow_service: Node = null
var _options_action: Callable = Callable()
var _previous_focus: Control = null
var _is_open: bool = false
var _show_quit: bool = true
var _buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_resolve_buttons()
	_connect_buttons()


func configure(options: Dictionary) -> Dictionary:
	var flow_variant: Variant = options.get("flow_service")
	if not (flow_variant is Node):
		return _error(
			"invalid_flow_service",
			"flow_service must be a Node implementing the Game Flow contract"
		)

	var flow: Node = flow_variant as Node
	for method_name in [
		"set_paused",
		"is_paused",
		"go_to_main_menu",
		"main_menu_id",
		"request_quit",
	]:
		if not flow.has_method(method_name):
			return _error(
				"invalid_flow_service",
				"flow_service is missing required method",
				{"method": method_name}
			)

	var options_callable := Callable()
	if options.has("options_action"):
		var callable_variant: Variant = options.get("options_action")
		if typeof(callable_variant) != TYPE_CALLABLE:
			return _error(
				"invalid_options_action",
				"options_action must be a Callable"
			)
		options_callable = callable_variant as Callable

	var show_quit_variant: Variant = options.get("show_quit", true)
	if typeof(show_quit_variant) != TYPE_BOOL:
		return _error("invalid_show_quit", "show_quit must be bool")

	_resolve_buttons()
	for action_id in [
		ACTION_RESUME,
		ACTION_OPTIONS,
		ACTION_MAIN_MENU,
		ACTION_QUIT,
	]:
		if not _buttons.has(action_id):
			return _error(
				"missing_pause_control",
				"pause menu scene is missing a required Button",
				{"action_id": action_id}
			)

	_flow_service = flow
	_options_action = options_callable
	_show_quit = bool(show_quit_variant)

	if options.has("labels"):
		var label_result: Dictionary = set_labels(options.get("labels"))
		if not bool(label_result.get("ok", false)):
			return label_result

	_refresh_action_availability()
	return _success("pause_menu_configured", {"state": state_snapshot()})


func set_labels(labels_variant: Variant) -> Dictionary:
	if not (labels_variant is Dictionary):
		return _error("invalid_labels", "labels must be a Dictionary")

	var labels: Dictionary = labels_variant as Dictionary
	for raw_key in labels.keys():
		if typeof(raw_key) != TYPE_STRING:
			return _error("invalid_label_key", "label action ids must be String")
		var action_id: String = String(raw_key)
		if not _buttons.has(action_id):
			return _error(
				"unknown_action",
				"label action id is not supported",
				{"action_id": action_id}
			)
		if typeof(labels[raw_key]) != TYPE_STRING:
			return _error(
				"invalid_label",
				"label text must be String",
				{"action_id": action_id}
			)

	for raw_key in labels.keys():
		var action_id: String = String(raw_key)
		var button: Button = _buttons[action_id] as Button
		button.text = String(labels[raw_key])

	return _success("labels_changed")


func open_menu() -> Dictionary:
	var ready_result: Dictionary = _validate_runtime_ready()
	if not bool(ready_result.get("ok", false)):
		return ready_result
	if _is_open:
		return _success("menu_already_open", {"state": state_snapshot()})

	var viewport: Viewport = get_viewport()
	var current_focus: Control = viewport.gui_get_focus_owner()
	if is_instance_valid(current_focus) and not is_ancestor_of(current_focus):
		_previous_focus = current_focus
	else:
		_previous_focus = null

	var pause_result: Dictionary = _call_flow_dictionary(
		"set_paused",
		[true]
	)
	if not bool(pause_result.get("ok", false)):
		return pause_result

	_refresh_action_availability()
	_is_open = true
	show()
	move_to_front()
	call_deferred("_focus_initial_control")
	menu_opened.emit()

	return _success("pause_menu_opened", {"state": state_snapshot()})


func close_menu() -> Dictionary:
	var ready_result: Dictionary = _validate_runtime_ready()
	if not bool(ready_result.get("ok", false)):
		return ready_result
	if not _is_open:
		return _success("menu_already_closed", {"state": state_snapshot()})

	action_requested.emit(ACTION_RESUME)
	var resume_result: Dictionary = _call_flow_dictionary(
		"set_paused",
		[false]
	)
	if not bool(resume_result.get("ok", false)):
		action_failed.emit(ACTION_RESUME, resume_result.duplicate(true))
		return resume_result

	_is_open = false
	hide()
	menu_closed.emit(ACTION_RESUME)
	action_completed.emit(ACTION_RESUME, resume_result.duplicate(true))
	call_deferred("_restore_previous_focus")

	return _success("pause_menu_closed", {"state": state_snapshot()})


func toggle_menu() -> Dictionary:
	if _is_open:
		return close_menu()
	return open_menu()


func request_action(action_id: String) -> Dictionary:
	if not _is_open:
		return _error("menu_not_open", "pause menu must be open before actions run")

	match action_id:
		ACTION_RESUME:
			return close_menu()
		ACTION_OPTIONS:
			return _request_options()
		ACTION_MAIN_MENU:
			return _request_main_menu()
		ACTION_QUIT:
			return _request_quit()
		_:
			return _error(
				"unknown_action",
				"pause menu action is not supported",
				{"action_id": action_id}
			)


func is_open() -> bool:
	return _is_open


func action_button(action_id: String) -> Button:
	if not _buttons.has(action_id):
		return null
	return _buttons[action_id] as Button


func state_snapshot() -> Dictionary:
	return {
		"configured": is_instance_valid(_flow_service),
		"open": _is_open,
		"paused": (
			is_instance_valid(_flow_service)
			and bool(_flow_service.call("is_paused"))
		),
		"options_available": _options_action.is_valid(),
		"main_menu_available": _main_menu_available(),
		"quit_available": _show_quit,
		"has_previous_focus": is_instance_valid(_previous_focus),
	}


func _request_options() -> Dictionary:
	if not _options_action.is_valid():
		return _emit_action_failure(
			ACTION_OPTIONS,
			_error(
				"action_unavailable",
				"game did not configure an options action",
				{"action_id": ACTION_OPTIONS}
			)
		)

	action_requested.emit(ACTION_OPTIONS)
	var value: Variant = _options_action.call()
	var result: Dictionary = _normalize_action_result(
		ACTION_OPTIONS,
		value
	)
	if not bool(result.get("ok", false)):
		action_failed.emit(ACTION_OPTIONS, result.duplicate(true))
		return result

	action_completed.emit(ACTION_OPTIONS, result.duplicate(true))
	return result


func _request_main_menu() -> Dictionary:
	if not _main_menu_available():
		return _emit_action_failure(
			ACTION_MAIN_MENU,
			_error(
				"action_unavailable",
				"game did not configure a main menu scene",
				{"action_id": ACTION_MAIN_MENU}
			)
		)

	action_requested.emit(ACTION_MAIN_MENU)
	var result: Dictionary = _call_flow_dictionary("go_to_main_menu")
	if not bool(result.get("ok", false)):
		action_failed.emit(ACTION_MAIN_MENU, result.duplicate(true))
		return result

	_is_open = false
	hide()
	_previous_focus = null
	menu_closed.emit(ACTION_MAIN_MENU)
	action_completed.emit(ACTION_MAIN_MENU, result.duplicate(true))
	return result


func _request_quit() -> Dictionary:
	if not _show_quit:
		return _emit_action_failure(
			ACTION_QUIT,
			_error(
				"action_unavailable",
				"quit action is disabled for this menu",
				{"action_id": ACTION_QUIT}
			)
		)

	action_requested.emit(ACTION_QUIT)
	var result: Dictionary = _call_flow_dictionary("request_quit")
	if not bool(result.get("ok", false)):
		action_failed.emit(ACTION_QUIT, result.duplicate(true))
		return result

	action_completed.emit(ACTION_QUIT, result.duplicate(true))
	return result


func _emit_action_failure(
	action_id: String,
	result: Dictionary
) -> Dictionary:
	action_failed.emit(action_id, result.duplicate(true))
	return result


func _normalize_action_result(
	action_id: String,
	value: Variant
) -> Dictionary:
	if value is Dictionary:
		var dictionary_result: Dictionary = value as Dictionary
		if dictionary_result.has("ok"):
			return dictionary_result.duplicate(true)

	if typeof(value) == TYPE_BOOL and not bool(value):
		return _error(
			"action_blocked",
			"pause menu action returned false",
			{"action_id": action_id}
		)

	return _success(
		"action_completed",
		{
			"action_id": action_id,
			"value": value,
		}
	)


func _validate_runtime_ready() -> Dictionary:
	if not is_inside_tree():
		return _error(
			"not_in_scene_tree",
			"pause menu must be inside the SceneTree"
		)
	if not is_instance_valid(_flow_service):
		return _error(
			"pause_menu_not_configured",
			"configure the pause menu before using it"
		)
	return _success("pause_menu_ready")


func _main_menu_available() -> bool:
	if not is_instance_valid(_flow_service):
		return false
	var value: Variant = _flow_service.call("main_menu_id")
	return typeof(value) == TYPE_STRING and not String(value).is_empty()


func _refresh_action_availability() -> void:
	if _buttons.has(ACTION_OPTIONS):
		var options_button: Button = _buttons[ACTION_OPTIONS] as Button
		options_button.visible = _options_action.is_valid()
		options_button.disabled = not _options_action.is_valid()

	if _buttons.has(ACTION_MAIN_MENU):
		var main_menu_button: Button = _buttons[ACTION_MAIN_MENU] as Button
		var menu_available: bool = _main_menu_available()
		main_menu_button.visible = menu_available
		main_menu_button.disabled = not menu_available

	if _buttons.has(ACTION_QUIT):
		var quit_button: Button = _buttons[ACTION_QUIT] as Button
		quit_button.visible = _show_quit
		quit_button.disabled = not _show_quit


func _resolve_buttons() -> void:
	_buttons.clear()
	_resolve_button(ACTION_RESUME, resume_button_path)
	_resolve_button(ACTION_OPTIONS, options_button_path)
	_resolve_button(ACTION_MAIN_MENU, main_menu_button_path)
	_resolve_button(ACTION_QUIT, quit_button_path)


func _resolve_button(action_id: String, path: NodePath) -> void:
	var node: Node = get_node_or_null(path)
	if node is Button:
		_buttons[action_id] = node


func _connect_buttons() -> void:
	for action_id in _buttons.keys():
		var button: Button = _buttons[action_id] as Button
		var callback := Callable(self, "_on_action_button_pressed").bind(
			String(action_id)
		)
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)


func _on_action_button_pressed(action_id: String) -> void:
	request_action(action_id)


func _focus_initial_control() -> void:
	if not _is_open:
		return
	var resume_button: Button = action_button(ACTION_RESUME)
	if (
		is_instance_valid(resume_button)
		and resume_button.visible
		and not resume_button.disabled
	):
		resume_button.grab_focus()


func _restore_previous_focus() -> void:
	var target: Control = _previous_focus
	_previous_focus = null
	if not is_instance_valid(target):
		return
	if not target.is_inside_tree():
		return
	if not target.is_visible_in_tree():
		return
	if target.focus_mode == Control.FOCUS_NONE:
		return
	target.grab_focus()


func _call_flow_dictionary(
	method_name: String,
	args: Array = []
) -> Dictionary:
	if not is_instance_valid(_flow_service):
		return _error(
			"pause_menu_not_configured",
			"configure the pause menu before using it"
		)

	var value: Variant = _flow_service.callv(method_name, args)
	if not (value is Dictionary):
		return _error(
			"invalid_flow_result",
			"Game Flow method must return a Dictionary",
			{"method": method_name}
		)
	return (value as Dictionary).duplicate(true)


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
