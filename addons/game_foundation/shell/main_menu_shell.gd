extends Control

const FocusNavigationBaseline = preload(
	"res://addons/game_foundation/shell/focus_navigation_baseline.gd"
)
const UIFeedbackHooks = preload(
	"res://addons/game_foundation/shell/ui_feedback_hooks.gd"
)
const TranslationContract = preload(
	"res://addons/game_foundation/localization/translation_contract.gd"
)

signal menu_activated
signal menu_deactivated
signal action_requested(action_id: String)
signal action_completed(action_id: String, result: Dictionary)
signal action_failed(action_id: String, result: Dictionary)

const ACTION_NEW_GAME: String = "new_game"
const ACTION_CONTINUE: String = "continue"
const ACTION_OPTIONS: String = "options"
const ACTION_QUIT: String = "quit"

@export var continue_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/ContinueButton"
)
@export var new_game_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/NewGameButton"
)
@export var options_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/OptionsButton"
)
@export var quit_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Actions/QuitButton"
)

var _flow_service: Node = null
var _actions: Dictionary = {}
var _buttons: Dictionary = {}
var _continue_available: bool = false
var _show_quit: bool = true
var _active: bool = true
var _manage_focus_navigation: bool = true
var _translation_entries: Dictionary = {}
var _label_overrides: Dictionary = {}
var _feedback_hooks: Object = null
var _last_feedback_result: Dictionary = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		call_deferred("_refresh_translated_labels")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_active = visible
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
	if not flow.has_method("request_quit"):
		return _error(
			"invalid_flow_service",
			"flow_service is missing required method",
			{"method": "request_quit"}
		)

	var next_actions: Dictionary = {}
	var action_keys := {
		ACTION_NEW_GAME: "new_game_action",
		ACTION_CONTINUE: "continue_action",
		ACTION_OPTIONS: "options_action",
	}
	for action_id in action_keys.keys():
		var option_key: String = String(action_keys[action_id])
		var action_callable := Callable()
		if options.has(option_key):
			var callable_variant: Variant = options.get(option_key)
			if typeof(callable_variant) != TYPE_CALLABLE:
				return _error(
					"invalid_action",
					"menu action must be a Callable",
					{
						"action_id": String(action_id),
						"option_key": option_key,
					}
				)
			action_callable = callable_variant as Callable
			if not action_callable.is_valid():
				return _error(
					"invalid_action",
					"menu action Callable must be valid",
					{
						"action_id": String(action_id),
						"option_key": option_key,
					}
				)
		next_actions[String(action_id)] = action_callable

	var continue_variant: Variant = options.get("continue_available", false)
	if typeof(continue_variant) != TYPE_BOOL:
		return _error(
			"invalid_continue_available",
			"continue_available must be bool"
		)

	var show_quit_variant: Variant = options.get("show_quit", true)
	if typeof(show_quit_variant) != TYPE_BOOL:
		return _error("invalid_show_quit", "show_quit must be bool")

	var manage_focus_variant: Variant = options.get("manage_focus_navigation", true)
	if typeof(manage_focus_variant) != TYPE_BOOL:
		return _error(
			"invalid_manage_focus_navigation",
			"manage_focus_navigation must be bool"
		)

	var feedback_hooks: Object = null
	if options.has("feedback_hooks"):
		var feedback_variant: Variant = options.get("feedback_hooks")
		if not (feedback_variant is Object):
			return _error(
				"invalid_feedback_hooks",
				"feedback_hooks must be an Object"
			)
		feedback_hooks = feedback_variant as Object
		if not feedback_hooks.has_method("request_feedback"):
			return _error(
				"invalid_feedback_hooks",
				"feedback_hooks must implement request_feedback(event_id, context)"
			)

	_resolve_buttons()
	for action_id in [
		ACTION_CONTINUE,
		ACTION_NEW_GAME,
		ACTION_OPTIONS,
		ACTION_QUIT,
	]:
		if not _buttons.has(action_id):
			return _error(
				"missing_main_menu_control",
				"main menu scene is missing a required Button",
				{"action_id": action_id}
			)

	_flow_service = flow
	_actions = next_actions
	_continue_available = bool(continue_variant)
	_show_quit = bool(show_quit_variant)
	_manage_focus_navigation = bool(manage_focus_variant)
	_feedback_hooks = feedback_hooks
	_last_feedback_result = {}

	var translation_result: Dictionary = set_translation_entries(
		options.get("translation_entries", {})
	)
	if not bool(translation_result.get("ok", false)):
		return translation_result

	if options.has("labels"):
		var label_result: Dictionary = set_labels(options.get("labels"))
		if not bool(label_result.get("ok", false)):
			return label_result

	_active = visible
	_refresh_action_availability()
	if _active:
		call_deferred("_focus_initial_control")

	return _success("main_menu_configured", {"state": state_snapshot()})


