extends "collapsible_panel.gd"
## Items Used panel: daily item usage and the run's aggregated item uses.
##
## Standalone collapsible panel (not embedded). It owns its drag position and
## collapse state, starts collapsed, and is shop-gated by the reminder layer.
## Content is pushed by hud/items_used_controller.gd whenever usage changes.

const SpeciesIcons = preload("../core/species_icons.gd")

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
const MAX_WIDTH := 300.0
const TAB_EXTRA_WIDTH := 30.0

# Ratacomb Stoner row pinned to the bottom of the expanded panel:
# [checkbox] [Ratacomb icon] Ratacomb Stoner [Green Stone icon] [?]
const CONTROLS_GAP := 6.0
const CONTROLS_HEIGHT := 16.0
const CHECKBOX_SIZE := 16.0
const ROW_ICON_SIZE := 10.0
## 25% larger than the Green Stone marker, rounded up.
const RATACOMB_ICON_SIZE := 13.0
const RATACOMB_ICON_RAISE := 1.0
## The Label is centred by the font's line box, which sits high against the
## boxed checkbox and "?" glyphs. Only the text is shifted, not the row.
const CONTROL_LABEL_DROP := 2.0
const CONTROL_ITEM_GAP := 3.0
## Click target for the "?" button; the glyph inside is capped at ROW_ICON_SIZE.
const TIPS_BUTTON_SIZE := 12.0
const CONTROL_LABEL := "Ratacomb Stoner"
const CONTROL_TOOLTIP := "Show Ratacomb / Green Stone strategy reminders."
const GREEN_STONE_ID := "green_stone"
const RATACOMB_SPECIES_ID := "ratacomb"
const QUESTION_ICON := "blueQMark.png"

# Sits below the Trinkets panel, which starts at 12.5% of the viewport height.
const LEFT_MARGIN := 55.0
const TOP_OFFSET_RATIO := 0.45

const MUTED_COLOR := Style.MUTED_COLOR
const SECTION_LABEL := "ITEMS USED THIS RUN"
const EMPTY_TEXT := "No items used yet"

var _day_used := 0
var _day_allowance := 0

var _config = null
var _item_icons = null
var _stoner_check: CheckBox = null
var _stoner_label: Label = null
var _ratacomb_icon: TextureRect = null
var _stone_icon: TextureRect = null
var _tips_button: Button = null
var _separator: ColorRect = null
var _tips_popup = null
var _stoner_row_rect := Rect2()


func _init() -> void:
	super._init()
	clamp_to_viewport = true
	minimized = true
	reveal = 0.0
	# The panel always shows while its setting is on, including at zero uses.
	# Collapsed with no rows, the base would otherwise skip drawing the header.
	draw_when_empty = true
	_build_controls()


## Ratacomb Stoner row: [checkbox] [Green Stone] Ratacomb Stoner [Green Stone] [?].
## All real controls childed to this panel; they show only while expanded.
func _build_controls() -> void:
	_separator = _build_horizontal_rule(self)

	_stoner_check = CheckBox.new()
	_stoner_check.text = ""
	_stoner_check.tooltip_text = CONTROL_TOOLTIP
	Style.blank_checkbox(_stoner_check, _text_font, FONT_SIZE)
	_stoner_check.toggled.connect(_on_stoner_toggled)
	add_child(_stoner_check)

	_ratacomb_icon = _make_row_icon()
	_stone_icon = _make_row_icon()

	_stoner_label = Label.new()
	_stoner_label.text = CONTROL_LABEL
	_stoner_label.tooltip_text = CONTROL_TOOLTIP
	_stoner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stoner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stoner_label.add_theme_color_override("font_color", LABEL_COLOR)
	_stoner_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if _text_font != null:
		_stoner_label.add_theme_font_override("font", _text_font)
	add_child(_stoner_label)

	_tips_button = Button.new()
	_tips_button.focus_mode = Control.FOCUS_NONE
	_tips_button.tooltip_text = "Green Stone tips"
	_tips_button.custom_minimum_size = Vector2(TIPS_BUTTON_SIZE, TIPS_BUTTON_SIZE)
	Style.compact_button(_tips_button)
	_tips_button.add_theme_font_size_override("font_size", FONT_SIZE)
	if _text_font != null:
		_tips_button.add_theme_font_override("font", _text_font)
	# The source glyph is 128x201 (taller than every other row icon), so square
	# it first: expand_icon then centres a square canvas instead of letting the
	# tall texture hug the button's left edge.
	var question_texture := PanelIcons.square_icon(str(get_script().resource_path), QUESTION_ICON)
	if question_texture != null:
		_tips_button.icon = question_texture
		_tips_button.expand_icon = true
		# Match the Green Stone marker rather than filling the button, which
		# compact_button's border + content margin would otherwise shrink to.
		_tips_button.add_theme_constant_override("icon_max_width", int(ROW_ICON_SIZE))
	else:
		_tips_button.text = "?"
	_tips_button.pressed.connect(_on_tips_pressed)
	add_child(_tips_button)


func _make_row_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	return icon


## Bind the shared config/icons so the checkbox and its Ratacomb/Green Stone
## markers reflect the current settings.
func setup(config, item_icons = null) -> void:
	_config = config
	_item_icons = item_icons
	if _stoner_check != null and _config != null:
		_stoner_check.set_pressed_no_signal(_config.ratacomb_stoner_enabled())
	_sync_row_icons()


