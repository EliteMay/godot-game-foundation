extends Node

const SettingsEditSession = preload(
	"res://addons/game_foundation/settings/settings_edit_session.gd"
)
const SettingsOptionControl = preload(
	"res://addons/game_foundation/settings/settings_option_control.gd"
)
const SettingsSystem = preload(
	"res://addons/game_foundation/settings/settings_system.gd"
)

var _failed: bool = false
var _runtime_settings: Dictionary = {}
var _persisted_settings: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var gameplay_defaults: Dictionary = {
		"difficulty": "normal",
		"camera_sensitivity": 1.0,
	}
	var initial: Dictionary = SettingsSystem.default_settings(gameplay_defaults)
	(initial.get("audio", {}) as Dictionary)["master"] = 0.8
	(initial.get("display", {}) as Dictionary)["window_mode"] = "windowed"
	(initial.get("display", {}) as Dictionary)["resolution"] = [1280, 720]
	(initial.get("display", {}) as Dictionary)["vsync"] = true
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
		"settings session should configure"
	)

	var container := VBoxContainer.new()
	add_child(container)

	var toggle := SettingsOptionControl.new()
	container.add_child(toggle)
	_expect_ok(
		toggle.configure(
			session,
			{"type": "toggle", "path": "display.vsync", "label": "VSync"}
		),
		"toggle control should configure"
	)
	_expect_true(toggle.input_control() is CheckButton, "toggle should create CheckButton")
	_expect_equal(toggle.label_control().text, "VSync", "toggle label should be game-defined")
	_expect_equal(toggle.value(), true, "toggle should reflect draft value")

	var slider := SettingsOptionControl.new()
	container.add_child(slider)
	_expect_ok(
		slider.configure(
			session,
			{
				"type": "slider",
				"path": ["audio", "master"],
				"label": "Master",
				"min": 0.0,
				"max": 1.0,
				"step": 0.1,
				"decimals": 0,
				"display_multiplier": 100.0,
				"suffix": "%",
			}
		),
		"slider control should configure"
	)
	_expect_true(slider.input_control() is HSlider, "slider should create HSlider")
	_expect_equal(slider.value_label_control().text, "80%", "slider formatting should be configurable")

	var list := SettingsOptionControl.new()
	container.add_child(list)
	_expect_ok(
		list.configure(
			session,
			{
				"type": "list",
				"path": "display.window_mode",
				"label": "Window Mode",
				"options": [
					{"label": "Windowed", "value": "windowed"},
					{"label": "Fullscreen", "value": "fullscreen"},
					{"label": "Borderless", "value": "borderless"},
				],
			}
		),
		"list control should configure"
	)
	_expect_true(list.input_control() is OptionButton, "list should create OptionButton")
	_expect_equal(int(list.state_snapshot().get("choice_count", 0)), 3, "list choice count")

	var resolution := SettingsOptionControl.new()
	container.add_child(resolution)
	_expect_ok(
		resolution.configure(
			session,
			{
				"type": "resolution",
				"path": "display.resolution",
				"label": "Resolution",
				"options": [
					[1280, 720],
					{"label": "Full HD", "value": [1920, 1080]},
				],
			}
		),
		"resolution control should configure"
	)
	_expect_true(resolution.input_control() is OptionButton, "resolution should create OptionButton")

	_expect_ok(toggle.set_value(false), "toggle should update session draft")
	_expect_equal(
		bool((session.draft_settings().get("display", {}) as Dictionary).get("vsync", true)),
		false,
		"toggle should write nested path"
	)
	_expect_equal(
		bool((_runtime_settings.get("display", {}) as Dictionary).get("vsync", true)),
		false,
		"toggle should preview runtime"
	)

	_expect_ok(slider.set_value(0.5), "slider should update session draft")
	_expect_equal(
		float((session.draft_settings().get("audio", {}) as Dictionary).get("master", -1.0)),
		0.5,
		"slider should update audio master"
	)
	_expect_equal(slider.value_label_control().text, "50%", "slider label should track draft")

	_expect_ok(list.set_value("fullscreen"), "list should update session draft")
	_expect_equal(
		String((session.draft_settings().get("display", {}) as Dictionary).get("window_mode", "")),
		"fullscreen",
		"list should update selected value"
	)

	_expect_ok(resolution.set_value([1920, 1080]), "resolution should update draft")
	_expect_equal(
		(session.draft_settings().get("display", {}) as Dictionary).get("resolution", []),
		[1920, 1080],
		"resolution should update width/height pair"
	)

	_expect_code(list.set_value("exclusive"), "value_not_in_options", "list should reject unknown value")
	_expect_code(slider.set_value(2.0), "slider_value_out_of_range", "slider should reject out of range")

	_expect_ok(session.reset_to_defaults(), "session reset should succeed")
	await get_tree().process_frame
	_expect_equal(toggle.value(), true, "toggle should follow session reset")
	_expect_equal(slider.value(), 1.0, "slider should follow session reset")
	_expect_equal(list.value(), "windowed", "list should follow session reset")
	_expect_equal(resolution.value(), [1280, 720], "resolution should follow session reset")

	_expect_ok(session.cancel(), "session cancel should succeed")
	await get_tree().process_frame
	_expect_true((toggle.input_control() as CheckButton).disabled, "canceled session should disable control")
	_expect_equal(
		bool((_runtime_settings.get("display", {}) as Dictionary).get("vsync", false)),
		true,
		"cancel should restore runtime baseline"
	)
	_expect_equal(
		bool((_persisted_settings.get("display", {}) as Dictionary).get("vsync", false)),
		true,
		"controls must not persist before Apply"
	)

	container.queue_free()
	_finish()


func _preview_apply(settings: Dictionary) -> Dictionary:
	_runtime_settings = settings.duplicate(true)
	return {"ok": true, "code": "preview_applied"}


func _persist(settings: Dictionary) -> Dictionary:
	_persisted_settings = settings.duplicate(true)
	return {"ok": true, "code": "persisted", "settings": _persisted_settings.duplicate(true)}


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


func _expect_code(result: Dictionary, expected: String, message: String) -> void:
	if String(result.get("code", "")) != expected:
		_fail(message + " / expected=" + expected + " actual=" + String(result.get("code", "")))


func _expect_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail(message + " / expected=" + str(expected) + " actual=" + str(actual))


func _fail(message: String) -> void:
	_failed = true
	push_error("SETTINGS_OPTION_CONTROL_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("SETTINGS_OPTION_CONTROL_SMOKE: PASS")
		get_tree().quit(0)
