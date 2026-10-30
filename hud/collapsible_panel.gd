extends "comfort_panel.gd"
## CollapsiblePanel - shared collapsible-header mechanics for Creature Comforts panels.
##
## Provides the header bar with a -/+ toggle button, header dragging, an animated reveal that
## ignores Engine.time_scale, and the shared panel/header/button styling.
##
## Subclasses own their layout: implement header_text(), full_height(), _apply_size(), and
## _draw_body() (rows only; the base draws the body background, header, and button). The shared
## `_entries` / `_content_key` row-state vars are provided for the subclass show_*() methods.
##
## Behaviour adapted from examples/MyBattleStats/disabled_collapsible_panel.gd.

# Collapsible panel geometry
const HEAD_H := 16.0
const BTN := 12.0
const ANIM_SEC := 0.14
const DRAG_THRESHOLD := 3.0
const TITLE_FONT_SIZE := 11

const HEADER_BG := Color("#2b3a52")      # Slightly lighter navy for the header bar
const INK_COLOR := Color("#ecf0f1")      # "-" / "+" glyph colour

var _entries: Array = []  # Array of subclass-defined row Dictionaries
var _content_key := ""    # Cheap change detection for subclass show_*() callers

# Collapsible state
var minimized := false
var reveal := 1.0  # 1 = expanded, 0 = minimized (animated)

var _panel_style: StyleBoxFlat
var _header_style: StyleBoxFlat
var _button_style: StyleBoxFlat

var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	_setup_styles()
	_text_font = _build_panel_font()


func _setup_styles() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(3)
	_panel_style.set_content_margin_all(3)

	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = HEADER_BG
	_header_style.border_color = BORDER_COLOR
	_header_style.set_border_width_all(1)
	_header_style.set_corner_radius_all(3)
	_header_style.set_content_margin_all(3)

	_button_style = StyleBoxFlat.new()
	_button_style.bg_color = BORDER_COLOR
	_button_style.set_corner_radius_all(2)
	_button_style.set_content_margin_all(2)


# --- Subclass hooks -------------------------------------------------------------

## Header title (between the left edge and the -/+ button).
func header_text() -> String:
	return ""


## Height of the panel when fully expanded.
func full_height() -> float:
	return HEAD_H


## Set `size` from the current reveal and the subclass layout.
func _apply_size() -> void:
	pass


## Draw the rows only; the base already drew the body background before calling this.
func _draw_body(_width: float) -> void:
	pass


# --- Shared behaviour -----------------------------------------------------------

func set_minimized(on: bool, animate := true) -> void:
	if on == minimized and (_tween == null or not _tween.is_running()):
		return
	minimized = on
	if _tween != null:
		_tween.kill()
	var target := 0.0 if on else 1.0
	if not animate or not is_inside_tree():
		reveal = target
		_apply_size()
		queue_redraw()
	else:
		# The game slows / stops Engine.time_scale (KO slow motion, pause), so animate in
		# real time. Position is intentionally NOT re-anchored: the top stays fixed and the
		# panel expands downward (subclasses choose their own anchoring).
		_tween = create_tween().set_ignore_time_scale(true)
		_tween.tween_method(func(v: float):
			reveal = v
			_apply_size()
			queue_redraw(), reveal, target, ANIM_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func toggle() -> void:
	set_minimized(not minimized)


## Width of the header bar and its button. Defaults to the panel width; subclasses can keep
## the header compact (e.g. only as wide as the collapsed tab) while the body stays wider.
func header_width() -> float:
	return size.x


func button_rect() -> Rect2:
	return Rect2(Vector2(header_width() - 8 - BTN - 3, 2.0), Vector2(BTN, BTN))


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	if _entries.is_empty() and reveal <= 0.01:
		return

	var ci := get_canvas_item()
	var w := size.x

	# Body background + rows (rows only when expanded)
	if reveal > 0.01:
		_panel_style.draw(ci, Rect2(Vector2(0, 4), Vector2(w, maxf(size.y - 4, 8))))
		_draw_body(w)

	# Header bar (may be narrower than the body; see header_width())
	var hw := header_width()
	_header_style.draw(ci, Rect2(Vector2(7, 0), Vector2(hw - 14, HEAD_H)))
	_draw_title(Rect2(Vector2(12, 0), Vector2(button_rect().position.x - 16, HEAD_H)))

	# -/+ button
	var b := button_rect()
	_button_style.draw(ci, b)
	var c := b.get_center().floor()
	draw_rect(Rect2(c.x - 3, c.y, 6, 1), INK_COLOR)
	if minimized:
		draw_rect(Rect2(c.x, c.y - 3, 1, 7), INK_COLOR)


## Header title, trimmed so it never runs under the button, centred vertically.
func _draw_title(r: Rect2) -> void:
	var t := _fit_text(_text_font, header_text(), TITLE_FONT_SIZE, r.size.x)
	var baseline := r.position.y + HEAD_H * 0.5 + 3.0
	_draw_text_shadow(Vector2(r.position.x, baseline), t, VALUE_COLOR, TITLE_FONT_SIZE)


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEAD_H + 1:
				return  # body: not ours to handle
			_pressing = true
			_dragged = false
			_press_pos = event.position
		elif _pressing:
			_pressing = false
			if not _dragged:
				toggle()
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		if not _dragged and event.position.distance_to(_press_pos) >= DRAG_THRESHOLD:
			_dragged = true
		if _dragged:
			# event.relative is the mouse delta in screen space; using it (instead of comparing
			# local event.position against a fixed press point) avoids the feedback loop that made
			# the panel jump/snap back as it moved under the cursor.
			position += event.relative
		accept_event()
