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
var _plain_lure := false
var _sweet_lure := false
var _research_notes := false
var _vip_pass := false
var _plain_lure_check: CheckBox
var _sweet_lure_check: CheckBox
var _research_notes_check: CheckBox
var _vip_pass_check: CheckBox
var _plain_lure_icon: TextureRect
var _sweet_lure_icon: TextureRect
var _research_notes_icon: TextureRect
var _vip_pass_icon: TextureRect
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

## Recalculate a rank's rarity percentages from its base weights. Plain Lure
## adds +20 Common; Sweet Lure adds +10 Common and +15 Uncommon; Research Notes
## adds +30 Legendary; VIP Pass zeroes Common and Uncommon. All are applied to
## the base weights before the total is computed, so toggling never accumulates.
## Returns whole percentages (rounded), one per rarity column.
static func _row_percentages(row: Array, plain_lure: bool, sweet_lure: bool, research_notes: bool, vip_pass: bool) -> Array:
	var weights := []
	for i in range(1, row.size()):
		weights.append(int(row[i]))
	if plain_lure:
		weights[0] += PLAIN_LURE_COMMON_BONUS
	if sweet_lure:
		weights[0] += SWEET_LURE_COMMON_BONUS
		weights[1] += SWEET_LURE_UNCOMMON_BONUS
	if research_notes:
		weights[4] += RESEARCH_NOTES_LEGENDARY_BONUS
	if vip_pass:
		weights[0] = 0
		weights[1] = 0
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
	_plain_lure_icon = _build_trinket_icon()
	_sweet_lure_icon = _build_trinket_icon()
	_research_notes_icon = _build_trinket_icon()
	_vip_pass_icon = _build_trinket_icon()
	_plain_lure_check = _build_modifier_check(
		"Plain Lure: +20 common weight",
		"Preview +20 Common weight",
		_on_plain_lure_toggled)
	_sweet_lure_check = _build_modifier_check(
		"Sweet Lure: +10 common, +15 uncommon weight",
		"Preview +10 Common and +15 Uncommon weight",
		_on_sweet_lure_toggled)
	_research_notes_check = _build_modifier_check(
		"Research Notes: +30 legendary weight",
		"Preview +30 Legendary weight",
		_on_research_notes_toggled)
	_vip_pass_check = _build_modifier_check(
		"VIP Pass: Bans Common, Uncommon",
		"Bans Common and Uncommon rarities",
		_on_vip_pass_toggled)


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
	_plain_lure = _owns_trinket(_held_trinket_ids, TRINKET_PLAIN_LURE)
	_sweet_lure = _owns_trinket(_held_trinket_ids, TRINKET_SWEET_LURE)
	_research_notes = _owns_trinket(_held_trinket_ids, TRINKET_RESEARCH_NOTES)
	_vip_pass = _owns_trinket(_held_trinket_ids, TRINKET_VIP_PASS)
	if _plain_lure_check != null:
		_plain_lure_check.set_pressed_no_signal(_plain_lure)
	if _sweet_lure_check != null:
		_sweet_lure_check.set_pressed_no_signal(_sweet_lure)
	if _research_notes_check != null:
		_research_notes_check.set_pressed_no_signal(_research_notes)
	if _vip_pass_check != null:
		_vip_pass_check.set_pressed_no_signal(_vip_pass)
	_apply_trinket_icons()
	super._open_popup()


func _close_popup() -> void:
	super._close_popup()
	if _plain_lure_check != null:
		_plain_lure_check.visible = false
	if _sweet_lure_check != null:
		_sweet_lure_check.visible = false
	if _research_notes_check != null:
		_research_notes_check.visible = false
	if _vip_pass_check != null:
		_vip_pass_check.visible = false
	if _plain_lure_icon != null:
		_plain_lure_icon.visible = false
	if _sweet_lure_icon != null:
		_sweet_lure_icon.visible = false
	if _research_notes_icon != null:
		_research_notes_icon.visible = false
	if _vip_pass_icon != null:
		_vip_pass_icon.visible = false


func _on_plain_lure_toggled(on: bool) -> void:
	_plain_lure = on
	queue_redraw()


func _on_sweet_lure_toggled(on: bool) -> void:
	_sweet_lure = on
	queue_redraw()


func _on_research_notes_toggled(on: bool) -> void:
	_research_notes = on
	queue_redraw()


func _on_vip_pass_toggled(on: bool) -> void:
	_vip_pass = on
	queue_redraw()


func _apply_trinket_icons() -> void:
	if _trinket_icons_provider == null:
		_trinket_icons_provider = TrinketIcons.new()
	_set_icon_texture(_plain_lure_icon, TRINKET_PLAIN_LURE)
	_set_icon_texture(_sweet_lure_icon, TRINKET_SWEET_LURE)
	_set_icon_texture(_research_notes_icon, TRINKET_RESEARCH_NOTES)
	_set_icon_texture(_vip_pass_icon, TRINKET_VIP_PASS)


func _set_icon_texture(icon: TextureRect, trinket_id: String) -> void:
	if icon == null:
		return
	icon.texture = _trinket_icons_provider.icon(trinket_id)


func _position_modifier_checks(rect: Rect2) -> void:
	var y := rect.position.y + TITLE_H + POPUP_PADDING
	var icon_x := rect.position.x + POPUP_PADDING
	var check_x := icon_x + TRINKET_ICON_SIZE + TRINKET_ICON_GAP
	var icon_y := y + (CHECK_ROW_H - TRINKET_ICON_SIZE) * 0.5 + TRINKET_ICON_Y_OFFSET
	if _plain_lure_icon != null:
		_plain_lure_icon.visible = true
		_plain_lure_icon.position = Vector2(icon_x, icon_y)
	if _plain_lure_check != null:
		_plain_lure_check.visible = true
		_plain_lure_check.position = Vector2(check_x, y)
	if _sweet_lure_icon != null:
		_sweet_lure_icon.visible = true
		_sweet_lure_icon.position = Vector2(icon_x, icon_y + CHECK_ROW_H + CHECK_ROW_GAP)
	if _sweet_lure_check != null:
		_sweet_lure_check.visible = true
		_sweet_lure_check.position = Vector2(check_x, y + CHECK_ROW_H + CHECK_ROW_GAP)
	if _research_notes_icon != null:
		_research_notes_icon.visible = true
		_research_notes_icon.position = Vector2(icon_x, icon_y + (CHECK_ROW_H + CHECK_ROW_GAP) * 2.0)
	if _research_notes_check != null:
		_research_notes_check.visible = true
		_research_notes_check.position = Vector2(check_x, y + (CHECK_ROW_H + CHECK_ROW_GAP) * 2.0)
	if _vip_pass_icon != null:
		_vip_pass_icon.visible = true
		_vip_pass_icon.position = Vector2(icon_x, icon_y + (CHECK_ROW_H + CHECK_ROW_GAP) * 3.0)
	if _vip_pass_check != null:
		_vip_pass_check.visible = true
		_vip_pass_check.position = Vector2(check_x, y + (CHECK_ROW_H + CHECK_ROW_GAP) * 3.0)


func _modifier_rows_height() -> float:
	return CHECK_ROW_H * 4.0 + CHECK_ROW_GAP * 3.0


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
	var pct: int = _row_percentages(row, _plain_lure, _sweet_lure, _research_notes, _vip_pass)[column - 1]
	# \u2014 keeps the source plain ASCII (the auto-updater rejects non-ASCII scripts).
	return "\u2014" if pct == 0 else "%d%%" % pct
