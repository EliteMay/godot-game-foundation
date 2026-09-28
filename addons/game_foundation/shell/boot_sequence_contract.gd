extends Node

signal state_changed(state: Dictionary)
signal stage_changed(stage: Dictionary, state: Dictionary)
signal stage_finished(stage_id: String, skipped: bool, state: Dictionary)
signal sequence_completed(state: Dictionary)
signal sequence_failed(result: Dictionary, state: Dictionary)

const PHASE_IDLE: String = "idle"
const PHASE_RUNNING: String = "running"
const PHASE_COMPLETED: String = "completed"
const PHASE_FAILED: String = "failed"

const MAX_STAGES: int = 32
const MAX_STAGE_ID_LENGTH: int = 64

var _stages: Array[Dictionary] = []
var _phase: String = PHASE_IDLE
var _current_index: int = -1
var _completed_count: int = 0
var _last_result: Dictionary = {}


func configure(stages: Array) -> Dictionary:
	if _phase == PHASE_RUNNING:
		return _error(
			"boot_sequence_running",
			"boot sequence cannot be reconfigured while running"
		)

	var normalized: Dictionary = _normalize_stages(stages)
	if not bool(normalized.get("ok", false)):
		return normalized

	_stages = (normalized.get("stages", []) as Array).duplicate(true)
	_phase = PHASE_IDLE
	_current_index = -1
	_completed_count = 0
	_last_result = {}
	_emit_state()
	return _success(
		"boot_sequence_configured",
		{"state": status_snapshot()}
	)


func start() -> Dictionary:
	if _phase == PHASE_RUNNING:
		return _error(
			"boot_sequence_running",
			"boot sequence is already running"
		)
	if _stages.is_empty():
		return _error(
			"boot_sequence_not_configured",
			"configure at least one boot stage before starting"
		)
	if _phase != PHASE_IDLE:
		return _error(
			"boot_sequence_reset_required",
			"reset the completed or failed sequence before starting again"
		)

	_phase = PHASE_RUNNING
	_current_index = 0
	_completed_count = 0
	_last_result = {}
	_emit_state()
	_emit_stage()
	return _success(
		"boot_sequence_started",
		{"state": status_snapshot()}
	)


func complete_current() -> Dictionary:
	return _advance_current(false)


func skip_current() -> Dictionary:
	if _phase != PHASE_RUNNING:
		return _error(
			"boot_sequence_not_running",
			"boot sequence must be running before a stage can be skipped"
		)

	var stage: Dictionary = current_stage()
	if not bool(stage.get("skippable", false)):
		return _error(
			"boot_stage_not_skippable",
			"current boot stage is not skippable",
			{"stage_id": String(stage.get("id", ""))}
		)

	return _advance_current(true)


func fail_current(code: String, message: String) -> Dictionary:
	if _phase != PHASE_RUNNING:
		return _error(
			"boot_sequence_not_running",
			"boot sequence must be running before a stage can fail"
		)

	var normalized_code: String = code.strip_edges()
	var normalized_message: String = message.strip_edges()
	if normalized_code.is_empty():
		return _error(
			"invalid_failure_code",
			"boot failure code must not be empty"
		)
	if normalized_message.is_empty():
		return _error(
			"invalid_failure_message",
			"boot failure message must not be empty"
		)

	var stage: Dictionary = current_stage()
	_phase = PHASE_FAILED
	_last_result = _error(
		normalized_code,
		normalized_message,
		{"stage_id": String(stage.get("id", ""))}
	)
	var state: Dictionary = status_snapshot()
	state_changed.emit(state.duplicate(true))
	sequence_failed.emit(
		_last_result.duplicate(true),
		state.duplicate(true)
	)
	return _last_result.duplicate(true)


func reset() -> Dictionary:
	if _phase == PHASE_RUNNING:
		return _error(
			"boot_sequence_running",
			"running boot sequence must finish or fail before reset"
		)

	_phase = PHASE_IDLE
	_current_index = -1
	_completed_count = 0
	_last_result = {}
	_emit_state()
	return _success(
		"boot_sequence_reset",
		{"state": status_snapshot()}
	)


