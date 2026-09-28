extends RefCounted

const KIND_INITIALIZATION: String = "initialization"


static func inactive() -> Dictionary:
	return {
		"active": false,
		"kind": "",
		"stage": "",
		"code": "",
		"message": "",
		"retry_supported": false,
		"save_writes_blocked": false,
		"diagnostics_available": false,
	}


static func initialization_failure(
	stage: String,
	result: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	var normalized_stage: String = stage.strip_edges()
	if normalized_stage.is_empty():
		normalized_stage = "unknown"

	var code: String = String(
		result.get("code", "initialization_failed")
	).strip_edges()
	if code.is_empty():
		code = "initialization_failed"

	var message: String = String(
		result.get(
			"message",
			"Foundation runtime initialization failed"
		)
	).strip_edges()
	if message.is_empty():
		message = "Foundation runtime initialization failed"

	return {
		"active": true,
		"kind": KIND_INITIALIZATION,
		"stage": normalized_stage,
		"code": code,
		"message": message,
		"retry_supported": _retry_supported_for_stage(
			normalized_stage
		),
		"save_writes_blocked": bool(
			context.get("save_writes_blocked", false)
		),
		"diagnostics_available": bool(
			context.get("diagnostics_available", false)
		),
	}


static func _retry_supported_for_stage(stage: String) -> bool:
	return stage in [
		"configure",
		"scene_tree",
	]
