extends Node

const SettingsRuntime = preload(
	"res://addons/game_foundation/settings/settings_runtime.gd"
)
const GlobalMusicService = preload(
	"res://addons/game_foundation/audio/global_music_service.gd"
)
const OneShotAudioService = preload(
	"res://addons/game_foundation/audio/one_shot_audio_service.gd"
)

const TEST_BUSES: PackedStringArray = [
	"Foundation Test Master",
	"Foundation Test BGM",
	"Foundation Test SFX",
	"Foundation Test UI",
	"Foundation Test Voice",
]

var _failed: bool = false
var _created_bus_names: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var setup_result: Dictionary = _create_test_buses()
	_expect_ok(setup_result, "temporary audio buses should be created")
	if not bool(setup_result.get("ok", false)):
		_finish()
		return

	var audio_bus_map: Dictionary = {
		"master": TEST_BUSES[0],
		"bgm": TEST_BUSES[1],
		"sfx": TEST_BUSES[2],
		"ui": TEST_BUSES[3],
		"voice": TEST_BUSES[4],
	}

	var settings: Dictionary = {
		"audio": {
			"master": 0.8,
			"bgm": 0.6,
			"sfx": 0.4,
		},
	}
	var audio_applied: Dictionary = SettingsRuntime.apply_audio(
		settings,
		audio_bus_map
	)
	_expect_ok(audio_applied, "Settings audio should apply through the shared bus map")
	_expect_equal(
		(audio_applied.get("missing_buses", []) as Array).size(),
		0,
		"all temporary buses should exist"
	)
	_expect_array_contains_all(
		audio_applied.get("applied", []) as Array,
		[TEST_BUSES[0], TEST_BUSES[1], TEST_BUSES[2]],
		"Settings should apply Master / BGM / SFX buses"
	)
	_expect_bus_volume(TEST_BUSES[0], 0.8, "Master volume should match settings")
	_expect_bus_volume(TEST_BUSES[1], 0.6, "BGM volume should match settings")
	_expect_bus_volume(TEST_BUSES[2], 0.4, "SFX volume should match settings")

	var music := GlobalMusicService.new()
	add_child(music)
	_expect_ok(
		music.configure({
			"audio_bus_map": audio_bus_map,
			"persist_across_scenes": false,
			"default_fade_seconds": 0.0,
			"default_crossfade_seconds": 0.0,
		}),
		"Global Music should configure from the same bus map"
	)
	_expect_equal(
		String(music.status_snapshot().get("bus_name", "")),
		TEST_BUSES[1],
		"Global Music should route to the BGM bus"
	)

	var one_shots := OneShotAudioService.new()
	add_child(one_shots)
	_expect_ok(
		one_shots.configure({
			"audio_bus_map": audio_bus_map,
			"persist_across_scenes": false,
			"max_active_players": 16,
		}),
		"One-shot Audio should configure from the same bus map"
	)

	var long_stream: AudioStreamWAV = _make_wav(1.0)
	var music_started: Dictionary = music.play_music(
		long_stream,
		{
			"track_id": "integration_bgm",
			"fade_in_seconds": 0.0,
		}
	)
	_expect_ok(music_started, "BGM should start")
	_expect_equal(
		String(music_started.get("bus_name", "")),
		TEST_BUSES[1],
		"BGM playback should use the shared BGM bus"
	)

	var sfx: Dictionary = one_shots.play_sfx(long_stream, {"tag": "integration_sfx"})
	var ui: Dictionary = one_shots.play_ui(long_stream, {"tag": "integration_ui"})
	var voice: Dictionary = one_shots.play_voice(long_stream, {"tag": "integration_voice"})
	_expect_ok(sfx, "SFX should start")
	_expect_ok(ui, "UI sound should start")
	_expect_ok(voice, "Voice should start")
	_expect_equal(String(sfx.get("bus_name", "")), TEST_BUSES[2], "SFX should use SFX bus")
	_expect_equal(String(ui.get("bus_name", "")), TEST_BUSES[3], "UI should use UI bus")
	_expect_equal(String(voice.get("bus_name", "")), TEST_BUSES[4], "Voice should use Voice bus")

	var owner_2d := Node2D.new()
	owner_2d.name = "AudioIntegration2D"
	add_child(owner_2d)
	var owner_3d := Node3D.new()
	owner_3d.name = "AudioIntegration3D"
	add_child(owner_3d)

	var spatial_2d: Dictionary = one_shots.play_2d(
		long_stream,
		owner_2d,
		Vector2(10.0, 20.0),
		{"tag": "integration_2d"}
	)
	var spatial_3d: Dictionary = one_shots.play_3d(
		long_stream,
		owner_3d,
		Vector3(1.0, 2.0, 3.0),
		{"tag": "integration_3d"}
	)
	_expect_ok(spatial_2d, "2D one-shot should start")
	_expect_ok(spatial_3d, "3D one-shot should start")
	_expect_equal(
		String(spatial_2d.get("bus_name", "")),
		TEST_BUSES[2],
		"2D helper should default to the shared SFX bus"
	)
	_expect_equal(
		String(spatial_3d.get("bus_name", "")),
		TEST_BUSES[2],
		"3D helper should default to the shared SFX bus"
	)

	_expect_true(music.is_music_playing(), "music should report active playback")
	_expect_equal(
		int(one_shots.status_snapshot().get("active_player_count", 0)),
		5,
		"SFX / UI / Voice / 2D / 3D should all be tracked"
	)

	var music_disposed: Dictionary = music.dispose_audio()
	var one_shots_disposed: Dictionary = one_shots.dispose_audio()
	_expect_ok(music_disposed, "Global Music cleanup should succeed")
	_expect_ok(one_shots_disposed, "One-shot cleanup should succeed")
	await get_tree().process_frame

	_expect_true(not music.is_music_playing(), "music should stop after dispose")
	_expect_true(
		not bool(music.status_snapshot().get("configured", true)),
		"music should return to unconfigured state after dispose"
	)
	_expect_equal(
		int(one_shots.status_snapshot().get("active_player_count", -1)),
		0,
		"one-shot cleanup should clear all active tracking"
	)
	_expect_equal(
		_count_spatial_audio_children(owner_2d),
		0,
		"2D spatial player should be removed during service cleanup"
	)
	_expect_equal(
		_count_spatial_audio_children(owner_3d),
		0,
		"3D spatial player should be removed during service cleanup"
	)

	music.queue_free()
	one_shots.queue_free()
	owner_2d.queue_free()
	owner_3d.queue_free()
	await get_tree().process_frame

	_remove_test_buses()
	_finish()


