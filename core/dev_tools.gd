extends RefCounted
## Debug-gated developer tooling: Ctrl+Shift hotkeys and diagnostics dumps.
##
## Extracted from mod_main.gd. Wraps core/dev_hotkeys.gd and core/diagnostics.gd
## so the mod only holds one reference for all debug-only behavior.

const DevHotkeys = preload("dev_hotkeys.gd")
const Diagnostics = preload("diagnostics.gd")

var _hotkeys = null
var _diagnostics = null


func _init(logger) -> void:
	_hotkeys = DevHotkeys.new()
	_diagnostics = Diagnostics.new(logger)


## Poll the Ctrl+Shift dev toggles (Debug Logging / Deep Inspection).
func poll(logger) -> void:
	_hotkeys.poll(logger)


## Run the debug-gated dumps for a shop visit.
func on_shop_entered(state) -> void:
	_diagnostics.on_shop_entered(state)


## Log the trinket icon resolution for the held ids (debug only).
func log_trinket_icons(held) -> void:
	_diagnostics.log_trinket_icons(held)


## Defer the one-shot catalog overview until autoloads such as GameDatabase exist.
func log_catalog_deferred() -> void:
	_diagnostics.call_deferred("log_catalog")
