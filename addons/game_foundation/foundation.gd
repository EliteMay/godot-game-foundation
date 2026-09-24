extends RefCounted

const FOUNDATION_VERSION: String = "0.2.0-dev"
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
	])
