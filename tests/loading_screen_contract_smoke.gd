extends Node

const GameFlowService = preload(
	"res://addons/game_foundation/flow/game_flow_service.gd"
)
const AsyncSceneLoader = preload(
	"res://addons/game_foundation/shell/async_scene_loader.gd"
)
const LoadingScreenContract = preload(
	"res://addons/game_foundation/shell/loading_screen_contract.gd"
)

const MAX_WAIT_FRAMES: int = 300

var _failed: bool = false
var _states: Array[Dictionary] = []
var _progress_events: Array[float] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var flow := GameFlowService.new()
	add_child(flow)
	await get_tree().process_frame

	_expect_ok(
		flow.configure_scene_contract(
			{
				"menu": "res://demo/demo.tscn",
				"gameplay": "res://tests/foundation_smoke.tscn",
			},
			"menu"
		),
		"scene contract should configure"
	)

	var loader := AsyncSceneLoader.new()
	add_child(loader)
	await get_tree().process_frame
	_expect_ok(
		loader.configure(Callable(flow, "resolve_scene_path")),
		"async loader should use GameFlow scene resolver"
	)

	var contract := LoadingScreenContract.new()
	add_child(contract)
	await get_tree().process_frame
	contract.state_changed.connect(_on_state_changed)
	contract.progress_changed.connect(_on_progress_changed)

	_expect_code(
		contract.request_scene("menu"),
		"loader_not_configured",
		"contract should reject requests before loader configuration"
	)
	_expect_ok(
		contract.configure(loader),
		"loading screen contract should bind to async loader"
	)
	_expect_equal(
		String(contract.status_snapshot().get("phase", "")),
		"idle",
		"fresh contract should expose idle state"
	)

	_expect_code(
		contract.request_scene("unknown"),
		"unknown_scene",
		"immediate loader rejection should be surfaced"
	)
	_expect_equal(
		String(contract.status_snapshot().get("phase", "")),
		"failed",
		"immediate loader rejection should become failed presentation state"
	)
	_expect_equal(
		String(contract.status_snapshot().get("last_code", "")),
		"unknown_scene",
		"failure state should preserve loader result code"
	)
	_expect_ok(contract.reset_state(), "failed state should reset while idle")

	var request: Dictionary = contract.request_scene("menu")
	_expect_code(
		request,
		"load_started",
		"declared scene should start through the loading contract"
	)
	_expect_equal(
		String(contract.status_snapshot().get("phase", "")),
		"loading",
		"load_started signal should expose loading state"
	)
	_expect_equal(
		String(contract.status_snapshot().get("scene_id", "")),
		"menu",
		"loading state should expose current scene id"
	)

	_expect_code(
		contract.request_scene("gameplay"),
		"loader_busy",
		"second request should preserve active loading state"
	)
	_expect_equal(
		String(contract.status_snapshot().get("phase", "")),
		"loading",
		"busy rejection must not replace the active loading state with failure"
	)

	await _wait_until_idle(loader, "menu")
	var final_state: Dictionary = contract.status_snapshot()
	_expect_equal(
		String(final_state.get("phase", "")),
		"loaded",
		"completed loader should expose loaded presentation state"
	)
	_expect_equal(
		String(final_state.get("scene_id", "")),
		"menu",
		"loaded state should retain completed scene id"
	)
	_expect_equal(
		String(final_state.get("path", "")),
		"res://demo/demo.tscn",
		"loaded state should retain resolved scene path"
	)
	_expect_close(
		float(final_state.get("progress", 0.0)),
		1.0,
		0.001,
		"loaded state should expose full progress"
	)
	_expect_equal(
		String(final_state.get("last_code", "")),
		"load_completed",
		"loaded state should expose loader completion code"
	)
	_expect_true(
		not _states.is_empty(),
		"visual consumers should be able to observe state_changed without a Foundation theme"
	)
	_expect_true(
		not _progress_events.is_empty(),
		"visual consumers should receive normalized progress events"
	)

	_expect_ok(contract.reset_state(), "loaded state should reset")
	_expect_equal(
		String(contract.status_snapshot().get("phase", "")),
		"idle",
		"reset should return to idle"
	)

	contract.queue_free()
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


func _on_state_changed(state: Dictionary) -> void:
	_states.append(state.duplicate(true))


func _on_progress_changed(
	_scene_id: String,
	value: float,
	_state: Dictionary
) -> void:
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
	push_error("LOADING_SCREEN_CONTRACT_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("LOADING_SCREEN_CONTRACT_SMOKE: PASS")
		get_tree().quit(0)
