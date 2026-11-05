extends "comfort_panel.gd"
## Bottom-right battle card: the opponent's display name and MMR.
##
## Positioned about 30% up from the bottom of the viewport. Two lines:
##   <opponent name>
##   MMR: <value>
## The panel is battle-only and shares the Battle Status Panel toggle with the
## lives/wins/day HUD.

const RIGHT_MARGIN := 15.0
const BOTTOM_RATIO := 0.25
const PANEL_HEIGHT := 24.0
const PADDING := 4.0
const MIN_WIDTH := 70.0
const MAX_WIDTH := 160.0
const NAME_SIZE := 9
const NAME_BASELINE := 10.0
const MMR_SIZE := 7
const MMR_BASELINE := 20.0

var _name := ""
var _mmr := "-"
var _panel_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	size = Vector2(MIN_WIDTH, PANEL_HEIGHT)
	custom_minimum_size = Vector2(MIN_WIDTH, PANEL_HEIGHT)
	_setup_styles()
	_text_font = _build_panel_font()


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)
	_anchor_bottom_right()


func _setup_styles() -> void:
	_panel_style = _build_hud_box()


func show_opponent(opp_name: String, mmr: String) -> void:
	if _name == opp_name and _mmr == mmr and visible:
		return
	_name = opp_name
	_mmr = mmr
	_apply_size()
	visible = true
	queue_redraw()


func hide_panel() -> void:
	if not visible:
		return
	visible = false
	queue_redraw()


func _apply_size() -> void:
	var name_w := 0.0
	var mmr_w := 0.0
	if _text_font != null:
		name_w = _text_font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
		mmr_w = _text_font.get_string_size(_mmr_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, MMR_SIZE).x
	var w := clampf(maxf(name_w, mmr_w) + PADDING * 2.0, MIN_WIDTH, MAX_WIDTH)
	size = Vector2(w, PANEL_HEIGHT)
	_anchor_bottom_right()


func _mmr_text() -> String:
	return "MMR: %s" % _mmr


func _anchor_bottom_right() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	position = Vector2(
		roundf(viewport_size.x - size.x - RIGHT_MARGIN),
		roundf(viewport_size.y * (1.0 - BOTTOM_RATIO) - size.y * 0.5)
	)


func _on_viewport_resized() -> void:
	_anchor_bottom_right()


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var shown := _fit_text(_text_font, _name, NAME_SIZE, size.x - PADDING * 2.0)
	_draw_text_shadow(Vector2(PADDING, NAME_BASELINE), shown, VALUE_COLOR, NAME_SIZE)
	_draw_text_shadow(Vector2(PADDING, MMR_BASELINE), _mmr_text(), LABEL_COLOR, MMR_SIZE)
