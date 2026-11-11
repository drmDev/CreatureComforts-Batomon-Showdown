extends "table_modal_panel.gd"
## Shop rank odds table modal.

const LEFT_MARGIN := 100.0
const BOTTOM_OFFSET_RATIO := 0.20  # Button bottom sits 20% of the viewport height above the bottom

const COLUMN_FRACTIONS := [0.12, 0.16, 0.18, 0.14, 0.20, 0.20]
const HEADER_LABELS := ["Rank", "Common", "Uncommon", "Rare", "Super Rare", "Legendary"]

const RARITY_COLORS := Style.RARITY_COLORS

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


func _button_texture_path() -> String:
	return "../assets/icons/rankChart.png"


func _button_position(viewport_size: Vector2) -> Vector2:
	var button := _button_size()
	return Vector2(LEFT_MARGIN, roundf(viewport_size.y * (1.0 - BOTTOM_OFFSET_RATIO) - button))


func _popup_title() -> String:
	return "SHOP RANK ODDS"


func _log_label() -> String:
	return "RANK ODDS"


func _log_detail() -> String:
	return "rank=%d" % _rank


# --- Table description ----------------------------------------------------------

func _table_row_count() -> int:
	return RANK_ODDS.size()


func _table_column_fractions() -> Array:
	return COLUMN_FRACTIONS


func _table_header_labels() -> Array:
	return HEADER_LABELS


func _table_header_color(column: int) -> Color:
	return LABEL_COLOR if column == 0 else RARITY_COLORS[column - 1]


func _table_current_row_color(column: int) -> Color:
	return VALUE_COLOR if column == 0 else RARITY_COLORS[column - 1]


func _table_current_row() -> int:
	return _rank - 1


func _table_cell_text(row_index: int, column: int) -> String:
	var row: Array = RANK_ODDS[row_index]
	if column == 0:
		return "14+" if int(row[0]) == 14 else str(int(row[0]))
	var pct := int(row[column])
	# \u2014 keeps the source plain ASCII (the auto-updater rejects non-ASCII scripts).
	return "\u2014" if pct == 0 else "%d%%" % pct
