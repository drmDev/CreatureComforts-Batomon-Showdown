extends "comfort_panel.gd"
## Icons: the game's own heart and trophy textures are loaded from the packed UI
## textures; the calendar icon is loaded from the mod's assets. A missing icon falls
## back to its text label.

const CONTENT_PADDING := 4.0
const CONTENT_INSET := 2.0  # Extra left/right breathing room inside the padding
const ROW_HEIGHT := 12.0
const FONT_SIZE := 9
const TOP_OFFSET := 244.0   # Fixed distance from the top of the battle screen

const LABEL_GAP := 3.0
const GROUP_GAP := 8.0
const ICON_SIZE := 10.0
const CALENDAR_ICON_SIZE := 13  # Calendar art has ~20% transparent padding; draw it larger to match
const ICON_GAP := 2.0

var _player_stats: Dictionary = {}
var _panel_style: StyleBoxFlat
var _heart_texture: Texture2D = null
var _trophy_texture: Texture2D = null
var _calendar_texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_setup_styles()
	_text_font = _build_panel_font()
	# Verified game asset paths (packed in batomon_showdown.pck).
	_heart_texture = load("res://assets/ui/textures/shop/lives_icon.png")
	_trophy_texture = load("res://assets/ui/textures/shop/wins_icon.png")
	_calendar_texture = _load_texture("../assets/icons/calendar.png")
	# Width is fitted to the measured label/value text; start with the placeholder widths.
	size = Vector2(_measure_content_width({}), CONTENT_PADDING + ROW_HEIGHT + CONTENT_PADDING)


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)
	_anchor_centered()


func _setup_styles() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(3)
	_panel_style.set_content_margin_all(CONTENT_PADDING)


func update_stats(new_stats: Dictionary) -> void:
	if new_stats == _player_stats:
		return
	_player_stats = new_stats
	var fitted_width := _measure_content_width(new_stats)
	if not is_equal_approx(size.x, fitted_width):
		size.x = fitted_width
		_anchor_centered()
	queue_redraw()


func _measure_content_width(stats: Dictionary) -> float:
	var hp := str(stats.get("hp", "?"))
	var wins := str(stats.get("wins", "?"))
	var day := str(stats.get("day", "?"))

	var content_width := 0.0
	content_width += _stat_group_width("HP", hp, _heart_texture) + GROUP_GAP
	content_width += _stat_group_width("Wins", wins, _trophy_texture) + GROUP_GAP
	content_width += _stat_group_width("Day", day, _calendar_texture)

	return ceilf(CONTENT_PADDING + CONTENT_INSET + content_width + CONTENT_INSET + CONTENT_PADDING)


func _stat_group_width(label: String, value: String, icon: Texture2D) -> float:
	var lead := _icon_size(icon) + ICON_GAP if icon != null else _text_width(label) + LABEL_GAP
	return lead + _text_width(value)


## Display size for an icon; the calendar art has more transparent padding than the game icons.
func _icon_size(icon: Texture2D) -> float:
	return CALENDAR_ICON_SIZE if icon == _calendar_texture else ICON_SIZE


func _text_width(text: String) -> float:
	if _text_font == null:
		return 0.0
	return _text_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _anchor_centered() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	position = Vector2(roundf((viewport_size.x - size.x) * 0.5), TOP_OFFSET)


func _on_viewport_resized() -> void:
	_anchor_centered()


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	_draw_stats_row()


func _draw_stats_row() -> void:
	if _player_stats.is_empty():
		return

	var content_left := CONTENT_PADDING + CONTENT_INSET
	var row_top := CONTENT_PADDING
	var baseline := row_top + ROW_HEIGHT - 2.0
	var cursor_x := content_left

	var hp := str(_player_stats.get("hp", "?"))
	var wins := str(_player_stats.get("wins", "?"))
	var day := str(_player_stats.get("day", "?"))

	cursor_x = _draw_stat(cursor_x, row_top, baseline, "HP", hp, _heart_texture)
	cursor_x = _draw_stat(cursor_x, row_top, baseline, "Wins", wins, _trophy_texture)
	_draw_stat(cursor_x, row_top, baseline, "Day", day, _calendar_texture)


func _draw_stat(start_x: float, row_top: float, baseline: float, label: String, value: String, icon: Texture2D) -> float:
	var cursor_x := start_x

	if icon != null:
		var icon_size := _icon_size(icon)
		var icon_y := row_top + (ROW_HEIGHT - icon_size) * 0.5
		draw_texture_rect(icon, Rect2(Vector2(cursor_x, icon_y), Vector2(icon_size, icon_size)), false)
		cursor_x += icon_size + ICON_GAP
	else:
		_draw_text_shadow(Vector2(cursor_x, baseline), label, LABEL_COLOR, FONT_SIZE)
		cursor_x += _text_width(label) + LABEL_GAP

	_draw_text_shadow(Vector2(cursor_x, baseline), value, VALUE_COLOR, FONT_SIZE)
	cursor_x += _text_width(value) + GROUP_GAP

	return cursor_x


