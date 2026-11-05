extends RefCounted
## Shows battle trinket gains on the panel.
##
## Extracted from mod_main.gd. Filters junk trinkets, summarizes duplicate ids,
## and respects the Trinkets Gained Panel feature toggle.
##
## Lifecycle: `apply_finalized` is called once per battle, when the battle state ends (which may
## be an event or gift screen). The panel is shop-gated, so the gains wait there until the player
## is back in the shop, then auto-hide after AUTO_HIDE_SEC (or sooner on collapse / the next
## battle). An empty result means "no battle was being tracked" and must NOT hide an already
## visible panel.

const TrinketGains = preload("../core/trinket_gains.gd")
const LogFormatterScript = preload("../core/log_formatter.gd")
const ModConfig = preload("../core/mod_config.gd")
const JUNK_TRINKET_ID := LogFormatterScript.JUNK_TRINKET_ID

var _panel = null
var _formatter = null
var _feature_enabled: Callable
var _icon_provider = null
# Bumped whenever the panel is hidden or re-shown, so a stale auto-hide timer
# cannot close a newer panel.
var _auto_hide_token := 0


func setup(panel, formatter, feature_enabled: Callable, icon_provider = null) -> void:
	_panel = panel
	_formatter = formatter
	_feature_enabled = feature_enabled
	_icon_provider = icon_provider


## Apply the result of a finished battle.
## - {} (nothing was tracked): leave the panel exactly as it is.
## - non-empty gains with show_panel: show them (or hide when nothing is displayable).
## - non-empty gains with show_panel == false (e.g. a trainer/run change): clear the panel.
## Returns true when the panel shows gains.
func apply_finalized(gains: Dictionary, show_panel := true) -> bool:
	if gains.is_empty():
		return false
	if not show_panel:
		hide()
		return false
	return show_gains(gains)


## Hide and clear the panel when a new battle starts; gains from the previous battle are stale.
func on_battle_started() -> void:
	hide()


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
	var entries := summarize(shown_ids, _formatter)
	TrinketGains.attach_icons(entries, _icon_provider)
	_panel.show_gains(entries)
	_start_auto_hide()
	return true


func hide() -> void:
	_auto_hide_token += 1
	if _panel != null:
		_panel.hide_panel()


## Hide the panel after AUTO_HIDE_SEC of being actually visible. The panel is
## shop-gated, so it can be marked visible during the results/event screens while
## the reminder layer is still hidden; waiting for is_visible_in_tree() gives the
## player the full countdown once the shop opens instead of counting through
## those screens.
func _start_auto_hide() -> void:
	_auto_hide_token += 1
	# Tests use a plain RefCounted stand-in for the panel; only a real Control
	# can report visibility and own a SceneTreeTimer.
	if not (_panel is CanvasItem):
		return
	_auto_hide_after_visible(_auto_hide_token)


func _auto_hide_after_visible(token: int) -> void:
	while token == _auto_hide_token and _panel is CanvasItem and _panel.get_tree() != null:
		if _panel.is_visible_in_tree():
			break
		await _panel.get_tree().create_timer(0.25).timeout
	if token != _auto_hide_token or not (_panel is CanvasItem) or _panel.get_tree() == null:
		return
	await _panel.get_tree().create_timer(TrinketGains.AUTO_HIDE_SEC).timeout
	if token == _auto_hide_token:
		hide()


## Group ids into {id, name, count} entries, highest quantity first. Ties keep
## first-seen order.
static func summarize(ids: Array, formatter) -> Array:
	var counts := {}
	for tid in ids:
		var key := str(tid)
		counts[key] = counts.get(key, 0) + 1

	var entries: Array = []
	for tid in counts.keys():
		entries.append({"id": tid, "name": formatter.format_trinket_name(tid), "count": int(counts[tid])})
	return TrinketGains.sort_by_count_desc(entries)


