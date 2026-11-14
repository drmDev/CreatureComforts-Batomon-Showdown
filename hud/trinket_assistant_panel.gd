extends "comfort_panel.gd"
## Clippy-style assistant for the Positional Trinkets Summary.
##
## This is a transient companion: the icon and the speech bubble appear together
## only while the introduction is active. Dismissing the bubble hides both and
## leaves the summary panel untouched. The control follows the movable summary
## panel and stays on the reminder layer, so it is already shop-gated.

const TrinketAssistant = preload("../core/trinket_assistant.gd")
const UiSound = preload("../core/ui_sound.gd")

const ICON_SIZE := Vector2(22.0, 30.0)
const BUBBLE_MAX_WIDTH := 220.0
const BUBBLE_PADDING := 6.0
const BUBBLE_FONT_SIZE := 8
const BUBBLE_LINE_HEIGHT := 11.0
const BUBBLE_GAP := 4.0
const VIEWPORT_MARGIN := 8.0
const TARGET_LINE_CHARS := 32
const HINT_TEXT := "Click to dismiss"
const HINT_FONT_SIZE := 6
const HINT_GAP := 2.0
const SOUND_FILE := "naviListen.ogg"
const FALLBACK_VIEWPORT_SIZE := Vector2(1280, 720)
const PANEL_AVOID_GROW := 2.0

var _anchor_panel = null
var _icon_button: AssistantIconButton
var _bubble: AssistantBubble
var _clippy_texture: Texture2D
var _icon_style: StyleBoxFlat
var _bubble_style: StyleBoxFlat
var _sound = null
var _bubble_lines: Array = []
var _bubble_size := Vector2.ZERO
var _last_panel_rect := Rect2()
var _last_viewport_size := Vector2.ZERO


func _init() -> void:
	_text_font = _build_panel_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	visible = false

	_clippy_texture = _load_texture("../assets/icons/clippy.png")
	_icon_style = _build_hud_box()

	_bubble_style = StyleBoxFlat.new()
	_bubble_style.bg_color = BG_COLOR
	_bubble_style.border_color = BORDER_COLOR
	_bubble_style.set_border_width_all(1)
	_bubble_style.set_corner_radius_all(3)
	_bubble_style.set_content_margin_all(BUBBLE_PADDING)

	_icon_button = AssistantIconButton.new()
	_icon_button.name = "AssistantIcon"
	_icon_button.texture = _clippy_texture
	_icon_button.style_box = _icon_style
	add_child(_icon_button)

	_bubble = AssistantBubble.new()
	_bubble.name = "AssistantBubble"
	_bubble.style_box = _bubble_style
	_bubble.font = _text_font
	_bubble.on_press = hide_bubble
	add_child(_bubble)


func setup(anchor_panel, sounds_enabled: Callable = Callable(), sound_volume: Callable = Callable()) -> void:
	_anchor_panel = anchor_panel
	_sound = UiSound.new()
	_sound.setup(self, SOUND_FILE, sounds_enabled, sound_volume)
	_compute_bubble_layout()


func set_icon_pressed(callable: Callable) -> void:
	_icon_button.on_press = callable


## Show the icon and bubble together and play the Navi sound once per appearance.
func show_bubble() -> void:
	if visible:
		return
	visible = true
	set_process(true)
	if _sound != null:
		_sound.play()
	_update_layout()


## Hide the icon and bubble together. The summary panel is intentionally left alone.
func hide_bubble() -> void:
	if not visible:
		return
	visible = false
	set_process(false)


func _input(event) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_bubble()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _anchor_panel == null or not is_instance_valid(_anchor_panel):
		hide_bubble()
		return
	if not _anchor_panel.visible:
		hide_bubble()
		return

	var panel_rect := Rect2(_anchor_panel.position, _anchor_panel.size)
	var viewport_size := _viewport_size()
	if panel_rect == _last_panel_rect and viewport_size == _last_viewport_size:
		return
	_last_panel_rect = panel_rect
	_last_viewport_size = viewport_size
	_update_layout()


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else FALLBACK_VIEWPORT_SIZE


