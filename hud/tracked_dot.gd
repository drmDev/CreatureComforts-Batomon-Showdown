extends Control
## Tiny solid blue activity dot, shared by the Watchlist tabs and the unified
## Trinkets panel so both use the exact same indicator style.
##
## The dot only paints itself; callers place and size it. MOUSE_FILTER_IGNORE
## keeps it from intercepting clicks on the control it sits on.

const Style = preload("../core/style.gd")
const COLOR := Style.TRACKED_DOT_COLOR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 2
	resized.connect(func(): queue_redraw())


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	if radius <= 0.0:
		return
	draw_circle(size * 0.5, radius, COLOR)
