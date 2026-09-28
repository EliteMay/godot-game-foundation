extends Node

const FoundationRuntime = preload(
	"res://addons/game_foundation/runtime/foundation_runtime.gd"
)

var _failed: bool = false
var _failure_signal_count: int = 0
var _failure_state_signal_count: int = 0
var _last_failure_signal: Dictionary = {}
var _last_state_signal: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var runtime := FoundationRuntime.new()
	runtime.initialization_failed.connect(
		_on_initialization_failed
	)
	runtime.runtime_failure_changed.connect(
		_on_runtime_failure_changed
	)

	_expect_ok(
		runtime.configure({
			"settings": {"enabled": false},
			"input": {"enabled": false},
			"flow": {"enabled": false},
			"diagnostics": {"enabled": false},
			"runtime_test": {"enabled": false},
		}),
		"runtime should configure before failure-state smoke"
	)

	var failed_initialize: Dictionary = runtime.initialize()
	_expect_true(
		not bool(failed_initialize.get("ok", true)),
		"initializing outside SceneTree should fail"
	)
	_expect_equal(
		String(failed_initialize.get("code", "")),
		"not_in_scene_tree",
		"failure result should preserve original code"
	)

	var state: Dictionary = runtime.runtime_failure_state()
	_expect_true(
		bool(state.get("active", false)),
		"runtime failure state should become active"
	)
	_expect_equal(
		String(state.get("kind", "")),
		"initialization",
		"failure kind should identify initialization"
	)
	_expect_equal(
		String(state.get("stage", "")),
		"scene_tree",
		"failure stage should identify SceneTree readiness"
	)
	_expect_equal(
		String(state.get("code", "")),
		"not_in_scene_tree",
		"failure state should expose the failure code"
	)
	_expect_true(
		bool(state.get("retry_supported", false)),
		"pre-side-effect SceneTree failure may be retried"
	)
	_expect_true(
		not bool(state.get("save_writes_blocked", true)),
		"SceneTree failure should not claim save writes are blocked"
	)
	_expect_true(
		runtime.has_runtime_failure(),
		"runtime should report an active failure"
	)
	_expect_equal(
		_failure_signal_count,
		1,
		"initialization_failed should emit once"
	)
	_expect_equal(
		_failure_state_signal_count,
		1,
		"runtime_failure_changed should emit active state"
	)
	_expect_equal(
		String(_last_failure_signal.get("stage", "")),
		"scene_tree",
		"initialization_failed signal should expose state"
	)
	_expect_true(
		bool(
			(
				failed_initialize.get(
					"runtime_failure",
					{}
				) as Dictionary
			).get("active", false)
		),
		"initialize result should include runtime failure state"
	)

	var status: Dictionary = runtime.status_snapshot()
	_expect_true(
		bool(status.get("has_runtime_failure", false)),
		"status snapshot should expose active runtime failure"
	)
	_expect_equal(
		String(
			(
				status.get("runtime_failure", {}) as Dictionary
			).get("code", "")
		),
		"not_in_scene_tree",
		"status snapshot should expose failure details"
	)

	add_child(runtime)
	await get_tree().process_frame
	var retry_result: Dictionary = runtime.initialize()
	_expect_ok(
		retry_result,
		"runtime should initialize after entering SceneTree"
	)
	_expect_true(
		not runtime.has_runtime_failure(),
		"successful initialization should clear failure state"
	)
	_expect_true(
		not bool(
			runtime.runtime_failure_state().get(
				"active",
				true
			)
		),
		"cleared state should be inactive"
	)
	_expect_equal(
		_failure_state_signal_count,
		2,
		"clearing failure should emit state change"
	)
	_expect_true(
		not bool(_last_state_signal.get("active", true)),
		"last failure-state signal should report inactive"
	)
	_expect_true(
		not bool(
			runtime.status_snapshot().get(
				"has_runtime_failure",
				true
			)
		),
		"status should clear runtime failure after success"
	)

	runtime.queue_free()
	_finish()


func _on_initialization_failed(
	_result: Dictionary,
	state: Dictionary
) -> void:
	_failure_signal_count += 1
	_last_failure_signal = state.duplicate(true)


func _on_runtime_failure_changed(
	state: Dictionary
) -> void:
	_failure_state_signal_count += 1
	_last_state_signal = state.duplicate(true)


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


func _fail(message: String) -> void:
	_failed = true
	push_error("RUNTIME_FAILURE_STATE_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("RUNTIME_FAILURE_STATE_SMOKE: PASS")
		get_tree().quit(0)
