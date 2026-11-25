extends "collapsible_panel.gd"
## Gained tab content: trinkets acquired during the last battle.
##
## Gift content from a consumed Locked Box / Mysterious Chest is excluded
## upstream (it is applied after the frozen battle_over snapshot), so this view
## only receives legitimate gains.
##
## Embedded in hud/trinkets_panel.gd, which owns the frame, header, tabs and
## visibility. Content is cleared when the next battle starts or the run changes.

const TrinketGains = preload("../core/trinket_gains.gd")

const CONTENT_PADDING := 5.0
const ROW_HEIGHT := 14.0
const ROW_GAP := 1.0
const FONT_SIZE := 8
const ICON_SIZE := 10.0
const ICON_GAP := 2.0
const QTY_GAP := 2.0
const ICON_Y_OFFSET := 2.0  # Nudge the icon down so it lines up with the text baseline


func full_height() -> float:
	return CONTENT_PADDING * 2.0 + (ROW_HEIGHT + ROW_GAP) * float(_entries.size())


## Show the non-junk gains. Unchanged content (every poll) is a no-op.
func show_gains(entries: Array) -> void:
	var key := _make_content_key(entries)
	_entries = entries
	if key == _content_key:
		return
	_content_key = key
	_notify_layout()
	queue_redraw()


func hide_panel() -> void:
	if _entries.is_empty():
		return
	_entries.clear()
	_content_key = ""
	_notify_layout()
	queue_redraw()


func _make_content_key(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%dx %s | %s" % [
			int(entry.get("count", 0)), str(entry.get("name", "")), str(_icon(entry) != null)])
	return "|".join(parts)


func _icon(entry: Dictionary) -> Texture2D:
	var icon = entry.get("icon")
	return icon if icon is Texture2D else null


func _draw_body(_width: float) -> void:
	var cursor_y := CONTENT_PADDING
	for entry in _entries:
		var baseline := cursor_y + ROW_HEIGHT - 2.0
		var cursor_x := CONTENT_PADDING + 1.0
		var icon := _icon(entry)
		if icon != null:
			var icon_y := cursor_y + (ROW_HEIGHT - ICON_SIZE) * 0.5 + ICON_Y_OFFSET
			draw_texture_rect(icon, Rect2(Vector2(cursor_x, icon_y), Vector2(ICON_SIZE, ICON_SIZE)), false)
			cursor_x += ICON_SIZE + ICON_GAP
		var qty := TrinketGains.qty_text(int(entry.get("count", 0)))
		if not qty.is_empty():
			_draw_text_shadow(Vector2(cursor_x, baseline), qty, LABEL_COLOR, FONT_SIZE)
			cursor_x += _text_font.get_string_size(qty, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + QTY_GAP
		_draw_text_shadow(Vector2(cursor_x, baseline), str(entry.get("name", "")), LABEL_COLOR, FONT_SIZE)
		cursor_y += ROW_HEIGHT + ROW_GAP
