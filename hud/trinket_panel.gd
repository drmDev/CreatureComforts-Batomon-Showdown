extends "collapsible_panel.gd"
## Gift content from a consumed Locked Box / Mysterious Chest is excluded upstream (it is
## applied after the frozen battle_over snapshot), so this panel only receives legitimate gains.
##
## The panel is shop-gated (it lives on the reminder layer), so the overlay gate holds it back
## through the results/event/gift screens and shows it once the shop is interactive. It stays
## visible until the player collapses it or starts the next battle, which hides and clears it.

const TrinketGains = preload("../core/trinket_gains.gd")

const PANEL_WIDTH := 185.0
const CONTENT_PADDING := 5.0
const ROW_HEIGHT := 14.0
const ROW_GAP := 1.0
const FONT_SIZE := 8
const HEADER_FONT_SIZE := 9  # Smaller than the shared TITLE_FONT_SIZE (11) for a compact header
const ICON_SIZE := 10.0
const ICON_GAP := 2.0
const QTY_GAP := 2.0
const ICON_Y_OFFSET := 2.0  # Nudge the icon down so it lines up with the text baseline

const MARGIN_RIGHT := 10.0
const MARGIN_BOTTOM := 130.0  # Leaves room for the shop's bottom-right controls / companion toast

# Anchor only the first time the panel is shown. Later battles reuse the position the player
# moved it to, so dragging it once is enough.
var _anchored := false


func full_height() -> float:
	return HEAD_H + CONTENT_PADDING + ROW_HEIGHT * float(_entries.size()) \
		+ ROW_GAP * float(_entries.size()) + CONTENT_PADDING


func header_text() -> String:
	return "Trinkets Gained"


## Idempotent: only the FIRST call (hidden -> visible) expands/un-minimizes the panel. Later
## calls with the same content do nothing, which preserves any drag position and the minimize
## animation. The panel never hides itself; see the header comment.
func show_gains(entries: Array) -> void:
	var key := _make_content_key(entries)
	var first_show := not visible
	_entries = entries
	if first_show:
		reveal = 1.0
		minimized = false
		_content_key = key
		_apply_size()
		if not _anchored:
			_anchor_bottom_right()
			_anchored = true
	elif key != _content_key:
		_content_key = key
		_apply_size()
	visible = true
	queue_redraw()


func hide_panel() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_entries.clear()
	_content_key = ""
	reveal = 1.0
	minimized = false
	visible = false
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


## Width of the [icon] [qty] [name] row, excluding the panel padding.
func _row_width(entry: Dictionary) -> float:
	var w := 0.0
	if _icon(entry) != null:
		w += ICON_SIZE + ICON_GAP
	var qty := TrinketGains.qty_text(int(entry.get("count", 0)))
	if not qty.is_empty():
		w += _text_font.get_string_size(qty, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + QTY_GAP
	w += _text_font.get_string_size(str(entry.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return w


func _apply_size() -> void:
	size = Vector2(_content_width(), lerpf(HEAD_H + 1.0, full_height(), reveal))


func _content_width() -> float:
	if _text_font == null:
		return PANEL_WIDTH
	var row_w := 0.0
	for entry in _entries:
		row_w = maxf(row_w, _row_width(entry))
	var body_min := row_w + CONTENT_PADDING * 2.0 + 2.0
	var title_w := _text_font.get_string_size(header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE).x
	# Tighter than the base header inset: the title starts 2 px inside the header and
	# leaves a 2 px gap before the -/+ button (see _draw_title), so the panel can be
	# narrower without ellipsizing the title.
	var header_min := title_w + BTN + 22.0
	return maxf(body_min, header_min)


func _anchor_bottom_right() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	position = Vector2(viewport_size.x - size.x - MARGIN_RIGHT, viewport_size.y - size.y - MARGIN_BOTTOM)


## Tighter title rect than the base: 2 px inside the header and a 2 px gap before the
## -/+ button, matching the header_min calculation in _content_width().
func _draw_title(_r: Rect2) -> void:
	var start_x := 9.0
	var max_w := button_rect().position.x - start_x - 2.0
	var t := _fit_text(_text_font, header_text(), HEADER_FONT_SIZE, max_w)
	var baseline := HEAD_H * 0.5 + 2.5
	_draw_text_shadow(Vector2(start_x, baseline), t, VALUE_COLOR, HEADER_FONT_SIZE)


func _draw_body(_width: float) -> void:
	var cursor_y := HEAD_H + CONTENT_PADDING
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


