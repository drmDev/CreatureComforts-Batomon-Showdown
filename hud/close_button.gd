extends Control
## Close (X) button shared by the watchlist and saved-builds popups. Uses the
## shared close icon so both popups read as the same widget.

const PanelIcons = preload("panel_icons.gd")
const SIZE := 14.0

var on_press: Callable
var _close_texture: Texture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Close"
	custom_minimum_size = Vector2(SIZE, SIZE)
	_close_texture = PanelIcons.load_icon(str(get_script().resource_path), PanelIcons.CLOSE)


func _draw() -> void:
	PanelIcons.draw_fit(self, _close_texture, Rect2(Vector2.ZERO, size))


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if on_press.is_valid():
			on_press.call()
		accept_event()