func _compute_bubble_layout() -> void:
	var viewport_size := _viewport_size()
	# Size the bubble to roughly TARGET_LINE_CHARS monospace columns so the
	# dialogue wraps into three balanced lines instead of one very long pair.
	var target_text_width := _text_font.get_string_size(
		"M".repeat(TARGET_LINE_CHARS), HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT_SIZE
	).x
	var max_inner := minf(BUBBLE_MAX_WIDTH, viewport_size.x - VIEWPORT_MARGIN * 2.0) - BUBBLE_PADDING * 2.0
	var inner_width := minf(target_text_width, max_inner)
	if inner_width <= 0.0:
		inner_width = BUBBLE_MAX_WIDTH - BUBBLE_PADDING * 2.0

	_bubble_lines = _wrap_text(TrinketAssistant.INTRO_TEXT, inner_width, BUBBLE_FONT_SIZE)
	var height := BUBBLE_PADDING * 2.0 \
		+ float(_bubble_lines.size()) * BUBBLE_LINE_HEIGHT \
		+ HINT_GAP + float(HINT_FONT_SIZE)
	_bubble_size = Vector2(inner_width + BUBBLE_PADDING * 2.0, height)


func _wrap_text(text: String, max_width: float, font_size: int) -> Array:
	if text.is_empty() or max_width <= 0.0:
		return [text]
	var lines: Array = []
	var current := ""
	for word in text.split(" "):
		var candidate := word if current.is_empty() else current + " " + word
		if _text_font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			current = candidate
		else:
			if not current.is_empty():
				lines.append(current)
			current = word
	if not current.is_empty():
		lines.append(current)
	return lines


func _update_layout() -> void:
	if _anchor_panel == null or not is_instance_valid(_anchor_panel):
		hide_bubble()
		return

	var panel_rect := Rect2(_anchor_panel.position, _anchor_panel.size)
	_compute_bubble_layout()
	var placement := _choose_placement(panel_rect)

	var icon_pos: Vector2 = placement["icon"]
	var bubble_pos: Vector2 = placement["bubble"]
	position = icon_pos
	size = ICON_SIZE

	_icon_button.size = ICON_SIZE
	_icon_button.position = Vector2.ZERO

	_bubble.size = _bubble_size
	_bubble.position = bubble_pos - icon_pos
	_bubble.lines = _bubble_lines
	_bubble.font_size = BUBBLE_FONT_SIZE
	_bubble.line_height = BUBBLE_LINE_HEIGHT
	_bubble.padding = BUBBLE_PADDING
	_bubble.tail_side = placement["tail"]
	_bubble.text_color = VALUE_COLOR
	_bubble.shadow_color = SHADOW_COLOR
	_bubble.border_color = BORDER_COLOR
	_bubble.fill_color = BG_COLOR
	_bubble.hint_text = HINT_TEXT
	_bubble.hint_font_size = HINT_FONT_SIZE
	_bubble.hint_gap = HINT_GAP
	_bubble.hint_color = LABEL_COLOR

	_icon_button.queue_redraw()
	_bubble.queue_redraw()


