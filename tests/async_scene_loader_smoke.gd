extends Node

const GameFlowService = preload(
	"res://addons/game_foundation/flow/game_flow_service.gd"
)
const AsyncSceneLoader = preload(
	"res://addons/game_foundation/shell/async_scene_loader.gd"
)

const MAX_WAIT_FRAMES: int = 300

var _failed: bool = false
var _progress_events: Array[float] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var flow := GameFlowService.new()
	add_child(flow)
	await get_tree().process_frame

	var contract := {
		"menu": "res://demo/demo.tscn",
		"gameplay": "res://tests/foundation_smoke.tscn",
		"missing": "res://tests/does_not_exist.tscn",
	}
	_expect_ok(
		flow.configure_scene_contract(contract, "menu"),
		"scene contract should configure"
	)

	var loader := AsyncSceneLoader.new()
	add_child(loader)
	await get_tree().process_frame
	loader.load_progress.connect(_on_load_progress)

	_expect_code(
		loader.request_scene("menu"),
		"scene_resolver_not_configured",
		"loader should reject requests before resolver setup"
	)
	_expect_ok(
		loader.configure(Callable(flow, "resolve_scene_path")),
		"GameFlowService resolver should configure"
	)

	_expect_code(
		loader.request_scene("unknown"),
		"unknown_scene",
		"unknown scene id should be rejected by the scene contract"
	)

	var request: Dictionary = loader.request_scene("menu")
	_expect_code(
		request,
		"load_started",
		"declared scene should begin background loading"
	)
	_expect_code(
		loader.request_scene("menu"),
		"duplicate_request",
		"same scene should be rejected while already loading"
	)
	_expect_code(
		loader.request_scene("gameplay"),
		"loader_busy",
		"different scene should be rejected while loader is busy"
	)

	await _wait_until_idle(loader, "menu")
	_expect_true(
		loader.loaded_scene() is PackedScene,
		"completed background load should expose a PackedScene"
	)
	_expect_equal(
		loader.loaded_scene_id(),
		"menu",
		"loaded scene id should match request"
	)
	_expect_equal(
		loader.loaded_path(),
		"res://demo/demo.tscn",
		"loaded path should come from GameFlowService scene contract"
	)
	_expect_close(
		loader.progress(),
		1.0,
		0.001,
		"completed load should report full progress"
	)
	_expect_code(
		loader.last_result(),
		"load_completed",
		"last result should record successful completion"
	)

	var taken: PackedScene = loader.take_loaded_scene()
	_expect_true(
		taken is PackedScene,
		"take_loaded_scene should return the completed resource"
	)
	_expect_true(
		loader.loaded_scene() == null,
		"take_loaded_scene should clear retained resource"
	)

	var missing_result: Dictionary = loader.request_scene("missing")
	if bool(missing_result.get("ok", false)):
		await _wait_until_idle(loader, "missing")
		_expect_true(
			not bool(loader.last_result().get("ok", true)),
			"missing scene should eventually fail"
		)
	else:
		_expect_code(
			missing_result,
			"threaded_request_failed",
			"missing scene may fail immediately at request time"
		)

	_expect_true(
		not loader.is_loading(),
		"loader should be idle after failure"
	)
	_expect_true(
		not _progress_events.is_empty(),
		"successful background load should expose progress events"
	)

	loader.queue_free()
	flow.queue_free()
	_finish()


func _wait_until_idle(loader: Node, label: String) -> void:
	var frames: int = 0
	while bool(loader.call("is_loading")) and frames < MAX_WAIT_FRAMES:
		frames += 1
		await get_tree().process_frame

	if bool(loader.call("is_loading")):
		_fail(label + " background load did not finish within frame budget")


func _on_load_progress(_scene_id: String, value: float) -> void:
	_progress_events.append(value)


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
	push_error("ASYNC_SCENE_LOADER_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("ASYNC_SCENE_LOADER_SMOKE: PASS")
		get_tree().quit(0)