func set_translation_entries(entries_variant: Variant) -> Dictionary:
	var normalized: Dictionary = TranslationContract.normalize_entries(
		TranslationContract.SHELL_MAIN_MENU,
		entries_variant
	)
	if not bool(normalized.get("ok", false)):
		return normalized

	_translation_entries = (
		normalized.get("entries", {}) as Dictionary
	).duplicate(true)
	return _refresh_translated_labels()


func refresh_translations() -> Dictionary:
	return _refresh_translated_labels()


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
		_label_overrides[action_id] = String(labels[raw_key])

	return _refresh_translated_labels()


func _refresh_translated_labels() -> Dictionary:
	if _buttons.is_empty():
		_resolve_buttons()

	var resolved: Dictionary = TranslationContract.resolve_labels(
		TranslationContract.SHELL_MAIN_MENU,
		_translation_entries
	)
	if not bool(resolved.get("ok", false)):
		return resolved

	var labels: Dictionary = resolved.get("labels", {}) as Dictionary
	for action_id in labels.keys():
		if not _buttons.has(action_id):
			continue
		var button: Button = _buttons[action_id] as Button
		if _label_overrides.has(action_id):
			button.text = String(_label_overrides[action_id])
		else:
			button.text = String(labels[action_id])

	return _success(
		"translations_refreshed",
		{
			"locale": String(resolved.get("locale", "")),
			"sources": (
				resolved.get("sources", {}) as Dictionary
			).duplicate(true),
		}
	)


func set_continue_available(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_BOOL:
		return _error(
			"invalid_continue_available",
			"continue availability must be bool"
		)

	_continue_available = bool(value)
	_refresh_action_availability()
	return _success(
		"continue_availability_changed",
		{"state": state_snapshot()}
	)


func activate_menu() -> Dictionary:
	var ready_result: Dictionary = _validate_runtime_ready()
	if not bool(ready_result.get("ok", false)):
		return ready_result

	_active = true
	show()
	_refresh_action_availability()
	call_deferred("_focus_initial_control")
	menu_activated.emit()
	_request_ui_feedback(UIFeedbackHooks.EVENT_OPEN)
	return _success("main_menu_activated", {"state": state_snapshot()})


func deactivate_menu() -> Dictionary:
	var ready_result: Dictionary = _validate_runtime_ready()
	if not bool(ready_result.get("ok", false)):
		return ready_result

	_active = false
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner) and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	hide()
	menu_deactivated.emit()
	_request_ui_feedback(UIFeedbackHooks.EVENT_CLOSE)
	return _success("main_menu_deactivated", {"state": state_snapshot()})


func focus_initial_action() -> Dictionary:
	var ready_result: Dictionary = _validate_runtime_ready()
	if not bool(ready_result.get("ok", false)):
		return ready_result
	if not _active or not visible:
		return _error(
			"menu_not_active",
			"main menu must be active before focus is assigned"
		)

	var action_id: String = _focus_initial_control()
	if action_id.is_empty():
		return _error(
			"no_focusable_action",
			"main menu has no visible enabled action"
		)
	return _success("initial_focus_assigned", {"action_id": action_id})


