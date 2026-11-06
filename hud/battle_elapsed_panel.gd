extends "comfort_panel.gd"
## Small post-battle readout showing the simulation's total elapsed time.
##
## The value is the battle simulation's own clock (simulation.data.time_elapsed),
## not wall-clock time: fast-forwarding and replay steps make the two differ. The
## panel is shown at each visual battle's conclusion (including replays); the
## caller hides it while a replay runs and when the battle is left.

const PANEL_WIDTH := 64.0
const PANEL_HEIGHT := 16.0
const BOTTOM_MARGIN := 32.0
const OFFSET_RATIO := 0.10
const UP_PANEL_OFFSET := 2.7

const TEXT_SIZE := 8
const TEXT_BASELINE := 11.0

var _text := "Elapsed: 0.0s"
var _panel_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_setup_styles()
	_text_font = _build_panel_font()


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)
	_anchor_bottom_center()


func _setup_styles() -> void:
	_panel_style = _build_hud_box()


## Show the panel with a pre-formatted duration (e.g. "12.3s"). It stays up
## until hide_panel() is called (leaving the battle or starting a new one).
func show_elapsed(seconds_text: String) -> void:
	var next_text := "Elapsed: %s" % seconds_text
	if _text == next_text and visible:
		return
	_text = next_text
	visible = true
	queue_redraw()


## Hide the panel immediately.
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
		roundf(centered_x),
		roundf(bottom_y - viewport_size.y * 0.5 * OFFSET_RATIO - PANEL_HEIGHT * UP_PANEL_OFFSET)
	)


func _on_viewport_resized() -> void:
	_anchor_bottom_center()


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	_draw_text_shadow(Vector2(0.0, TEXT_BASELINE), _text, VALUE_COLOR, TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
