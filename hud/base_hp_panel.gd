extends "shop_modal_panel.gd"
## Shop base HP by day table modal, including the run's trinket/trainer HP bonus.

const BaseHp = preload("../core/base_hp.gd")

const BTN_SIZE := 20.0
# 22% across the viewport, 25 px above the rank-odds button's row.
const LEFT_RATIO := 0.22
# Same vertical row as the rank-odds button, then shifted up by UP_OFFSET_PX.
const BOTTOM_OFFSET_RATIO := 0.20
const UP_OFFSET_PX := 25.0

const HEADER_ROW_H := 16.0
const HEADER_GAP := 2.0
const ROW_H := 14.0

const HEADER_FONT_SIZE := 8
const BODY_FONT_SIZE := 8

# Day | Base HP | Total (base + the run's trinket/trainer HP bonus)
const COLUMN_FRACTIONS := [0.18, 0.40, 0.42]
const HEADER_LABELS := ["Day", "Base HP", "Total"]
const COLUMN_COLORS := [Style.VALUE_COLOR, Style.RARITY_RARE, Style.BORDER_COLOR]

const HIGHLIGHT_COLOR := Style.HIGHLIGHT_COLOR

var _day := 1
var _bonus := 0


func set_day(day: int, total_hp: int) -> void:
	_day = maxi(day, 1)
	_bonus = BaseHp.bonus(total_hp, _day)
	_ensure_visible()


func _button_size() -> float:
	return BTN_SIZE


func _button_texture_path() -> String:
	return "../assets/icons/heartChart.png"


func _button_position(viewport_size: Vector2) -> Vector2:
	return Vector2(roundf(viewport_size.x * LEFT_RATIO), roundf(viewport_size.y * (1.0 - BOTTOM_OFFSET_RATIO) - BTN_SIZE - UP_OFFSET_PX))


func _popup_title() -> String:
	return "BASE HP BY DAY"


func _popup_height() -> float:
	return TITLE_H + POPUP_PADDING + HEADER_ROW_H + HEADER_GAP + BaseHp.MAX_DAY * ROW_H + POPUP_PADDING


func _on_button_created() -> void:
	log_line.emit("BASE HP | button created | day=%d" % _day)


func _on_button_hidden() -> void:
	log_line.emit("BASE HP | button removed | leaving shop")


func _on_popup_opened() -> void:
	log_line.emit("BASE HP | popup opened | day=%d" % _day)


func _on_popup_closed() -> void:
	log_line.emit("BASE HP | popup closed")


func _draw_content(r: Rect2) -> void:
	_draw_table(r)


func _draw_table(r: Rect2) -> void:
	var inner_left := r.position.x + POPUP_PADDING
	var inner_w := r.size.x - POPUP_PADDING * 2.0
	var header_y := r.position.y + TITLE_H + POPUP_PADDING
	var columns := COLUMN_FRACTIONS.size()

	var x := inner_left
	for i in range(columns):
		var cw: float = inner_w * COLUMN_FRACTIONS[i]
		var color: Color = LABEL_COLOR if i == 0 else COLUMN_COLORS[i]
		_draw_text_shadow(Vector2(x, header_y + HEADER_ROW_H - TEXT_BASELINE_OFFSET), HEADER_LABELS[i], color, HEADER_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, cw)
		x += cw

	draw_line(Vector2(inner_left, header_y + HEADER_ROW_H), Vector2(inner_left + inner_w, header_y + HEADER_ROW_H), BORDER_COLOR, 1.0)

	var row_y := header_y + HEADER_ROW_H + HEADER_GAP
	for i in range(BaseHp.MAX_DAY):
		var day := i + 1
		var is_current := day == _day
		if is_current:
			draw_rect(Rect2(Vector2(inner_left, row_y), Vector2(inner_w, ROW_H)), HIGHLIGHT_COLOR)
		var cx := inner_left
		for column in range(columns):
			var cw: float = inner_w * COLUMN_FRACTIONS[column]
			var color: Color = LABEL_COLOR
			if is_current:
				color = COLUMN_COLORS[column]
			_draw_text_shadow(Vector2(cx, row_y + ROW_H - TEXT_BASELINE_OFFSET), _cell_text(day, column), color, BODY_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, cw)
			cx += cw
		row_y += ROW_H


func _cell_text(day: int, column: int) -> String:
	if column == 0:
		return str(day)
	if column == 1:
		return _format_hp(BaseHp.for_day(day))
	return _format_hp(BaseHp.with_bonus(day, _bonus))


func _format_hp(value: int) -> String:
	var s := str(value)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