## Try the safest placements first: icon beside the panel with the bubble above
## or beside the icon, then the icon above/below the panel. The first candidate
## that fits the viewport and does not overlap the panel wins.
func _choose_placement(panel_rect: Rect2) -> Dictionary:
	var icon_size := ICON_SIZE
	var bubble_size := _bubble_size
	var panel_grown := panel_rect.grow(PANEL_AVOID_GROW)

	var candidates: Array = [
		_make_placement(
			Vector2(panel_rect.position.x - icon_size.x - BUBBLE_GAP, panel_rect.position.y),
			Vector2(panel_rect.position.x - icon_size.x - BUBBLE_GAP + icon_size.x * 0.5 - bubble_size.x * 0.5, panel_rect.position.y - bubble_size.y - BUBBLE_GAP),
			"bottom"
		),
		_make_placement(
			Vector2(panel_rect.position.x + panel_rect.size.x + BUBBLE_GAP, panel_rect.position.y),
			Vector2(panel_rect.position.x + panel_rect.size.x + BUBBLE_GAP + icon_size.x * 0.5 - bubble_size.x * 0.5, panel_rect.position.y - bubble_size.y - BUBBLE_GAP),
			"bottom"
		),
		_make_placement(
			Vector2(panel_rect.position.x - icon_size.x - BUBBLE_GAP, panel_rect.position.y),
			Vector2(panel_rect.position.x - icon_size.x - BUBBLE_GAP - BUBBLE_GAP - bubble_size.x, panel_rect.position.y + icon_size.y * 0.5 - bubble_size.y * 0.5),
			"right"
		),
		_make_placement(
			Vector2(panel_rect.position.x + panel_rect.size.x + BUBBLE_GAP, panel_rect.position.y),
			Vector2(panel_rect.position.x + panel_rect.size.x + BUBBLE_GAP + icon_size.x + BUBBLE_GAP, panel_rect.position.y + icon_size.y * 0.5 - bubble_size.y * 0.5),
			"left"
		),
		_make_placement(
			Vector2(panel_rect.position.x, panel_rect.position.y - icon_size.y - BUBBLE_GAP),
			Vector2(panel_rect.position.x + icon_size.x * 0.5 - bubble_size.x * 0.5, panel_rect.position.y - icon_size.y - BUBBLE_GAP - bubble_size.y - BUBBLE_GAP),
			"bottom"
		),
		_make_placement(
			Vector2(panel_rect.position.x, panel_rect.position.y + panel_rect.size.y + BUBBLE_GAP),
			Vector2(panel_rect.position.x + icon_size.x * 0.5 - bubble_size.x * 0.5, panel_rect.position.y + panel_rect.size.y + BUBBLE_GAP + icon_size.y + BUBBLE_GAP),
			"top"
		),
	]

	for candidate in candidates:
		var icon_rect := Rect2(candidate["icon"], icon_size)
		var bubble_rect := Rect2(candidate["bubble"], bubble_size)
		if _rect_fits(icon_rect) and _rect_fits(bubble_rect) \
				and not bubble_rect.intersects(panel_grown) \
				and not icon_rect.intersects(panel_grown):
			return candidate

	# Last resort: clamp the first candidate into the viewport.
	var fallback: Dictionary = candidates[0]
	fallback["icon"] = _clamp_rect(Rect2(fallback["icon"], icon_size)).position
	fallback["bubble"] = _clamp_rect(Rect2(fallback["bubble"], bubble_size)).position
	return fallback


func _make_placement(icon_pos: Vector2, bubble_pos: Vector2, tail_side: String) -> Dictionary:
	return {"icon": icon_pos, "bubble": bubble_pos, "tail": tail_side}


func _rect_fits(rect: Rect2) -> bool:
	var vs := _viewport_size()
	return rect.position.x >= VIEWPORT_MARGIN \
		and rect.position.y >= VIEWPORT_MARGIN \
		and rect.end.x <= vs.x - VIEWPORT_MARGIN \
		and rect.end.y <= vs.y - VIEWPORT_MARGIN


func _clamp_rect(rect: Rect2) -> Rect2:
	var vs := _viewport_size()
	var x := clampf(rect.position.x, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, vs.x - VIEWPORT_MARGIN - rect.size.x))
	var y := clampf(rect.position.y, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, vs.y - VIEWPORT_MARGIN - rect.size.y))
	return Rect2(Vector2(x, y), rect.size)


