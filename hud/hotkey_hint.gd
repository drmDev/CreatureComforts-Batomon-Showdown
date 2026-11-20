extends PanelContainer
## Simple hover hint that shows a fixed label above a target control.
##
## A lightweight stand-in for the game's HotkeyHintPrompt: it watches one
## control's mouse_entered/mouse_exited and, after a short dwell, shows a small
## navy/gold panel above it. The hotkey module re-watches it whenever the active
## phase changes (shop bag vs. battle fast-forward).

const Style = preload("../core/style.gd")

const HOVER_DELAY := 0.2
const GAP := 3.0
const EDGE_MARGIN := 2.0
const FONT_SIZE := 9
const TEXT_COLOR := Style.VALUE_COLOR
const SHADOW_COLOR := Style.SHADOW_COLOR
const BG_COLOR := Style.BG_COLOR
const BORDER_COLOR := Style.BORDER_COLOR
const PADDING := 3

var _label: Label
var _watched: Control = null
var _entered: Callable = Callable()
var _exited: Callable = Callable()
var _hovered: Control = null
var _text := ""
var _dwell := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_color = BORDER_COLOR
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(2)
	panel_style.set_content_margin_all(PADDING)
	add_theme_stylebox_override("panel", panel_style)

	_label = Label.new()
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(_label)


## Watch a control and show `text` above it after a short hover.
func watch(target: Control, text: String) -> void:
	unwatch()
	_watched = target
	_entered = _on_entered.bind(target, text)
	_exited = _on_exited.bind(target)
	target.mouse_entered.connect(_entered)
	target.mouse_exited.connect(_exited)


## Disconnect from the currently watched control and hide.
func unwatch() -> void:
	if _watched != null and is_instance_valid(_watched):
		if _entered.is_valid() and _watched.mouse_entered.is_connected(_entered):
			_watched.mouse_entered.disconnect(_entered)
		if _exited.is_valid() and _watched.mouse_exited.is_connected(_exited):
			_watched.mouse_exited.disconnect(_exited)
	_watched = null
	_entered = Callable()
	_exited = Callable()
	_hide()


func _on_entered(target: Control, text: String) -> void:
	_hovered = target
	_text = text
	_dwell = 0.0
	visible = false
	set_process(true)


func _on_exited(target: Control) -> void:
	if target == _hovered:
		_hide()


func _hide() -> void:
	_hovered = null
	visible = false
	set_process(false)


## Show the hint for `target` immediately. Used by the purchase reminder, which
## is driven by the card's own hover signal rather than mouse_entered.
func show_for(target: Control, text: String) -> void:
	_hovered = target
	_text = text
	_dwell = 0.0
	visible = false
	set_process(true)


## Hide the hint without disconnecting any watched control.
func hide_hint() -> void:
	_hide()


func _process(delta: float) -> void:
	if _hovered == null or not is_instance_valid(_hovered) or not _hovered.is_visible_in_tree():
		_hide()
		return
	_dwell += delta
	if _dwell < HOVER_DELAY:
		return
	if not visible:
		_label.text = _text
		_place()
		visible = true


func _place() -> void:
	reset_size()
	var xf := _hovered.get_global_transform_with_canvas()
	var rect := Rect2(xf.origin, _hovered.size * xf.get_scale())
	var view_size := get_viewport().get_visible_rect().size
	var x := rect.position.x + (rect.size.x - size.x) * 0.5
	var y := rect.position.y - size.y - GAP
	if y < EDGE_MARGIN:
		y = rect.position.y + rect.size.y + GAP
	var max_x := maxf(view_size.x - size.x - EDGE_MARGIN, EDGE_MARGIN)
	global_position = Vector2(clampf(x, EDGE_MARGIN, max_x), y)
