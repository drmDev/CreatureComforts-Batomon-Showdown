extends "table_modal_panel.gd"
## Shop rank odds table modal.

const TrinketIcons = preload("../core/trinket_icons.gd")

const LEFT_MARGIN := 100.0
const BOTTOM_OFFSET_RATIO := 0.20  # Button bottom sits 20% of the viewport height above the bottom

const COLUMN_FRACTIONS := [0.12, 0.16, 0.18, 0.14, 0.20, 0.20]
const HEADER_LABELS := ["Rank", "Common", "Uncommon", "Rare", "Super Rare", "Legendary"]

const RARITY_COLORS := Style.RARITY_COLORS

const CHECK_ROW_H := 16.0
const CHECK_ROW_GAP := 2.0
const CHECK_GAP := 4.0
const PLAIN_LURE_COMMON_BONUS := 20
const SWEET_LURE_COMMON_BONUS := 10
const SWEET_LURE_UNCOMMON_BONUS := 15
const RESEARCH_NOTES_LEGENDARY_BONUS := 30

const TRINKET_PLAIN_LURE := "plain_lure"
const TRINKET_SWEET_LURE := "sweet_lure"
const TRINKET_RESEARCH_NOTES := "research_notes"
const TRINKET_VIP_PASS := "vip_pass"
const TRINKET_ICON_SIZE := 12.0
const TRINKET_ICON_GAP := 4.0
const TRINKET_ICON_Y_OFFSET := -2.0  # Nudge the icon up so it lines up with the checkbox

## Rarity weight deltas are indexed like HEADER_LABELS without the Rank column:
## [Common, Uncommon, Rare, Super Rare, Legendary]. `ban` zeroes those indices.
const TRINKET_DEFS := [
	{"id": TRINKET_PLAIN_LURE, "label": "Plain Lure: +20 common weight", "tooltip": "Preview +20 Common weight", "delta": [PLAIN_LURE_COMMON_BONUS, 0, 0, 0, 0]},
	{"id": TRINKET_SWEET_LURE, "label": "Sweet Lure: +10 common, +15 uncommon weight", "tooltip": "Preview +10 Common and +15 Uncommon weight", "delta": [SWEET_LURE_COMMON_BONUS, SWEET_LURE_UNCOMMON_BONUS, 0, 0, 0]},
	{"id": TRINKET_RESEARCH_NOTES, "label": "Research Notes: +30 legendary weight", "tooltip": "Preview +30 Legendary weight", "delta": [0, 0, 0, 0, RESEARCH_NOTES_LEGENDARY_BONUS]},
	{"id": TRINKET_VIP_PASS, "label": "VIP Pass: Bans Commons and Uncommons", "tooltip": "Bans Common and Uncommon rarities", "ban": [0, 1]},
]

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
var _trinket_states: Array = []
var _trinket_checks: Array = []
var _trinket_icons: Array = []
var _blank_style: StyleBoxEmpty
var _held_trinket_ids: Array = []
var _trinket_icons_provider = null


func set_rank(rank: int, held_trinket_ids = []) -> void:
	_rank = clampi(rank, 1, 14)
	_held_trinket_ids = []
	if held_trinket_ids != null:
		for tid in held_trinket_ids:
			_held_trinket_ids.append(str(tid))
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


# --- Trinket preview ------------------------------------------------------------

## Recalculate a rank's rarity percentages from its base weights. `states` is a
## bool per TRINKET_DEFS entry; each enabled trinket applies its weight delta or
## ban to the base weights before the total is computed, so toggling never
## accumulates. Returns whole percentages (rounded), one per rarity column.
static func _row_percentages(row: Array, states: Array) -> Array:
	var weights := []
	for i in range(1, row.size()):
		weights.append(int(row[i]))
	for i in range(TRINKET_DEFS.size()):
		if not states[i]:
			continue
		var def: Dictionary = TRINKET_DEFS[i]
		if def.has("delta"):
			var delta: Array = def["delta"]
			for j in range(delta.size()):
				weights[j] += int(delta[j])
		if def.has("ban"):
			for j in def["ban"]:
				weights[j] = 0
	var total := 0
	for weight in weights:
		total += weight
	if total == 0:
		# No eligible rarity remains (ranks 1-3 with VIP Pass alone): show Rare.
		return [0, 0, 100, 0, 0]
	var percentages := []
	for weight in weights:
		percentages.append(roundi(weight * 100.0 / total))
	return percentages


