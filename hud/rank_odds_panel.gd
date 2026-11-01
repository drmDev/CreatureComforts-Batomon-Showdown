extends "comfort_panel.gd"

signal log_line(message: String)
## Emitted when the modal popup opens or closes, so sibling HUD widgets can hide.
signal popup_visibility_changed(open: bool)

const BTN_SIZE := 20.0
const LEFT_MARGIN := 100.0
const BOTTOM_OFFSET_RATIO := 0.20  # Button bottom sits 20% of the viewport height above the bottom

const POPUP_WIDTH := 320.0
const POPUP_PADDING := 8.0
const TITLE_H := 22.0
const HEADER_ROW_H := 16.0
const HEADER_GAP := 2.0
const ROW_H := 14.0
const CLOSE_BTN := 14.0
const VIEWPORT_MARGIN := 8.0
const TEXT_BASELINE_OFFSET := 4.0
const FALLBACK_VIEWPORT_SIZE := Vector2(1280, 720)

const TITLE_FONT_SIZE := 11
const HEADER_FONT_SIZE := 8
const BODY_FONT_SIZE := 8

const COLUMN_FRACTIONS := [0.12, 0.16, 0.18, 0.14, 0.20, 0.20]
const HEADER_LABELS := ["Rank", "Common", "Uncommon", "Rare", "Super Rare", "Legendary"]

const RARITY_COLORS := Style.RARITY_COLORS
const HEADER_BG := Style.HEADER_BG
const HIGHLIGHT_COLOR := Style.HIGHLIGHT_COLOR
const DIM_COLOR := Style.DIM_COLOR

# Rank 14 represents "14+" (the final row). 0 renders as an em dash.
const RANK_ODDS := [
	[1, 100, 0, 0, 0, 0],
	[2, 90, 10, 0, 0, 0],
	[3, 75, 25, 0, 0, 0],
	[4, 67, 30, 3, 0, 0],
	[5, 55, 30, 15, 0, 0],
	[6, 45, 32, 20, 3, 0],
	[7, 30, 40, 25, 5, 0],
	[8, 25, 30, 35, 10, 0],
	[9, 20, 25, 38, 15, 2],
	[10, 15, 20, 40, 20, 5],
	[11, 10, 20, 35, 25, 10],
	[12, 5, 15, 30, 35, 15],
	[13, 1, 10, 30, 39, 20],
	[14, 1, 2, 20, 47, 30],
]

var _rank := 1
var _popup_open := false
var _button_screen_pos := Vector2.ZERO

var _button_texture: Texture2D = null
var _button_style: StyleBoxFlat
var _popup_style: StyleBoxFlat
var _header_style: StyleBoxFlat
var _close_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false
	_setup_styles()
	_text_font = _build_panel_font()
	_button_texture = _load_texture("../assets/icons/rankChart.png")
	size = Vector2(BTN_SIZE, BTN_SIZE)


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)
	_anchor()


func _setup_styles() -> void:
	_button_style = _build_hud_box()

	_popup_style = StyleBoxFlat.new()
	_popup_style.bg_color = BG_COLOR
	_popup_style.border_color = BORDER_COLOR
	_popup_style.set_border_width_all(2)
	_popup_style.set_corner_radius_all(4)

	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = HEADER_BG
	_header_style.border_color = BORDER_COLOR
	_header_style.set_border_width_all(1)
	_header_style.set_corner_radius_all(4)

	_close_style = StyleBoxFlat.new()
	_close_style.bg_color = BORDER_COLOR
	_close_style.set_corner_radius_all(2)


func set_rank(rank: int) -> void:
	_rank = clampi(rank, 1, 14)
	if not visible:
		visible = true
		_anchor()
		log_line.emit("RANK ODDS | button created | rank=%d" % rank)
	queue_redraw()


func hide_panel() -> void:
	if _popup_open:
		_close_popup()
	if not visible:
		return
	visible = false
	log_line.emit("RANK ODDS | button removed | leaving shop")
	queue_redraw()


## Ensure the popup is closed on shop entry (safety net; hide_panel already closes it).
func reset_for_shop() -> void:
	if _popup_open:
		_close_popup()


func _anchor() -> void:
	var viewport_size := _viewport_size()
	_button_screen_pos = Vector2(LEFT_MARGIN, roundf(viewport_size.y * (1.0 - BOTTOM_OFFSET_RATIO) - BTN_SIZE))
	if _popup_open:
		position = Vector2.ZERO
		size = viewport_size
	else:
		position = _button_screen_pos
		size = Vector2(BTN_SIZE, BTN_SIZE)
	queue_redraw()


func _on_viewport_resized() -> void:
	_anchor()


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	return viewport.get_visible_rect().size if viewport != null else FALLBACK_VIEWPORT_SIZE


func _open_popup() -> void:
	if _popup_open:
		return
	_popup_open = true
	_anchor()
	grab_focus()
	log_line.emit("RANK ODDS | popup opened | rank=%d" % _rank)
	popup_visibility_changed.emit(true)
	queue_redraw()


func _close_popup() -> void:
	if not _popup_open:
		return
	_popup_open = false
	_anchor()
	log_line.emit("RANK ODDS | popup closed")
	popup_visibility_changed.emit(false)
	queue_redraw()