func request_action(action_id: String) -> Dictionary:
	var ready_result: Dictionary = _validate_runtime_ready()
	if not bool(ready_result.get("ok", false)):
		return ready_result
	if not _active or not visible:
		return _error(
			"menu_not_active",
			"main menu must be active before actions run"
		)

	match action_id:
		ACTION_NEW_GAME, ACTION_CONTINUE, ACTION_OPTIONS:
			return _request_callable_action(action_id)
		ACTION_QUIT:
			return _request_quit()
		_:
			return _error(
				"unknown_action",
				"main menu action is not supported",
				{"action_id": action_id}
			)


func is_active() -> bool:
	return _active and visible


func action_button(action_id: String) -> Button:
	if not _buttons.has(action_id):
		return null
	return _buttons[action_id] as Button


func state_snapshot() -> Dictionary:
	return {
		"configured": is_instance_valid(_flow_service),
		"active": is_active(),
		"new_game_available": _action_callable_available(ACTION_NEW_GAME),
		"continue_slot_configured": _action_callable_available(ACTION_CONTINUE),
		"continue_available": _continue_action_available(),
		"options_available": _action_callable_available(ACTION_OPTIONS),
		"quit_available": _show_quit,
		"focused_action_id": focused_action_id(),
		"managed_focus_navigation": _manage_focus_navigation,
		"navigation_baseline": FocusNavigationBaseline.snapshot(
			_focus_controls()
		),
		"feedback_hooks_configured": is_instance_valid(_feedback_hooks),
		"feedback": _feedback_state_snapshot(),
		"last_feedback_result": _last_feedback_result.duplicate(true),
	}


func _request_callable_action(action_id: String) -> Dictionary:
	if not _action_callable_available(action_id):
		return _emit_action_failure(
			action_id,
			_error(
				"action_unavailable",
				"game did not configure this main menu action",
				{"action_id": action_id}
			)
		)

	if action_id == ACTION_CONTINUE and not _continue_available:
		return _emit_action_failure(
			action_id,
			_error(
				"action_unavailable",
				"continue action is not currently available",
				{"action_id": action_id}
			)
		)

	action_requested.emit(action_id)
	var action_callable: Callable = _actions[action_id] as Callable
	var value: Variant = action_callable.call()
	var result: Dictionary = _normalize_action_result(action_id, value)
	if not bool(result.get("ok", false)):
		action_failed.emit(action_id, result.duplicate(true))
		return result

	action_completed.emit(action_id, result.duplicate(true))
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
	var value: Variant = _flow_service.call("request_quit")
	if not (value is Dictionary):
		var invalid_result := _error(
			"invalid_flow_result",
			"Game Flow request_quit must return a Dictionary",
			{"method": "request_quit"}
		)
		action_failed.emit(ACTION_QUIT, invalid_result.duplicate(true))
		return invalid_result

	var result: Dictionary = (value as Dictionary).duplicate(true)
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
			"main menu action returned false",
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
			"main menu must be inside the SceneTree"
		)
	if not is_instance_valid(_flow_service):
		return _error(
			"main_menu_not_configured",
			"configure the main menu before using it"
		)
	return _success("main_menu_ready")


func _action_callable_available(action_id: String) -> bool:
	if not _actions.has(action_id):
		return false
	var action_callable: Callable = _actions[action_id] as Callable
	return action_callable.is_valid()


func _continue_action_available() -> bool:
	return _action_callable_available(ACTION_CONTINUE) and _continue_available


