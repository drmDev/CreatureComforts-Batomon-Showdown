extends Control
## TrinketPanel - Compact panel showing trinkets gained since the last shop visit.
## Appears right-center on screen when returning to the shop with gains.
## Auto-hides after 10 seconds. Uses NP_QoL panel drawing pattern.
##
## References:
##   - examples/NP_QoL/disabled_player_hud.gd  (panel _draw, row layout)
##   - examples/NP_QoL/disabled_ui_skin.gd      (StyleBoxFlat, font loading, draw_text_with_shadow)

const PANEL_WIDTH := 180.0
const CONTENT_PADDING := 6.0
const ROW_HEIGHT := 16.0
const ROW_GAP := 2.0
const FONT_SIZE := 10
const TITLE_FONT_SIZE := 11
const DISPLAY_DURATION_MS := 10000  # Auto-hide after 5 seconds
const MARGIN_RIGHT := 10.0

const BG_COLOR := Color("#1a2332")       # Dark navy (matches reminder_label)
const BORDER_COLOR := Color("#f39c12")   # Gold (matches reminder_label)
const TITLE_COLOR := Color("#ecf0f1")    # Light text
const TEXT_COLOR := Color("#d4d8e0")     # Slightly dimmer for rows
const SHADOW_COLOR := Color("#2c3e50")   # Dark shadow

const FALLBACK_FONTS := [
	"res://assets/ui/fonts/NotoSansJP-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansKR-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansSC-ExtraBold.ttf",
]
const SYSTEM_FALLBACKS := ["Leelawadee UI", "Tahoma", "Segoe UI", "Noto Sans Thai", "Noto Sans", "Arial Unicode MS", "Droid Sans Fallback"]


var _entries: Array = []  # Array of Dictionary {"name": String, "count": int}
var _panel_style: StyleBoxFlat
var _text_font: Font
var _hide_at_ms := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_setup_style()
	_setup_font()


func _setup_style() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(3)
	_panel_style.set_content_margin_all(3)


func _setup_font() -> void:
	var fallbacks: Array[Font] = []
	for font_path in FALLBACK_FONTS:
		if ResourceLoader.exists(font_path):
			var font_resource = load(font_path)
			if font_resource is Font:
				fallbacks.append(font_resource)
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(SYSTEM_FALLBACKS)
	fallbacks.append(system_font)

	_text_font = SystemFont.new()
	_text_font.font_names = PackedStringArray(["Consolas"])
	_text_font.fallbacks = fallbacks


## Show the panel with the given entries.
## entries: Array of Dictionary {"name": String, "count": int}
func show_gains(entries: Array) -> void:
	_entries = entries
	_compute_size()
	_compute_position()
	_hide_at_ms = Time.get_ticks_msec() + DISPLAY_DURATION_MS
	visible = true
	queue_redraw()


## Hide the panel immediately.
func hide_panel() -> void:
	_entries.clear()
	_hide_at_ms = 0
	visible = false
	queue_redraw()


func _compute_size() -> void:
	var num_rows := 1 + _entries.size()  # title + entries
	var h := CONTENT_PADDING * 2.0 + ROW_HEIGHT * float(num_rows) + ROW_GAP * float(_entries.size())
	size = Vector2(PANEL_WIDTH, h)


func _compute_position() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := MARGIN_RIGHT
	position = Vector2(viewport_size.x - size.x - margin, (viewport_size.y - size.y) * 0.5)


func _process(_delta: float) -> void:
	if _hide_at_ms > 0 and Time.get_ticks_msec() >= _hide_at_ms:
		hide_panel()


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	if _entries.is_empty():
		return

	# Draw panel background
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

	# Draw title row
	var cursor_y := CONTENT_PADDING
	var baseline := cursor_y + ROW_HEIGHT - 2.0
	_draw_text(Vector2(CONTENT_PADDING + 1.0, baseline), "Trinkets Gained", TITLE_COLOR, TITLE_FONT_SIZE)

	# Draw entry rows
	cursor_y += ROW_HEIGHT + ROW_GAP
	for entry in _entries:
		baseline = cursor_y + ROW_HEIGHT - 2.0
		var line := "%dx %s" % [entry.count, entry.name]
		_draw_text(Vector2(CONTENT_PADDING + 1.0, baseline), line, TEXT_COLOR, FONT_SIZE)
		cursor_y += ROW_HEIGHT + ROW_GAP


## Draw text with a light shadow for readability (mirrors NP_QoL ui_skin.draw_text_with_shadow).
func _draw_text(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	draw_string(_text_font, pos + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, SHADOW_COLOR)
	draw_string(_text_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)