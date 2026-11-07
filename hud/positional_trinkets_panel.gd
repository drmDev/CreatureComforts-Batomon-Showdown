extends "collapsible_panel.gd"
## Movable, collapsible summary of the player's positional trinket bonuses.
##
## The panel is shop-gated by the reminder layer. It starts collapsed on the
## first shop visit, anchors at 25% of the viewport width and height, and keeps
## the player's dragged position and collapsed/expanded choice across visits.

const PositionalTrinkets = preload("../core/positional_trinkets.gd")

const CONTENT_PADDING := 5.0
const BODY_TOP_PADDING := 4.0
const LINE_HEIGHT := 12.0
const SECTION_GAP := 4.0
const INDENT_WIDTH := 8.0
const FONT_SIZE := 8
const SECTION_FONT_SIZE := 9
const MAX_WIDTH := 280.0
const TAB_EXTRA_WIDTH := 30.0
const CLIPPY_SIZE := 16.0
const CLIPPY_GAP := 2.0
const CLIPPY_THRESHOLD := 10

const SECTION_ORDER := ["left", "top_middle", "right"]
const SECTION_LABELS := {
	"left": "LEFT COLUMN",
	"top_middle": "TOP MIDDLE",
	"right": "RIGHT COLUMN",
}

var _summary: Dictionary = {}
var _anchored := false
var _initialized := false
var _clippy_texture: Texture2D = null
var _trinket_count := 0


func _init() -> void:
	# Base _init sets up styles and the panel font. Without it, _draw() returns early and
	# only the clippy icon is visible.
	super._init()
	clamp_to_viewport = true
	draw_when_empty = true
	clip_contents = false


func _ready() -> void:
	_clippy_texture = _load_texture("../assets/icons/clippy.png")
	minimized = true
	reveal = 0.0
	_apply_size()
	_connect_viewport_resize(_on_viewport_resized)


func header_text() -> String:
	return "Positional Trinkets"


func header_width() -> float:
	return _tab_width()


## Show the current summary. The first call starts collapsed and anchors the
## panel; later calls preserve the player's position and collapsed state.
## `trinket_count` is the total number of held trinkets, used for the clippy
## icon threshold.
func show_summary(summary: Dictionary, trinket_count: int = 0) -> void:
	var key := "%d|%s" % [trinket_count, str(summary)]
	var first_show := not _initialized
	_summary = summary
	_trinket_count = trinket_count
	if first_show:
		_initialized = true
		minimized = true
		reveal = 0.0
		_content_key = key
		_apply_size()
		if not _anchored:
			_anchor_initial()
			_anchored = true
	elif key != _content_key:
		_content_key = key
		_apply_size()
	visible = true
	queue_redraw()


func hide_panel() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_summary = {}
	_content_key = ""
	visible = false
	queue_redraw()


## Reset to the collapsed state on a new run/trainer. The dragged position is
## kept, so the player does not have to move the panel again.
func reset_collapsed() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_initialized = false
	minimized = true
	reveal = 0.0
	_summary = {}
	_content_key = ""
	visible = false
	_apply_size()
	queue_redraw()


func full_height() -> float:
	var rows := _build_rows()
	var height := HEAD_H + BODY_TOP_PADDING + CONTENT_PADDING
	for row in rows:
		height += float(row.get("gap_before", 0.0)) + LINE_HEIGHT
	return height + CONTENT_PADDING


func _apply_size() -> void:
	var width := lerpf(_tab_width(), _content_width(), reveal)
	size = Vector2(width, lerpf(HEAD_H + 1.0, full_height(), reveal))
	_clamp_to_viewport()


func _content_width() -> float:
	if _text_font == null:
		return MAX_WIDTH
	var max_width := 0.0
	for row in _build_rows():
		var text := str(row.get("text", ""))
		var font_size := int(row.get("font_size", FONT_SIZE))
		var indent := float(row.get("indent", 0)) * INDENT_WIDTH
		var width := indent + _text_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_width = maxf(max_width, width)
	return clampf(max_width + CONTENT_PADDING * 2.0 + 2.0, _tab_width(), MAX_WIDTH)


