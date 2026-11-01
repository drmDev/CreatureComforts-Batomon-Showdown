extends "collapsible_panel.gd"
## Gift content from a consumed Locked Box / Mysterious Chest is excluded upstream (it is
## applied after the frozen battle_over snapshot), so this panel only receives legitimate gains.

const PANEL_WIDTH := 185.0
const CONTENT_PADDING := 5.0
const ROW_HEIGHT := 14.0
const ROW_GAP := 1.0
const FONT_SIZE := 8
const HEADER_FONT_SIZE := 9  # Smaller than the shared TITLE_FONT_SIZE (11) for a compact header

const DISPLAY_DURATION_MS := 8000  # Auto-hide after 8 seconds on the results screen
const MARGIN_RIGHT := 10.0
const MARGIN_BOTTOM := 130.0       # Leaves room for a bottom-right toast from a companion mod

var _hide_at_ms := 0


func full_height() -> float:
	return HEAD_H + CONTENT_PADDING + ROW_HEIGHT * float(_entries.size()) \
		+ ROW_GAP * float(_entries.size()) + CONTENT_PADDING


func header_text() -> String:
	return "Trinkets Gained"


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


func _make_content_key(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%dx %s" % [int(entry.get("count", 0)), str(entry.get("name", ""))])
	return "|".join(parts)


func _apply_size() -> void:
	size = Vector2(_content_width(), lerpf(HEAD_H + 1.0, full_height(), reveal))


func _content_width() -> float:
	if _text_font == null:
		return PANEL_WIDTH
	var row_w := 0.0
	for entry in _entries:
		var line := "%dx %s" % [int(entry.get("count", 0)), str(entry.get("name", ""))]
		row_w = maxf(row_w, _text_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
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
		var line := "%dx %s" % [int(entry.get("count", 0)), str(entry.get("name", ""))]
		_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, baseline), line, LABEL_COLOR, FONT_SIZE)
		cursor_y += ROW_HEIGHT + ROW_GAP


func _process(_delta: float) -> void:
	if visible and _hide_at_ms > 0 and Time.get_ticks_msec() >= _hide_at_ms:
		hide_panel()
