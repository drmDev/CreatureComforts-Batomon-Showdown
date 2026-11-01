extends Control
## Close (X) button shared by the watchlist and saved-builds popups: a gold
## rounded box with dark arms drawn straight onto the canvas, so both popups read
## as the same widget.

const Style = preload("../core/style.gd")
const SIZE := 14.0
const ARM := 3.0
const ARM_WIDTH := 1.5

var on_press: Callable
var _box: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Close"
	custom_minimum_size = Vector2(SIZE, SIZE)
	_box = StyleBoxFlat.new()
	_box.bg_color = Style.BORDER_COLOR
	_box.set_corner_radius_all(2)


func _draw() -> void:
	_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var c := size * 0.5
	draw_line(c + Vector2(-ARM, -ARM), c + Vector2(ARM, ARM), Style.BG_COLOR, ARM_WIDTH)
	draw_line(c + Vector2(-ARM, ARM), c + Vector2(ARM, -ARM), Style.BG_COLOR, ARM_WIDTH)


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if on_press.is_valid():
			on_press.call()
		accept_event()
