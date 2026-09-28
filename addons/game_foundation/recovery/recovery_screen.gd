extends Control

const RecoveryScreenContract = preload(
	"res://addons/game_foundation/recovery/recovery_screen_contract.gd"
)
const FocusNavigationBaseline = preload(
	"res://addons/game_foundation/shell/focus_navigation_baseline.gd"
)
const TranslationContract = preload(
	"res://addons/game_foundation/localization/translation_contract.gd"
)

signal screen_opened(state: Dictionary)
signal screen_closed
signal action_requested(action_id: String)
signal action_completed(action_id: String, result: Dictionary)
signal action_failed(action_id: String, result: Dictionary)
signal recovery_succeeded(result: Dictionary)

@export var title_label_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/Title"
)
@export var summary_label_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/Summary"
)
@export var details_label_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/Details"
)
@export var state_hint_label_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/StateHint"
)
@export var status_label_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/Status"
)
@export var retry_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/Actions/RetryButton"
)
@export var main_menu_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/Actions/MainMenuButton"
)
@export var safe_quit_button_path: NodePath = NodePath(
	"Center/Panel/Margin/Content/Actions/SafeQuitButton"
)

var _contract: RefCounted = null
var _translation_entries: Dictionary = {}
var _label_overrides: Dictionary = {}
var _manage_focus_navigation: bool = true
var _open: bool = false
var _title_label: Label = null
var _summary_label: Label = null
var _details_label: Label = null
var _state_hint_label: Label = null
var _status_label: Label = null
var _buttons: Dictionary = {}


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_TRANSLATION_CHANGED
		and is_node_ready()
	):
		call_deferred("_refresh_translated_labels")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_resolve_controls()
	_connect_buttons()


func configure(options: Dictionary) -> Dictionary:
	var manage_focus_variant: Variant = options.get(
		"manage_focus_navigation",
		true
	)
	if typeof(manage_focus_variant) != TYPE_BOOL:
		return _error(
			"invalid_manage_focus_navigation",
			"manage_focus_navigation must be bool"
		)

	var translation_result: Dictionary = (
		TranslationContract.normalize_entries(
			TranslationContract.SHELL_RECOVERY_SCREEN,
			options.get("translation_entries", {})
		)
	)
	if not bool(translation_result.get("ok", false)):
		return translation_result

	var labels_variant: Variant = options.get("labels", {})
	if not (labels_variant is Dictionary):
		return _error(
			"invalid_labels",
			"labels must be a Dictionary"
		)
	var labels: Dictionary = labels_variant as Dictionary
	for key in labels.keys():
		if typeof(key) != TYPE_STRING:
			return _error(
				"invalid_labels",
				"label ids must be String"
			)
		if typeof(labels[key]) != TYPE_STRING:
			return _error(
				"invalid_labels",
				"label overrides must be String",
				{"label_id": String(key)}
			)

	_resolve_controls()
	var controls_result: Dictionary = _validate_controls()
	if not bool(controls_result.get("ok", false)):
		return controls_result

	var contract := RecoveryScreenContract.new()
	_connect_contract(contract)

	var contract_options: Dictionary = {
		"runtime": options.get("runtime"),
	}
	for key in [
		"retry_action",
		"main_menu_action",
		"safe_quit_action",
	]:
		if options.has(key):
			contract_options[key] = options[key]

	var configured: Dictionary = contract.configure(
		contract_options
	)
	if not bool(configured.get("ok", false)):
		return configured

	_contract = contract
	_manage_focus_navigation = bool(manage_focus_variant)
	_translation_entries = (
		translation_result.get("entries", {}) as Dictionary
	).duplicate(true)
	_label_overrides = labels.duplicate(true)
	_open = false

	_refresh_translated_labels()
	_apply_snapshot(_contract.call("state_snapshot"))

	return _success(
		"recovery_screen_configured",
		{"state": state_snapshot()}
	)


func open_screen() -> Dictionary:
	if not is_instance_valid(_contract):
		return _error(
			"recovery_screen_not_configured",
			"recovery screen must be configured before opening"
		)

	var refreshed: Dictionary = _contract.call("refresh")
	if not bool(refreshed.get("ok", false)):
		return refreshed

	var snapshot: Dictionary = _contract.call(
		"state_snapshot"
	)
	if not bool(snapshot.get("active", false)):
		return _error(
			"no_active_runtime_failure",
			"recovery screen requires an active runtime failure"
		)

	_open = true
	show()
	_apply_snapshot(snapshot)
	_assign_initial_focus()
	screen_opened.emit(snapshot.duplicate(true))
	return _success(
		"recovery_screen_opened",
		{"state": state_snapshot()}
	)


func close_screen() -> Dictionary:
	if not _open:
		return _success(
			"recovery_screen_already_closed",
			{"state": state_snapshot()}
		)
	_open = false
	hide()
	screen_closed.emit()
	return _success(
		"recovery_screen_closed",
		{"state": state_snapshot()}
	)


