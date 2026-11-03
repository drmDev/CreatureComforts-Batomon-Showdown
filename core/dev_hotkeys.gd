extends RefCounted
## Ctrl+Shift dev toggle polling (Debug Logging / Deep Inspection).
##
## Extracted from mod_main.gd. Mutates the flags on core/mod_logger.gd and logs
## each change. Not user-facing; startup defaults live in dev/dev_config.gd.

const DevConfig = preload("../dev/dev_config.gd")

var _debug_was_down := false
var _inspect_was_down := false


func poll(logger) -> void:
	var modifier_held := Input.is_key_pressed(Key.KEY_CTRL) and Input.is_key_pressed(Key.KEY_SHIFT)
	var debug_down := modifier_held and Input.is_key_pressed(DevConfig.TOGGLE_DEBUG_KEY)
	var inspect_down := modifier_held and Input.is_key_pressed(DevConfig.TOGGLE_INSPECT_KEY)

	if debug_down and not _debug_was_down:
		logger.debug_logging = not logger.debug_logging
		logger.log_message("Dev toggle: Debug Logging = %s" % logger.debug_logging)
	if inspect_down and not _inspect_was_down:
		logger.deep_inspection = not logger.deep_inspection
		logger.log_message("Dev toggle: Deep Inspection = %s" % logger.deep_inspection)

	_debug_was_down = debug_down
	_inspect_was_down = inspect_down
