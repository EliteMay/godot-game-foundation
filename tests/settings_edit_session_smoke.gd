extends Node

const SettingsEditSession = preload(
	"res://addons/game_foundation/settings/settings_edit_session.gd"
)
const SettingsSystem = preload(
	"res://addons/game_foundation/settings/settings_system.gd"
)

var _failed: bool = false
var _runtime_settings: Dictionary = {}
var _persisted_settings: Dictionary = {}
var _fail_next_preview: bool = false
var _fail_next_persist: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var gameplay_defaults: Dictionary = {
		"look_sensitivity": 1.0,
	}
	var initial: Dictionary = SettingsSystem.default_settings(gameplay_defaults)
	(initial.get("audio", {}) as Dictionary)["master"] = 0.8
	(initial.get("gameplay", {}) as Dictionary)["look_sensitivity"] = 1.25
	_runtime_settings = initial.duplicate(true)
	_persisted_settings = initial.duplicate(true)

	var session := SettingsEditSession.new()
	_expect_ok(
		session.configure(
			initial,
			gameplay_defaults,
			Callable(self, "_preview_apply"),
			Callable(self, "_persist")
		),
		"session configure"
	)
	_expect_true(session.is_active(), "configured session should be active")
	_expect_true(not session.has_changes(), "new session should start clean")

	var changed: Dictionary = initial.duplicate(true)
	(changed.get("audio", {}) as Dictionary)["master"] = 0.4
	(changed.get("gameplay", {}) as Dictionary)["look_sensitivity"] = 1.75
	_expect_ok(session.set_draft(changed), "draft preview")
	_expect_equal(
		float((_runtime_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.4,
		"preview should apply audio value to runtime"
	)
	_expect_true(session.has_changes(), "previewed draft should be dirty")
	_expect_equal(
		float((_persisted_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"preview must not persist settings"
	)

	_expect_ok(session.cancel(), "cancel")
	_expect_true(not session.is_active(), "cancel should close the session")
	_expect_equal(
		float((_runtime_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"cancel should restore runtime to the opening baseline"
	)
	_expect_equal(
		float((_persisted_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"cancel must not change persisted settings"
	)

	var reset_session := SettingsEditSession.new()
	_expect_ok(
		reset_session.configure(
			initial,
			gameplay_defaults,
			Callable(self, "_preview_apply"),
			Callable(self, "_persist")
		),
		"reset session configure"
	)
	_expect_ok(reset_session.reset_to_defaults(), "reset draft")
	_expect_equal(
		float((_runtime_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		1.0,
		"reset should preview common defaults"
	)
	_expect_equal(
		float((_runtime_settings.get("gameplay", {}) as Dictionary).get("look_sensitivity", -1.0)),
		1.0,
		"reset should preserve game-provided defaults"
	)
	_expect_equal(
		float((_persisted_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"reset should remain temporary until Apply"
	)
	_expect_ok(reset_session.cancel(), "cancel after reset")
	_expect_equal(
		float((_runtime_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"cancel after reset should restore the opening baseline"
	)

	var apply_session := SettingsEditSession.new()
	_expect_ok(
		apply_session.configure(
			initial,
			gameplay_defaults,
			Callable(self, "_preview_apply"),
			Callable(self, "_persist")
		),
		"apply session configure"
	)
	var applied_candidate: Dictionary = initial.duplicate(true)
	(applied_candidate.get("audio", {}) as Dictionary)["master"] = 0.6
	_expect_ok(apply_session.set_draft(applied_candidate), "apply draft preview")
	_expect_ok(apply_session.apply(), "apply")
	_expect_true(apply_session.is_active(), "Apply should keep the edit session available")
	_expect_true(not apply_session.has_changes(), "Apply should advance the session baseline")
	_expect_equal(
		float((_persisted_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.6,
		"Apply should persist the draft"
	)

	var after_apply: Dictionary = apply_session.draft_settings()
	(after_apply.get("audio", {}) as Dictionary)["master"] = 0.3
	_expect_ok(apply_session.set_draft(after_apply), "post-apply draft preview")
	_expect_ok(apply_session.cancel(), "post-apply cancel")
	_expect_equal(
		float((_runtime_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.6,
		"Cancel after Apply should restore the latest committed baseline"
	)

	var failure_session := SettingsEditSession.new()
	_runtime_settings = initial.duplicate(true)
	_persisted_settings = initial.duplicate(true)
	_expect_ok(
		failure_session.configure(
			initial,
			gameplay_defaults,
			Callable(self, "_preview_apply"),
			Callable(self, "_persist")
		),
		"failure session configure"
	)
	var failing_candidate: Dictionary = initial.duplicate(true)
	(failing_candidate.get("audio", {}) as Dictionary)["master"] = 0.2
	_fail_next_preview = true
	var preview_failure: Dictionary = failure_session.set_draft(failing_candidate)
	_expect_code(
		preview_failure,
		"preview_apply_failed",
		"failed preview should report preview_apply_failed"
	)
	_expect_equal(
		float((_runtime_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"failed preview should roll runtime back to the previous preview"
	)
	_expect_equal(
		float((failure_session.draft_settings().get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"failed preview should not replace the draft"
	)

	_expect_ok(failure_session.set_draft(failing_candidate), "retry preview")
	_fail_next_persist = true
	var persist_failure: Dictionary = failure_session.apply()
	_expect_code(
		persist_failure,
		"apply_persist_failed",
		"failed persistence should not advance the baseline"
	)
	_expect_true(failure_session.is_active(), "persistence failure should keep session recoverable")
	_expect_ok(failure_session.cancel(), "cancel after persistence failure")
	_expect_equal(
		float((_runtime_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"cancel after persistence failure should restore the original baseline"
	)
	_expect_equal(
		float((_persisted_settings.get("audio", {}) as Dictionary).get("master", -1.0)),
		0.8,
		"failed persistence should leave committed settings unchanged"
	)

	_finish()


func _preview_apply(settings: Dictionary) -> Dictionary:
	_runtime_settings = settings.duplicate(true)
	if _fail_next_preview:
		_fail_next_preview = false
		return {
			"ok": false,
			"code": "preview_fixture_failure",
		}
	return {
		"ok": true,
		"code": "preview_fixture_applied",
	}


func _persist(settings: Dictionary) -> Dictionary:
	if _fail_next_persist:
		_fail_next_persist = false
		return {
			"ok": false,
			"code": "persist_fixture_failure",
		}
	_persisted_settings = settings.duplicate(true)
	return {
		"ok": true,
		"code": "persist_fixture_saved",
		"settings": _persisted_settings.duplicate(true),
	}


func _expect_ok(result: Dictionary, label: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(label + " failed / " + str(result))


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


func _fail(message: String) -> void:
	_failed = true
	push_error("SETTINGS_EDIT_SESSION_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("SETTINGS_EDIT_SESSION_SMOKE: PASS")
		get_tree().quit(0)
