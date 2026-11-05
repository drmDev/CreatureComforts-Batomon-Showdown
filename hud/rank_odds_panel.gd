extends "shop_modal_panel.gd"
## Shop rank odds table modal.

const BTN_SIZE := 20.0
const LEFT_MARGIN := 100.0
const BOTTOM_OFFSET_RATIO := 0.20  # Button bottom sits 20% of the viewport height above the bottom

const HEADER_ROW_H := 16.0
const HEADER_GAP := 2.0
const ROW_H := 14.0

const HEADER_FONT_SIZE := 8
const BODY_FONT_SIZE := 8

const COLUMN_FRACTIONS := [0.12, 0.16, 0.18, 0.14, 0.20, 0.20]
const HEADER_LABELS := ["Rank", "Common", "Uncommon", "Rare", "Super Rare", "Legendary"]

const RARITY_COLORS := Style.RARITY_COLORS
const HIGHLIGHT_COLOR := Style.HIGHLIGHT_COLOR

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


func set_rank(rank: int) -> void:
	_rank = clampi(rank, 1, 14)
	_ensure_visible()


func _button_size() -> float:
	return BTN_SIZE


func _button_texture_path() -> String:
	return "../assets/icons/rankChart.png"


func _button_position(viewport_size: Vector2) -> Vector2:
	return Vector2(LEFT_MARGIN, roundf(viewport_size.y * (1.0 - BOTTOM_OFFSET_RATIO) - BTN_SIZE))


func _popup_title() -> String:
	return "SHOP RANK ODDS"


func _popup_height() -> float:
	return TITLE_H + POPUP_PADDING + HEADER_ROW_H + HEADER_GAP + RANK_ODDS.size() * ROW_H + POPUP_PADDING


func _on_button_created() -> void:
	log_line.emit("RANK ODDS | button created | rank=%d" % _rank)


func _on_button_hidden() -> void:
	log_line.emit("RANK ODDS | button removed | leaving shop")


func _on_popup_opened() -> void:
	log_line.emit("RANK ODDS | popup opened | rank=%d" % _rank)


func _on_popup_closed() -> void:
	log_line.emit("RANK ODDS | popup closed")


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
	# \u2014 keeps the source plain ASCII (the auto-updater rejects non-ASCII scripts).
	return "\u2014" if pct == 0 else "%d%%" % pct
