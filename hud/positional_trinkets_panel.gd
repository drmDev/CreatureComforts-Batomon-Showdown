extends "collapsible_panel.gd"
## Movable, collapsible summary of the player's positional trinket bonuses.
##
## The panel is shop-gated by the reminder layer. It starts collapsed on the
## first shop visit, anchors at 25% of the viewport width and height, and keeps
## the player's dragged position and collapsed/expanded choice across visits.

const PositionalTrinkets = preload("../core/positional_trinkets.gd")

const CONTENT_PADDING := 4.0
const BODY_TOP_PADDING := 3.0
const LINE_HEIGHT := 11.0
const SECTION_GAP := 3.0
const TAG_GAP := 6.0
const FONT_SIZE := 8
const SECTION_FONT_SIZE := 9
const TAG_FONT_SIZE := 7
const MAX_WIDTH := 300.0
const TAB_EXTRA_WIDTH := 30.0
const SEPARATOR_ALPHA := 0.35

const SECTION_ORDER := ["left", "top_middle", "right"]
const SECTION_LABELS := {
	"left": "Left Column",
	"top_middle": "Top Middle",
	"right": "Right Column",
}

var _summary: Dictionary = {}
var _anchored := false
var _initialized := false
var _layout_cache: Array = []
var _layout_key := ""


func _init() -> void:
	# Base _init sets up styles and the panel font. Without it, _draw() returns early.
	super._init()
	clamp_to_viewport = true
	draw_when_empty = true


func _ready() -> void:
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
func show_summary(summary: Dictionary) -> void:
	var key := str(summary)
	var first_show := not _initialized
	_summary = summary
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
	var height := HEAD_H + BODY_TOP_PADDING + CONTENT_PADDING
	for row in _layout():
		height += float(row.get("gap_before", 0.0)) + float(row.get("height", LINE_HEIGHT))
	return height + CONTENT_PADDING


func _apply_size() -> void:
	var width := lerpf(_tab_width(), _content_width(), reveal)
	size = Vector2(width, lerpf(HEAD_H + 1.0, full_height(), reveal))
	_clamp_to_viewport()


func _content_width() -> float:
	if _text_font == null:
		return MAX_WIDTH
	var tag_col := _tag_column_width()
	var max_width := 0.0
	for row in _build_rows():
		var text := str(row.get("text", ""))
		var font_size := int(row.get("font_size", FONT_SIZE))
		var width := _text_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if str(row.get("kind", "")) == "bonus":
			width += tag_col
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


func _build_rows() -> Array:
	if not bool(_summary.get("has_any", false)):
		return [{
			"text": "No positional trinkets",
			"kind": "muted",
			"color": LABEL_COLOR,
			"font_size": FONT_SIZE,
		}]

	var rows: Array = []
	var first_section := true
	for position in SECTION_ORDER:
		var section: Dictionary = _summary.get(position, {})
		rows.append({
			"text": SECTION_LABELS[position],
			"kind": "heading",
			"color": VALUE_COLOR,
			"font_size": SECTION_FONT_SIZE,
			"gap_before": 0.0 if first_section else SECTION_GAP,
		})
		first_section = false
		var ordered := PositionalTrinkets.ordered_effects(section)
		if ordered.is_empty():
			rows.append({
				"text": "No bonuses",
				"kind": "muted",
				"color": LABEL_COLOR,
				"font_size": FONT_SIZE,
			})
		else:
			for entry in ordered:
				var effect: Dictionary = entry["effect"]
				var timing := str(entry["timing"])
				rows.append({
					"text": PositionalTrinkets.format_effect(effect),
					"tag": PositionalTrinkets.TAG_LABELS.get(timing, timing),
					"kind": "bonus",
					"color": VALUE_COLOR,
					"font_size": FONT_SIZE,
				})
	return rows


func _tag_column_width() -> float:
	if _text_font == null:
		return 0.0
	var width := 0.0
	for tag in ["Battle Start", "Passive"]:
		width = maxf(width, _text_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT_SIZE).x)
	return width + TAG_GAP


func _wrap_text(text: String, max_width: float, font_size: int) -> Array:
	if max_width <= 0.0 or text.is_empty():
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


func _layout() -> Array:
	if _layout_key == _content_key and not _layout_cache.is_empty():
		return _layout_cache
	_layout_cache = []
	_layout_key = _content_key
	if _text_font == null:
		return _layout_cache
	var content_width := _content_width()
	var text_col := maxf(content_width - CONTENT_PADDING * 2.0 - 2.0 - _tag_column_width(), 20.0)
	for row in _build_rows():
		var kind := str(row.get("kind", "text"))
		var text := str(row.get("text", ""))
		var font_size := int(row.get("font_size", FONT_SIZE))
		var lines: Array = [text]
		var height := LINE_HEIGHT
		if kind == "bonus":
			lines = _wrap_text(text, text_col, font_size)
			height = float(lines.size()) * LINE_HEIGHT
		_layout_cache.append({
			"kind": kind,
			"text": text,
			"tag": str(row.get("tag", "")),
			"font_size": font_size,
			"gap_before": float(row.get("gap_before", 0.0)),
			"lines": lines,
			"height": height,
		})
	return _layout_cache


func _draw_body(_width: float) -> void:
	var rows := _layout()
	var cursor_y := HEAD_H + BODY_TOP_PADDING
	var tag_col := _tag_column_width()
	var tag_box_width := tag_col - TAG_GAP
	var right_edge := size.x - CONTENT_PADDING - 1.0
	for row in rows:
		var gap := float(row.get("gap_before", 0.0))
		if gap > 0.0:
			var sep_y := cursor_y + gap * 0.5
			draw_line(
				Vector2(CONTENT_PADDING + 1.0, sep_y),
				Vector2(size.x - CONTENT_PADDING - 1.0, sep_y),
				Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, SEPARATOR_ALPHA),
				1.0
			)
		cursor_y += gap
		var kind := str(row.get("kind", "text"))
		var font_size := int(row.get("font_size", FONT_SIZE))
		var color: Color = row.get("color", VALUE_COLOR)
		var x := CONTENT_PADDING + 1.0
		var baseline := cursor_y + LINE_HEIGHT - 3.0
		if kind == "bonus":
			var lines: Array = row.get("lines", [])
			for i in range(lines.size()):
				_draw_text_shadow(Vector2(x, baseline + float(i) * LINE_HEIGHT), str(lines[i]), color, font_size)
			if reveal >= 0.999:
				var tag := str(row.get("tag", ""))
				if not tag.is_empty():
					_draw_text_shadow(
						Vector2(right_edge - tag_box_width, baseline),
						tag,
						LABEL_COLOR,
						TAG_FONT_SIZE,
						HORIZONTAL_ALIGNMENT_RIGHT,
						tag_box_width
					)
		else:
			_draw_text_shadow(Vector2(x, baseline), str(row.get("text", "")), color, font_size)
		cursor_y += float(row.get("height", LINE_HEIGHT))
