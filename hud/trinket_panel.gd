extends "collapsible_panel.gd"
## TrinketPanel - Collapsible panel showing non-junk trinkets earned during a battle.
##
## Appears bottom-right when the battle state ends and the panel is shown, and auto-hides
## after a few seconds. It only shows when at least one non-junk trinket was earned; that
## filtering is done by mod_main before calling show_gains().
##
## Gift content from a consumed Locked Box / Mysterious Chest is excluded upstream (it is
## applied after the frozen battle_over snapshot), so this panel only receives legitimate gains.
##
## Collapsible header mechanics (header bar, -/+ toggle, drag, animated reveal, shared styling)
## live in collapsible_panel.gd. This subclass supplies the bottom-right anchoring, the
## single-line "Nx name" rows, and the results-screen auto-hide timer.

const PANEL_WIDTH := 185.0
const CONTENT_PADDING := 6.0
const ROW_HEIGHT := 16.0
const ROW_GAP := 2.0
const FONT_SIZE := 10

# Display
const DISPLAY_DURATION_MS := 8000  # Auto-hide after 8 seconds on the results screen
const MARGIN_RIGHT := 10.0
const MARGIN_BOTTOM := 130.0       # Leaves room for a bottom-right toast from a companion mod

var _hide_at_ms := 0


## Height of the panel when fully expanded (depends on the number of entries).
func full_height() -> float:
	return HEAD_H + CONTENT_PADDING + ROW_HEIGHT * float(_entries.size()) \
		+ ROW_GAP * float(_entries.size()) + CONTENT_PADDING


## Header title (between the left edge and the -/+ button).
func header_text() -> String:
	return "Trinkets Gained"


## Show the panel with the given (already non-junk filtered) entries.
## entries: Array of Dictionary {"name": String, "count": int}
##
## Idempotent: only the FIRST call (hidden -> visible) anchors the panel. Later calls with the
## same content do nothing, which preserves any drag position and the minimize animation.
func show_gains(entries: Array) -> void:
	var key := _make_content_key(entries)
	var first_show := not visible
	_entries = entries
	if first_show:
		# Start each battle expanded and positioned above the bottom-right toast area.
		reveal = 1.0
		minimized = false
		_content_key = key
		_apply_size()
		_anchor_bottom_right()
	elif key != _content_key:
		_content_key = key
		_apply_size()
	_hide_at_ms = Time.get_ticks_msec() + DISPLAY_DURATION_MS
	visible = true
	queue_redraw()


## Hide the panel immediately.
func hide_panel() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_entries.clear()
	_content_key = ""
	reveal = 1.0
	minimized = false
	_hide_at_ms = 0
	visible = false
	queue_redraw()


## Stable, ordered text key used to detect whether the displayed rows changed.
func _make_content_key(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%dx %s" % [int(entry.get("count", 0)), str(entry.get("name", ""))])
	return "|".join(parts)


func _apply_size() -> void:
	# Keep the width we were set to (or a default) and animate height between header-only and full.
	var w := size.x
	if w <= 0.0:
		w = PANEL_WIDTH
	size = Vector2(w, lerpf(HEAD_H + 1.0, full_height(), reveal))


func _anchor_bottom_right() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	position = Vector2(viewport_size.x - size.x - MARGIN_RIGHT, viewport_size.y - size.y - MARGIN_BOTTOM)


## Single-line rows: "Nx Name".
func _draw_body(_width: float) -> void:
	var cursor_y := HEAD_H + CONTENT_PADDING
	for entry in _entries:
		var baseline := cursor_y + ROW_HEIGHT - 2.0
		var line := "%dx %s" % [entry.count, entry.name]
		_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, baseline), line, LABEL_COLOR, FONT_SIZE)
		cursor_y += ROW_HEIGHT + ROW_GAP


func _process(_delta: float) -> void:
	if visible and _hide_at_ms > 0 and Time.get_ticks_msec() >= _hide_at_ms:
		hide_panel()
