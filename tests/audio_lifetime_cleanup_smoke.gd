extends Node

const GlobalMusicService = preload(
	"res://addons/game_foundation/audio/global_music_service.gd"
)
const OneShotAudioService = preload(
	"res://addons/game_foundation/audio/one_shot_audio_service.gd"
)

var _failed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var long_stream: AudioStreamWAV = _make_wav(1.0)

	var music := GlobalMusicService.new()
	add_child(music)
	_expect_ok(
		music.configure({
			"bus_name": "Master",
			"persist_across_scenes": false,
		}),
		"music should configure"
	)
	_expect_ok(
		music.play_music(
			long_stream,
			{"track_id": "old", "fade_in_seconds": 0.5}
		),
		"music fade fixture should start"
	)
	var music_disposed: Dictionary = music.dispose_audio()
	_expect_code(
		music_disposed,
		"global_music_disposed",
		"music dispose should return stable result"
	)
	_expect_true(
		bool(music_disposed.get("had_transition", false)),
		"music dispose should report canceled transition"
	)
	_expect_equal(
		int(music_disposed.get("cleared_player_count", 0)),
		1,
		"music dispose should clear the referenced stream player"
	)
	_expect_true(
		not bool(music.status_snapshot().get("configured", true)),
		"music should require configure after dispose"
	)
	_expect_true(
		not bool(music.status_snapshot().get("transition_active", true)),
		"music transition state should be reset"
	)
	for child in music.get_children():
		if child is AudioStreamPlayer:
			_expect_true(
				(child as AudioStreamPlayer).stream == null,
				"music dispose should release AudioStream references"
			)
			_expect_true(
				not (child as AudioStreamPlayer).playing,
				"music dispose should stop reusable players"
			)

	_expect_ok(
		music.configure({
			"bus_name": "Master",
			"persist_across_scenes": false,
		}),
		"disposed music service should be reusable"
	)
	_expect_ok(
		music.play_music(
			long_stream,
			{"track_id": "new", "fade_in_seconds": 0.0}
		),
		"reused music service should play"
	)
	await get_tree().create_timer(0.55, true, false, true).timeout
	_expect_equal(
		music.current_track_id(),
		"new",
		"stale transition callback must not overwrite reused music state"
	)
	_expect_true(music.is_music_playing(), "reused music should still be playing")
	music.queue_free()
	await get_tree().process_frame
	_expect_true(not is_instance_valid(music), "music service should free cleanly")

	var owner_2d := Node2D.new()
	owner_2d.name = "LifecycleSpatialOwner"
	add_child(owner_2d)

	var one_shots := OneShotAudioService.new()
	add_child(one_shots)
	_expect_ok(
		one_shots.configure({
			"persist_across_scenes": false,
			"max_active_players": 8,
		}),
		"one-shot service should configure"
	)
	var global_result: Dictionary = one_shots.play_sfx(long_stream, {"tag": "global"})
	_expect_ok(global_result, "global one-shot should start")
	var spatial_result: Dictionary = one_shots.play_2d(
		long_stream,
		owner_2d,
		Vector2(8.0, 16.0),
		{"tag": "spatial"}
	)
	_expect_ok(spatial_result, "spatial one-shot should start")
	_expect_equal(
		int(one_shots.status_snapshot().get("active_player_count", 0)),
		2,
		"fixture should track global and spatial players"
	)

	var one_shot_disposed: Dictionary = one_shots.dispose_audio()
	_expect_code(
		one_shot_disposed,
		"one_shot_audio_disposed",
		"one-shot dispose should return stable result"
	)
	_expect_equal(
		int(one_shot_disposed.get("cleared_player_count", 0)),
		2,
		"one-shot dispose should clear all tracked players"
	)
	_expect_equal(
		int(one_shots.status_snapshot().get("active_player_count", -1)),
		0,
		"one-shot dispose should clear tracking immediately"
	)
	_expect_true(
		not bool(one_shots.status_snapshot().get("configured", true)),
		"one-shot dispose should require configure before new playback"
	)
	await get_tree().process_frame
	_expect_equal(
		_count_audio_children(owner_2d),
		0,
		"spatial players should be removed from the external world owner"
	)

	_expect_ok(
		one_shots.configure({"persist_across_scenes": false}),
		"disposed one-shot service should be reusable"
	)
	_expect_ok(
		one_shots.play_ui(long_stream, {"tag": "reused"}),
		"reused one-shot service should play"
	)
	_expect_equal(
		int(one_shots.status_snapshot().get("active_player_count", 0)),
		1,
		"reused service should track new playback"
	)
	_expect_ok(one_shots.stop_all(), "reused service stop_all should work")
	await get_tree().process_frame

	var exit_owner := Node2D.new()
	exit_owner.name = "ServiceExitSpatialOwner"
	add_child(exit_owner)
	var exit_service := OneShotAudioService.new()
	add_child(exit_service)
	_expect_ok(
		exit_service.configure({"persist_across_scenes": false}),
		"service-exit fixture should configure"
	)
	_expect_ok(
		exit_service.play_2d(long_stream, exit_owner, Vector2.ZERO),
		"service-exit spatial one-shot should start"
	)
	_expect_equal(
		_count_audio_children(exit_owner),
		1,
		"service-exit fixture should own one spatial player"
	)
	exit_service.queue_free()
	await get_tree().process_frame
	_expect_true(
		not is_instance_valid(exit_service),
		"one-shot service should free cleanly"
	)
	_expect_equal(
		_count_audio_children(exit_owner),
		0,
		"service exit must remove external spatial players"
	)

	one_shots.queue_free()
	owner_2d.queue_free()
	exit_owner.queue_free()
	await get_tree().process_frame
	_finish()


func _count_audio_children(parent: Node) -> int:
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
	push_error("AUDIO_LIFETIME_CLEANUP_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("AUDIO_LIFETIME_CLEANUP_SMOKE: PASS")
		get_tree().quit(0)
