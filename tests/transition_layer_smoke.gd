extends Node

const TransitionLayer = preload(
	"res://addons/game_foundation/shell/transition_layer.gd"
)

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var transition := TransitionLayer.new()
	add_child(transition)
	await get_tree().process_frame

	var configured: Dictionary = transition.configure({
		"duration_seconds": 0.03,
		"color": Color(0.1, 0.2, 0.3, 0.8),
		"motion_scale": 1.0,
		"layer": 96,
	})
	_expect_ok(configured, "valid transition config should succeed")
	_expect_equal(
		int(transition.state_snapshot().get("layer", 0)),
		96,
		"configured CanvasLayer should persist"
	)

	_expect_code(
		transition.configure({"duration_seconds": -0.1}),
		"invalid_duration",
		"negative default duration should be rejected"
	)
	_expect_code(
		transition.configure({"color": "black"}),
		"invalid_color",
		"non-Color transition color should be rejected"
	)
	_expect_code(
		transition.set_motion_scale(1.5),
		"invalid_motion_scale",
		"motion scale above 1 should be rejected"
	)

	var fade_out_result: Dictionary = transition.fade_out()
	_expect_code(
		fade_out_result,
		"transition_started",
		"fade out should start an animated transition"
	)
	_expect_code(
		transition.fade_in(),
		"transition_in_progress",
		"duplicate transition should be rejected while active"
	)
	await transition.transition_completed

	var covered: Dictionary = transition.state_snapshot()
	_expect_close(
		float(covered.get("alpha", 0.0)),
		0.8,
		0.01,
		"fade out should cover the screen with configured alpha"
	)
	_expect_true(
		not bool(covered.get("transitioning", true)),
		"completed fade out should not remain active"
	)

	var fade_in_result: Dictionary = transition.fade_in(0.02)
	_expect_code(
		fade_in_result,
		"transition_started",
		"fade in should start an animated transition"
	)
	await transition.transition_completed
	_expect_close(
		float(transition.state_snapshot().get("alpha", 1.0)),
		0.0,
		0.01,
		"fade in should reveal the scene"
	)

	_expect_ok(
		transition.set_reduced_motion(true),
		"reduced motion should be configurable"
	)
	var immediate: Dictionary = transition.fade_out()
	_expect_code(
		immediate,
		"transition_completed_immediately",
		"reduced motion should disable animation duration"
	)
	_expect_close(
		float(transition.state_snapshot().get("alpha", 0.0)),
		0.8,
		0.01,
		"reduced-motion fade should still reach the target state"
	)

	_expect_ok(
		transition.configure({"motion_scale": 0.25}),
		"motion scale should support shortened animation"
	)
	var shortened: Dictionary = transition.fade_in(0.04)
	_expect_code(
		shortened,
		"transition_started",
		"non-zero motion scale should still animate"
	)
	_expect_close(
		float(shortened.get("duration_seconds", 0.0)),
		0.01,
		0.001,
		"motion scale should shorten effective duration"
	)
	await transition.transition_completed

	transition.queue_free()
	_finish()


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


func _expect_code(result: Dictionary, expected: String, message: String) -> void:
	if String(result.get("code", "")) != expected:
		_fail(
			message
			+ " / expected="
			+ expected
			+ " actual="
			+ String(result.get("code", ""))
		)


func _expect_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail(
			message
			+ " / expected="
			+ str(expected)
			+ " actual="
			+ str(actual)
		)


func _expect_close(
	actual: float,
	expected: float,
	tolerance: float,
	message: String
) -> void:
	if absf(actual - expected) > tolerance:
		_fail(
			message
			+ " / expected="
			+ str(expected)
			+ " actual="
			+ str(actual)
		)


func _fail(message: String) -> void:
	_failed = true
	push_error("TRANSITION_LAYER_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("TRANSITION_LAYER_SMOKE: PASS")
		get_tree().quit(0)
