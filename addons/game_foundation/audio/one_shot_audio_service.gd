extends Node

signal one_shot_started(kind: String, token: int, result: Dictionary)
signal one_shot_finished(kind: String, token: int, reason: String)

const AudioBusContract = preload(
	"res://addons/game_foundation/audio/audio_bus_contract.gd"
)

const DEFAULT_MAX_ACTIVE_PLAYERS: int = 64
const MAX_ACTIVE_PLAYERS_LIMIT: int = 256
const MIN_VOLUME_DB: float = -80.0
const MAX_VOLUME_DB: float = 24.0
const MIN_PITCH_SCALE: float = 0.01
const MAX_PITCH_SCALE: float = 4.0

var _configured: bool = false
var _persist_across_scenes: bool = true
var _max_active_players: int = DEFAULT_MAX_ACTIVE_PLAYERS
var _audio_bus_map: Dictionary = {}
var _using_audio_bus_contract: bool = false
var _bus_names: Dictionary = {
	"sfx": "Master",
	"ui": "Master",
	"voice": "Master",
}

var _next_token: int = 1
var _active: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _configured and _persist_across_scenes:
		call_deferred("_promote_to_root_if_needed")


func configure(options: Dictionary = {}) -> Dictionary:
	if not _active.is_empty():
		return _error(
			"active_one_shots",
			"one-shot audio service cannot be reconfigured while players are active"
		)

	var max_active_players: int = int(
		options.get("max_active_players", DEFAULT_MAX_ACTIVE_PLAYERS)
	)
	if max_active_players < 1 or max_active_players > MAX_ACTIVE_PLAYERS_LIMIT:
		return _error(
			"invalid_max_active_players",
			"max_active_players must be between 1 and "
			+ str(MAX_ACTIVE_PLAYERS_LIMIT)
		)

	if options.has("audio_bus_map") and options.has("bus_names"):
		return _error(
			"ambiguous_bus_configuration",
			"use either audio_bus_map or legacy bus_names, not both"
		)

	var bus_names_result: Dictionary = {}
	var normalized_bus_map: Dictionary = {}
	var using_audio_bus_contract: bool = false
	if options.has("audio_bus_map"):
		var shared_result: Dictionary = AudioBusContract.one_shot_bus_map(
			options.get("audio_bus_map", {})
		)
		if not bool(shared_result.get("ok", false)):
			return shared_result
		bus_names_result = {
			"ok": true,
			"bus_names": (
				shared_result.get("bus_map", {}) as Dictionary
			).duplicate(true),
		}
		normalized_bus_map = (
			shared_result.get("full_bus_map", {}) as Dictionary
		).duplicate(true)
		using_audio_bus_contract = true
	else:
		bus_names_result = _normalize_bus_names(
			options.get("bus_names", {})
		)
		if not bool(bus_names_result.get("ok", false)):
			return bus_names_result

	_persist_across_scenes = bool(options.get("persist_across_scenes", true))
	_max_active_players = max_active_players
	_audio_bus_map = normalized_bus_map
	_using_audio_bus_contract = using_audio_bus_contract
	_bus_names = (
		bus_names_result.get("bus_names", {}) as Dictionary
	).duplicate(true)
	_configured = true

	var persistence_result: Dictionary = _success(
		"persistence_not_requested",
		{"persistent": false}
	)
	if _persist_across_scenes and is_inside_tree():
		persistence_result = _promote_to_root_if_needed()

	return _success(
		"one_shot_audio_configured",
		{
			"persist_across_scenes": _persist_across_scenes,
			"max_active_players": _max_active_players,
			"bus_names": _bus_names.duplicate(true),
			"audio_bus_map": _audio_bus_map.duplicate(true),
			"using_audio_bus_contract": _using_audio_bus_contract,
			"persistence": persistence_result,
		}
	)


func is_configured() -> bool:
	return _configured


func promote_to_scene_tree_root() -> Dictionary:
	if not _configured:
		return _error(
			"service_not_configured",
			"one-shot audio service must be configured before promotion"
		)
	return _promote_to_root_if_needed()


func play_sfx(stream: AudioStream, options: Dictionary = {}) -> Dictionary:
	return _play_global("sfx", "sfx", stream, options)


func play_ui(stream: AudioStream, options: Dictionary = {}) -> Dictionary:
	return _play_global("ui", "ui", stream, options)


func play_voice(stream: AudioStream, options: Dictionary = {}) -> Dictionary:
	return _play_global("voice", "voice", stream, options)


