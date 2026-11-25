extends "collapsible_panel.gd"
## Items Used panel: daily item usage and the run's aggregated item uses.
##
## Standalone collapsible panel (not embedded). It owns its drag position and
## collapse state, starts collapsed, and is shop-gated by the reminder layer.
## Content is pushed by hud/items_used_controller.gd whenever usage changes.

const CONTENT_PADDING := 6.0
const TODAY_LINE_H := 12.0
const SECTION_GAP := 6.0
const SECTION_LABEL_H := 12.0
const ROW_HEIGHT := 14.0
const ROW_GAP := 1.0
const FONT_SIZE := 8
const SECTION_FONT_SIZE := 7
const ICON_SIZE := 10.0
const ICON_GAP := 3.0
const QTY_GAP := 6.0
const ICON_Y_OFFSET := 2.0  # Nudge the icon down so it lines up with the text baseline
const PANEL_WIDTH := 200.0
const MAX_WIDTH := 280.0
const TAB_EXTRA_WIDTH := 30.0

# Sits below the Trinkets panel, which starts at 12.5% of the viewport height.
const LEFT_MARGIN := 55.0
const TOP_OFFSET_RATIO := 0.45

const MUTED_COLOR := Style.MUTED_COLOR
const SECTION_LABEL := "ITEMS USED THIS RUN"
const EMPTY_TEXT := "No items used yet"

var _day_used := 0
var _day_allowance := 0


func _init() -> void:
	super._init()
	clamp_to_viewport = true
	minimized = true
	reveal = 0.0
	# The panel always shows while its setting is on, including at zero uses.
	# Collapsed with no rows, the base would otherwise skip drawing the header.
	draw_when_empty = true


func _ready() -> void:
	_apply_size()
	_anchor_default()
	_connect_viewport_resize(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_apply_size()


## Center-free default spot: left side, below the Trinkets panel. Only used for
## the first show; dragging once keeps the player's position.
func _anchor_default() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var bounds := viewport.get_visible_rect().size
	position = Vector2(LEFT_MARGIN, bounds.y * TOP_OFFSET_RATIO)
	_clamp_to_viewport()


func header_text() -> String:
	return "Items Used"


func header_width() -> float:
	return _tab_width()


## Show the current snapshot. Unchanged content on later polls is a no-op, and
## the player's collapsed state and drag position are preserved.
func show_usage(snapshot: Dictionary) -> void:
	_day_used = int(snapshot.get("day_used", 0))
	_day_allowance = int(snapshot.get("day_allowance", 0))
	_entries = snapshot.get("entries", [])
	var key := _make_content_key()
	if key == _content_key and visible:
		return
	_content_key = key
	_apply_size()
	visible = true
	queue_redraw()


## Hide without dropping content or the player's collapse choice.
func hide_panel() -> void:
	if not visible:
		return
	if _tween != null:
		_tween.kill()
		_tween = null
	visible = false


func full_height() -> float:
	var rows := maxi(_entries.size(), 1)  # the empty state occupies one row
	return HEAD_H + CONTENT_PADDING + TODAY_LINE_H + SECTION_GAP + SECTION_LABEL_H \
		+ float(rows) * (ROW_HEIGHT + ROW_GAP) + CONTENT_PADDING


func _apply_size() -> void:
	var width := lerpf(_tab_width(), _content_width(), reveal)
	size = Vector2(width, lerpf(HEAD_H + 1.0, full_height(), reveal))
	_clamp_to_viewport()


func _tab_width() -> float:
	if _text_font == null:
		return PANEL_WIDTH
	var title_width := _text_font.get_string_size(header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	return title_width + BTN + TAB_EXTRA_WIDTH


func _content_width() -> float:
	if _text_font == null:
		return PANEL_WIDTH
	var today := _text_font.get_string_size(_today_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var inner := maxf(today, _text_font.get_string_size(SECTION_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, SECTION_FONT_SIZE).x)
	for entry in _entries:
		var row := ICON_SIZE + ICON_GAP
		row += _text_font.get_string_size(str(entry.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		row += QTY_GAP + _text_font.get_string_size(_qty_text(entry), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		inner = maxf(inner, row)
	return clampf(inner + CONTENT_PADDING * 2.0 + 2.0, _tab_width(), MAX_WIDTH)


func _make_content_key() -> String:
	var parts: Array[String] = [_today_text()]
	for entry in _entries:
		parts.append("%s %s" % [str(entry.get("id", "")), _qty_text(entry)])
	return "|".join(parts)


func _today_text() -> String:
	return "Today: %d / %d" % [_day_used, _day_allowance]


func _qty_text(entry: Dictionary) -> String:
	return "x%d" % int(entry.get("count", 0))


func _icon(entry: Dictionary) -> Texture2D:
	var icon = entry.get("icon")
	return icon if icon is Texture2D else null


func _draw_body(width: float) -> void:
	var x := CONTENT_PADDING + 1.0
	var cursor_y := HEAD_H + CONTENT_PADDING
	_draw_text_shadow(Vector2(x, cursor_y + TODAY_LINE_H - 3.0), _today_text(), VALUE_COLOR, FONT_SIZE)
	cursor_y += TODAY_LINE_H + SECTION_GAP
	_draw_text_shadow(Vector2(x, cursor_y + SECTION_LABEL_H - 3.0), SECTION_LABEL, BORDER_COLOR, SECTION_FONT_SIZE)
	cursor_y += SECTION_LABEL_H

	if _entries.is_empty():
		_draw_text_shadow(Vector2(x, cursor_y + ROW_HEIGHT - 3.0), EMPTY_TEXT, MUTED_COLOR, FONT_SIZE)
		return

	var right_edge := width - CONTENT_PADDING - 1.0
	for entry in _entries:
		var baseline := cursor_y + ROW_HEIGHT - 3.0
		var cursor_x := x
		var icon := _icon(entry)
		if icon != null:
			var icon_y := cursor_y + (ROW_HEIGHT - ICON_SIZE) * 0.5 + ICON_Y_OFFSET
			draw_texture_rect(icon, Rect2(Vector2(cursor_x, icon_y), Vector2(ICON_SIZE, ICON_SIZE)), false)
			cursor_x += ICON_SIZE + ICON_GAP
		var qty := _qty_text(entry)
		var qty_width := _text_font.get_string_size(qty, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		_draw_text_shadow(Vector2(right_edge - qty_width, baseline), qty, LABEL_COLOR, FONT_SIZE)
		var name_width := maxf(right_edge - qty_width - QTY_GAP - cursor_x, 0.0)
		var name := _fit_text(_text_font, str(entry.get("name", "")), FONT_SIZE, name_width)
		_draw_text_shadow(Vector2(cursor_x, baseline), name, VALUE_COLOR, FONT_SIZE)
		cursor_y += ROW_HEIGHT + ROW_GAP
