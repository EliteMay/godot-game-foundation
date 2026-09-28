extends Node

const TranslationContract = preload(
	"res://addons/game_foundation/localization/translation_contract.gd"
)
const MainMenuScene = preload(
	"res://addons/game_foundation/shell/main_menu_shell.tscn"
)
const PauseMenuScene = preload(
	"res://addons/game_foundation/shell/pause_menu_shell.tscn"
)

class FakeFlowService:
	extends Node

	func request_quit(_exit_code: int = 0) -> Dictionary:
		return {"ok": true, "code": "quit_requested"}

	func set_paused(value: bool) -> Dictionary:
		get_tree().paused = value
		return {"ok": true, "code": "pause_changed", "paused": value}

	func is_paused() -> bool:
		return get_tree() != null and get_tree().paused

	func go_to_main_menu() -> Dictionary:
		get_tree().paused = false
		return {"ok": true, "code": "scene_change_requested"}

	func main_menu_id() -> String:
		return "menu"


var _failed: bool = false
var _original_locale: String = ""
var _ja_translation: Translation = null
var _en_translation: Translation = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_original_locale = TranslationServer.get_locale()
	_install_test_translations()
	TranslationServer.set_locale("ja")

	var fallback_result: Dictionary = TranslationContract.resolve_labels(
		TranslationContract.SHELL_MAIN_MENU
	)
	_expect_ok(fallback_result, "default translation contract should resolve")
	_expect_equal(
		String(
			(fallback_result.get("labels", {}) as Dictionary)
			.get("continue", "")
		),
		"Continue",
		"missing Foundation translation should use the stable fallback"
	)

	var custom_result: Dictionary = TranslationContract.resolve_labels(
		TranslationContract.SHELL_MAIN_MENU,
		{
			"new_game": {
				"key": "GAME_MENU_START",
				"fallback": "Start",
				"context": "menu",
			},
		}
	)
	_expect_ok(custom_result, "game translation override should resolve")
	_expect_equal(
		String(
			(custom_result.get("labels", {}) as Dictionary)
			.get("new_game", "")
		),
		"開始",
		"custom game translation should come from TranslationServer"
	)
	_expect_equal(
		String(
			(custom_result.get("sources", {}) as Dictionary)
			.get("new_game", "")
		),
		"translation",
		"resolved source should report TranslationServer usage"
	)

	_expect_code(
		TranslationContract.normalize_entries(
			TranslationContract.SHELL_MAIN_MENU,
			{"unknown": "BAD_KEY"}
		),
		"unknown_translation_action",
		"unknown shell actions should be rejected"
	)
	_expect_code(
		TranslationContract.normalize_entries(
			TranslationContract.SHELL_MAIN_MENU,
			{"new_game": ""}
		),
		"invalid_translation_key",
		"empty translation keys should be rejected"
	)

	var flow := FakeFlowService.new()
	add_child(flow)

	var main_shell := MainMenuScene.instantiate()
	add_child(main_shell)
	await get_tree().process_frame
	_expect_ok(
		main_shell.configure({
			"flow_service": flow,
			"new_game_action": Callable(self, "_action_ok"),
			"translation_entries": {
				"new_game": {
					"key": "GAME_MENU_START",
					"fallback": "Start",
					"context": "menu",
				},
				"quit": {
					"key": "GAME_MENU_QUIT",
					"fallback": "Exit",
					"context": "menu",
				},
			},
		}),
		"main menu should accept translation entries"
	)
	_expect_equal(
		main_shell.action_button("new_game").text,
		"開始",
		"main menu should render the active locale translation"
	)
	_expect_equal(
		main_shell.action_button("quit").text,
		"終了",
		"main menu should translate multiple action labels"
	)

	var pause_shell := PauseMenuScene.instantiate()
	add_child(pause_shell)
	await get_tree().process_frame
	_expect_ok(
		pause_shell.configure({
			"flow_service": flow,
			"translation_entries": {
				"resume": {
					"key": "GAME_PAUSE_RESUME",
					"fallback": "Resume",
					"context": "pause",
				},
			},
			"labels": {
				"quit": "固定終了",
			},
		}),
		"pause menu should accept translation entries plus legacy labels"
	)
	_expect_equal(
		pause_shell.action_button("resume").text,
		"再開",
		"pause menu should render translated labels"
	)
	_expect_equal(
		pause_shell.action_button("quit").text,
		"固定終了",
		"legacy labels should remain the final explicit override"
	)

	TranslationServer.set_locale("en")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_equal(
		main_shell.action_button("new_game").text,
		"Start Game",
		"locale changes should refresh main menu translations"
	)
	_expect_equal(
		main_shell.action_button("quit").text,
		"Exit Game",
		"locale changes should refresh all translated main menu actions"
	)
	_expect_equal(
		pause_shell.action_button("resume").text,
		"Resume Game",
		"locale changes should refresh pause menu translations"
	)
	_expect_equal(
		pause_shell.action_button("quit").text,
		"固定終了",
		"explicit legacy label overrides should survive locale changes"
	)

	_cleanup_test_translations()
	TranslationServer.set_locale(_original_locale)
	main_shell.queue_free()
	pause_shell.queue_free()
	flow.queue_free()
	get_tree().paused = false
	_finish()


func _install_test_translations() -> void:
	_ja_translation = Translation.new()
	_ja_translation.locale = "ja"
	_ja_translation.add_message(
		&"GAME_MENU_START",
		&"開始",
		&"menu"
	)
	_ja_translation.add_message(
		&"GAME_MENU_QUIT",
		&"終了",
		&"menu"
	)
	_ja_translation.add_message(
		&"GAME_PAUSE_RESUME",
		&"再開",
		&"pause"
	)
	TranslationServer.add_translation(_ja_translation)

	_en_translation = Translation.new()
	_en_translation.locale = "en"
	_en_translation.add_message(
		&"GAME_MENU_START",
		&"Start Game",
		&"menu"
	)
	_en_translation.add_message(
		&"GAME_MENU_QUIT",
		&"Exit Game",
		&"menu"
	)
	_en_translation.add_message(
		&"GAME_PAUSE_RESUME",
		&"Resume Game",
		&"pause"
	)
	TranslationServer.add_translation(_en_translation)


func _cleanup_test_translations() -> void:
	if _ja_translation != null:
		TranslationServer.remove_translation(_ja_translation)
	if _en_translation != null:
		TranslationServer.remove_translation(_en_translation)
	_ja_translation = null
	_en_translation = null


func _action_ok() -> Dictionary:
	return {"ok": true, "code": "action_ok"}


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
	push_error("TRANSLATION_CONTRACT_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("TRANSLATION_CONTRACT_SMOKE: PASS")
		get_tree().quit(0)