## Small self-drawn icon button. A plain Control has no content minimum, so the
## clippy asset can be drawn at exactly ICON_SIZE.
class AssistantIconButton extends Control:
	const PanelIcons = preload("panel_icons.gd")
	const ICON_INSET := 2.0

	var texture: Texture2D
	var style_box: StyleBoxFlat
	var on_press: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "Open Trinket Summary"

	func _draw() -> void:
		if style_box != null:
			style_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		if texture != null:
			var rect := Rect2(
				Vector2(ICON_INSET, ICON_INSET),
				size - Vector2(ICON_INSET * 2.0, ICON_INSET * 2.0)
			)
			PanelIcons.draw_fit(self, texture, rect)

	func _gui_input(event) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if on_press.is_valid():
				on_press.call()
			accept_event()


## Speech bubble drawn in the Creature Comforts style, with a small tail on the
## side facing the clippy icon. The whole bubble is clickable to dismiss it.
class AssistantBubble extends Control:
	const TAIL_LENGTH := 6.0
	const TAIL_HALF_WIDTH := 5.0

	var style_box: StyleBoxFlat
	var font: Font
	var lines: Array = []
	var font_size := 8
	var line_height := 11.0
	var padding := 6.0
	var tail_side := ""
	var text_color := Color.WHITE
	var shadow_color := Color.BLACK
	var border_color := Color.WHITE
	var fill_color := Color("#1a2332")
	var hint_text := ""
	var hint_font_size := 6
	var hint_gap := 2.0
	var hint_color := Color(1, 1, 1, 0.5)
	var on_press: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		if style_box != null:
			style_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		if font != null:
			var y := padding + float(font_size)
			for line in lines:
				draw_string(font, Vector2(padding, y + 1.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
				draw_string(font, Vector2(padding, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
				y += line_height
			if not hint_text.is_empty():
				var hint_baseline := padding + float(lines.size()) * line_height + hint_gap + float(hint_font_size)
				draw_string(font, Vector2(padding, hint_baseline + 1.0), hint_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - padding * 2.0, hint_font_size, shadow_color)
				draw_string(font, Vector2(padding, hint_baseline), hint_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - padding * 2.0, hint_font_size, hint_color)
		_draw_tail()

	func _gui_input(event) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if on_press.is_valid():
				on_press.call()
			accept_event()

	func _draw_tail() -> void:
		if tail_side.is_empty():
			return
		var tip := Vector2.ZERO
		var base_a := Vector2.ZERO
		var base_b := Vector2.ZERO
		match tail_side:
			"bottom":
				tip = Vector2(size.x * 0.5, size.y + TAIL_LENGTH)
				base_a = Vector2(clampf(size.x * 0.5 - TAIL_HALF_WIDTH, 0.0, size.x), size.y)
				base_b = Vector2(clampf(size.x * 0.5 + TAIL_HALF_WIDTH, 0.0, size.x), size.y)
			"top":
				tip = Vector2(size.x * 0.5, -TAIL_LENGTH)
				base_a = Vector2(clampf(size.x * 0.5 - TAIL_HALF_WIDTH, 0.0, size.x), 0.0)
				base_b = Vector2(clampf(size.x * 0.5 + TAIL_HALF_WIDTH, 0.0, size.x), 0.0)
			"left":
				tip = Vector2(-TAIL_LENGTH, size.y * 0.5)
				base_a = Vector2(0.0, clampf(size.y * 0.5 - TAIL_HALF_WIDTH, 0.0, size.y))
				base_b = Vector2(0.0, clampf(size.y * 0.5 + TAIL_HALF_WIDTH, 0.0, size.y))
			"right":
				tip = Vector2(size.x + TAIL_LENGTH, size.y * 0.5)
				base_a = Vector2(size.x, clampf(size.y * 0.5 - TAIL_HALF_WIDTH, 0.0, size.y))
				base_b = Vector2(size.x, clampf(size.y * 0.5 + TAIL_HALF_WIDTH, 0.0, size.y))
			_:
				return

		draw_colored_polygon(PackedVector2Array([base_a, base_b, tip]), fill_color)
		draw_line(base_a, tip, border_color, 1.0)
		draw_line(base_b, tip, border_color, 1.0)