func play_2d(
	stream: AudioStream,
	parent: Node,
	global_position: Vector2,
	options: Dictionary = {}
) -> Dictionary:
	if not (parent is Node2D):
		return _error(
			"invalid_spatial_parent",
			"2D one-shot parent must be a Node2D"
		)
	if not parent.is_inside_tree():
		return _error(
			"spatial_parent_not_in_tree",
			"2D one-shot parent must be inside the SceneTree"
		)

	var prepared: Dictionary = _prepare_request(
		"audio_2d",
		"sfx",
		stream,
		options
	)
	if not bool(prepared.get("ok", false)):
		return prepared

	var player := AudioStreamPlayer2D.new()
	parent.add_child(player)
	player.global_position = global_position
	_apply_common_player_options(player, stream, prepared)

	var token: int = _register_player(
		player,
		"audio_2d",
		String(prepared.get("tag", "")),
		String(prepared.get("bus_name", "Master"))
	)
	player.play(float(prepared.get("start_position", 0.0)))

	var result := _success(
		"one_shot_started",
		{
			"token": token,
			"kind": "audio_2d",
			"tag": String(prepared.get("tag", "")),
			"bus_name": String(prepared.get("bus_name", "Master")),
			"global_position": [global_position.x, global_position.y],
			"parent_path": String(parent.get_path()),
		}
	)
	one_shot_started.emit("audio_2d", token, result.duplicate(true))
	return result


func play_3d(
	stream: AudioStream,
	parent: Node,
	global_position: Vector3,
	options: Dictionary = {}
) -> Dictionary:
	if not (parent is Node3D):
		return _error(
			"invalid_spatial_parent",
			"3D one-shot parent must be a Node3D"
		)
	if not parent.is_inside_tree():
		return _error(
			"spatial_parent_not_in_tree",
			"3D one-shot parent must be inside the SceneTree"
		)

	var prepared: Dictionary = _prepare_request(
		"audio_3d",
		"sfx",
		stream,
		options
	)
	if not bool(prepared.get("ok", false)):
		return prepared

	var player := AudioStreamPlayer3D.new()
	parent.add_child(player)
	player.global_position = global_position
	_apply_common_player_options(player, stream, prepared)

	var token: int = _register_player(
		player,
		"audio_3d",
		String(prepared.get("tag", "")),
		String(prepared.get("bus_name", "Master"))
	)
	player.play(float(prepared.get("start_position", 0.0)))

	var result := _success(
		"one_shot_started",
		{
			"token": token,
			"kind": "audio_3d",
			"tag": String(prepared.get("tag", "")),
			"bus_name": String(prepared.get("bus_name", "Master")),
			"global_position": [
				global_position.x,
				global_position.y,
				global_position.z,
			],
			"parent_path": String(parent.get_path()),
		}
	)
	one_shot_started.emit("audio_3d", token, result.duplicate(true))
	return result


func stop_one_shot(token: int) -> Dictionary:
	if not _active.has(token):
		return _error(
			"unknown_one_shot",
			"one-shot token is not active",
			{"token": token}
		)

	var entry: Dictionary = _active[token] as Dictionary
	var kind: String = String(entry.get("kind", ""))
	_release_token(token, "stopped", true)
	return _success(
		"one_shot_stopped",
		{
			"token": token,
			"kind": kind,
		}
	)


func stop_all() -> Dictionary:
	var tokens: Array = _active.keys().duplicate()
	for token_variant in tokens:
		_release_token(int(token_variant), "stopped_all", true)
	return _success(
		"all_one_shots_stopped",
		{"stopped_count": tokens.size()}
	)


func status_snapshot() -> Dictionary:
	var by_kind: Dictionary = {
		"sfx": 0,
		"ui": 0,
		"voice": 0,
		"audio_2d": 0,
		"audio_3d": 0,
	}
	for entry_variant in _active.values():
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var kind: String = String(entry.get("kind", ""))
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1

	return {
		"configured": _configured,
		"persist_across_scenes": _persist_across_scenes,
		"parent_is_scene_tree_root": (
			is_inside_tree()
			and get_tree() != null
			and get_parent() == get_tree().root
		),
		"max_active_players": _max_active_players,
		"active_player_count": _active.size(),
		"active_by_kind": by_kind,
		"bus_names": _bus_names.duplicate(true),
		"audio_bus_map": _audio_bus_map.duplicate(true),
		"using_audio_bus_contract": _using_audio_bus_contract,
	}


func active_tokens() -> PackedInt64Array:
	var result := PackedInt64Array()
	for token_variant in _active.keys():
		result.append(int(token_variant))
	return result


func _play_global(
	kind: String,
	bus_key: String,
	stream: AudioStream,
	options: Dictionary
) -> Dictionary:
	var prepared: Dictionary = _prepare_request(
		kind,
		bus_key,
		stream,
		options
	)
	if not bool(prepared.get("ok", false)):
		return prepared

	var player := AudioStreamPlayer.new()
	add_child(player)
	_apply_common_player_options(player, stream, prepared)

	var token: int = _register_player(
		player,
		kind,
		String(prepared.get("tag", "")),
		String(prepared.get("bus_name", "Master"))
	)
	player.play(float(prepared.get("start_position", 0.0)))

	var result := _success(
		"one_shot_started",
		{
			"token": token,
			"kind": kind,
			"tag": String(prepared.get("tag", "")),
			"bus_name": String(prepared.get("bus_name", "Master")),
		}
	)
	one_shot_started.emit(kind, token, result.duplicate(true))
	return result


