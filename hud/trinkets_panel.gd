extends "collapsible_panel.gd"
## Unified Trinkets panel: one movable, collapsible panel with three tabs.
##
## Alerts  - held one-shot trinket reminders (hud/trinket_reminders_panel.gd)
## Gained  - trinkets acquired during the last battle (hud/trinket_panel.gd)
## Bonuses - positional and economical trinket summary (hud/positional_trinkets_panel.gd)
##
## The three feature panels stay independent and only render their bodies into
## this panel; it owns dragging, collapsing, tab selection, scrolling, and the
## activity indicators. Tab activity reuses the Watchlist's blue dot
## (hud/tracked_dot.gd).

const TrinketRemindersPanel = preload("trinket_reminders_panel.gd")
const TrinketPanel = preload("trinket_panel.gd")
const PositionalTrinketsPanel = preload("positional_trinkets_panel.gd")
const TrackedDot = preload("tracked_dot.gd")

const TAB_ALERTS := "alerts"
const TAB_GAINED := "gained"
const TAB_BONUSES := "bonuses"
const TABS := [TAB_ALERTS, TAB_GAINED, TAB_BONUSES]
const TAB_LABELS := {
	TAB_ALERTS: "Alerts",
	TAB_GAINED: "Gained",
	TAB_BONUSES: "Bonuses",
}

const PANEL_WIDTH := 260.0
const MIN_PANEL_WIDTH := 180.0
const TAB_BAR_HEIGHT := 14.0
const TAB_FONT_SIZE := 8
# Header geometry mirrored from collapsible_panel._draw: the title starts at
# TITLE_LEFT and stops TITLE_RIGHT_INSET before the minimize button.
const TITLE_LEFT := 12.0
const TITLE_RIGHT_INSET := 16.0
const TAB_PADDING := 3.0
const TAB_DOT_INSET := 3.0
const DOT_SIZE := 4.0
const DOT_GAP := 2.0
const BODY_BOTTOM_PADDING := 3.0
const MIN_BODY_HEIGHT := 18.0
const MAX_BODY_HEIGHT_RATIO := 0.6
const SCROLL_STEP := 24.0
const SCROLLBAR_WIDTH := 2.0
const SCROLLBAR_INSET := 2.0

# Left-aligned with the reminder label, matching the old reminders panel.
const LEFT_MARGIN := 55.0
const TOP_OFFSET_RATIO := 0.125
const FALLBACK_TOP_OFFSET := 100.0

## Tab content views. The controllers keep talking to these independently.
var alerts_view = null
var gained_view = null
var bonuses_view = null

var _tab := TAB_ALERTS
## Activity dot state per tab. Bonuses never flags, so it has no entry.
var _dots := {TAB_ALERTS: false, TAB_GAINED: false}
var _scroll := 0.0
var _config = null
var _feature_enabled := true
var _gained_flagged := false
var _gained_seen_key := ""

var _tab_style: StyleBoxFlat
var _tab_selected_style: StyleBoxFlat
var _tab_dots: Array = []
var _header_dot: Control = null


func _init() -> void:
	super._init()
	clamp_to_viewport = true
	draw_when_empty = true
	_setup_tab_styles()
	alerts_view = _make_view(TrinketRemindersPanel.new())
	gained_view = _make_view(TrinketPanel.new())
	bonuses_view = _make_view(PositionalTrinketsPanel.new())
	for _index in range(TABS.size()):
		var dot := TrackedDot.new()
		dot.size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.visible = false
		add_child(dot)
		_tab_dots.append(dot)
	_header_dot = TrackedDot.new()
	_header_dot.size = Vector2(DOT_SIZE, DOT_SIZE)
	_header_dot.visible = false
	add_child(_header_dot)


func _setup_tab_styles() -> void:
	_tab_style = StyleBoxFlat.new()
	_tab_style.bg_color = BG_COLOR
	_tab_style.border_color = BORDER_COLOR
	_tab_style.set_border_width_all(1)
	_tab_style.set_corner_radius_all(2)
	_tab_style.set_content_margin_all(1)

	_tab_selected_style = _tab_style.duplicate()
	_tab_selected_style.bg_color = BORDER_COLOR
	_tab_selected_style.border_color = BORDER_COLOR


## Bind the shared configuration so the last selected tab survives sessions.
func setup(config) -> void:
	_config = config
	if _config == null:
		return
	var stored := str(_config.trinkets_tab())
	if TABS.has(stored):
		_tab = stored


func _make_view(view):
	view.embedded = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.visible = true
	add_child(view)
	view.layout_changed.connect(_on_view_layout_changed)
	return view


func _ready() -> void:
	var top := FALLBACK_TOP_OFFSET
	var viewport := get_viewport()
	if viewport != null:
		top = viewport.get_visible_rect().size.y * TOP_OFFSET_RATIO
	position = Vector2(LEFT_MARGIN, top)
	minimized = true
	reveal = 0.0
	_connect_viewport_resize(_on_viewport_resized)
	_sync_indicators()
	_apply_size()


