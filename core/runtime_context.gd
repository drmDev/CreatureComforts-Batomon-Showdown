extends RefCounted
## Shared collaborators passed to every subsystem.
##
## Extracted from mod_main.gd. Bundles the formatter, logger, feature-toggle
## configuration, chime queue, and trinket icon resolver so each subsystem's
## setup() takes one dependency object instead of a long positional list.

const ModConfig = preload("mod_config.gd")

var formatter = null
var logger = null
var config = null
var chimes = null
var trinket_icons = null


func _init(p_formatter, p_logger, p_config, p_chimes, p_trinket_icons) -> void:
	formatter = p_formatter
	logger = p_logger
	config = p_config
	chimes = p_chimes
	trinket_icons = p_trinket_icons


## True when a user-facing feature is enabled. Defaults to enabled when the
## configuration module is unavailable (e.g. standalone run).
func feature_enabled(key: String) -> bool:
	if config == null:
		return true
	return config.is_enabled(key)


## Every sound the mod plays (reminders and UI feedback) is gated by the same
## setting, so one toggle mutes all of them.
func sounds_enabled() -> bool:
	return feature_enabled(ModConfig.KEY_NOTIFICATION_SOUNDS)
