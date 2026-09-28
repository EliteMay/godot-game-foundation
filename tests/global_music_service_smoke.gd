extends Node

const GlobalMusicService = preload(
	"res://addons/game_foundation/audio/global_music_service.gd"
)

var _failed: bool = false
var _service: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var holder := Node.new()
	holder.name = "SceneOwnedHolder"
	add_child(holder)

	_service = GlobalMusicService.new()
	holder.add_child(_service)

	var configured: Dictionary = _service.configure(
		{
			"bus_name": "Master",
			"default_fade_seconds": 0.02,
			"default_crossfade_seconds": 0.03,
			"persist_across_scenes": true,
		}
	)
	_expect_ok(configured, "global music service should configure")
	_expect_equal(
		String(_service.status_snapshot().get("bus_name", "")),
		"Master",
		"configured bus name should be exposed"
	)
	_expect_equal(
		int(_service.status_snapshot().get("player_count", 0)),
		2,
		"crossfade service should own two reusable music players"
	)
	_expect_true(
		_service.get_parent() == get_tree().root,
		"persistent music service should move under SceneTree root"
	)

	holder.queue_free()
	await get_tree().process_frame
	_expect_true(
		is_instance_valid(_service) and _service.is_inside_tree(),
		"scene-owned parent cleanup should not free persistent music service"
	)

	var first_stream := AudioStreamGenerator.new()
	first_stream.mix_rate = 22050.0
	first_stream.buffer_length = 0.1
	var first: Dictionary = _service.play_music(
		first_stream,
		{
			"track_id": "menu",
			"fade_in_seconds": 0.0,
		}
	)
	_expect_ok(first, "first music track should start")
	_expect_code(first, "music_started", "zero fade should start immediately")
	_expect_true(_service.is_music_playing(), "first track should report playing")
	_expect_equal(_service.current_track_id(), "menu", "current track id should be menu")
	_expect_true(
		_service.current_stream() == first_stream,
		"current stream should match first track"
	)

	var duplicate: Dictionary = _service.play_music(
		first_stream,
		{"track_id": "menu"}
	)
	_expect_code(
		duplicate,
		"music_already_playing",
		"same stream should not restart unless requested"
	)

	var second_stream := AudioStreamGenerator.new()
	second_stream.mix_rate = 24000.0
	second_stream.buffer_length = 0.1
	var crossfade: Dictionary = _service.play_music(
		second_stream,
		{
			"track_id": "gameplay",
			"crossfade_seconds": 0.03,
		}
	)
	_expect_code(
		crossfade,
		"music_crossfade_started",
		"second track should start a crossfade"
	)
	_expect_true(
		bool(_service.status_snapshot().get("transition_active", false)),
		"crossfade should expose active transition state"
	)
	_expect_equal(
		String(_service.status_snapshot().get("pending_track_id", "")),
		"gameplay",
		"crossfade should expose pending track id"
	)

	var blocked: Dictionary = _service.stop_music(0.0)
	_expect_code(
		blocked,
		"transition_in_progress",
		"overlapping music operations should be rejected deterministically"
	)

	await get_tree().create_timer(0.08, true, false, true).timeout
	_expect_true(
		not bool(_service.status_snapshot().get("transition_active", true)),
		"crossfade should complete"
	)
	_expect_equal(
		_service.current_track_id(),
		"gameplay",
		"crossfade should commit new track id"
	)
	_expect_true(
		_service.current_stream() == second_stream,
		"crossfade should commit new stream"
	)

	var fade_out: Dictionary = _service.stop_music(0.02)
	_expect_code(
		fade_out,
		"music_stop_started",
		"positive stop duration should start fade out"
	)
	await get_tree().create_timer(0.06, true, false, true).timeout
	_expect_true(not _service.is_music_playing(), "fade out should stop music")
	_expect_equal(_service.current_track_id(), "", "stop should clear track id")

	var restart: Dictionary = _service.play_music(
		first_stream,
		{
			"track_id": "menu",
			"fade_in_seconds": 0.02,
		}
	)
	_expect_code(
		restart,
		"music_fade_in_started",
		"positive first-track duration should start fade in"
	)
	await get_tree().create_timer(0.06, true, false, true).timeout
	_expect_true(_service.is_music_playing(), "fade in should finish with playing track")
	_expect_equal(_service.current_track_id(), "menu", "fade in should keep track id")

	var stopped: Dictionary = _service.stop_music(0.0)
	_expect_code(stopped, "music_stopped", "zero fade should stop immediately")
	_expect_true(not _service.is_music_playing(), "immediate stop should stop player")

	_expect_ok(
		_service.play_music(
			first_stream,
			{"track_id": "cleanup", "fade_in_seconds": 0.5}
		),
		"lifecycle fixture should start"
	)
	var disposed: Dictionary = _service.dispose_audio()
	_expect_code(
		disposed,
		"global_music_disposed",
		"dispose should return stable result"
	)
	_expect_true(
		bool(disposed.get("had_transition", false)),
		"dispose should report an active transition"
	)
	_expect_true(
		not bool(_service.status_snapshot().get("transition_active", true)),
		"dispose should clear transition state"
	)
	_expect_true(
		not bool(_service.status_snapshot().get("configured", true)),
		"dispose should require reconfigure"
	)
	for child in _service.get_children():
		if child is AudioStreamPlayer:
			_expect_true(
				(child as AudioStreamPlayer).stream == null,
				"dispose should release music stream references"
			)
			_expect_true(
				not (child as AudioStreamPlayer).playing,
				"dispose should stop reusable music players"
			)

	_expect_ok(
		_service.configure(
			{
				"bus_name": "Master",
				"persist_across_scenes": true,
			}
		),
		"service should reconfigure after dispose"
	)
	_expect_ok(
		_service.play_music(
			second_stream,
			{"track_id": "reused", "fade_in_seconds": 0.0}
		),
		"reconfigured service should play a new track"
	)
	await get_tree().create_timer(0.55, true, false, true).timeout
	_expect_equal(
		_service.current_track_id(),
		"reused",
		"disposed transition must not overwrite reused service state"
	)
	_expect_true(
		_service.is_music_playing(),
		"reused service should remain playing after old transition duration"
	)
	_expect_ok(
		_service.stop_music(0.0),
		"reused service should stop normally"
	)

	_expect_code(
		_service.play_music(first_stream, {"fade_in_seconds": 31.0}),
		"invalid_fade_seconds",
		"fade longer than supported maximum should be rejected"
	)

	var local_service := GlobalMusicService.new()
	add_child(local_service)
	_expect_ok(
		local_service.configure(
			{
				"bus_name": "Master",
				"persist_across_scenes": false,
			}
		),
		"non-persistent service should configure"
	)
	_expect_true(
		local_service.get_parent() == self,
		"persist_across_scenes=false should keep game-owned parent"
	)
	local_service.queue_free()

	_service.queue_free()
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
	push_error("GLOBAL_MUSIC_SERVICE_SMOKE: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("GLOBAL_MUSIC_SERVICE_SMOKE: PASS")
		get_tree().quit(0)