func _sync_row_icons() -> void:
	if _ratacomb_icon != null and _ratacomb_icon.texture == null:
		_ratacomb_icon.texture = SpeciesIcons.icon_for(RATACOMB_SPECIES_ID)
	if _stone_icon != null and _stone_icon.texture == null and _item_icons != null:
		_stone_icon.texture = _item_icons.icon(GREEN_STONE_ID)


## The Green Stone tips popup is owned by the reminder layer (it must not be
## clipped by this panel).
func set_tips_popup(popup) -> void:
	_tips_popup = popup


func _on_stoner_toggled(pressed: bool) -> void:
	if _config != null:
		_config.set_ratacomb_stoner_enabled(pressed)


func _on_tips_pressed() -> void:
	if _tips_popup != null and is_instance_valid(_tips_popup):
		_tips_popup.toggle_popup()


## Clicking the label or the icons toggles the checkbox; clicks on the checkbox
## and the "?" button are handled by those children first.
func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _stoner_row_rect.size.x > 0.0 and _stoner_row_rect.has_point(event.position):
			_stoner_check.button_pressed = not _stoner_check.button_pressed
			accept_event()
			return
	super._gui_input(event)


func _ready() -> void:
	_apply_size()
	_anchor_default()
	_connect_viewport_resize(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_apply_size()


## Default spot: left side, below the Trinkets panel. Only used for the first
## show; dragging once keeps the player's position.
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
		+ float(rows) * (ROW_HEIGHT + ROW_GAP) \
		+ CONTROLS_GAP + CONTROLS_HEIGHT + CONTENT_PADDING


func _apply_size() -> void:
	var content_width := _content_width()
	size = Vector2(
		lerpf(_tab_width(), content_width, reveal),
		lerpf(HEAD_H + 1.0, full_height(), reveal))
	_layout_controls(content_width)
	_clamp_to_viewport()


func _layout_controls(width: float) -> void:
	# Retry the icons once the game database is available (setup may run first).
	_sync_row_icons()
	var show_controls := not minimized and reveal > 0.5
	_separator.visible = show_controls
	_stoner_check.visible = show_controls
	_stoner_label.visible = show_controls
	_ratacomb_icon.visible = show_controls
	_stone_icon.visible = show_controls
	_tips_button.visible = show_controls
	_stoner_row_rect = Rect2()
	if not show_controls or _text_font == null:
		return

	var y := full_height() - CONTENT_PADDING - CONTROLS_HEIGHT
	# Centred on the row, then raised by RATACOMB_ICON_RAISE to sit level with
	# the (dropped) label text.
	var ratacomb_y := y + (CONTROLS_HEIGHT - RATACOMB_ICON_SIZE) * 0.5 - RATACOMB_ICON_RAISE
	var stone_y := y + (CONTROLS_HEIGHT - ROW_ICON_SIZE) * 0.5
	var label_width := _text_font.get_string_size(CONTROL_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x

	_separator.position = Vector2(CONTENT_PADDING, y - CONTROLS_GAP * 0.5)
	_separator.size = Vector2(maxf(width - CONTENT_PADDING * 2.0, 1.0), 1.0)

	var x := CONTENT_PADDING
	_stoner_check.position = Vector2(x, y)
	_stoner_check.size = Vector2(CHECKBOX_SIZE, CONTROLS_HEIGHT)
	x += CHECKBOX_SIZE + CONTROL_ITEM_GAP
	_ratacomb_icon.position = Vector2(x, ratacomb_y)
	_ratacomb_icon.size = Vector2(RATACOMB_ICON_SIZE, RATACOMB_ICON_SIZE)
	x += RATACOMB_ICON_SIZE + CONTROL_ITEM_GAP
	_stoner_label.position = Vector2(x, y + CONTROL_LABEL_DROP)
	_stoner_label.size = Vector2(label_width, CONTROLS_HEIGHT)
	x += label_width + CONTROL_ITEM_GAP
	_stone_icon.position = Vector2(x, stone_y)
	_stone_icon.size = Vector2(ROW_ICON_SIZE, ROW_ICON_SIZE)
	x += ROW_ICON_SIZE + CONTROL_ITEM_GAP
	_tips_button.position = Vector2(x, y + (CONTROLS_HEIGHT - TIPS_BUTTON_SIZE) * 0.5)
	_tips_button.size = Vector2(TIPS_BUTTON_SIZE, TIPS_BUTTON_SIZE)

	# Label/icons click area (the checkbox and "?" handle their own clicks).
	_stoner_row_rect = Rect2(
		Vector2(CONTENT_PADDING, y),
		Vector2(x - CONTENT_PADDING, CONTROLS_HEIGHT))


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
	var controls := CHECKBOX_SIZE + CONTROL_ITEM_GAP \
		+ RATACOMB_ICON_SIZE + CONTROL_ITEM_GAP \
		+ _text_font.get_string_size(CONTROL_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x \
		+ CONTROL_ITEM_GAP + ROW_ICON_SIZE + CONTROL_ITEM_GAP + TIPS_BUTTON_SIZE
	inner = maxf(inner, controls)
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