func _prepare_request(
	kind: String,
	bus_key: String,
	stream: AudioStream,
	options: Dictionary
) -> Dictionary:
	if not _configured:
		return _error(
			"service_not_configured",
			"one-shot audio service is not configured"
		)
	if stream == null:
		return _error(
			"audio_stream_required",
			"one-shot AudioStream cannot be null"
		)
	if _active.size() >= _max_active_players:
		return _error(
			"active_player_limit_reached",
			"one-shot active player limit has been reached",
			{
				"max_active_players": _max_active_players,
				"active_player_count": _active.size(),
			}
		)

	var volume_db: float = float(options.get("volume_db", 0.0))
	if volume_db < MIN_VOLUME_DB or volume_db > MAX_VOLUME_DB:
		return _error(
			"invalid_volume_db",
			"volume_db must be between "
			+ str(MIN_VOLUME_DB)
			+ " and "
			+ str(MAX_VOLUME_DB)
		)

	var pitch_scale: float = float(options.get("pitch_scale", 1.0))
	if pitch_scale < MIN_PITCH_SCALE or pitch_scale > MAX_PITCH_SCALE:
		return _error(
			"invalid_pitch_scale",
			"pitch_scale must be between "
			+ str(MIN_PITCH_SCALE)
			+ " and "
			+ str(MAX_PITCH_SCALE)
		)

	var start_position: float = float(options.get("start_position", 0.0))
	if start_position < 0.0:
		return _error(
			"invalid_start_position",
			"start_position must be 0 or greater"
		)

	var default_bus_name: String = String(_bus_names.get(bus_key, "Master"))
	var bus_name: String = String(
		options.get("bus_name", default_bus_name)
	).strip_edges()
	if bus_name.is_empty():
		return _error("invalid_bus_name", "bus_name cannot be empty")

	return _success(
		"one_shot_request_valid",
		{
			"kind": kind,
			"tag": String(options.get("tag", "")),
			"bus_name": bus_name,
			"volume_db": volume_db,
			"pitch_scale": pitch_scale,
			"start_position": start_position,
		}
	)


func _apply_common_player_options(
	player: Node,
	stream: AudioStream,
	prepared: Dictionary
) -> void:
	player.set("stream", stream)
	player.set("bus", StringName(String(prepared.get("bus_name", "Master"))))
	player.set("volume_db", float(prepared.get("volume_db", 0.0)))
	player.set("pitch_scale", float(prepared.get("pitch_scale", 1.0)))


func _register_player(
	player: Node,
	kind: String,
	tag: String,
	bus_name: String
) -> int:
	var token: int = _next_token
	_next_token += 1

	_active[token] = {
		"player": player,
		"kind": kind,
		"tag": tag,
		"bus_name": bus_name,
	}
	player.connect("finished", Callable(self, "_on_player_finished").bind(token))
	player.tree_exited.connect(_on_player_tree_exited.bind(token))
	return token


func _on_player_finished(token: int) -> void:
	_release_token(token, "finished", true)


func _on_player_tree_exited(token: int) -> void:
	_release_token(token, "tree_exited", false)


func _release_token(token: int, reason: String, queue_player: bool) -> void:
	if not _active.has(token):
		return

	var entry: Dictionary = _active[token] as Dictionary
	var player: Node = entry.get("player") as Node
	var kind: String = String(entry.get("kind", ""))
	_active.erase(token)

	if queue_player and is_instance_valid(player):
		if player.has_method("stop"):
			player.call("stop")
		player.queue_free()

	one_shot_finished.emit(kind, token, reason)


func _normalize_bus_names(value: Variant) -> Dictionary:
	if value != null and not (value is Dictionary):
		return _error(
			"invalid_bus_names",
			"bus_names must be a Dictionary"
		)

	var normalized: Dictionary = {
		"sfx": "Master",
		"ui": "Master",
		"voice": "Master",
	}
	if value is Dictionary:
		var candidate: Dictionary = value as Dictionary
		for key in ["sfx", "ui", "voice"]:
			if not candidate.has(key):
				continue
			var bus_name: String = String(candidate.get(key, "")).strip_edges()
			if bus_name.is_empty():
				return _error(
					"invalid_bus_name",
					"bus_names." + key + " cannot be empty",
					{"bus_key": key}
				)
			normalized[key] = bus_name

	return _success(
		"bus_names_normalized",
		{"bus_names": normalized}
	)


func _promote_to_root_if_needed() -> Dictionary:
	if not is_inside_tree() or get_tree() == null:
		return _error(
			"not_in_scene_tree",
			"one-shot audio service must be inside the SceneTree to persist across scenes"
		)
	if get_parent() == get_tree().root:
		return _success("already_scene_persistent", {"persistent": true})

	reparent(get_tree().root)
	return _success("scene_persistence_enabled", {"persistent": true})


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
