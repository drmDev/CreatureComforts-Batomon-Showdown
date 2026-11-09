extends "comfort_panel.gd"
## Shared scaffolding for the shop's small icon-button modals.
##
## Owns the button, modal frame, close box, viewport anchoring, and input.
## Subclasses provide the button texture/size/position, popup title and height,
## and the popup content (normally a table).

signal log_line(message: String)
## Emitted when the modal popup opens or closes, so sibling HUD widgets can hide.
signal popup_visibility_changed(open: bool)

const POPUP_WIDTH := 320.0
const POPUP_PADDING := 8.0
const TITLE_H := 22.0
const CLOSE_BTN := 14.0
const VIEWPORT_MARGIN := 8.0
const TEXT_BASELINE_OFFSET := 4.0
const FALLBACK_VIEWPORT_SIZE := Vector2(1280, 720)

const TITLE_FONT_SIZE := 11

const HEADER_BG := Style.HEADER_BG
const DIM_COLOR := Style.DIM_COLOR

var _popup_open := false
var _button_screen_pos := Vector2.ZERO

var _button_texture: Texture2D = null
var _close_texture: Texture2D = null
var _button_style: StyleBoxFlat
var _popup_style: StyleBoxFlat
var _header_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false
	_setup_styles()
	_text_font = _build_panel_font()
	_button_texture = _load_texture(_button_texture_path())
	_close_texture = _load_icon(PanelIcons.CLOSE)
	size = Vector2(_button_size(), _button_size())


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)
	_anchor()


# --- Subclass hooks -----------------------------------------------------------------------------

func _button_size() -> float:
	return 20.0


func _button_texture_path() -> String:
	return ""


func _button_position(_viewport_size: Vector2) -> Vector2:
	return Vector2.ZERO


func _popup_title() -> String:
	return ""


func _popup_height() -> float:
	return TITLE_H + POPUP_PADDING * 2.0


func _draw_content(_rect: Rect2) -> void:
	pass


## Optional hooks so subclasses keep their own log wording.
func _on_button_created() -> void:
	pass


func _on_button_hidden() -> void:
	pass


func _on_popup_opened() -> void:
	pass


func _on_popup_closed() -> void:
	pass


# --- Lifecycle ----------------------------------------------------------------------------------

## Called by subclass setters after updating their state.
func _ensure_visible() -> void:
	if not visible:
		visible = true
		_anchor()
		_on_button_created()
	queue_redraw()


func hide_panel() -> void:
	if _popup_open:
		_close_popup()
	if not visible:
		return
	visible = false
	_on_button_hidden()
	queue_redraw()


## Ensure the popup is closed on shop entry (safety net; hide_panel already closes it).
func reset_for_shop() -> void:
	if _popup_open:
		_close_popup()


func _setup_styles() -> void:
	_button_style = _build_hud_box()

	_popup_style = StyleBoxFlat.new()
	_popup_style.bg_color = BG_COLOR
	_popup_style.border_color = BORDER_COLOR
	_popup_style.set_border_width_all(2)
	_popup_style.set_corner_radius_all(4)

	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = HEADER_BG
	_header_style.border_color = BORDER_COLOR
	_header_style.set_border_width_all(1)
	_header_style.set_corner_radius_all(4)


func _anchor() -> void:
	var viewport_size := _viewport_size()
	_button_screen_pos = _button_position(viewport_size)
	if _popup_open:
		position = Vector2.ZERO
		size = viewport_size
	else:
		position = _button_screen_pos
		size = Vector2(_button_size(), _button_size())
	queue_redraw()


func _on_viewport_resized() -> void:
	_anchor()


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	return viewport.get_visible_rect().size if viewport != null else FALLBACK_VIEWPORT_SIZE


func _open_popup() -> void:
	if _popup_open:
		return
	_popup_open = true
	_anchor()
	grab_focus()
	_on_popup_opened()
	popup_visibility_changed.emit(true)
	queue_redraw()


func _close_popup() -> void:
	if not _popup_open:
		return
	_popup_open = false
	_anchor()
	_on_popup_closed()
	popup_visibility_changed.emit(false)
	queue_redraw()


# --- Layout -------------------------------------------------------------------------------------

## Button rect in local coordinates (the control is button-sized when closed and
## viewport-sized when the popup is open).
func _button_rect() -> Rect2:
	var button_size := Vector2(_button_size(), _button_size())
	if _popup_open:
		return Rect2(_button_screen_pos, button_size)
	return Rect2(Vector2.ZERO, button_size)


func _popup_rect() -> Rect2:
	var viewport_size := _viewport_size()
	var w := minf(POPUP_WIDTH, viewport_size.x - VIEWPORT_MARGIN * 2.0)
	var h := minf(_popup_height(), viewport_size.y - VIEWPORT_MARGIN * 2.0)
	var x := roundf((viewport_size.x - w) * 0.5)
	var y := roundf((viewport_size.y - h) * 0.5)
	return Rect2(Vector2(x, y), Vector2(w, h))


func _close_rect() -> Rect2:
	var r := _popup_rect()
	return Rect2(
		Vector2(r.position.x + r.size.x - POPUP_PADDING - CLOSE_BTN, r.position.y + (TITLE_H - CLOSE_BTN) * 0.5),
		Vector2(CLOSE_BTN, CLOSE_BTN)
	)


# --- Drawing ------------------------------------------------------------------------------------

func _draw() -> void:
	if _text_font == null:
		return
	if _popup_open:
		_draw_popup()
	_draw_button()


func _draw_button() -> void:
	var r := _button_rect()
	_button_style.draw(get_canvas_item(), r)
	if _button_texture != null:
		var pad := 2.0
		_draw_texture_fit(_button_texture, Rect2(r.position + Vector2(pad, pad), r.size - Vector2(pad * 2.0, pad * 2.0)))
	else:
		_draw_text_shadow(r.position + Vector2(0.0, r.size.y - 6.0), "?", VALUE_COLOR, 10, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_popup() -> void:
	# Dim the shop behind the modal popup.
	draw_rect(Rect2(Vector2.ZERO, _viewport_size()), DIM_COLOR)

	var r := _popup_rect()
	_popup_style.draw(get_canvas_item(), r)

	var title_rect := Rect2(r.position, Vector2(r.size.x, TITLE_H))
	_header_style.draw(get_canvas_item(), title_rect)
	_draw_text_shadow(r.position + Vector2(POPUP_PADDING, TITLE_H - 6.0), _popup_title(), VALUE_COLOR, TITLE_FONT_SIZE)

	var close := _close_rect()
	if _close_texture != null:
		_draw_texture_fit(_close_texture, close)

	_draw_content(r)


# --- Input --------------------------------------------------------------------------------------

func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _popup_open:
			if _close_rect().has_point(event.position):
				_close_popup()
			elif not _popup_rect().has_point(event.position):
				_close_popup()  # Clicking the icon again or outside closes
			accept_event()
		elif _button_rect().has_point(event.position):
			_open_popup()
			accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _popup_open:
		_close_popup()
		accept_event()


func _unhandled_input(event) -> void:
	if _popup_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_popup()
		get_viewport().set_input_as_handled()