func _refresh_action_availability() -> void:
	if _buttons.has(ACTION_NEW_GAME):
		var new_button: Button = _buttons[ACTION_NEW_GAME] as Button
		var new_available: bool = _action_callable_available(ACTION_NEW_GAME)
		new_button.visible = new_available
		new_button.disabled = not new_available

	if _buttons.has(ACTION_CONTINUE):
		var continue_button: Button = _buttons[ACTION_CONTINUE] as Button
		var continue_configured: bool = _action_callable_available(ACTION_CONTINUE)
		continue_button.visible = continue_configured
		continue_button.disabled = not _continue_action_available()

	if _buttons.has(ACTION_OPTIONS):
		var options_button: Button = _buttons[ACTION_OPTIONS] as Button
		var options_available: bool = _action_callable_available(ACTION_OPTIONS)
		options_button.visible = options_available
		options_button.disabled = not options_available

	if _buttons.has(ACTION_QUIT):
		var quit_button: Button = _buttons[ACTION_QUIT] as Button
		quit_button.visible = _show_quit
		quit_button.disabled = not _show_quit

	_refresh_focus_navigation()
	_repair_focus_after_availability_change()


func focused_action_id() -> String:
	if not is_inside_tree():
		return ""
	var owner: Control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(owner):
		return ""
	for action_id in _buttons.keys():
		if owner == _buttons[action_id]:
			return String(action_id)
	return ""


func _focus_controls() -> Array:
	return [
		action_button(ACTION_CONTINUE),
		action_button(ACTION_NEW_GAME),
		action_button(ACTION_OPTIONS),
		action_button(ACTION_QUIT),
	]


func _refresh_focus_navigation() -> void:
	if not _manage_focus_navigation:
		return
	FocusNavigationBaseline.configure_vertical(_focus_controls())


func _repair_focus_after_availability_change() -> void:
	if not _active or not visible or not is_inside_tree():
		return
	var result: Dictionary = FocusNavigationBaseline.repair_focus(
		_focus_controls(),
		{"preserve_external_focus": true}
	)
	if not bool(result.get("ok", false)):
		call_deferred("_focus_initial_control")


func _resolve_buttons() -> void:
	_buttons.clear()
	_resolve_button(ACTION_CONTINUE, continue_button_path)
	_resolve_button(ACTION_NEW_GAME, new_game_button_path)
	_resolve_button(ACTION_OPTIONS, options_button_path)
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

		var focus_callback := Callable(
			self,
			"_on_action_button_focused"
		).bind(String(action_id))
		if not button.focus_entered.is_connected(focus_callback):
			button.focus_entered.connect(focus_callback)


func _on_action_button_pressed(action_id: String) -> void:
	_request_ui_feedback(
		UIFeedbackHooks.EVENT_ACTIVATE,
		action_id
	)
	request_action(action_id)


func _on_action_button_focused(action_id: String) -> void:
	_request_ui_feedback(
		UIFeedbackHooks.EVENT_FOCUS,
		action_id
	)


func _request_ui_feedback(
	event_id: String,
	action_id: String = ""
) -> void:
	if not is_instance_valid(_feedback_hooks):
		return
	var context: Dictionary = {
		"surface": "main_menu",
	}
	if not action_id.is_empty():
		context["action_id"] = action_id
	var value: Variant = _feedback_hooks.call(
		"request_feedback",
		event_id,
		context
	)
	if value is Dictionary:
		_last_feedback_result = (
			value as Dictionary
		).duplicate(true)
	else:
		_last_feedback_result = {
			"ok": true,
			"code": "feedback_result_unstructured",
			"value": value,
		}


func _feedback_state_snapshot() -> Dictionary:
	if not is_instance_valid(_feedback_hooks):
		return {}
	if not _feedback_hooks.has_method("state_snapshot"):
		return {}
	var value: Variant = _feedback_hooks.call("state_snapshot")
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _focus_initial_control() -> String:
	var result: Dictionary = FocusNavigationBaseline.focus_first(
		_focus_controls()
	)
	if not bool(result.get("ok", false)):
		return ""
	return focused_action_id()


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
