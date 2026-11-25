extends "collapsible_panel.gd"
## Alerts tab content: the player's held one-shot trinket reminders.
##
## Embedded in hud/trinkets_panel.gd, which owns the frame, header, tabs and
## visibility. This view only paints rows and reports its natural size.

const TrinketGains = preload("../core/trinket_gains.gd")
const TextWrap = preload("../core/text_wrap.gd")

const CONTENT_PADDING := 6.0
const NAME_LINE_H := 14.0
const DESC_LINE_H := 13.0
const ROW_GAP := 5.0
const NAME_FONT_SIZE := 8
const DESC_FONT_SIZE := 7
const ICON_SIZE := 10.0
const ICON_GAP := 2.0
const QTY_GAP := 2.0
const ICON_Y_OFFSET := 2.0  # Nudge the icon down so it lines up with the text baseline


func full_height() -> float:
	var total := CONTENT_PADDING * 2.0
	if _entries.is_empty():
		return total
	var row_w := embedded_width - CONTENT_PADDING * 2.0 - 2.0
	for entry in _entries:
		total += NAME_LINE_H + DESC_LINE_H * _desc_line_count(entry, row_w) + ROW_GAP
	return total


## Show the current reminders. Unchanged content (every shop poll) is a no-op.
func show_reminders(entries: Array) -> void:
	var key := _make_content_key(entries)
	if key == _content_key:
		return
	_entries = entries
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


func _name_line(entry: Dictionary) -> String:
	return str(entry.get("name", ""))


func _qty_text(entry: Dictionary) -> String:
	return TrinketGains.qty_text(int(entry.get("count", 1)))


func _icon(entry: Dictionary) -> Texture2D:
	var icon = entry.get("icon")
	return icon if icon is Texture2D else null


func _make_content_key(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%dx %s | %s | %s" % [
			int(entry.get("count", 1)), str(entry.get("name", "")),
			str(entry.get("desc", "")), str(_icon(entry) != null)])
	return "|".join(parts)


func _desc_line_count(entry: Dictionary, row_w: float) -> int:
	return maxi(1, TextWrap.wrap(_text_font, str(entry.get("desc", "")), DESC_FONT_SIZE, row_w, true).size())


func _draw_body(width: float) -> void:
	var cursor_y := CONTENT_PADDING
	var row_w := width - CONTENT_PADDING * 2.0 - 2.0
	for entry in _entries:
		var name_baseline := cursor_y + NAME_LINE_H - 3.0
		var text_x := CONTENT_PADDING + 1.0
		var cursor_x := text_x
		var icon := _icon(entry)
		if icon != null:
			var icon_y := cursor_y + (NAME_LINE_H - ICON_SIZE) * 0.5 + ICON_Y_OFFSET
			draw_texture_rect(icon, Rect2(Vector2(cursor_x, icon_y), Vector2(ICON_SIZE, ICON_SIZE)), false)
			cursor_x += ICON_SIZE + ICON_GAP
		var qty := _qty_text(entry)
		if not qty.is_empty():
			_draw_text_shadow(Vector2(cursor_x, name_baseline), qty, VALUE_COLOR, NAME_FONT_SIZE)
			cursor_x += _text_font.get_string_size(qty, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x + QTY_GAP
		var name_line := _fit_text(_text_font, _name_line(entry), NAME_FONT_SIZE, row_w - (cursor_x - text_x))
		_draw_text_shadow(Vector2(cursor_x, name_baseline), name_line, VALUE_COLOR, NAME_FONT_SIZE)
		cursor_y += NAME_LINE_H
		for desc_line in TextWrap.wrap(_text_font, str(entry.get("desc", "")), DESC_FONT_SIZE, row_w, true):
			var desc_baseline := cursor_y + DESC_LINE_H - 3.0
			_draw_text_shadow(Vector2(text_x, desc_baseline), desc_line, LABEL_COLOR, DESC_FONT_SIZE)
			cursor_y += DESC_LINE_H
		cursor_y += ROW_GAP
