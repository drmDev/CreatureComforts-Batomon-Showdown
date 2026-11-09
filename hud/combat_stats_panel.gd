extends "collapsible_panel.gd"
## Post-battle combat statistics panel: player team vs opponent team.
##
## Two columns (player left, opponent right). Team totals are shown at the top
## with a comparison operator between them; each team's unit breakdown follows
## underneath as a compact one-row-per-unit table. The panel is collapsible and
## draggable (inherited) and starts centered near the bottom of the screen.
##
## Ported from BatoStats++ (hud/combat_stats_panel.gd) when that mod was merged
## into Creature Comforts. It uses this mod's collapsible_panel base as-is: the
## panel anchors once on its first show and afterwards only clamps to the
## viewport, so a position the player dragged it to is kept.

const CombatStats = preload("../core/combat_stats.gd")
const SpeciesIcons = preload("../core/species_icons.gd")

const PADDING := 4.0
const GUTTER := 16.0
const ROW_H := 9.0
const SECTION_GAP := 3.0
const ROW_FONT_SIZE := 6
const TAB_EXTRA_WIDTH := 30.0
const BOTTOM_MARGIN := 32.0

# Compact unit table (one row per unit). Numeric columns are right-aligned and a
# little wider than their text, so values keep clear space from the column to the
# left (notably SHLD and CAST, which must never appear merged).
const TABLE_FONT_SIZE := 5
const TABLE_ROW_H := 9.0
const COL_UNIT_W := 54.0
const COL_DMG_W := 22.0
const COL_STATUS_W := 28.0
const COL_HEAL_W := 22.0
const COL_SHLD_W := 22.0
const COL_CAST_W := 20.0
const COL_WIDTHS := [COL_UNIT_W, COL_DMG_W, COL_STATUS_W, COL_HEAL_W, COL_SHLD_W, COL_CAST_W]
const COL_LABELS := ["UNIT", "DMG", "STATUS", "HEAL", "SHLD", "CAST"]
const TABLE_WIDTH := COL_UNIT_W + COL_DMG_W + COL_STATUS_W + COL_HEAL_W + COL_SHLD_W + COL_CAST_W

# Monster sprite drawn at the start of the UNIT cell, so a row reads
# [icon] [name]. The slot is always reserved, even when no icon resolves, so the
# names of every row and both teams stay aligned.
const ICON_SIZE := 8.0
const ICON_GAP := 2.0
const ICON_Y_OFFSET := -0.5  # nudge the sprite up so it meets the text baseline
const NAME_W := COL_UNIT_W - ICON_SIZE - ICON_GAP

# Each team's half of the panel is exactly as wide as its unit table, so the team
# heading, the totals and the table all share one column of width COLUMN_WIDTH.
const COLUMN_WIDTH := TABLE_WIDTH

# Comparison operator colours: green when the player leads, red when behind.
const GT_COLOR := Style.COMPARE_GOOD
const LT_COLOR := Style.COMPARE_BAD
const EQ_COLOR := LABEL_COLOR
const ZERO_COLOR := Style.MUTED_COLOR
const ROW_ALT_COLOR := Style.ROW_ALT_COLOR
const DIVIDER_COLOR := Style.DIVIDER_COLOR

var _snapshot: Dictionary = {}
var _icons: Dictionary = {}  # species_key -> Texture2D (or null for a miss)
var _anchored := false
var _show_totals := true


func _ready() -> void:
	# The panel has no body rows, so the header must draw while collapsed.
	draw_when_empty = true
	clamp_to_viewport = true
	_connect_viewport_resize(_on_viewport_resized)
	_apply_size()
	_anchor_default()


func header_text() -> String:
	return "Combat Stats"


## Show or hide the summed team comparison at the top of the panel. The per-unit
## tables are always shown.
func set_show_totals(on: bool) -> void:
	if _show_totals == on:
		return
	_show_totals = on
	_apply_size()
	_reposition()
	queue_redraw()


## Show the panel with a captured snapshot. An empty snapshot hides it.
func show_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		hide_panel()
		return
	_snapshot = snapshot
	_resolve_icons()
	_apply_size()
	_reposition()
	visible = true
	# From now on the panel keeps the position it was shown at (and any drag),
	# so a later battle does not snap it back to the default spot.
	_anchored = true
	queue_redraw()


func hide_panel() -> void:
	if not visible:
		return
	visible = false
	_icons.clear()
	queue_redraw()


