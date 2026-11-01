extends "comfort_panel.gd"

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

var _income: int = 0
var _panel_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	size = Vector2(PANEL_SIZE, PANEL_SIZE)
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)
	_setup_styles()
	_text_font = _build_panel_font()


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)
	_anchor_bottom_center()


func _setup_styles() -> void:
	_panel_style = _build_hud_box()


func set_income(value: int) -> void:
	if _income == value and visible:
		return
	_income = value
	visible = true
	queue_redraw()


## Hide the panel immediately. The overlay gate normally controls visibility; this is a
## defensive fallback for non-shop phases (battle, event, menu).
func hide_panel() -> void:
	if not visible:
		return
	visible = false
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
	_draw_text_shadow(Vector2(0.0, TITLE_BASELINE), TITLE_TEXT, LABEL_COLOR, TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_text_shadow(Vector2(0.0, VALUE_BASELINE), str(_income), VALUE_COLOR, VALUE_SIZE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