func _tab_width() -> float:
	if _text_font == null:
		return MAX_WIDTH
	var title_width := _text_font.get_string_size(header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	return title_width + BTN + TAB_EXTRA_WIDTH


func _anchor_initial() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var bounds := viewport.get_visible_rect().size
	position = Vector2(bounds.x * 0.25, bounds.y * 0.25)
	_clamp_to_viewport()


func _on_viewport_resized() -> void:
	_clamp_to_viewport()


## Draw the clippy icon just to the left of the panel once the player holds at
## least CLIPPY_THRESHOLD trinkets. The panel disables clipping so the icon can
## sit outside its own rect.
func _draw() -> void:
	if _trinket_count >= CLIPPY_THRESHOLD and _clippy_texture != null:
		draw_texture_rect(
			_clippy_texture,
			Rect2(Vector2(-CLIPPY_SIZE - CLIPPY_GAP, 0.0), Vector2(CLIPPY_SIZE, CLIPPY_SIZE)),
			false
		)
	super._draw()


## Keep the icon inside the viewport too: when it is visible, the panel cannot
## be dragged closer than the icon's width plus gap to the left edge.
func _clamp_to_viewport() -> void:
	super._clamp_to_viewport()
	if _trinket_count >= CLIPPY_THRESHOLD and _clippy_texture != null:
		position.x = maxf(position.x, CLIPPY_SIZE + CLIPPY_GAP)


func _build_rows() -> Array:
	if not bool(_summary.get("has_any", false)):
		return [{
			"text": "No positional trinkets",
			"indent": 0,
			"color": LABEL_COLOR,
			"font_size": FONT_SIZE,
		}]

	var rows: Array = []
	var first_section := true
	for position in SECTION_ORDER:
		var section: Dictionary = _summary.get(position, {})
		rows.append({
			"text": SECTION_LABELS[position],
			"indent": 0,
			"color": VALUE_COLOR,
			"font_size": SECTION_FONT_SIZE,
			"gap_before": 0.0 if first_section else SECTION_GAP,
		})
		first_section = false
		rows.append({
			"text": "Passive:",
			"indent": 1,
			"color": LABEL_COLOR,
			"font_size": FONT_SIZE,
		})
		_append_effects(rows, section.get("passive", []))
		rows.append({
			"text": "Permanent (Battle Start):",
			"indent": 1,
			"color": LABEL_COLOR,
			"font_size": FONT_SIZE,
		})
		_append_effects(rows, section.get("permanent", []))
	return rows


func _append_effects(rows: Array, effects: Array) -> void:
	if effects.is_empty():
		rows.append({
			"text": "None",
			"indent": 2,
			"color": LABEL_COLOR,
			"font_size": FONT_SIZE,
		})
		return
	for effect in effects:
		rows.append({
			"text": PositionalTrinkets.format_effect(effect),
			"indent": 2,
			"color": VALUE_COLOR,
			"font_size": FONT_SIZE,
		})


func _draw_body(width: float) -> void:
	var rows := _build_rows()
	var cursor_y := HEAD_H + BODY_TOP_PADDING
	draw_rect(
		Rect2(CONTENT_PADDING, HEAD_H + 2.0, maxf(0.0, width - CONTENT_PADDING * 2.0), 1.0),
		BORDER_COLOR
	)
	for row in rows:
		cursor_y += float(row.get("gap_before", 0.0))
		var baseline := cursor_y + LINE_HEIGHT - 3.0
		var x := CONTENT_PADDING + 1.0 + float(row.get("indent", 0)) * INDENT_WIDTH
		_draw_text_shadow(
			Vector2(x, baseline),
			str(row.get("text", "")),
			row.get("color", VALUE_COLOR),
			int(row.get("font_size", FONT_SIZE))
		)
		cursor_y += LINE_HEIGHT
