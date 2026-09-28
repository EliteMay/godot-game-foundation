extends Node

const AudioBusContract = preload(
	"res://addons/game_foundation/audio/audio_bus_contract.gd"
)
const GlobalMusicService = preload(
	"res://addons/game_foundation/audio/global_music_service.gd"
)
const OneShotAudioService = preload(
	"res://addons/game_foundation/audio/one_shot_audio_service.gd"
)
const FoundationRuntime = preload(
	"res://addons/game_foundation/runtime/foundation_runtime.gd"
)

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var legacy_map: Dictionary = {
		"master": "Main Mix",
		"bgm": "Music",
		"sfx": "Effects",
	}
	var normalized_result: Dictionary = AudioBusContract.normalize(legacy_map)
	_expect_ok(normalized_result, "legacy settings map should normalize")
	var normalized: Dictionary = normalized_result.get("bus_map", {})
	_expect_equal(
		String(normalized.get("master", "")),
		"Main Mix",
		"master mapping should be preserved"
	)
	_expect_equal(
		String(normalized.get("bgm", "")),
		"Music",
		"bgm mapping should be preserved"
	)
	_expect_equal(
		String(normalized.get("sfx", "")),
		"Effects",
		"sfx mapping should be preserved"
	)
	_expect_equal(
		String(normalized.get("ui", "")),
		"Effects",
		"legacy map should default ui to sfx"
	)
	_expect_equal(
		String(normalized.get("voice", "")),
		"Effects",
		"legacy map should default voice to sfx"
	)

	var extended_result: Dictionary = AudioBusContract.normalize(
		{
			"master": "Main Mix",
			"bgm": "Music",
			"sfx": "Effects",
			"ui": "Interface",
			"voice": "Dialogue",
			"ambience": "Ambience",
		}
	)
	_expect_ok(extended_result, "extended audio bus map should normalize")
	var extended: Dictionary = extended_result.get("bus_map", {})
	_expect_equal(
		String(extended.get("ui", "")),
		"Interface",
		"explicit ui bus should be preserved"
	)
	_expect_equal(
		String(extended.get("voice", "")),
		"Dialogue",
		"explicit voice bus should be preserved"
	)
	_expect_equal(
		String(extended.get("ambience", "")),
		"Ambience",
		"game-specific extra bus keys should be preserved"
	)

	var settings_result: Dictionary = AudioBusContract.settings_bus_map(extended)
	_expect_ok(settings_result, "settings bus map should resolve")
	var settings_map: Dictionary = settings_result.get("bus_map", {})
	_expect_equal(settings_map.size(), 3, "settings view should expose only volume setting keys")
	_expect_equal(
		String(settings_map.get("bgm", "")),
		"Music",
		"settings bgm should use shared contract"
	)

	var one_shot_result: Dictionary = AudioBusContract.one_shot_bus_map(extended)
	_expect_ok(one_shot_result, "one-shot bus map should resolve")
	var one_shot_map: Dictionary = one_shot_result.get("bus_map", {})
	_expect_equal(
		String(one_shot_map.get("sfx", "")),
		"Effects",
		"one-shot sfx should use shared contract"
	)
	_expect_equal(
		String(one_shot_map.get("ui", "")),
		"Interface",
		"one-shot ui should use shared contract"
	)
	_expect_equal(
		String(one_shot_map.get("voice", "")),
		"Dialogue",
		"one-shot voice should use shared contract"
	)

	_expect_code(
		AudioBusContract.normalize({"sfx": ""}),
		"invalid_audio_bus_name",
		"empty bus names should be rejected"
	)
	_expect_code(
		AudioBusContract.normalize({1: "Effects"}),
		"invalid_audio_bus_key",
		"non-string logical bus keys should be rejected"
	)
	_expect_code(
		AudioBusContract.resolve_bus(extended, "missing"),
		"unknown_audio_bus_key",
		"undeclared logical bus should be explicit"
	)

	var server_result: Dictionary = AudioBusContract.inspect_audio_server(extended)
	_expect_ok(server_result, "AudioServer inspection should be safe")
	var known_count: int = (
		(server_result.get("existing_buses", []) as Array).size()
		+ (server_result.get("missing_buses", []) as Array).size()
	)
	_expect_true(known_count >= 1, "AudioServer inspection should classify configured buses")

	var runtime := FoundationRuntime.new()
	add_child(runtime)
	var runtime_configured: Dictionary = runtime.configure(
		{
			"settings": {
				"enabled": false,
				"audio_bus_map": legacy_map,
			},
			"input": {"enabled": false},
			"flow": {"enabled": false},
			"diagnostics": {"enabled": false},
			"runtime_test": {"enabled": false},
		}
	)
	_expect_ok(runtime_configured, "FoundationRuntime should accept legacy audio_bus_map")
	var public_settings: Dictionary = (
		(runtime.public_config().get("settings", {}) as Dictionary)
	)
	var runtime_bus_map: Dictionary = (
		public_settings.get("audio_bus_map", {}) as Dictionary
	)
	_expect_equal(
		String(runtime_bus_map.get("ui", "")),
		"Effects",
		"FoundationRuntime should publish normalized ui fallback"
	)
	_expect_equal(
		String(runtime_bus_map.get("voice", "")),
		"Effects",
		"FoundationRuntime should publish normalized voice fallback"
	)
	runtime.queue_free()

	var music := GlobalMusicService.new()
	add_child(music)
	var music_configured: Dictionary = music.configure(
		{
			"persist_across_scenes": false,
			"audio_bus_map": extended,
		}
	)
	_expect_ok(music_configured, "Global Music should accept shared bus contract")
	_expect_equal(
		String(music.status_snapshot().get("bus_name", "")),
		"Music",
		"Global Music should resolve bgm from shared contract"
	)
	_expect_true(
		bool(music.status_snapshot().get("using_audio_bus_contract", false)),
		"Global Music should report shared contract mode"
	)
	var ambiguous_music := GlobalMusicService.new()
	add_child(ambiguous_music)
	_expect_code(
		ambiguous_music.configure(
			{
				"persist_across_scenes": false,
				"audio_bus_map": extended,
				"bus_name": "Other",
			}
		),
		"ambiguous_bus_configuration",
		"Global Music should reject two bus sources"
	)
	ambiguous_music.queue_free()
	music.queue_free()

	var one_shots := OneShotAudioService.new()
	add_child(one_shots)
	var one_shot_configured: Dictionary = one_shots.configure(
		{
			"persist_across_scenes": false,
			"audio_bus_map": extended,
		}
	)
	_expect_ok(one_shot_configured, "One-shot service should accept shared bus contract")
	var service_bus_names: Dictionary = (
		one_shots.status_snapshot().get("bus_names", {}) as Dictionary
	)
	_expect_equal(
		String(service_bus_names.get("sfx", "")),
		"Effects",
		"one-shot SFX should use shared contract"
	)
	_expect_equal(
		String(service_bus_names.get("ui", "")),
		"Interface",
		"one-shot UI should use shared contract"
	)
	_expect_equal(
		String(service_bus_names.get("voice", "")),
		"Dialogue",
		"one-shot Voice should use shared contract"
	)
	_expect_true(
		bool(one_shots.status_snapshot().get("using_audio_bus_contract", false)),
		"One-shot service should report shared contract mode"
	)

	var ambiguous_one_shot := OneShotAudioService.new()
	add_child(ambiguous_one_shot)
	_expect_code(
		ambiguous_one_shot.configure(
			{
				"persist_across_scenes": false,
				"audio_bus_map": extended,
				"bus_names": {"sfx": "Other"},
			}
		),
		"ambiguous_bus_configuration",
		"One-shot service should reject two default bus sources"
	)
	ambiguous_one_shot.queue_free()
	one_shots.queue_free()

	await get_tree().process_frame
	_finish()


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


func _fail(message: String) -> void:
	_failed = true
	push_error("AUDIO_BUS_CONTRACT_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("AUDIO_BUS_CONTRACT_SMOKE: PASS")
		get_tree().quit(0)
