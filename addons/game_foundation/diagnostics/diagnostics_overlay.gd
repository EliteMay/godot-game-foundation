extends CanvasLayer

const DEFAULT_REFRESH_SECONDS: float = 0.5

@export_range(0.1, 5.0, 0.1) var refresh_seconds: float = DEFAULT_REFRESH_SECONDS

var _service: Node = null
var _panel: PanelContainer
var _label: Label
var _elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_ui()
	visible = false


func _process(delta: float) -> void:
	if not visible or _service == null:
		return

	_elapsed += delta
	if _elapsed < refresh_seconds:
		return

	_elapsed = 0.0
	refresh_now()


func bind_service(service: Node) -> Dictionary:
	if service == null or not service.has_method("build_snapshot"):
		return {
			"ok": false,
			"code": "invalid_diagnostics_service",
		}

	_service = service
	refresh_now()
	return {
		"ok": true,
		"code": "diagnostics_service_bound",
	}


func set_overlay_visible(value: bool) -> void:
	visible = value
	if value:
		refresh_now()


func toggle_overlay() -> void:
	set_overlay_visible(not visible)


func refresh_now() -> void:
	if _service == null or not is_instance_valid(_label):
		return
	var snapshot: Dictionary = _service.call("build_snapshot")
	_label.text = format_snapshot(snapshot)


func rendered_text() -> String:
	if not is_instance_valid(_label):
		return ""
	return _label.text


static func format_snapshot(snapshot: Dictionary) -> String:
	var runtime: Dictionary = snapshot.get("runtime", {})
	var app: Dictionary = runtime.get("app", {})
	var foundation: Dictionary = runtime.get("foundation", {})
	var engine: Dictionary = runtime.get("engine", {})
	var runtime_state: Dictionary = runtime.get("runtime", {})
	var paths: Dictionary = snapshot.get("paths", {})
	var errors: Dictionary = snapshot.get("errors", {})
	var performance: Dictionary = snapshot.get("performance", {})
	var recent_errors_variant: Variant = errors.get("recent_errors", [])

	var lines: Array[String] = [
		"DIAGNOSTICS",
		"App: %s %s" % [
			String(app.get("name", "-")),
			String(app.get("version", "")),
		],
		"Foundation: %s" % String(foundation.get("version", "-")),
		"Godot: %s" % String(engine.get("version", "-")),
		"OS: %s %s" % [
			String(runtime_state.get("os", "-")),
			String(runtime_state.get("os_version", "")),
		],
		"Display: %s | FPS: %d" % [
			String(runtime_state.get("display_server", "-")),
			int(performance.get("fps", 0)),
		],
		"",
		"Paths:",
	]

	if paths.is_empty():
		lines.append("  (not configured)")
	else:
		var path_keys: Array = paths.keys()
		path_keys.sort()
		for raw_key in path_keys:
			lines.append(
				"  %s: %s" % [
					String(raw_key),
					String(paths[raw_key]),
				]
			)

	lines.append("")
	lines.append(
		"Logs: info=%d warning=%d error=%d" % [
			int(errors.get("info_count", 0)),
			int(errors.get("warning_count", 0)),
			int(errors.get("error_count", 0)),
		]
	)

	if recent_errors_variant is Array:
		var recent_errors: Array = recent_errors_variant as Array
		if not recent_errors.is_empty():
			lines.append("Recent errors:")
			for entry_variant in recent_errors:
				if not (entry_variant is Dictionary):
					continue
				var entry: Dictionary = entry_variant as Dictionary
				lines.append("  - " + String(entry.get("message", "")))

	return "\n".join(lines)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	_panel.custom_minimum_size = Vector2(620, 280)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.04, 0.94)
	style.border_color = Color(0.28, 0.34, 0.4, 0.9)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.text = "DIAGNOSTICS"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.9, 0.94, 0.97, 1.0))
	_panel.add_child(_label)
