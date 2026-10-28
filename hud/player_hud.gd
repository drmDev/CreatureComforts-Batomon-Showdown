extends Control
## PlayerHud - Compact battle HUD showing the player's HP, Wins, and Day.
##
## Ported from NP_QoL's player_hud.gd, but restyled to match Creature Comforts'
## other panels (dark navy background, gold border, Consolas font, light shadow).
## This version is text-only: no heart / badge / sun icons, just labels and values.
##
## Displays as a single line: "HP 3 | Wins 2 | Day 4"
## Shown only while a battle is active (mod_main controls visibility).

const PANEL_WIDTH := 150.0
const CONTENT_PADDING := 4.0
const ROW_HEIGHT := 12.0
const FONT_SIZE := 9

const LABEL_GAP := 3.0
const GROUP_GAP := 8.0
const SEPARATOR := " | "

# Panel palette (matches reminder_label / trinket_panel / achievement_panel)
const BG_COLOR := Color("#1a2332")       # Dark navy
const BORDER_COLOR := Color("#f39c12")   # Gold
const LABEL_COLOR := Color("#d4d8e0")    # Dimmer label text
const VALUE_COLOR := Color("#ecf0f1")    # Bright value text
const SHADOW_COLOR := Color("#2c3e50")   # Dark shadow

const FALLBACK_FONTS := [
	"res://assets/ui/fonts/NotoSansJP-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansKR-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansSC-ExtraBold.ttf",
]
const SYSTEM_FALLBACKS := ["Leelawadee UI", "Tahoma", "Segoe UI", "Noto Sans Thai", "Noto Sans", "Arial Unicode MS", "Droid Sans Fallback"]

var _player_stats: Dictionary = {}
var _panel_style: StyleBoxFlat
var _text_font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	size = Vector2(PANEL_WIDTH, CONTENT_PADDING + ROW_HEIGHT + CONTENT_PADDING)
	_setup_styles()
	_setup_font()


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)
	_anchor_centered()


func _setup_styles() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(3)
	_panel_style.set_content_margin_all(CONTENT_PADDING)


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


## Update the displayed stats. Expected keys: hp, wins, day (values are pre-formatted strings).
func update_stats(new_stats: Dictionary) -> void:
	_player_stats = new_stats
	queue_redraw()


func _anchor_centered() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	position = Vector2(roundf((viewport_size.x - size.x) * 0.5), 244.0)


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

	var content_left := CONTENT_PADDING + 2.0
	var row_top := CONTENT_PADDING
	var baseline := row_top + ROW_HEIGHT - 2.0
	var cursor_x := content_left

	var hp := str(_player_stats.get("hp", "?"))
	var wins := str(_player_stats.get("wins", "?"))
	var day := str(_player_stats.get("day", "?"))

	cursor_x = _draw_stat(cursor_x, baseline, "HP", hp)
	cursor_x = _draw_separator(cursor_x, baseline)
	cursor_x = _draw_stat(cursor_x, baseline, "Wins", wins)
	cursor_x = _draw_separator(cursor_x, baseline)
	_draw_stat(cursor_x, baseline, "Day", day)


## Draw "Label Value" and return the x cursor after the group.
func _draw_stat(start_x: float, baseline: float, label: String, value: String) -> float:
	var cursor_x := start_x

	_draw_text(Vector2(cursor_x, baseline), label, LABEL_COLOR)
	cursor_x += _text_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + LABEL_GAP

	_draw_text(Vector2(cursor_x, baseline), value, VALUE_COLOR)
	cursor_x += _text_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + GROUP_GAP

	return cursor_x


func _draw_separator(start_x: float, baseline: float) -> float:
	_draw_text(Vector2(start_x, baseline), SEPARATOR, LABEL_COLOR)
	return start_x + _text_font.get_string_size(SEPARATOR, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


## Draw text with a light shadow for readability (mirrors the other panels).
func _draw_text(pos: Vector2, text: String, color: Color) -> void:
	draw_string(_text_font, pos + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, SHADOW_COLOR)
	draw_string(_text_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, color)