func _create_test_buses() -> Dictionary:
	for bus_name in TEST_BUSES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			return {
				"ok": false,
				"code": "test_bus_already_exists",
				"bus_name": bus_name,
			}
		AudioServer.add_bus()
		var bus_index: int = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		_created_bus_names.append(bus_name)
	return {
		"ok": true,
		"code": "test_buses_created",
	}


func _remove_test_buses() -> void:
	for index in range(_created_bus_names.size() - 1, -1, -1):
		var bus_name: String = _created_bus_names[index]
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.remove_bus(bus_index)
	_created_bus_names.clear()


func _expect_bus_volume(bus_name: String, linear_value: float, message: String) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		_fail(message + " / bus missing")
		return
	var expected_db: float = linear_to_db(linear_value)
	var actual_db: float = AudioServer.get_bus_volume_db(bus_index)
	if not is_equal_approx(actual_db, expected_db):
		_fail(
			message
			+ " / expected_db="
			+ str(expected_db)
			+ " actual_db="
			+ str(actual_db)
		)


func _expect_array_contains_all(actual: Array, expected: Array, message: String) -> void:
	for expected_value in expected:
		if not actual.has(expected_value):
			_fail(message + " / missing=" + str(expected_value))


func _count_spatial_audio_children(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is AudioStreamPlayer2D or child is AudioStreamPlayer3D:
			count += 1
	return count


func _make_wav(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var sample_count: int = maxi(1, int(seconds * float(wav.mix_rate)))
	var bytes := PackedByteArray()
	bytes.resize(sample_count)
	for index in range(sample_count):
		bytes[index] = 128
	wav.data = bytes
	return wav


func _expect_ok(result: Dictionary, message: String) -> void:
	if not bool(result.get("ok", false)):
		_fail(message + " / code=" + String(result.get("code", "")))


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
	push_error("AUDIO_SERVICE_INTEGRATION_SMOKE: " + message)


func _finish() -> void:
	_remove_test_buses()
	if _failed:
		get_tree().quit(1)
	else:
		print("AUDIO_SERVICE_INTEGRATION_SMOKE: PASS")
		get_tree().quit(0)
