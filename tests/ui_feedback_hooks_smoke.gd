extends Node

const UIFeedbackHooks = preload(
	"res://addons/game_foundation/shell/ui_feedback_hooks.gd"
)
const TransitionLayer = preload(
	"res://addons/game_foundation/shell/transition_layer.gd"
)

class FakeMotionTarget:
	extends RefCounted

	var motion_scale: float = 1.0
	var reject_next: bool = false

	func set_motion_scale(value: Variant) -> Dictionary:
		if reject_next:
			reject_next = false
			return {
				"ok": false,
				"code": "motion_rejected",
			}
		motion_scale = float(value)
		return {
			"ok": true,
			"code": "motion_applied",
		}


var _failed: bool = false
var _feedback_events: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var target_a := FakeMotionTarget.new()
	var target_b := FakeMotionTarget.new()
	var hooks := UIFeedbackHooks.new()

	_expect_ok(
		hooks.configure({
			"motion_scale": 0.5,
			"feedback_enabled": true,
			"feedback_action": Callable(self, "_on_feedback"),
			"motion_targets": [target_a, target_b],
		}),
		"feedback hooks should configure"
	)
	_expect_float(
		target_a.motion_scale,
		0.5,
		"configured motion scale should apply to first target"
	)
	_expect_float(
		target_b.motion_scale,
		0.5,
		"configured motion scale should apply to second target"
	)

	_expect_ok(
		hooks.set_reduced_motion(true),
		"reduced motion should be enabled"
	)
	_expect_float(
		target_a.motion_scale,
		0.0,
		"reduced motion should disable target animation duration"
	)
	_expect_true(
		bool(hooks.state_snapshot().get("reduced_motion", false)),
		"snapshot should expose reduced motion"
	)

	_expect_ok(
		hooks.set_reduced_motion(false),
		"reduced motion should be disabled"
	)
	_expect_float(
		target_b.motion_scale,
		1.0,
		"normal motion should restore full target duration"
	)

	_expect_code(
		hooks.request_feedback(
			UIFeedbackHooks.EVENT_FOCUS,
			{"surface": "main_menu", "action_id": "new_game"}
		),
		"feedback_test_handled",
		"enabled feedback should call the game handler"
	)
	_expect_equal(
		_feedback_events.size(),
		1,
		"feedback handler should receive one event"
	)
	_expect_equal(
		String(_feedback_events[0].get("event_id", "")),
		UIFeedbackHooks.EVENT_FOCUS,
		"feedback event id should stay semantic"
	)

	_expect_ok(
		hooks.set_feedback_enabled(false),
		"feedback should be disableable"
	)
	_expect_code(
		hooks.request_feedback(
			UIFeedbackHooks.EVENT_ACTIVATE,
			{"surface": "main_menu", "action_id": "new_game"}
		),
		"feedback_skipped",
		"disabled feedback should not invoke the game handler"
	)
	_expect_equal(
		_feedback_events.size(),
		1,
		"disabled feedback must not call the handler"
	)

	_expect_ok(
		hooks.set_feedback_enabled(true),
		"feedback should be re-enabled"
	)
	target_b.reject_next = true
	var rollback_result: Dictionary = hooks.set_motion_scale(0.25)
	_expect_true(
		not bool(rollback_result.get("ok", true)),
		"partial motion apply failure should be surfaced"
	)
	_expect_float(
		target_a.motion_scale,
		1.0,
		"successful targets should roll back when another target rejects"
	)
	_expect_float(
		float(hooks.state_snapshot().get("motion_scale", -1.0)),
		1.0,
		"hook state should remain at the previous motion scale after rollback"
	)

	_expect_code(
		hooks.unregister_motion_target(target_b),
		"motion_target_unregistered",
		"motion targets should be removable"
	)
	_expect_ok(
		hooks.set_motion_scale(0.25),
		"remaining motion targets should still update"
	)
	_expect_float(
		target_a.motion_scale,
		0.25,
		"remaining target should receive updated scale"
	)

	_expect_true(
		not bool(
			hooks.request_feedback("   ").get("ok", true)
		),
		"empty feedback event ids should be rejected"
	)

	var transition := TransitionLayer.new()
	add_child(transition)
	await get_tree().process_frame
	_expect_ok(
		hooks.register_motion_target(transition),
		"real TransitionLayer should satisfy the motion target contract"
	)
	_expect_ok(
		hooks.set_reduced_motion(true),
		"reduced motion should propagate to TransitionLayer"
	)
	_expect_float(
		float(transition.state_snapshot().get("motion_scale", -1.0)),
		0.0,
		"TransitionLayer should receive reduced motion scale"
	)
	_expect_ok(
		hooks.unregister_motion_target(transition),
		"TransitionLayer should be removable as a motion target"
	)
	transition.queue_free()

	_finish()


func _on_feedback(
	event_id: String,
	context: Dictionary
) -> Dictionary:
	_feedback_events.append({
		"event_id": event_id,
		"context": context.duplicate(true),
	})
	return {
		"ok": true,
		"code": "feedback_test_handled",
	}


func _expect_ok(
	result: Dictionary,
	message: String
) -> void:
	if not bool(result.get("ok", false)):
		_fail(
			message
			+ " / code="
			+ String(result.get("code", ""))
		)


func _expect_code(
	result: Dictionary,
	expected: String,
	message: String
) -> void:
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


func _expect_equal(
	actual: Variant,
	expected: Variant,
	message: String
) -> void:
	if actual != expected:
		_fail(
			message
			+ " / expected="
			+ str(expected)
			+ " actual="
			+ str(actual)
		)


func _expect_float(
	actual: float,
	expected: float,
	message: String
) -> void:
	if not is_equal_approx(actual, expected):
		_fail(
			message
			+ " / expected="
			+ str(expected)
			+ " actual="
			+ str(actual)
		)


func _fail(message: String) -> void:
	_failed = true
	push_error("UI_FEEDBACK_HOOKS_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("UI_FEEDBACK_HOOKS_SMOKE: PASS")
		get_tree().quit(0)
