extends RefCounted


static func collect(app_info: Dictionary = {}) -> Dictionary:
	var engine_info: Dictionary = Engine.get_version_info()
	return {
		"app": {
			"name": String(app_info.get("name", ProjectSettings.get_setting("application/config/name", ""))),
			"version": String(app_info.get("version", ProjectSettings.get_setting("application/config/version", ""))),
		},
		"foundation": {
			"version": String(app_info.get("foundation_version", "")),
		},
		"engine": {
			"version": String(engine_info.get("string", "")),
			"major": int(engine_info.get("major", 0)),
			"minor": int(engine_info.get("minor", 0)),
			"patch": int(engine_info.get("patch", 0)),
			"status": String(engine_info.get("status", "")),
		},
		"runtime": {
			"os": OS.get_name(),
			"os_version": OS.get_version(),
			"display_server": DisplayServer.get_name(),
			"headless": DisplayServer.get_name() == "headless",
			"debug_build": OS.is_debug_build(),
			"processor_count": OS.get_processor_count(),
		},
	}
