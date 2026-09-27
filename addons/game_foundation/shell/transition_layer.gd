extends CanvasLayer

signal transition_started(kind: String, duration_seconds: float)
signal transition_completed(kind: String)
signal transition_cancelled(kind: String)

const DEFAULT_DURATION_SECONDS: float = 0.25
const MAX_DURATION_SECONDS: float = 10.0
const DEFAULT_LAYER: int = 100
const MIN_LAYER: int = -128
const MAX_LAYER: int = 128

var _duration_seconds: float = DEFAULT_DURATION_SECONDS
var _transition_color: Color = Color(0.0, 0.0, 0.0, 1.0)
var _motion_scale: float = 1.0
var _overlay: ColorRect = null
var _tween: Tween = null
var _active_kind: String = ""
var _active_target_alpha: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_overlay()


func configure(options: Dictionary = {}) -> Dictionary:
	if is_transitioning():
		return _error(
			"transition_in_progress",
			"transition settings cannot change while a transition is running"
		)

	if options.has("duration_seconds"):
		var duration_variant: Variant = options.get("duration_seconds")
		if not _is_number(duration_variant):
			return _error("invalid_duration", "duration_seconds must be numeric")
		var duration: float = float(duration_variant)
		if duration < 0.0 or duration > MAX_DURATION_SECONDS:
			return _error(
				"invalid_duration",
				"duration_seconds must be between 0 and " + str(MAX_DURATION_SECONDS)
			)
		_duration_seconds = duration

	if options.has("color"):
		var color_variant: Variant = options.get("color")
		if typeof(color_variant) != TYPE_COLOR:
			return _error("invalid_color", "color must be a Godot Color")
		_transition_color = color_variant as Color

	if options.has("motion_scale"):
		var scale_result: Dictionary = set_motion_scale(options.get("motion_scale"))
		if not bool(scale_result.get("ok", false)):
			return scale_result

	if options.has("layer"):
		var layer_variant: Variant = options.get("layer")
		if typeof(layer_variant) != TYPE_INT:
			return _error("invalid_layer", "layer must be an integer")
		var requested_layer: int = int(layer_variant)
		if requested_layer < MIN_LAYER or requested_layer > MAX_LAYER:
			return _error(
				"invalid_layer",
				"layer must be between " + str(MIN_LAYER) + " and " + str(MAX_LAYER)
			)
		layer = requested_layer

	_ensure_overlay()
	_apply_transition_color_preserving_alpha()
	return _success("transition_configured", {"state": state_snapshot()})


func set_motion_scale(value: Variant) -> Dictionary:
	if not _is_number(value):
		return _error("invalid_motion_scale", "motion_scale must be numeric")

	var scale: float = float(value)
	if scale < 0.0 or scale > 1.0:
		return _error(
			"invalid_motion_scale",
			"motion_scale must be between 0.0 and 1.0"
		)

	_motion_scale = scale
	return _success("motion_scale_changed", {"motion_scale": _motion_scale})


func set_reduced_motion(enabled: bool) -> Dictionary:
	return set_motion_scale(0.0 if enabled else 1.0)


func fade_out(duration_override: float = -1.0) -> Dictionary:
	return _start_transition(
		"fade_out",
		_transition_color.a,
		duration_override
	)


func fade_in(duration_override: float = -1.0) -> Dictionary:
	return _start_transition(
		"fade_in",
		0.0,
		duration_override
	)


func show_covered() -> Dictionary:
	cancel_transition()
	_set_overlay_alpha(_transition_color.a)
	return _success("covered", {"state": state_snapshot()})


func show_clear() -> Dictionary:
	cancel_transition()
	_set_overlay_alpha(0.0)
	return _success("clear", {"state": state_snapshot()})


func cancel_transition() -> Dictionary:
	if not is_transitioning():
		_tween = null
		_active_kind = ""
		return _success("transition_not_running")

	var cancelled_kind: String = _active_kind
	_tween.kill()
	_tween = null
	_active_kind = ""
	transition_cancelled.emit(cancelled_kind)
	return _success("transition_cancelled", {"kind": cancelled_kind})


func is_transitioning() -> bool:
	return _tween != null and _tween.is_running()


func state_snapshot() -> Dictionary:
	_ensure_overlay()
	return {
		"duration_seconds": _duration_seconds,
		"motion_scale": _motion_scale,
		"color": _transition_color.to_html(true),
		"layer": layer,
		"alpha": _overlay.color.a,
		"transitioning": is_transitioning(),
		"active_kind": _active_kind,
	}


func _start_transition(
	kind: String,
	target_alpha: float,
	duration_override: float
) -> Dictionary:
	_ensure_overlay()

	if is_transitioning():
		return _error(
			"transition_in_progress",
			"another transition is already running",
			{"active_kind": _active_kind}
		)

	var duration_result: Dictionary = _resolve_duration(duration_override)
	if not bool(duration_result.get("ok", false)):
		return duration_result

	var effective_duration: float = float(duration_result.get("duration_seconds", 0.0))
	var current_alpha: float = _overlay.color.a
	_active_kind = kind
	_active_target_alpha = target_alpha
	transition_started.emit(kind, effective_duration)

	if effective_duration <= 0.0 or is_equal_approx(current_alpha, target_alpha):
		_set_overlay_alpha(target_alpha)
		_active_kind = ""
		transition_completed.emit(kind)
		return _success("transition_completed_immediately", {
			"kind": kind,
			"duration_seconds": effective_duration,
			"state": state_snapshot(),
		})

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(
		Callable(self, "_set_overlay_alpha"),
		current_alpha,
		target_alpha,
		effective_duration
	)
	_tween.finished.connect(
		Callable(self, "_on_tween_finished").bind(kind),
		CONNECT_ONE_SHOT
	)

	return _success("transition_started", {
		"kind": kind,
		"duration_seconds": effective_duration,
	})


func _resolve_duration(duration_override: float) -> Dictionary:
	var base_duration: float = _duration_seconds
	if duration_override >= 0.0:
		if duration_override > MAX_DURATION_SECONDS:
			return _error(
				"invalid_duration",
				"duration override must not exceed " + str(MAX_DURATION_SECONDS)
			)
		base_duration = duration_override

	return _success("duration_resolved", {
		"duration_seconds": base_duration * _motion_scale,
	})


func _on_tween_finished(kind: String) -> void:
	_set_overlay_alpha(_active_target_alpha)
	_tween = null
	_active_kind = ""
	transition_completed.emit(kind)


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay):
		return

	_overlay = ColorRect.new()
	_overlay.name = "TransitionOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(
		_transition_color.r,
		_transition_color.g,
		_transition_color.b,
		0.0
	)
	add_child(_overlay)


func _apply_transition_color_preserving_alpha() -> void:
	if not is_instance_valid(_overlay):
		return

	var current_alpha: float = min(_overlay.color.a, _transition_color.a)
	_overlay.color = Color(
		_transition_color.r,
		_transition_color.g,
		_transition_color.b,
		current_alpha
	)


func _set_overlay_alpha(value: float) -> void:
	_ensure_overlay()
	_overlay.color = Color(
		_transition_color.r,
		_transition_color.g,
		_transition_color.b,
		clampf(value, 0.0, _transition_color.a)
	)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


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
