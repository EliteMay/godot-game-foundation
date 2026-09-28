extends Node

const OneShotAudioService = preload(
	"res://addons/game_foundation/audio/one_shot_audio_service.gd"
)

var _failed: bool = false
var _finished_events: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var holder := Node.new()
	holder.name = "SceneOwnedAudioHolder"
	add_child(holder)

	var service := OneShotAudioService.new()
	holder.add_child(service)
	service.one_shot_finished.connect(_on_one_shot_finished)

	var configured: Dictionary = service.configure(
		{
			"persist_across_scenes": true,
			"max_active_players": 8,
			"bus_names": {
				"sfx": "Master",
				"ui": "Master",
				"voice": "Master",
			},
		}
	)
	_expect_ok(configured, "one-shot service should configure")
	_expect_true(
		service.get_parent() == get_tree().root,
		"persistent one-shot service should move under SceneTree root"
	)
	_expect_equal(
		int(service.status_snapshot().get("max_active_players", 0)),
		8,
		"configured player limit should be exposed"
	)

	holder.queue_free()
	await get_tree().process_frame
	_expect_true(
		is_instance_valid(service) and service.is_inside_tree(),
		"scene-owned holder cleanup should not free persistent one-shot service"
	)

	var short_stream: AudioStreamWAV = _make_wav(0.05)
	var long_stream: AudioStreamWAV = _make_wav(1.0)

	var sfx: Dictionary = service.play_sfx(
		short_stream,
		{
			"tag": "hit",
			"volume_db": -6.0,
			"pitch_scale": 1.1,
		}
	)
	_expect_ok(sfx, "global SFX should start")
	_expect_equal(String(sfx.get("kind", "")), "sfx", "SFX kind should be reported")
	_expect_equal(String(sfx.get("bus_name", "")), "Master", "SFX bus should resolve")
	_expect_true(int(sfx.get("token", 0)) > 0, "SFX should return a token")

	var ui: Dictionary = service.play_ui(short_stream, {"tag": "confirm"})
	_expect_ok(ui, "UI one-shot should start")
	_expect_equal(String(ui.get("kind", "")), "ui", "UI kind should be reported")

	var voice: Dictionary = service.play_voice(short_stream, {"tag": "line"})
	_expect_ok(voice, "Voice one-shot should start")
	_expect_equal(
		String(voice.get("kind", "")),
		"voice",
		"Voice kind should be reported"
	)

	var counts: Dictionary = (
		service.status_snapshot().get("active_by_kind", {}) as Dictionary
	)
	_expect_equal(int(counts.get("sfx", 0)), 1, "SFX count should be tracked")
	_expect_equal(int(counts.get("ui", 0)), 1, "UI count should be tracked")
	_expect_equal(int(counts.get("voice", 0)), 1, "Voice count should be tracked")

	await get_tree().create_timer(0.18, true, false, true).timeout
	_expect_equal(
		int(service.status_snapshot().get("active_player_count", -1)),
		0,
		"finished global one-shots should clean themselves up"
	)
	_expect_true(
		_finished_events.size() >= 3,
		"finished one-shots should emit cleanup events"
	)

	var owner_2d := Node2D.new()
	owner_2d.name = "Spatial2DOwner"
	add_child(owner_2d)
	var spatial_2d: Dictionary = service.play_2d(
		long_stream,
		owner_2d,
		Vector2(12.0, 34.0),
		{"tag": "world_hit"}
	)
	_expect_ok(spatial_2d, "2D one-shot should start")
	_expect_equal(
		String(spatial_2d.get("kind", "")),
		"audio_2d",
		"2D kind should be reported"
	)
	_expect_equal(
		spatial_2d.get("global_position", []),
		[12.0, 34.0],
		"2D position should be reported"
	)

	owner_2d.queue_free()
	await get_tree().process_frame
	_expect_equal(
		int(service.status_snapshot().get("active_player_count", -1)),
		0,
		"scene-owned 2D player should leave tracking when its owner exits"
	)

	var owner_3d := Node3D.new()
	owner_3d.name = "Spatial3DOwner"
	add_child(owner_3d)
	var spatial_3d: Dictionary = service.play_3d(
		long_stream,
		owner_3d,
		Vector3(1.0, 2.0, 3.0),
		{"tag": "voice_world"}
	)
	_expect_ok(spatial_3d, "3D one-shot should start")
	_expect_equal(
		String(spatial_3d.get("kind", "")),
		"audio_3d",
		"3D kind should be reported"
	)
	_expect_equal(
		spatial_3d.get("global_position", []),
		[1.0, 2.0, 3.0],
		"3D position should be reported"
	)
	_expect_ok(
		service.stop_one_shot(int(spatial_3d.get("token", 0))),
		"one-shot token should support explicit stop"
	)
	_expect_equal(
		int(service.status_snapshot().get("active_player_count", -1)),
		0,
		"explicit stop should remove active player"
	)
	owner_3d.queue_free()

	_expect_code(
		service.play_2d(long_stream, Node.new(), Vector2.ZERO),
		"invalid_spatial_parent",
		"2D helper should reject a non-Node2D parent"
	)
	_expect_code(
		service.play_3d(null, Node3D.new(), Vector3.ZERO),
		"spatial_parent_not_in_tree",
		"3D helper should validate parent lifetime before playback"
	)
	_expect_code(
		service.play_sfx(null),
		"audio_stream_required",
		"global helper should reject null stream"
	)
	_expect_code(
		service.play_sfx(long_stream, {"volume_db": 30.0}),
		"invalid_volume_db",
		"unsafe volume_db should be rejected"
	)
	_expect_code(
		service.play_sfx(long_stream, {"pitch_scale": 0.0}),
		"invalid_pitch_scale",
		"invalid pitch should be rejected"
	)

	var limited := OneShotAudioService.new()
	add_child(limited)
	_expect_ok(
		limited.configure(
			{
				"persist_across_scenes": false,
				"max_active_players": 1,
			}
		),
		"limited service should configure"
	)
	var limited_first: Dictionary = limited.play_sfx(long_stream)
	_expect_ok(limited_first, "first limited one-shot should start")
	_expect_code(
		limited.play_ui(long_stream),
		"active_player_limit_reached",
		"active player limit should bound one-shot allocation"
	)
	var all_stopped: Dictionary = limited.stop_all()
	_expect_ok(all_stopped, "stop_all should succeed")
	_expect_equal(
		int(all_stopped.get("stopped_count", 0)),
		1,
		"stop_all should report stopped player count"
	)
	_expect_equal(
		int(limited.status_snapshot().get("active_player_count", -1)),
		0,
		"stop_all should clear active tracking"
	)

	limited.queue_free()
	service.queue_free()
	await get_tree().process_frame
	_finish()


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


func _on_one_shot_finished(kind: String, token: int, reason: String) -> void:
	_finished_events.append({
		"kind": kind,
		"token": token,
		"reason": reason,
	})


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
	push_error("ONE_SHOT_AUDIO_SERVICE_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("ONE_SHOT_AUDIO_SERVICE_SMOKE: PASS")
		get_tree().quit(0)
