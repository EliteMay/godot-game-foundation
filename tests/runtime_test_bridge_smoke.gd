extends Node

const RuntimeTestBridge = preload("res://addons/game_foundation/testing/runtime_test_bridge.gd")

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path: String = ProjectSettings.globalize_path(
		"user://runtime-test-bridge-smoke/state.json"
	)
	var bridge := RuntimeTestBridge.new()
	var configured: Dictionary = bridge.configure(
		output_path,
		"smoke-session",
		Callable(self, "_state_provider"),
		Callable(self, "_diagnostics_provider")
	)
	if not bool(configured.get("ok", false)):
		_fail("bridge configuration failed")

	add_child(bridge)
	await get_tree().process_frame

	var capture: Dictionary = bridge.capture_now()
	if not bool(capture.get("ok", false)):
		_fail("bridge capture failed: " + String(capture.get("code", "")))

	var file := FileAccess.open(output_path, FileAccess.READ)
	if file == null:
		_fail("bridge state file was not created")
		_finish()
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_fail("bridge state file is not valid JSON")
		_finish()
		return

	var payload: Dictionary = parsed as Dictionary
	if int(payload.get("schemaVersion", 0)) != 2:
		_fail("schemaVersion mismatch")
	if String(payload.get("sessionId", "")) != "smoke-session":
		_fail("sessionId mismatch")
	if int(payload.get("sequence", 0)) < 1:
		_fail("sequence should advance")

	var state_variant: Variant = payload.get("state", {})
	if not (state_variant is Dictionary):
		_fail("state payload is missing")
	else:
		var state: Dictionary = state_variant as Dictionary
		if String(state.get("mode", "")) != "smoke":
			_fail("provider state was not preserved")

	var diagnostics_variant: Variant = payload.get(
		"foundationDiagnostics",
		{}
	)
	if not (diagnostics_variant is Dictionary):
		_fail("foundation diagnostics payload is missing")
	else:
		var diagnostics: Dictionary = (
			diagnostics_variant as Dictionary
		)
		if String(diagnostics.get("source", "")) != (
			"godot-game-foundation"
		):
			_fail("foundation diagnostics source mismatch")
		var handoff: Dictionary = (
			diagnostics.get("handoff", {}) as Dictionary
		)
		if not bool(handoff.get("sanitized", false)):
			_fail("foundation diagnostics must be sanitized")
		if not bool(handoff.get("remote_eligible", false)):
			_fail("foundation diagnostics must be remote eligible")

	var invalid := RuntimeTestBridge.new()
	var invalid_config: Dictionary = invalid.configure(
		output_path + ".invalid",
		"invalid-session",
		Callable(self, "_invalid_state_provider")
	)
	if not bool(invalid_config.get("ok", false)):
		_fail("invalid-state bridge configuration should still succeed")
	else:
		var invalid_result: Dictionary = invalid.capture_now()
		if String(invalid_result.get("code", "")) != "provider_state_invalid":
			_fail("non-Dictionary provider state must be rejected")

	bridge.queue_free()
	invalid.queue_free()
	_finish()


func _state_provider() -> Dictionary:
	return {
		"mode": "smoke",
		"player": {
			"position": [1.0, 2.0, 3.0],
			"yaw": 0.25,
		},
	}


func _diagnostics_provider() -> Dictionary:
	return {
		"ok": true,
		"code": "diagnostics_export_built",
		"payload": {
			"schemaVersion": 1,
			"source": "godot-game-foundation",
			"handoff": {
				"sanitized": true,
				"remote_eligible": true,
			},
		},
	}


func _invalid_state_provider() -> Vector3:
	return Vector3.ONE


func _fail(message: String) -> void:
	_failed = true
	push_error("RUNTIME_TEST_BRIDGE_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("RUNTIME_TEST_BRIDGE_SMOKE: PASS")
		get_tree().quit(0)