func full_height() -> float:
	if _snapshot.is_empty():
		return HEAD_H + PADDING * 2.0
	var player: Dictionary = _snapshot.get("player_team", {})
	var opponent: Dictionary = _snapshot.get("opponent_team", {})
	var totals_h := 0.0
	var divider_h := 0.0
	if _show_totals:
		totals_h = ROW_H + SECTION_GAP + CombatStats.METRIC_KEYS.size() * ROW_H + SECTION_GAP
		divider_h = 1.0 + SECTION_GAP
	var table_h := maxf(_table_height(player.get("units", [])), _table_height(opponent.get("units", [])))
	return HEAD_H + PADDING + totals_h + divider_h + table_h + PADDING


func header_width() -> float:
	return _tab_width()


## Size only. Position is handled by _reposition(), never per animation frame, so the
## panel does not creep while it expands or collapses.
func _apply_size() -> void:
	var w := lerpf(_tab_width(), _content_width(), reveal)
	size = Vector2(w, lerpf(HEAD_H + 1.0, full_height(), reveal))


func _content_width() -> float:
	return PADDING * 2.0 + COLUMN_WIDTH * 2.0 + GUTTER


func _tab_width() -> float:
	if _text_font == null:
		return _content_width()
	var title_w := _text_font.get_string_size(header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	return title_w + BTN + TAB_EXTRA_WIDTH


## Height of one team's table: a header row plus one row per unit (or one
## "(no units)" row when the team is empty).
func _table_height(units: Array) -> float:
	return TABLE_ROW_H * (1 + maxi(units.size(), 1))


func _left_col_x() -> float:
	return PADDING


func _gutter_x() -> float:
	return PADDING + COLUMN_WIDTH


func _right_col_x() -> float:
	return PADDING + COLUMN_WIDTH + GUTTER


func _draw_body(_width: float) -> void:
	if _snapshot.is_empty():
		return
	var player: Dictionary = _snapshot.get("player_team", {})
	var opponent: Dictionary = _snapshot.get("opponent_team", {})
	var y := HEAD_H + PADDING
	if _show_totals:
		_draw_text_shadow(Vector2(_left_col_x(), y + ROW_H - 2.0), "Player Team", LABEL_COLOR, ROW_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, COLUMN_WIDTH)
		_draw_text_shadow(Vector2(_right_col_x(), y + ROW_H - 2.0), "Opponent Team", LABEL_COLOR, ROW_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, COLUMN_WIDTH)
		y += ROW_H + SECTION_GAP

		var player_totals: Dictionary = player.get("totals", {})
		var opponent_totals: Dictionary = opponent.get("totals", {})
		for key in CombatStats.METRIC_KEYS:
			var label := CombatStats.metric_label(key)
			var pv = player_totals.get(key)
			var ov = opponent_totals.get(key)
			var op := CombatStats.compare(pv, ov)
			var left_text := "%s: %s" % [label, CombatStats.format_value(pv)]
			var right_text := "%s: %s" % [label, CombatStats.format_value(ov)]
			var baseline := y + ROW_H - 2.0
			_draw_text_shadow(Vector2(_left_col_x(), baseline), left_text, VALUE_COLOR, ROW_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, COLUMN_WIDTH)
			_draw_text_shadow(Vector2(_gutter_x(), baseline), op, _operator_color(op), ROW_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, GUTTER)
			_draw_text_shadow(Vector2(_right_col_x(), baseline), right_text, VALUE_COLOR, ROW_FONT_SIZE)
			y += ROW_H
		y += SECTION_GAP

		# Subtle divider between the team totals and the unit tables.
		draw_rect(Rect2(_left_col_x(), y, _content_width() - PADDING * 2.0, 1.0), DIVIDER_COLOR)
		y += 1.0 + SECTION_GAP

	_draw_table(player.get("units", []), _left_col_x(), y)
	_draw_table(opponent.get("units", []), _right_col_x(), y)


## X offset of a column within a table whose left edge is x. One source of truth
## for the header row and every unit row, so both teams share identical spacing.
func _column_x(x: float, index: int) -> float:
	var offset := 0.0
	for i in range(index):
		offset += COL_WIDTHS[i]
	return x + offset


## Resolve every unit's species icon once per snapshot, so _draw never touches
## GameDatabase. Misses are stored as null and not retried for this snapshot.
func _resolve_icons() -> void:
	_icons.clear()
	for team_key in ["player_team", "opponent_team"]:
		var team: Dictionary = _snapshot.get(team_key, {})
		for unit in team.get("units", []):
			var key := str(unit.get("species_key", "")).strip_edges()
			if key.is_empty() or _icons.has(key):
				continue
			_icons[key] = SpeciesIcons.icon_for(key)


## Draw one team's compact table: a single header row, then one row per unit.
func _draw_table(units: Array, x: float, y: float) -> void:
	# Header row: the unit name is left-aligned, every numeric column right-aligned.
	for col in range(COL_WIDTHS.size()):
		var align := HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		_draw_table_cell(_column_x(x, col), y, COL_WIDTHS[col], COL_LABELS[col], LABEL_COLOR, align)
	y += TABLE_ROW_H

	if units.is_empty():
		_draw_table_cell(x, y, TABLE_WIDTH, "(no units)", LABEL_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
		return

	var maxima := _metric_maxima(units)
	for i in range(units.size()):
		var unit: Dictionary = units[i]
		if i % 2 == 1:
			draw_rect(Rect2(x, y, TABLE_WIDTH, TABLE_ROW_H), ROW_ALT_COLOR)
		# Monster icon, then the name in the same cell.
		var icon = _icons.get(str(unit.get("species_key", "")).strip_edges())
		if icon is Texture2D:
			var icon_y := y + (TABLE_ROW_H - ICON_SIZE) * 0.5 + ICON_Y_OFFSET
			_draw_texture_fit(icon, Rect2(Vector2(x, icon_y), Vector2(ICON_SIZE, ICON_SIZE)))
		var unit_name := _display_name(str(unit.get("unit_name", "")))
		if unit_name.is_empty():
			unit_name = str(unit.get("unit_id", "?"))
		unit_name = _fit_text(_text_font, unit_name, TABLE_FONT_SIZE, NAME_W)
		_draw_table_cell(x + ICON_SIZE + ICON_GAP, y, NAME_W, unit_name, VALUE_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
		for col in range(CombatStats.METRIC_KEYS.size()):
			var key: String = CombatStats.METRIC_KEYS[col]
			var cell := col + 1
			_draw_metric_cell(_column_x(x, cell), y, COL_WIDTHS[cell], unit.get(key), maxima.get(key))
		y += TABLE_ROW_H


## Highest value per metric across a team's units (null when no unit has it).
func _metric_maxima(units: Array) -> Dictionary:
	var maxima := {}
	for key in CombatStats.METRIC_KEYS:
		var best = null
		for unit in units:
			var value = unit.get(key)
			if value == null:
				continue
			var number := float(value)
			if best == null or number > best:
				best = number
		maxima[key] = best
	return maxima


func _draw_table_cell(x: float, y: float, w: float, text: String, color: Color, align: int) -> void:
	var baseline := y + TABLE_ROW_H - 2.0
	_draw_text_shadow(Vector2(x, baseline), text, color, TABLE_FONT_SIZE, align, w)


## Numeric cell: right-aligned, thousands-separated, muted when zero or missing,
## green when it is the team's top value for that metric (ties all highlight).
func _draw_metric_cell(x: float, y: float, w: float, value, best) -> void:
	var text := CombatStats.format_value(value)
	var color := VALUE_COLOR
	if _is_zero(value):
		color = ZERO_COLOR
	elif best != null and value != null and is_equal_approx(float(value), float(best)):
		color = GT_COLOR
	_draw_table_cell(x, y, w, text, color, HORIZONTAL_ALIGNMENT_RIGHT)


func _is_zero(value) -> bool:
	if value == null:
		return true
	return is_zero_approx(float(value))


## Colour for a comparison operator: green when the player leads, red when behind.
func _operator_color(op: String) -> Color:
	if op == ">":
		return GT_COLOR
	if op == "<":
		return LT_COLOR
	return EQ_COLOR


## Show only the species segment of a name such as "monster.name.leafleap".
func _short_name(raw_name: String) -> String:
	var dot := raw_name.rfind(".")
	if dot >= 0 and dot + 1 < raw_name.length():
		return raw_name.substr(dot + 1)
	return raw_name


## Short name with its first character capitalised (e.g. "leafleap" -> "Leafleap").
func _display_name(raw_name: String) -> String:
	var short := _short_name(raw_name)
	if short.is_empty():
		return short
	return short.substr(0, 1).to_upper() + short.substr(1)


## After the content size changes: anchor to the default spot until the panel has
## been shown once, then keep the player's position but inside the viewport.
func _reposition() -> void:
	if not _anchored:
		_anchor_default()
	else:
		_clamp_to_viewport()


## Center the panel horizontally near the bottom of the viewport.
func _anchor_default() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var x := (viewport_size.x - size.x) * 0.5
	var y := viewport_size.y - size.y - BOTTOM_MARGIN
	position = Vector2(roundf(x), roundf(y))
	_clamp_to_viewport()


func _on_viewport_resized() -> void:
	_reposition()
