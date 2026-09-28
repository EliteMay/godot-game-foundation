extends Node

signal music_started(track_id: String, result: Dictionary)
signal music_stopped(result: Dictionary)
signal transition_started(kind: String, result: Dictionary)
signal transition_completed(kind: String, result: Dictionary)

const SILENCE_DB: float = -80.0
const MAX_FADE_SECONDS: float = 30.0

var _configured: bool = false
var _bus_name: String = "Master"
var _default_fade_seconds: float = 0.25
var _default_crossfade_seconds: float = 0.5
var _persist_across_scenes: bool = true

var _players: Array[AudioStreamPlayer] = []
var _active_index: int = -1
var _current_track_id: String = ""
var _pending_track_id: String = ""
var _transition_active: bool = false
var _transition_kind: String = ""
var _active_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_players()
	if _configured and _persist_across_scenes:
		call_deferred("_promote_to_root_if_needed")


func configure(options: Dictionary = {}) -> Dictionary:
	if _transition_active:
		return _error(
			"transition_in_progress",
			"music service cannot be reconfigured during a fade or crossfade"
		)

	var bus_name: String = String(options.get("bus_name", "Master")).strip_edges()
	if bus_name.is_empty():
		return _error("invalid_bus_name", "bus_name cannot be empty")

	var fade_result: Dictionary = _validate_fade_seconds(
		float(options.get("default_fade_seconds", 0.25)),
		"default_fade_seconds"
	)
	if not bool(fade_result.get("ok", false)):
		return fade_result

	var crossfade_result: Dictionary = _validate_fade_seconds(
		float(options.get("default_crossfade_seconds", 0.5)),
		"default_crossfade_seconds"
	)
	if not bool(crossfade_result.get("ok", false)):
		return crossfade_result

	_bus_name = bus_name
	_default_fade_seconds = float(options.get("default_fade_seconds", 0.25))
	_default_crossfade_seconds = float(
		options.get("default_crossfade_seconds", 0.5)
	)
	_persist_across_scenes = bool(options.get("persist_across_scenes", true))
	_configured = true

	_ensure_players()
	_apply_bus_name()

	var persistence_result: Dictionary = _success(
		"persistence_not_requested",
		{"persistent": false}
	)
	if _persist_across_scenes and is_inside_tree():
		persistence_result = _promote_to_root_if_needed()

	return _success(
		"global_music_configured",
		{
			"bus_name": _bus_name,
			"default_fade_seconds": _default_fade_seconds,
			"default_crossfade_seconds": _default_crossfade_seconds,
			"persist_across_scenes": _persist_across_scenes,
			"persistence": persistence_result,
		}
	)


func is_configured() -> bool:
	return _configured


func promote_to_scene_tree_root() -> Dictionary:
	if not _configured:
		return _error(
			"service_not_configured",
			"global music service must be configured before promotion"
		)
	return _promote_to_root_if_needed()


func play_music(stream: AudioStream, options: Dictionary = {}) -> Dictionary:
	if not _configured:
		return _error(
			"service_not_configured",
			"global music service is not configured"
		)
	if stream == null:
		return _error("audio_stream_required", "music stream cannot be null")
	if _transition_active:
		return _error(
			"transition_in_progress",
			"another music fade or crossfade is still running",
			{"transition_kind": _transition_kind}
		)

	var start_position: float = float(options.get("start_position", 0.0))
	if start_position < 0.0:
		return _error(
			"invalid_start_position",
			"start_position must be 0 or greater"
		)

	var track_id: String = String(options.get("track_id", ""))
	var restart: bool = bool(options.get("restart", false))
	var current: AudioStreamPlayer = _current_player()
	if (
		current != null
		and current.playing
		and current.stream == stream
		and not restart
	):
		return _success(
			"music_already_playing",
			{
				"track_id": _current_track_id,
				"bus_name": _bus_name,
			}
		)

	if current != null and current.playing:
		var crossfade_seconds_result: Dictionary = _resolve_fade_seconds(
			options,
			"crossfade_seconds",
			_default_crossfade_seconds
		)
		if not bool(crossfade_seconds_result.get("ok", false)):
			return crossfade_seconds_result
		return _start_crossfade(
			stream,
			track_id,
			start_position,
			float(crossfade_seconds_result.get("seconds", 0.0))
		)

	var fade_seconds_result: Dictionary = _resolve_fade_seconds(
		options,
		"fade_in_seconds",
		_default_fade_seconds
	)
	if not bool(fade_seconds_result.get("ok", false)):
		return fade_seconds_result
	return _start_first_track(
		stream,
		track_id,
		start_position,
		float(fade_seconds_result.get("seconds", 0.0))
	)