func request_action(action_id: String) -> Dictionary:
	if not _open:
		return _error(
			"recovery_screen_not_open",
			"recovery screen must be open before actions run"
		)
	if not is_instance_valid(_contract):
		return _error(
			"recovery_screen_not_configured",
			"recovery screen contract is unavailable"
		)

	var result: Dictionary = _contract.call(
		"perform_action",
		action_id
	)
	var snapshot: Dictionary = _contract.call(
		"state_snapshot"
	)
	_apply_snapshot(snapshot)

	if (
		action_id == RecoveryScreenContract.ACTION_RETRY
		and bool(result.get("ok", false))
		and not bool(snapshot.get("active", false))
	):
		_open = false
		hide()
		recovery_succeeded.emit(result.duplicate(true))
		screen_closed.emit()

	return result


func state_snapshot() -> Dictionary:
	var contract_state: Dictionary = {}
	if is_instance_valid(_contract):
		contract_state = _contract.call(
			"state_snapshot"
		)
	return {
		"configured": is_instance_valid(_contract),
		"open": _open,
		"contract": contract_state,
		"focused_action_id": focused_action_id(),
		"managed_focus_navigation": _manage_focus_navigation,
		"navigation_baseline": FocusNavigationBaseline.snapshot(
			_focus_controls()
		),
	}


func action_button(action_id: String) -> Button:
	if not _buttons.has(action_id):
		return null
	return _buttons[action_id] as Button


func focused_action_id() -> String:
	if _buttons.is_empty():
		return ""
	var first: Button = _buttons.values()[0] as Button
	var viewport: Viewport = first.get_viewport()
	var owner: Control = viewport.gui_get_focus_owner()
	for action_id in _buttons.keys():
		if owner == _buttons[action_id]:
			return String(action_id)
	return ""


func _resolve_controls() -> void:
	_title_label = get_node_or_null(
		title_label_path
	) as Label
	_summary_label = get_node_or_null(
		summary_label_path
	) as Label
	_details_label = get_node_or_null(
		details_label_path
	) as Label
	_state_hint_label = get_node_or_null(
		state_hint_label_path
	) as Label
	_status_label = get_node_or_null(
		status_label_path
	) as Label
	_buttons = {
		RecoveryScreenContract.ACTION_RETRY: (
			get_node_or_null(retry_button_path) as Button
		),
		RecoveryScreenContract.ACTION_MAIN_MENU: (
			get_node_or_null(main_menu_button_path) as Button
		),
		RecoveryScreenContract.ACTION_SAFE_QUIT: (
			get_node_or_null(safe_quit_button_path) as Button
		),
	}


func _validate_controls() -> Dictionary:
	for label in [
		_title_label,
		_summary_label,
		_details_label,
		_state_hint_label,
		_status_label,
	]:
		if not is_instance_valid(label):
			return _error(
				"missing_recovery_control",
				"recovery screen scene is missing a required Label"
			)
	for action_id in _buttons.keys():
		if not is_instance_valid(_buttons[action_id]):
			return _error(
				"missing_recovery_control",
				"recovery screen scene is missing a required Button",
				{"action_id": String(action_id)}
			)
	return _success("recovery_controls_ready")


func _connect_buttons() -> void:
	if _buttons.is_empty():
		_resolve_controls()
	for action_id in _buttons.keys():
		var button: Button = _buttons[action_id] as Button
		if not is_instance_valid(button):
			continue
		var callback := Callable(
			self,
			"_on_action_button_pressed"
		).bind(String(action_id))
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)


func _connect_contract(contract: RefCounted) -> void:
	contract.connect(
		"action_requested",
		Callable(self, "_on_contract_action_requested")
	)
	contract.connect(
		"action_completed",
		Callable(self, "_on_contract_action_completed")
	)
	contract.connect(
		"action_failed",
		Callable(self, "_on_contract_action_failed")
	)
	contract.connect(
		"state_changed",
		Callable(self, "_on_contract_state_changed")
	)


func _on_action_button_pressed(action_id: String) -> void:
	request_action(action_id)


func _on_contract_action_requested(action_id: String) -> void:
	action_requested.emit(action_id)


func _on_contract_action_completed(
	action_id: String,
	result: Dictionary
) -> void:
	action_completed.emit(action_id, result.duplicate(true))


func _on_contract_action_failed(
	action_id: String,
	result: Dictionary
) -> void:
	action_failed.emit(action_id, result.duplicate(true))


func _on_contract_state_changed(snapshot: Dictionary) -> void:
	if not is_node_ready():
		return
	_apply_snapshot(snapshot)