func _on_viewport_resized() -> void:
	_apply_size()


func header_text() -> String:
	return "Trinkets"


func selected_tab() -> String:
	return _tab


func alerts_indicator_visible() -> bool:
	return bool(_dots.get(TAB_ALERTS, false))


func gained_indicator_visible() -> bool:
	return bool(_dots.get(TAB_GAINED, false))


## The collapsed header dot: on while any tab still needs attention.
func header_indicator_visible() -> bool:
	return alerts_indicator_visible() or gained_indicator_visible()


## Switch tabs, keeping the panel position and persisting the choice.
func select_tab(tab: String) -> void:
	if not TABS.has(tab):
		return
	_tab = tab
	_scroll = 0.0
	if tab == TAB_GAINED:
		_gained_seen_key = gained_view.content_key()
		_gained_flagged = false
	_sync_indicators()
	if _config != null:
		_config.set_trinkets_tab(tab)
	_apply_size()


## Show or hide the panel with the Trinkets Panel setting. Content collection
## continues either way, so re-enabling shows the current state immediately.
func set_enabled(on: bool) -> void:
	_feature_enabled = on
	if not on:
		visible = false
		return
	refresh_for_shop()


## Re-evaluate visibility from the current tab content. Called on each shop poll
## because the defensive phase hide is not undone by unchanged content.
func refresh_for_shop() -> void:
	if not _feature_enabled:
		visible = false
		return
	_sync_indicators()
	visible = _any_content()
	if visible:
		_apply_size()


## Hide without dropping content: the gains must survive results/event screens.
func hide_panel() -> void:
	visible = false


func _any_content() -> bool:
	return alerts_view.has_content() or gained_view.has_content() or bonuses_view.has_content()


func _view_for(tab: String):
	if tab == TAB_GAINED:
		return gained_view
	if tab == TAB_BONUSES:
		return bonuses_view
	return alerts_view


func _on_view_layout_changed() -> void:
	_sync_indicators()
	visible = _feature_enabled and _any_content()
	_apply_size()


## Recompute the tab dots. Alerts follow the live reminder list; Gained is
## flagged once per new reward set and cleared when its tab is opened.
func _sync_indicators() -> void:
	_dots[TAB_ALERTS] = alerts_view.has_content()
	_dots[TAB_GAINED] = _gained_needs_dot()


func _gained_needs_dot() -> bool:
	if not gained_view.has_content():
		_gained_seen_key = ""
		_gained_flagged = false
		return false
	# Open on the Gained tab: the player is looking at the rewards already.
	if _tab == TAB_GAINED:
		_gained_seen_key = gained_view.content_key()
		_gained_flagged = false
		return false
	if _gained_flagged:
		return true
	if gained_view.content_key() != _gained_seen_key:
		_gained_flagged = true
	return _gained_flagged


func _panel_width() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return PANEL_WIDTH
	var available := viewport.get_visible_rect().size.x - 16.0
	return minf(PANEL_WIDTH, maxf(available, MIN_PANEL_WIDTH))


func _max_body_height() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return MIN_BODY_HEIGHT
	var cap := viewport.get_visible_rect().size.y * MAX_BODY_HEIGHT_RATIO - HEAD_H - TAB_BAR_HEIGHT
	return maxf(cap, MIN_BODY_HEIGHT)


func _body_natural_height(width: float) -> float:
	return maxf(_view_for(_tab).embedded_height(width), MIN_BODY_HEIGHT)


func _visible_body_height(width: float) -> float:
	return minf(_body_natural_height(width), _max_body_height())


func full_height() -> float:
	var width := _panel_width()
	return HEAD_H + TAB_BAR_HEIGHT + _visible_body_height(width) + BODY_BOTTOM_PADDING