func current_stage() -> Dictionary:
	if _current_index < 0 or _current_index >= _stages.size():
		return {}
	return _stages[_current_index].duplicate(true)


func stages_snapshot() -> Array[Dictionary]:
	return _stages.duplicate(true)


func status_snapshot() -> Dictionary:
	var stage: Dictionary = current_stage()
	return {
		"phase": _phase,
		"configured": not _stages.is_empty(),
		"stage_count": _stages.size(),
		"current_index": _current_index,
		"current_stage_id": String(stage.get("id", "")),
		"current_stage_skippable": bool(stage.get("skippable", false)),
		"can_skip": (
			_phase == PHASE_RUNNING
			and bool(stage.get("skippable", false))
		),
		"completed_count": _completed_count,
		"last_code": String(_last_result.get("code", "")),
		"last_message": String(_last_result.get("message", "")),
	}


func _advance_current(skipped: bool) -> Dictionary:
	if _phase != PHASE_RUNNING:
		return _error(
			"boot_sequence_not_running",
			"boot sequence must be running before a stage can complete"
		)

	var stage: Dictionary = current_stage()
	var stage_id: String = String(stage.get("id", ""))
	_completed_count += 1

	if _completed_count >= _stages.size():
		_phase = PHASE_COMPLETED
		_current_index = -1
		_last_result = {}
		var completed_state: Dictionary = status_snapshot()
		stage_finished.emit(
			stage_id,
			skipped,
			completed_state.duplicate(true)
		)
		state_changed.emit(completed_state.duplicate(true))
		sequence_completed.emit(completed_state.duplicate(true))
		return _success(
			"boot_sequence_completed",
			{
				"stage_id": stage_id,
				"skipped": skipped,
				"state": completed_state,
			}
		)

	_current_index += 1
	var state: Dictionary = status_snapshot()
	stage_finished.emit(stage_id, skipped, state.duplicate(true))
	state_changed.emit(state.duplicate(true))
	_emit_stage()
	return _success(
		"boot_stage_skipped" if skipped else "boot_stage_completed",
		{
			"stage_id": stage_id,
			"state": state,
		}
	)


func _normalize_stages(stages: Array) -> Dictionary:
	if stages.is_empty():
		return _error(
			"boot_stages_empty",
			"boot sequence requires at least one stage"
		)
	if stages.size() > MAX_STAGES:
		return _error(
			"too_many_boot_stages",
			"boot sequence exceeds the maximum stage count",
			{"max_stages": MAX_STAGES}
		)

	var normalized: Array[Dictionary] = []
	var seen_ids: Dictionary = {}

	for index in range(stages.size()):
		var stage_variant: Variant = stages[index]
		if not (stage_variant is Dictionary):
			return _error(
				"invalid_boot_stage",
				"each boot stage must be a Dictionary",
				{"index": index}
			)

		var stage: Dictionary = stage_variant as Dictionary
		var stage_id: String = String(stage.get("id", "")).strip_edges()
		if stage_id.is_empty() or stage_id.length() > MAX_STAGE_ID_LENGTH:
			return _error(
				"invalid_boot_stage_id",
				"boot stage id must be non-empty and bounded",
				{"index": index}
			)
		if seen_ids.has(stage_id):
			return _error(
				"duplicate_boot_stage_id",
				"boot stage ids must be unique",
				{"stage_id": stage_id}
			)

		var skippable_variant: Variant = stage.get("skippable", false)
		if typeof(skippable_variant) != TYPE_BOOL:
			return _error(
				"invalid_boot_stage_skippable",
				"boot stage skippable must be a boolean",
				{"stage_id": stage_id}
			)

		seen_ids[stage_id] = true
		normalized.append({
			"id": stage_id,
			"skippable": bool(skippable_variant),
		})

	return _success(
		"boot_stages_normalized",
		{"stages": normalized}
	)


func _emit_state() -> void:
	state_changed.emit(status_snapshot())


func _emit_stage() -> void:
	var stage: Dictionary = current_stage()
	if stage.is_empty():
		return
	stage_changed.emit(
		stage.duplicate(true),
		status_snapshot()
	)


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