func _apply_snapshot(snapshot: Dictionary) -> void:
	if not is_instance_valid(_summary_label):
		return

	var failure: Dictionary = (
		snapshot.get("failure", {}) as Dictionary
	)
	var actions: Dictionary = (
		snapshot.get("actions", {}) as Dictionary
	)
	var busy: bool = bool(
		snapshot.get("action_in_progress", false)
	)

	_summary_label.text = String(
		failure.get(
			"message",
			"Foundation runtime failed to initialize."
		)
	)

	var stage: String = String(
		failure.get("stage", "unknown")
	)
	var code: String = String(
		failure.get("code", "initialization_failed")
	)
	_details_label.text = (
		"[" + stage + "] " + code
	)

	var hints: Array[String] = []
	var labels: Dictionary = _resolved_labels()
	if bool(failure.get("save_writes_blocked", false)):
		hints.append(
			String(labels.get("save_protected", ""))
		)
	if bool(failure.get("diagnostics_available", false)):
		hints.append(
			String(
				labels.get(
					"diagnostics_available",
					""
				)
			)
		)
	var visible_hints: Array[String] = []
	for hint in hints:
		if not hint.is_empty():
			visible_hints.append(hint)
	_state_hint_label.text = "\n".join(visible_hints)

	for action_id in _buttons.keys():
		var button: Button = _buttons[action_id] as Button
		var available: bool = bool(
			actions.get(String(action_id), false)
		)
		button.visible = available
		button.disabled = busy or not available

	var last_result: Dictionary = (
		snapshot.get("last_action_result", {}) as Dictionary
	)
	if last_result.is_empty():
		_status_label.text = ""
	elif bool(last_result.get("ok", false)):
		_status_label.text = ""
	else:
		_status_label.text = String(
			last_result.get(
				"message",
				last_result.get(
					"code",
					"Recovery action failed"
				)
			)
		)

	if _manage_focus_navigation:
		FocusNavigationBaseline.configure_vertical(
			_focus_controls()
		)
		FocusNavigationBaseline.repair_focus(
			_focus_controls()
		)


func _refresh_translated_labels() -> void:
	var labels: Dictionary = _resolved_labels()
	if is_instance_valid(_title_label):
		_title_label.text = String(
			labels.get("title", "Recovery needed")
		)
	if _buttons.has(RecoveryScreenContract.ACTION_RETRY):
		var retry: Button = _buttons[
			RecoveryScreenContract.ACTION_RETRY
		] as Button
		if is_instance_valid(retry):
			retry.text = String(
				labels.get("retry", "Retry")
			)
	if _buttons.has(
		RecoveryScreenContract.ACTION_MAIN_MENU
	):
		var main_menu: Button = _buttons[
			RecoveryScreenContract.ACTION_MAIN_MENU
		] as Button
		if is_instance_valid(main_menu):
			main_menu.text = String(
				labels.get("main_menu", "Main Menu")
			)
	if _buttons.has(
		RecoveryScreenContract.ACTION_SAFE_QUIT
	):
		var quit: Button = _buttons[
			RecoveryScreenContract.ACTION_SAFE_QUIT
		] as Button
		if is_instance_valid(quit):
			quit.text = String(
				labels.get("safe_quit", "Quit")
			)

	if is_instance_valid(_contract):
		_apply_snapshot(
			_contract.call("state_snapshot")
		)


func _resolved_labels() -> Dictionary:
	var resolved: Dictionary = (
		TranslationContract.resolve_labels(
			TranslationContract.SHELL_RECOVERY_SCREEN,
			_translation_entries
		)
	)
	var labels: Dictionary = {}
	if bool(resolved.get("ok", false)):
		labels = (
			resolved.get("labels", {}) as Dictionary
		).duplicate(true)
	else:
		labels = {
			"title": "Recovery needed",
			"retry": "Retry",
			"main_menu": "Main Menu",
			"safe_quit": "Quit",
			"save_protected": (
				"Save data is protected from overwrite."
			),
			"diagnostics_available": (
				"Diagnostics are available."
			),
		}
	for key in _label_overrides.keys():
		labels[String(key)] = String(
			_label_overrides[key]
		)
	return labels


func _assign_initial_focus() -> void:
	if not _manage_focus_navigation:
		return
	FocusNavigationBaseline.configure_vertical(
		_focus_controls()
	)
	FocusNavigationBaseline.focus_first(
		_focus_controls()
	)


func _focus_controls() -> Array:
	var controls: Array = []
	for action_id in [
		RecoveryScreenContract.ACTION_RETRY,
		RecoveryScreenContract.ACTION_MAIN_MENU,
		RecoveryScreenContract.ACTION_SAFE_QUIT,
	]:
		if not _buttons.has(action_id):
			continue
		var button: Button = _buttons[action_id] as Button
		if is_instance_valid(button):
			controls.append(button)
	return controls


func _success(
	code: String,
	extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"code": code,
	}
	for key in extra:
		result[key] = extra[key]
	return result


func _error(
	code: String,
	message: String,
	extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"code": code,
		"message": message,
	}
	for key in extra:
		result[key] = extra[key]
	return result
