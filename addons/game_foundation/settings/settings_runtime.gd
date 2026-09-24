extends RefCounted


static func apply_settings(
	settings: Dictionary,
	audio_bus_map: Dictionary = {
		"master": "Master",
		"bgm": "BGM",
		"sfx": "SFX",
	}
) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {
			"ok": true,
			"code": "headless_skipped",
			"audio": {
				"applied": [],
				"missing_buses": [],
			},
			"display": {
				"applied": false,
			},
		}

	var audio_result: Dictionary = apply_audio(settings, audio_bus_map)
	var display_result: Dictionary = apply_display(settings)
	return {
		"ok": bool(audio_result.get("ok", false)) and bool(display_result.get("ok", false)),
		"code": "applied",
		"audio": audio_result,
		"display": display_result,
	}


static func apply_audio(
	settings: Dictionary,
	audio_bus_map: Dictionary = {
		"master": "Master",
		"bgm": "BGM",
		"sfx": "SFX",
	}
) -> Dictionary:
	var audio_variant: Variant = settings.get("audio", {})
	if not (audio_variant is Dictionary):
		return {
			"ok": false,
			"code": "audio_settings_missing",
		}

	var audio: Dictionary = audio_variant as Dictionary
	var applied: Array[String] = []
	var missing_buses: Array[String] = []

	for setting_key in ["master", "bgm", "sfx"]:
		var bus_name: String = String(audio_bus_map.get(setting_key, ""))
		if bus_name.is_empty():
			continue

		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			missing_buses.append(bus_name)
			continue

		var volume: float = clampf(float(audio.get(setting_key, 1.0)), 0.0, 1.0)
		AudioServer.set_bus_mute(bus_index, volume <= 0.0001)
		AudioServer.set_bus_volume_db(
			bus_index,
			-80.0 if volume <= 0.0001 else linear_to_db(volume)
		)
		applied.append(bus_name)

	return {
		"ok": true,
		"code": "audio_applied",
		"applied": applied,
		"missing_buses": missing_buses,
	}


static func apply_display(settings: Dictionary) -> Dictionary:
	var display_variant: Variant = settings.get("display", {})
	if not (display_variant is Dictionary):
		return {
			"ok": false,
			"code": "display_settings_missing",
		}

	var display: Dictionary = display_variant as Dictionary
	var mode: String = String(display.get("window_mode", "windowed"))
	var resolution_variant: Variant = display.get("resolution", [1280, 720])
	var resolution := Vector2i(1280, 720)

	if resolution_variant is Array:
		var values: Array = resolution_variant as Array
		if values.size() == 2:
			resolution = Vector2i(int(values[0]), int(values[1]))

	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_BORDERLESS,
		mode == "borderless"
	)

	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED
		if bool(display.get("vsync", true))
		else DisplayServer.VSYNC_DISABLED
	)

	return {
		"ok": true,
		"code": "display_applied",
		"window_mode": mode,
		"resolution": [resolution.x, resolution.y],
		"vsync": bool(display.get("vsync", true)),
	}