## True when `id` (bare or "trinket_"-prefixed) is present in the held ids.
static func _owns_trinket(held_ids: Array, id: String) -> bool:
	for held in held_ids:
		var h := str(held)
		if h == id or h == "trinket_" + id:
			return true
	return false


func _ready() -> void:
	super._ready()
	_blank_style = StyleBoxEmpty.new()
	for i in range(TRINKET_DEFS.size()):
		var def: Dictionary = TRINKET_DEFS[i]
		_trinket_states.append(false)
		_trinket_icons.append(_build_trinket_icon())
		_trinket_checks.append(_build_modifier_check(def["label"], def["tooltip"], _on_trinket_toggled.bind(i)))


func _build_modifier_check(text: String, tooltip: String, handler: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.tooltip_text = tooltip
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_constant_override("icon_max_width", 12)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		check.add_theme_stylebox_override(state, _blank_style)
	if _text_font != null:
		check.add_theme_font_override("font", _text_font)
	check.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	check.toggled.connect(handler)
	check.visible = false
	add_child(check)
	check.size = check.get_combined_minimum_size()
	return check


## Fixed-size icon holder that keeps the trinket sprite's aspect ratio, matching
## the icon treatment in the saved-builds and trinket-reminder panels.
func _build_trinket_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(TRINKET_ICON_SIZE, TRINKET_ICON_SIZE)
	icon.size = Vector2(TRINKET_ICON_SIZE, TRINKET_ICON_SIZE)
	icon.visible = false
	add_child(icon)
	return icon


func _open_popup() -> void:
	for i in range(TRINKET_DEFS.size()):
		_trinket_states[i] = _owns_trinket(_held_trinket_ids, TRINKET_DEFS[i]["id"])
		if _trinket_checks[i] != null:
			_trinket_checks[i].set_pressed_no_signal(_trinket_states[i])
	_apply_trinket_icons()
	super._open_popup()


func _close_popup() -> void:
	super._close_popup()
	for i in range(_trinket_checks.size()):
		if _trinket_checks[i] != null:
			_trinket_checks[i].visible = false
		if _trinket_icons[i] != null:
			_trinket_icons[i].visible = false


func _on_trinket_toggled(on: bool, index: int) -> void:
	_trinket_states[index] = on
	queue_redraw()


func _apply_trinket_icons() -> void:
	if _trinket_icons_provider == null:
		_trinket_icons_provider = TrinketIcons.new()
	for i in range(TRINKET_DEFS.size()):
		if _trinket_icons[i] != null:
			_trinket_icons[i].texture = _trinket_icons_provider.icon(TRINKET_DEFS[i]["id"])


func _position_modifier_checks(rect: Rect2) -> void:
	var y := rect.position.y + TITLE_H + POPUP_PADDING
	var icon_x := rect.position.x + POPUP_PADDING
	var check_x := icon_x + TRINKET_ICON_SIZE + TRINKET_ICON_GAP
	var icon_y := y + (CHECK_ROW_H - TRINKET_ICON_SIZE) * 0.5 + TRINKET_ICON_Y_OFFSET
	for i in range(_trinket_checks.size()):
		var row_y := y + (CHECK_ROW_H + CHECK_ROW_GAP) * i
		if _trinket_icons[i] != null:
			_trinket_icons[i].visible = true
			_trinket_icons[i].position = Vector2(icon_x, icon_y + (CHECK_ROW_H + CHECK_ROW_GAP) * i)
		if _trinket_checks[i] != null:
			_trinket_checks[i].visible = true
			_trinket_checks[i].position = Vector2(check_x, row_y)


func _modifier_rows_height() -> float:
	return CHECK_ROW_H * TRINKET_DEFS.size() + CHECK_ROW_GAP * (TRINKET_DEFS.size() - 1)


func _popup_height() -> float:
	return super._popup_height() + _modifier_rows_height() + CHECK_GAP


func _draw_content(rect: Rect2) -> void:
	_position_modifier_checks(rect)
	var offset := _modifier_rows_height() + CHECK_GAP
	var table_rect := Rect2(
		rect.position + Vector2(0.0, offset),
		rect.size - Vector2(0.0, offset))
	_draw_table(table_rect)


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
	var pct: int = _row_percentages(row, _trinket_states)[column - 1]
	# \u2014 keeps the source plain ASCII (the auto-updater rejects non-ASCII scripts).
	return "\u2014" if pct == 0 else "%d%%" % pct
