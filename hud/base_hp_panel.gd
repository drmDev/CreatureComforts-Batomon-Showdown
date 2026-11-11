extends "table_modal_panel.gd"
## Shop base HP by day table modal, including the run's trinket/trainer HP bonus.

const BaseHp = preload("../core/base_hp.gd")

# 22% across the viewport, 25 px above the rank-odds button's row.
const LEFT_RATIO := 0.22
# Same vertical row as the rank-odds button, then shifted up by UP_OFFSET_PX.
const BOTTOM_OFFSET_RATIO := 0.20
const UP_OFFSET_PX := 25.0

# Day | Base HP | Total (base + the run's trinket/trainer HP bonus)
const COLUMN_FRACTIONS := [0.18, 0.40, 0.42]
const HEADER_LABELS := ["Day", "Base HP", "Total"]
const COLUMN_COLORS := [Style.VALUE_COLOR, Style.RARITY_RARE, Style.BORDER_COLOR]

var _day := 1
var _bonus := 0


func set_day(day: int, total_hp: int) -> void:
	_day = maxi(day, 1)
	_bonus = BaseHp.bonus(total_hp, _day)
	_ensure_visible()


func _button_texture_path() -> String:
	return "../assets/icons/heartChart.png"


func _button_position(viewport_size: Vector2) -> Vector2:
	var button := _button_size()
	return Vector2(roundf(viewport_size.x * LEFT_RATIO), roundf(viewport_size.y * (1.0 - BOTTOM_OFFSET_RATIO) - button - UP_OFFSET_PX))


func _popup_title() -> String:
	return "BASE HP BY DAY"


func _log_label() -> String:
	return "BASE HP"


func _log_detail() -> String:
	return "day=%d" % _day


# --- Table description ----------------------------------------------------------

func _table_row_count() -> int:
	return BaseHp.MAX_DAY


func _table_column_fractions() -> Array:
	return COLUMN_FRACTIONS


func _table_header_labels() -> Array:
	return HEADER_LABELS


func _table_header_color(column: int) -> Color:
	return LABEL_COLOR if column == 0 else COLUMN_COLORS[column]


func _table_current_row_color(column: int) -> Color:
	return COLUMN_COLORS[column]


func _table_current_row() -> int:
	return _day - 1


func _table_cell_text(row_index: int, column: int) -> String:
	var day := row_index + 1
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
