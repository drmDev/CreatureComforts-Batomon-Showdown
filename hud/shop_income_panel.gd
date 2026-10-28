extends Control
## ShopIncomePanel - Tiny square panel showing the player's current daily income.
##
## Displayed bottom-center while the shop is on screen. The value is the run's
## per-day income: the base schedule (35 gold on Day 1, +5 per day) plus every
## `gold_gain` passive bonus the player owns (e.g. Gold Nugget +3).
##
## Matches the shared Creature Comforts panel look (dark navy background, gold
## border, Consolas font, light shadow). Draws directly; no child nodes.

const PANEL_SIZE := 16.0
const BOTTOM_MARGIN := 16.0
const OFFSET_RATIO := 0.10
const UP_PANEL_OFFSET := 2.4
const RIGHT_VIEWPORT_OFFSET := 0.01

const TITLE_TEXT := "INCOME"
const TITLE_SIZE := 3
const TITLE_BASELINE := 6.0
const VALUE_SIZE := 8
const VALUE_BASELINE := 14.0

# Panel palette (matches reminder_label / player_hud / trinket_panel)
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

var _income: int = 0
var _panel_style: StyleBoxFlat
var _text_font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	size = Vector2(PANEL_SIZE, PANEL_SIZE)
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)
	_setup_styles()
	_setup_font()


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)
	_anchor_bottom_center()


func _setup_styles() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(3)


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


## Update and show the panel. The shop's overlay layer controls when it is on screen.
func set_income(value: int) -> void:
	if _income == value and visible:
		return
	_income = value
	visible = true
	queue_redraw()


func _anchor_bottom_center() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var centered_x := (viewport_size.x - size.x) * 0.5
	var bottom_y := viewport_size.y - size.y - BOTTOM_MARGIN
	position = Vector2(
		roundf(centered_x + viewport_size.x * (0.5 * OFFSET_RATIO + RIGHT_VIEWPORT_OFFSET)),
		roundf(bottom_y - viewport_size.y * 0.5 * OFFSET_RATIO - PANEL_SIZE * UP_PANEL_OFFSET)
	)


func _on_viewport_resized() -> void:
	_anchor_bottom_center()


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	_draw_text(Vector2(0.0, TITLE_BASELINE), TITLE_TEXT, TITLE_SIZE, LABEL_COLOR)
	_draw_text(Vector2(0.0, VALUE_BASELINE), str(_income), VALUE_SIZE, VALUE_COLOR)


## Draw horizontally centered text with a light shadow for readability.
func _draw_text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_text_font, pos + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, SHADOW_COLOR)
	draw_string(_text_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