## Width of the header bar when fully collapsed: just the title plus the
## minimize button (and the activity dot when it is shown).
func _tab_width() -> float:
	if _text_font == null:
		return MIN_PANEL_WIDTH
	var title_w := _text_font.get_string_size(header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	return title_w + 8.0 + BTN + 3.0 + TITLE_RIGHT_INSET + _header_dot_reserve()


func _header_dot_reserve() -> float:
	return DOT_SIZE + DOT_GAP if header_indicator_visible() else 0.0


## The panel is only as wide as its collapsed header while collapsed, then
## grows to the content width as it expands (and shrinks back on collapse).
func _apply_size() -> void:
	var width := _panel_width()
	size = Vector2(
		lerpf(_tab_width(), width, reveal),
		lerpf(HEAD_H + 1.0, full_height(), reveal))
	_layout(width)
	_clamp_to_viewport()
	queue_redraw()


func _layout(width: float) -> void:
	var visible_body := _visible_body_height(width)
	var body_top := HEAD_H + TAB_BAR_HEIGHT
	var natural := _body_natural_height(width)
	_scroll = clampf(_scroll, 0.0, maxf(0.0, natural - visible_body))
	for tab in TABS:
		var view = _view_for(tab)
		view.size = Vector2(width, maxf(view.embedded_height(width), MIN_BODY_HEIGHT))
		view.position = Vector2(0.0, body_top - _scroll)
		view.visible = _feature_enabled and not minimized and tab == _tab
	_layout_dots(width)


func _layout_dots(width: float) -> void:
	for index in range(TABS.size()):
		var dot: Control = _tab_dots[index]
		var rect := _tab_rect(index, width)
		dot.visible = bool(_dots.get(TABS[index], false)) and not minimized and reveal > 0.5
		dot.size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.position = Vector2(
			rect.position.x + rect.size.x - DOT_SIZE - TAB_DOT_INSET,
			rect.position.y + TAB_DOT_INSET)
	_header_dot.visible = header_indicator_visible() and (minimized or reveal < 0.5)
	_header_dot.size = Vector2(DOT_SIZE, DOT_SIZE)
	_header_dot.position = Vector2(_title_end_x() + DOT_GAP, (HEAD_H - DOT_SIZE) * 0.5)


func _tab_rect(index: int, width: float) -> Rect2:
	var inner := maxf(width - TAB_PADDING * 2.0, 1.0)
	var tab_w := inner / float(TABS.size())
	return Rect2(
		Vector2(TAB_PADDING + tab_w * float(index), HEAD_H + 1.0),
		Vector2(tab_w, TAB_BAR_HEIGHT))


## X where the header title text ends (the collapsed dot sits just past it).
func _title_end_x() -> float:
	if _text_font == null:
		return TITLE_LEFT
	var r := Rect2(Vector2(TITLE_LEFT, 0), Vector2(button_rect().position.x - TITLE_RIGHT_INSET, HEAD_H))
	var text := _fit_text(_text_font, header_text(), TITLE_FONT_SIZE, r.size.x - _header_dot_reserve())
	return r.position.x + _text_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x


func _tab_index_at(pos: Vector2) -> int:
	if minimized or reveal < 0.5:
		return -1
	if pos.y < HEAD_H + 1.0 or pos.y > HEAD_H + 1.0 + TAB_BAR_HEIGHT:
		return -1
	var width := _panel_width()
	for index in range(TABS.size()):
		if _tab_rect(index, width).has_point(pos):
			return index
	return -1


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _scroll_by(-SCROLL_STEP):
				accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _scroll_by(SCROLL_STEP):
				accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var index := _tab_index_at(event.position)
			if index >= 0:
				select_tab(TABS[index])
				accept_event()
				return
	super._gui_input(event)


func _scroll_by(delta: float) -> bool:
	var width := _panel_width()
	var max_scroll := maxf(0.0, _body_natural_height(width) - _visible_body_height(width))
	if max_scroll <= 0.0:
		return false
	var next := clampf(_scroll + delta, 0.0, max_scroll)
	if is_equal_approx(next, _scroll):
		return false
	_scroll = next
	_layout(width)
	queue_redraw()
	return true


func _draw_title(r: Rect2) -> void:
	var text := header_text()
	if _text_font == null:
		return
	var fitted := _fit_text(_text_font, text, TITLE_FONT_SIZE, r.size.x - _header_dot_reserve())
	var baseline := r.position.y + HEAD_H * 0.5 + 3.0
	_draw_text_shadow(Vector2(r.position.x, baseline), fitted, VALUE_COLOR, TITLE_FONT_SIZE)


func _draw_body(width: float) -> void:
	for index in range(TABS.size()):
		_draw_tab(index, width)
	_draw_scrollbar(width)


func _draw_tab(index: int, width: float) -> void:
	var tab: String = TABS[index]
	var rect := _tab_rect(index, width)
	var ci := get_canvas_item()
	var selected := tab == _tab
	var style: StyleBoxFlat = _tab_selected_style if selected else _tab_style
	style.draw(ci, rect)
	if _text_font == null:
		return
	var label := str(TAB_LABELS[tab])
	var baseline := rect.position.y + rect.size.y * 0.5 + float(TAB_FONT_SIZE) * 0.35
	var color := BG_COLOR if selected else VALUE_COLOR
	draw_string(_text_font, Vector2(rect.position.x, baseline), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, TAB_FONT_SIZE, color)


func _draw_scrollbar(width: float) -> void:
	var natural := _body_natural_height(width)
	var visible_body := _visible_body_height(width)
	if natural <= visible_body + 0.5:
		return
	var body_y := HEAD_H + TAB_BAR_HEIGHT + 1.0
	var track_h := maxf(visible_body - 2.0, 1.0)
	var thumb_h := maxf(6.0, track_h * clampf(visible_body / natural, 0.0, 1.0))
	var progress := _scroll / (natural - visible_body)
	var x := width - SCROLLBAR_INSET - SCROLLBAR_WIDTH
	var track := Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.16)
	var thumb := Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.6)
	draw_rect(Rect2(Vector2(x, body_y), Vector2(SCROLLBAR_WIDTH, track_h)), track)
	draw_rect(Rect2(Vector2(x, body_y + (track_h - thumb_h) * clampf(progress, 0.0, 1.0)),
		Vector2(SCROLLBAR_WIDTH, thumb_h)), thumb)