## Button rect in local coordinates (the control is button-sized when closed and
## viewport-sized when the popup is open).
func _button_rect() -> Rect2:
	if _popup_open:
		return Rect2(_button_screen_pos, Vector2(BTN_SIZE, BTN_SIZE))
	return Rect2(Vector2.ZERO, Vector2(BTN_SIZE, BTN_SIZE))


func _popup_rect() -> Rect2:
	var viewport_size := _viewport_size()
	var w := minf(POPUP_WIDTH, viewport_size.x - VIEWPORT_MARGIN * 2.0)
	var h := minf(_popup_height(), viewport_size.y - VIEWPORT_MARGIN * 2.0)
	var x := roundf((viewport_size.x - w) * 0.5)
	var y := roundf((viewport_size.y - h) * 0.5)
	return Rect2(Vector2(x, y), Vector2(w, h))


func _popup_height() -> float:
	return TITLE_H + POPUP_PADDING + HEADER_ROW_H + HEADER_GAP + RANK_ODDS.size() * ROW_H + POPUP_PADDING


func _close_rect() -> Rect2:
	var r := _popup_rect()
	return Rect2(
		Vector2(r.position.x + r.size.x - POPUP_PADDING - CLOSE_BTN, r.position.y + (TITLE_H - CLOSE_BTN) * 0.5),
		Vector2(CLOSE_BTN, CLOSE_BTN)
	)


func _draw() -> void:
	if _text_font == null:
		return
	if _popup_open:
		_draw_popup()
	_draw_button()


func _draw_button() -> void:
	var r := _button_rect()
	_button_style.draw(get_canvas_item(), r)
	if _button_texture != null:
		var pad := 2.0
		draw_texture_rect(_button_texture, Rect2(r.position + Vector2(pad, pad), r.size - Vector2(pad * 2.0, pad * 2.0)), false)
	else:
		_draw_text_shadow(r.position + Vector2(0.0, r.size.y - 6.0), "?", VALUE_COLOR, 10, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_popup() -> void:
	# Dim the shop behind the modal popup.
	draw_rect(Rect2(Vector2.ZERO, _viewport_size()), DIM_COLOR)

	var r := _popup_rect()
	_popup_style.draw(get_canvas_item(), r)

	var title_rect := Rect2(r.position, Vector2(r.size.x, TITLE_H))
	_header_style.draw(get_canvas_item(), title_rect)
	_draw_text_shadow(r.position + Vector2(POPUP_PADDING, TITLE_H - 6.0), "SHOP RANK ODDS", VALUE_COLOR, TITLE_FONT_SIZE)

	var close := _close_rect()
	_close_style.draw(get_canvas_item(), close)
	var c := close.get_center()
	draw_line(c + Vector2(-3, -3), c + Vector2(3, 3), BG_COLOR, 1.5)
	draw_line(c + Vector2(-3, 3), c + Vector2(3, -3), BG_COLOR, 1.5)

	_draw_table(r)


func _draw_table(r: Rect2) -> void:
	var inner_left := r.position.x + POPUP_PADDING
	var inner_w := r.size.x - POPUP_PADDING * 2.0
	var header_y := r.position.y + TITLE_H + POPUP_PADDING
	var columns := COLUMN_FRACTIONS.size()

	var x := inner_left
	for i in range(columns):
		var cw: float = inner_w * COLUMN_FRACTIONS[i]
		var color: Color = LABEL_COLOR if i == 0 else RARITY_COLORS[i - 1]
		_draw_text_shadow(Vector2(x, header_y + HEADER_ROW_H - TEXT_BASELINE_OFFSET), HEADER_LABELS[i], color, HEADER_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, cw)
		x += cw

	draw_line(Vector2(inner_left, header_y + HEADER_ROW_H), Vector2(inner_left + inner_w, header_y + HEADER_ROW_H), BORDER_COLOR, 1.0)

	var row_y := header_y + HEADER_ROW_H + HEADER_GAP
	for row in RANK_ODDS:
		var is_current := int(row[0]) == _rank
		if is_current:
			draw_rect(Rect2(Vector2(inner_left, row_y), Vector2(inner_w, ROW_H)), HIGHLIGHT_COLOR)
		var cx := inner_left
		for i in range(columns):
			var cw: float = inner_w * COLUMN_FRACTIONS[i]
			var color: Color = LABEL_COLOR
			if is_current:
				color = VALUE_COLOR if i == 0 else RARITY_COLORS[i - 1]
			_draw_text_shadow(Vector2(cx, row_y + ROW_H - TEXT_BASELINE_OFFSET), _cell_text(row, i), color, BODY_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, cw)
			cx += cw
		row_y += ROW_H


func _cell_text(row: Array, column: int) -> String:
	if column == 0:
		return "14+" if int(row[0]) == 14 else str(int(row[0]))
	var pct := int(row[column])
	return "—" if pct == 0 else "%d%%" % pct


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _popup_open:
			if _close_rect().has_point(event.position):
				_close_popup()
			elif not _popup_rect().has_point(event.position):
				_close_popup()  # Clicking the icon again or outside closes
			accept_event()
		elif _button_rect().has_point(event.position):
			_open_popup()
			accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _popup_open:
		_close_popup()
		accept_event()


func _unhandled_input(event) -> void:
	if _popup_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_popup()
		get_viewport().set_input_as_handled()
