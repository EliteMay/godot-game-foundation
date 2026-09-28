extends Node

const BootSequenceContract = preload(
	"res://addons/game_foundation/shell/boot_sequence_contract.gd"
)

var _failed: bool = false
var _stage_changes: Array[String] = []
var _finished_stages: Array[String] = []
var _completed_events: int = 0
var _failed_events: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var contract := BootSequenceContract.new()
	add_child(contract)
	await get_tree().process_frame

	contract.stage_changed.connect(_on_stage_changed)
	contract.stage_finished.connect(_on_stage_finished)
	contract.sequence_completed.connect(_on_sequence_completed)
	contract.sequence_failed.connect(_on_sequence_failed)

	_expect_code(
		contract.start(),
		"boot_sequence_not_configured",
		"sequence should reject start before configuration"
	)
	_expect_code(
		contract.configure([]),
		"boot_stages_empty",
		"empty boot sequence should be rejected"
	)
	_expect_code(
		contract.configure([
			{"id": "opening"},
			{"id": "opening"},
		]),
		"duplicate_boot_stage_id",
		"duplicate stage ids should be rejected"
	)
	_expect_code(
		contract.configure([
			{"id": "opening", "skippable": "yes"},
		]),
		"invalid_boot_stage_skippable",
		"skippable must be a boolean"
	)

	_expect_ok(
		contract.configure([
			{"id": "publisher", "skippable": false},
			{"id": "opening", "skippable": true},
			{"id": "handoff", "skippable": false},
		]),
		"valid boot sequence should configure"
	)
	var idle: Dictionary = contract.status_snapshot()
	_expect_equal(
		String(idle.get("phase", "")),
		"idle",
		"configured sequence should stay idle until started"
	)
	_expect_equal(
		int(idle.get("stage_count", 0)),
		3,
		"configured sequence should expose stage count"
	)

	_expect_code(
		contract.start(),
		"boot_sequence_started",
		"sequence should start at the first stage"
	)
	_expect_equal(
		String(contract.status_snapshot().get("current_stage_id", "")),
		"publisher",
		"first stage should become current"
	)
	_expect_code(
		contract.skip_current(),
		"boot_stage_not_skippable",
		"non-skippable stage should reject skip"
	)
	_expect_code(
		contract.configure([{"id": "replacement"}]),
		"boot_sequence_running",
		"running sequence should reject reconfiguration"
	)

	_expect_code(
		contract.complete_current(),
		"boot_stage_completed",
		"normal completion should advance to the next stage"
	)
	_expect_equal(
		String(contract.status_snapshot().get("current_stage_id", "")),
		"opening",
		"second stage should become current after completion"
	)
	_expect_true(
		bool(contract.status_snapshot().get("can_skip", false)),
		"skippable stage should expose can_skip"
	)

	_expect_code(
		contract.skip_current(),
		"boot_stage_skipped",
		"skippable stage should advance without being treated as failure"
	)
	_expect_equal(
		String(contract.status_snapshot().get("current_stage_id", "")),
		"handoff",
		"skip should advance to the next stage"
	)
	_expect_equal(
		int(contract.status_snapshot().get("completed_count", 0)),
		2,
		"completed count should include skipped stages"
	)

	var failed_result: Dictionary = contract.fail_current(
		"handoff_unavailable",
		"handoff target is not ready"
	)
	_expect_code(
		failed_result,
		"handoff_unavailable",
		"consumer-provided failure code should be preserved"
	)
	_expect_equal(
		String(contract.status_snapshot().get("phase", "")),
		"failed",
		"failed stage should place sequence in failed state"
	)
	_expect_equal(
		String(contract.status_snapshot().get("current_stage_id", "")),
		"handoff",
		"failed state should retain the stage that failed"
	)
	_expect_equal(
		_failed_events,
		1,
		"failure signal should fire once"
	)
	_expect_code(
		contract.start(),
		"boot_sequence_reset_required",
		"failed sequence should require explicit reset"
	)
	_expect_ok(
		contract.reset(),
		"failed sequence should reset"
	)

	_expect_ok(
		contract.start(),
		"reset sequence should start again"
	)
	_expect_ok(
		contract.complete_current(),
		"publisher stage should complete on second run"
	)
	_expect_ok(
		contract.skip_current(),
		"opening should remain skippable on second run"
	)
	var completed: Dictionary = contract.complete_current()
	_expect_code(
		completed,
		"boot_sequence_completed",
		"last stage completion should complete the sequence"
	)
	_expect_equal(
		String(contract.status_snapshot().get("phase", "")),
		"completed",
		"sequence should expose completed phase"
	)
	_expect_equal(
		int(contract.status_snapshot().get("completed_count", 0)),
		3,
		"completed sequence should count every stage"
	)
	_expect_equal(
		String(contract.status_snapshot().get("current_stage_id", "")),
		"",
		"completed sequence should not retain an active stage"
	)
	_expect_equal(
		_completed_events,
		1,
		"completion signal should fire once"
	)
	_expect_code(
		contract.complete_current(),
		"boot_sequence_not_running",
		"completed sequence should reject extra completion"
	)

	_expect_true(
		_stage_changes.has("publisher")
		and _stage_changes.has("opening")
		and _stage_changes.has("handoff"),
		"stage changes should expose each configured stage to presentation consumers"
	)
	_expect_true(
		_finished_stages.has("publisher")
		and _finished_stages.has("opening")
		and _finished_stages.has("handoff"),
		"stage finish events should expose progression without owning visuals"
	)

	contract.queue_free()
	_finish()


func _on_stage_changed(stage: Dictionary, _state: Dictionary) -> void:
	_stage_changes.append(String(stage.get("id", "")))


func _on_stage_finished(
	stage_id: String,
	_skipped: bool,
	_state: Dictionary
) -> void:
	_finished_stages.append(stage_id)


func _on_sequence_completed(_state: Dictionary) -> void:
	_completed_events += 1


func _on_sequence_failed(
	_result: Dictionary,
	_state: Dictionary
) -> void:
	_failed_events += 1


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


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


func _fail(message: String) -> void:
	_failed = true
	push_error("BOOT_SEQUENCE_CONTRACT_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("BOOT_SEQUENCE_CONTRACT_SMOKE: PASS")
		get_tree().quit(0)
