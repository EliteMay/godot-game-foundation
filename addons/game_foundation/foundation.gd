extends RefCounted

const FOUNDATION_VERSION: String = "0.8.0-dev"
const GODOT_BASELINE: String = "4.7.2"


static func info() -> Dictionary:
	return {
		"name": "Godot Game Foundation",
		"foundation_version": FOUNDATION_VERSION,
		"godot_baseline": GODOT_BASELINE,
	}


static func capabilities() -> PackedStringArray:
	return PackedStringArray([
		"foundation_core",
		"generic_save_system",
		"save_versioning",
		"atomic_save",
		"backup_recovery",
		"migration_hook",
		"autosave_api",
		"settings_system",
		"audio_settings",
		"display_settings",
		"gameplay_settings_extension",
		"settings_persistence",
		"input_system",
		"input_rebind",
		"input_persistence",
		"keyboard_mouse_bindings",
		"gamepad_binding_model",
		"game_flow",
		"pause_service",
		"scene_contract",
		"main_menu_contract",
		"safe_quit_hooks",
		"diagnostics",
		"runtime_version_info",
		"log_service",
		"debug_overlay",
		"error_summary",
		"windows_build",
		"windows_export_preset",
		"ci_export_artifact",
		"build_metadata",
		"starter_template",
		"managed_foundation_distribution",
	])
