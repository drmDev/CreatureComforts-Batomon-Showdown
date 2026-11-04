extends RefCounted
## Feeds the held one-shot trinket reminder panel.
##
## Extracted from mod_main.gd. Builds entries from run.trinket_ids, logs
## change-only updates, and queues the one-time chime when reminders appear.

const NodeUtils = preload("../core/node_utils.gd")
const TrackedTrinkets = preload("../core/tracked_trinkets.gd")
const ModConfig = preload("../core/mod_config.gd")

var _panel = null
var _formatter = null
var _logger = null
var _chimes = null
var _feature_enabled: Callable
var _alerted := false
var _last_entries: Dictionary = {}


func setup(panel, formatter, logger, chimes, feature_enabled: Callable) -> void:
	_panel = panel
	_formatter = formatter
	_logger = logger
	_chimes = chimes
	_feature_enabled = feature_enabled


## Refresh the panel from the player's held one-shot trinkets. `gate` is the
## shop overlay gate used for the one-time chime.
func update(run, gate) -> void:
	if _panel == null:
		return
	if not _feature_enabled.call(ModConfig.KEY_TRINKET_REMINDERS):
		_panel.hide_panel()
		_chimes.clear_trinket()
		return

	# Accept any iterable (Array or PackedStringArray), matching capture_state.
	var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	if held == null:
		held = []

	var entries: Array = TrackedTrinkets.build_entries(held, _formatter.format_trinket_name)

	if entries.is_empty():
		# Zero reminders: hide and reset to collapsed so a later regain starts collapsed.
		_panel.reset_collapsed()
		_alerted = false  # A later regain re-triggers the alert
		_chimes.clear_trinket()  # Nothing left to announce
		_log_changes(entries)
		return

	_panel.show_reminders(entries)
	_log_changes(entries)
	# First appearance, or first after the list was cleared: chime once. The panel stays
	# collapsed; the player expands it manually.
	if not _alerted:
		_alerted = true
		_chimes.queue_trinket()
		_chimes.try_play(gate)


func on_trainer_changed() -> void:
	if _panel != null:
		_panel.reset_collapsed()
	_alerted = false
	_last_entries.clear()
	_chimes.clear_trinket()


func on_feature_toggled(key: String, value: bool) -> void:
	if value:
		return
	if key == ModConfig.KEY_TRINKET_REMINDERS:
		if _panel != null:
			_panel.hide_panel()
		_chimes.clear_trinket()


func _log_changes(entries: Array) -> void:
	var current := {}
	for entry in entries:
		var name := str(entry.get("name", ""))
		current[name] = "%s x%d" % [name, int(entry.get("count", 1))]
	_logger.log_keyed_changes("TRINKET REMINDER", _last_entries, current)
	_last_entries = current
