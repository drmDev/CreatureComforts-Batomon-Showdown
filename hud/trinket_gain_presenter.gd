extends RefCounted
## Shows battle trinket gains on the results panel.
##
## Extracted from mod_main.gd. Filters junk trinkets, summarizes duplicate ids,
## and respects the Trinkets Gained Panel feature toggle.

const TrinketGains = preload("../core/trinket_gains.gd")
const LogFormatterScript = preload("../core/log_formatter.gd")
const ModConfig = preload("../core/mod_config.gd")
const JUNK_TRINKET_ID := LogFormatterScript.JUNK_TRINKET_ID

var _panel = null
var _formatter = null
var _feature_enabled: Callable


func setup(panel, formatter, feature_enabled: Callable) -> void:
	_panel = panel
	_formatter = formatter
	_feature_enabled = feature_enabled


## Show the non-junk gains. Returns true when the panel was updated.
func show_gains(gains: Dictionary) -> bool:
	if _panel == null:
		return false
	if not _feature_enabled.call(ModConfig.KEY_TRINKETS_GAINED_PANEL):
		hide()
		return false
	var shown_ids: Array = TrinketGains.displayable_ids(gains.get("ids", []), JUNK_TRINKET_ID)
	if shown_ids.is_empty():
		hide()
		return false
	_panel.show_gains(summarize(shown_ids, _formatter))
	return true


func hide() -> void:
	if _panel != null:
		_panel.hide_panel()


## Group ids into {name, count} entries, preserving first-seen order.
static func summarize(ids: Array, formatter) -> Array:
	var counts := {}
	for tid in ids:
		var key := str(tid)
		counts[key] = counts.get(key, 0) + 1

	var entries: Array = []
	for tid in counts.keys():
		entries.append({"name": formatter.format_trinket_name(tid), "count": int(counts[tid])})
	return entries