func stop_music(fade_seconds: float = -1.0) -> Dictionary:
	if not _configured:
		return _error(
			"service_not_configured",
			"global music service is not configured"
		)
	if _transition_active:
		return _error(
			"transition_in_progress",
			"another music fade or crossfade is still running",
			{"transition_kind": _transition_kind}
		)

	var current: AudioStreamPlayer = _current_player()
	if current == null or not current.playing:
		_reset_playback_state()
		return _success("music_already_stopped")

	var seconds: float = (
		_default_fade_seconds
		if fade_seconds < 0.0
		else fade_seconds
	)
	var validation: Dictionary = _validate_fade_seconds(seconds, "fade_seconds")
	if not bool(validation.get("ok", false)):
		return validation

	if seconds <= 0.0:
		var track_id: String = _current_track_id
		_stop_and_clear_player(current)
		_reset_playback_state()
		var stopped := _success(
			"music_stopped",
			{"track_id": track_id}
		)
		music_stopped.emit(stopped.duplicate(true))
		return stopped

	_transition_active = true
	_transition_kind = "fade_out"
	_pending_track_id = ""
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.tween_property(current, "volume_db", SILENCE_DB, seconds)
	_active_tween.finished.connect(_finish_fade_out.bind(current, _current_track_id))

	var started := _success(
		"music_stop_started",
		{
			"track_id": _current_track_id,
			"fade_seconds": seconds,
		}
	)
	transition_started.emit("fade_out", started.duplicate(true))
	return started


func current_stream() -> AudioStream:
	var current: AudioStreamPlayer = _current_player()
	return current.stream if current != null else null


func current_track_id() -> String:
	return _current_track_id


func is_music_playing() -> bool:
	var current: AudioStreamPlayer = _current_player()
	return current != null and current.playing


func status_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"bus_name": _bus_name,
		"default_fade_seconds": _default_fade_seconds,
		"default_crossfade_seconds": _default_crossfade_seconds,
		"persist_across_scenes": _persist_across_scenes,
		"parent_is_scene_tree_root": (
			is_inside_tree()
			and get_tree() != null
			and get_parent() == get_tree().root
		),
		"playing": is_music_playing(),
		"current_track_id": _current_track_id,
		"pending_track_id": _pending_track_id,
		"active_player_index": _active_index,
		"transition_active": _transition_active,
		"transition_kind": _transition_kind,
		"player_count": _players.size(),
	}


func _start_first_track(
	stream: AudioStream,
	track_id: String,
	start_position: float,
	fade_seconds: float
) -> Dictionary:
	var index: int = 0 if _active_index < 0 else _active_index
	var player: AudioStreamPlayer = _players[index]
	_prepare_player(player, stream)
	_active_index = index
	_current_track_id = track_id
	_pending_track_id = ""

	if fade_seconds <= 0.0:
		player.volume_db = 0.0
		player.play(start_position)
		var result := _success(
			"music_started",
			{
				"track_id": track_id,
				"fade_seconds": 0.0,
				"bus_name": _bus_name,
			}
		)
		music_started.emit(track_id, result.duplicate(true))
		return result

	player.volume_db = SILENCE_DB
	player.play(start_position)
	_transition_active = true
	_transition_kind = "fade_in"
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.tween_property(player, "volume_db", 0.0, fade_seconds)
	_active_tween.finished.connect(_finish_fade_in.bind(player, track_id))

	var started := _success(
		"music_fade_in_started",
		{
			"track_id": track_id,
			"fade_seconds": fade_seconds,
			"bus_name": _bus_name,
		}
	)
	transition_started.emit("fade_in", started.duplicate(true))
	return started


func _start_crossfade(
	stream: AudioStream,
	track_id: String,
	start_position: float,
	crossfade_seconds: float
) -> Dictionary:
	var old_index: int = _active_index
	var new_index: int = 1 if old_index == 0 else 0
	var old_player: AudioStreamPlayer = _players[old_index]
	var new_player: AudioStreamPlayer = _players[new_index]
	_stop_and_clear_player(new_player)
	_prepare_player(new_player, stream)

	if crossfade_seconds <= 0.0:
		var previous_track_id: String = _current_track_id
		_stop_and_clear_player(old_player)
		new_player.volume_db = 0.0
		new_player.play(start_position)
		_active_index = new_index
		_current_track_id = track_id
		_pending_track_id = ""
		var changed := _success(
			"music_started",
			{
				"track_id": track_id,
				"previous_track_id": previous_track_id,
				"crossfade_seconds": 0.0,
				"bus_name": _bus_name,
			}
		)
		music_started.emit(track_id, changed.duplicate(true))
		return changed

	_pending_track_id = track_id
	new_player.volume_db = SILENCE_DB
	new_player.play(start_position)
	_transition_active = true
	_transition_kind = "crossfade"
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.set_parallel(true)
	_active_tween.tween_property(old_player, "volume_db", SILENCE_DB, crossfade_seconds)
	_active_tween.tween_property(new_player, "volume_db", 0.0, crossfade_seconds)
	_active_tween.finished.connect(
		_finish_crossfade.bind(
			old_player,
			new_player,
			new_index,
			_current_track_id,
			track_id
		)
	)

	var started := _success(
		"music_crossfade_started",
		{
			"track_id": track_id,
			"previous_track_id": _current_track_id,
			"crossfade_seconds": crossfade_seconds,
			"bus_name": _bus_name,
		}
	)
	transition_started.emit("crossfade", started.duplicate(true))
	return started


func _finish_fade_in(player: AudioStreamPlayer, track_id: String) -> void:
	if not is_instance_valid(player):
		_reset_transition_state()
		return
	player.volume_db = 0.0
	_reset_transition_state()
	var result := _success(
		"music_started",
		{
			"track_id": track_id,
			"fade_seconds": 0.0,
			"bus_name": _bus_name,
		}
	)
	music_started.emit(track_id, result.duplicate(true))
	transition_completed.emit("fade_in", result.duplicate(true))


func _finish_crossfade(
	old_player: AudioStreamPlayer,
	new_player: AudioStreamPlayer,
	new_index: int,
	previous_track_id: String,
	track_id: String
) -> void:
	if is_instance_valid(old_player):
		_stop_and_clear_player(old_player)
	if not is_instance_valid(new_player):
		_reset_playback_state()
		return
	new_player.volume_db = 0.0
	_active_index = new_index
	_current_track_id = track_id
	_pending_track_id = ""
	_reset_transition_state()
	var result := _success(
		"music_started",
		{
			"track_id": track_id,
			"previous_track_id": previous_track_id,
			"bus_name": _bus_name,
		}
	)
	music_started.emit(track_id, result.duplicate(true))
	transition_completed.emit("crossfade", result.duplicate(true))


func _finish_fade_out(player: AudioStreamPlayer, track_id: String) -> void:
	if is_instance_valid(player):
		_stop_and_clear_player(player)
	_reset_playback_state()
	var result := _success(
		"music_stopped",
		{"track_id": track_id}
	)
	music_stopped.emit(result.duplicate(true))
	transition_completed.emit("fade_out", result.duplicate(true))


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer" + str(index + 1)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)
	_apply_bus_name()


func _apply_bus_name() -> void:
	for player in _players:
		player.bus = StringName(_bus_name)


func _prepare_player(player: AudioStreamPlayer, stream: AudioStream) -> void:
	player.stop()
	player.stream = stream
	player.bus = StringName(_bus_name)
	player.volume_db = 0.0


func _stop_and_clear_player(player: AudioStreamPlayer) -> void:
	player.stop()
	player.stream = null
	player.volume_db = 0.0


func _current_player() -> AudioStreamPlayer:
	if _active_index < 0 or _active_index >= _players.size():
		return null
	return _players[_active_index]


func _promote_to_root_if_needed() -> Dictionary:
	if not is_inside_tree() or get_tree() == null:
		return _error(
			"not_in_scene_tree",
			"global music service must be inside the SceneTree to persist across scenes"
		)
	if get_parent() == get_tree().root:
		return _success("already_scene_persistent", {"persistent": true})

	reparent(get_tree().root)
	return _success("scene_persistence_enabled", {"persistent": true})


func _resolve_fade_seconds(
	options: Dictionary,
	key: String,
	default_value: float
) -> Dictionary:
	var seconds: float = float(options.get(key, default_value))
	var validation: Dictionary = _validate_fade_seconds(seconds, key)
	if not bool(validation.get("ok", false)):
		return validation
	return _success("fade_seconds_resolved", {"seconds": seconds})


func _validate_fade_seconds(seconds: float, field_name: String) -> Dictionary:
	if seconds < 0.0 or seconds > MAX_FADE_SECONDS:
		return _error(
			"invalid_fade_seconds",
			field_name + " must be between 0 and " + str(MAX_FADE_SECONDS),
			{"field": field_name, "value": seconds}
		)
	return _success("valid_fade_seconds")


func _reset_transition_state() -> void:
	_transition_active = false
	_transition_kind = ""
	_active_tween = null


func _reset_playback_state() -> void:
	_active_index = -1
	_current_track_id = ""
	_pending_track_id = ""
	_reset_transition_state()


func _success(code: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "code": code}
	for key in extra:
		result[key] = extra[key]
	return result


func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": false, "code": code, "message": message}
	for key in extra:
		result[key] = extra[key]
	return result
