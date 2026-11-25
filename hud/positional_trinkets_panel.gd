extends "collapsible_panel.gd"
## Bonuses tab content: the player's positional and economical trinket bonuses.
##
## Renders two groups: the positional breakdown (left column, top middle, right
## column) and the economical trinkets (sell value, income, gold payouts). A
## group is omitted when the player holds no trinket from it.
##
## Embedded in hud/trinkets_panel.gd, which owns the frame, header, tabs and
## visibility. This view only paints rows and reports its natural size.

const PositionalTrinkets = preload("../core/positional_trinkets.gd")
const EconomicalTrinkets = preload("../core/economical_trinkets.gd")

const CONTENT_PADDING := 3.0
const BODY_TOP_PADDING := 2.0
const LINE_HEIGHT := 10.0
const CATEGORY_GAP := 4.0
const POSITION_GAP := 2.0
const TAG_GAP := 6.0
const FONT_SIZE := 8
const CATEGORY_FONT_SIZE := 9
const POSITION_FONT_SIZE := 7
const SECONDARY_FONT_SIZE := 7
const TAG_FONT_SIZE := 7
const SEPARATOR_ALPHA := 0.35

## Dimmest text, used for secondary explanations such as "No more Items".
const MUTED_COLOR := Style.MUTED_COLOR

const SECTION_LABELS := {
	"left": "LEFT COLUMN",
	"top_middle": "TOP MIDDLE",
	"right": "RIGHT COLUMN",
}

var _summary: Dictionary = {}
var _layout_cache: Array = []
var _layout_key := ""
var _rows_cache: Array = []
var _rows_key := ""


## Show the current summary. Unchanged content (every shop poll) is a no-op.
func show_summary(summary: Dictionary) -> void:
	var key := str(summary)
	if key == _content_key:
		return
	_summary = summary
	_content_key = key
	_notify_layout()
	queue_redraw()


func hide_panel() -> void:
	if _summary.is_empty():
		return
	_summary = {}
	_content_key = ""
	_notify_layout()
	queue_redraw()


func full_height() -> float:
	var height := BODY_TOP_PADDING + CONTENT_PADDING
	for row in _layout():
		height += float(row.get("gap_before", 0.0)) + float(row.get("height", LINE_HEIGHT))
	return height + CONTENT_PADDING


## True when a summary is held (drives the host panel's visibility).
func has_content() -> bool:
	return not _summary.is_empty()


## Drop the wrapped-row cache when the host changes the assigned width.
func embedded_height(width: float) -> float:
	if not is_equal_approx(width, embedded_width):
		_layout_cache = []
		_layout_key = ""
	return super.embedded_height(width)


func _content_width() -> float:
	return embedded_width


## Rows are rebuilt only when the summary or assigned width changes, so repeated
## shop polls and redraws reuse the cached rows.
func _build_rows() -> Array:
	if _rows_key == _content_key and not _rows_cache.is_empty():
		return _rows_cache
	_rows_key = _content_key
	_rows_cache = _compose_rows()
	return _rows_cache


func _compose_rows() -> Array:
	var positional: Dictionary = _summary.get("positional", {})
	var economical: Dictionary = _summary.get("economical", {})
	var has_positional := bool(positional.get("has_any", false))
	var has_economical := bool(economical.get("has_any", false))
	if not has_positional and not has_economical:
		return [{
			"text": "No trinket bonuses",
			"kind": "muted",
			"color": LABEL_COLOR,
			"font_size": FONT_SIZE,
		}]

	var rows: Array = []
	var first_category := true
	if has_positional:
		rows.append(_category_row("POSITIONAL", first_category))
		first_category = false
		# Only positions with active bonuses are shown, so the panel stays
		# compact and a column appears as soon as a relevant trinket is held.
		for position in PositionalTrinkets.active_positions(positional):
			rows.append({
				"text": SECTION_LABELS[position],
				"kind": "position",
				"color": LABEL_COLOR,
				"font_size": POSITION_FONT_SIZE,
				"gap_before": POSITION_GAP,
			})
			for entry in PositionalTrinkets.ordered_effects(positional.get(position, {})):
				var effect: Dictionary = entry["effect"]
				var timing := str(entry["timing"])
				rows.append({
					"text": PositionalTrinkets.format_effect(effect),
					"tag": PositionalTrinkets.TAG_LABELS.get(timing, timing),
					"kind": "bonus",
					"color": VALUE_COLOR,
					"font_size": FONT_SIZE,
				})
	if has_economical:
		rows.append(_category_row("ECONOMY", first_category))
		first_category = false
		for entry in EconomicalTrinkets.ordered_effects(economical):
			var effect: Dictionary = entry["effect"]
			var timing := str(entry["timing"])
			if effect.has("text"):
				# Secondary explanations (e.g. "No more Items") are muted and
				# carry no effect tag.
				rows.append({
					"text": EconomicalTrinkets.format_effect(effect),
					"kind": "secondary",
					"color": MUTED_COLOR,
					"font_size": SECONDARY_FONT_SIZE,
				})
			else:
				rows.append({
					"text": EconomicalTrinkets.format_effect(effect, timing),
					"tag": EconomicalTrinkets.TAG_LABELS.get(timing, timing),
					"kind": "bonus",
					"color": VALUE_COLOR,
					"font_size": FONT_SIZE,
				})
	return rows


func _category_row(text: String, first: bool) -> Dictionary:
	return {
		"text": text,
		"kind": "category",
		"color": BORDER_COLOR,
		"font_size": CATEGORY_FONT_SIZE,
		"gap_before": 0.0 if first else CATEGORY_GAP,
		"separator": not first,
	}


func _tag_column_width() -> float:
	if _text_font == null:
		return 0.0
	var width := 0.0
	for row in _build_rows():
		var tag := str(row.get("tag", ""))
		if tag.is_empty():
			continue
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
	var full_col := maxf(content_width - CONTENT_PADDING * 2.0 - 2.0, 20.0)
	for row in _build_rows():
		var kind := str(row.get("kind", "text"))
		var text := str(row.get("text", ""))
		var font_size := int(row.get("font_size", FONT_SIZE))
		var lines: Array = [text]
		var height := LINE_HEIGHT
		if kind == "bonus":
			lines = _wrap_text(text, text_col, font_size)
			height = float(lines.size()) * LINE_HEIGHT
		elif kind == "secondary":
			lines = _wrap_text(text, full_col, font_size)
			height = float(lines.size()) * LINE_HEIGHT
		_layout_cache.append({
			"kind": kind,
			"text": text,
			"tag": str(row.get("tag", "")),
			"font_size": font_size,
			"gap_before": float(row.get("gap_before", 0.0)),
			"separator": bool(row.get("separator", false)),
			"lines": lines,
			"height": height,
		})
	return _layout_cache


func _draw_body(_width: float) -> void:
	var rows := _layout()
	var cursor_y := BODY_TOP_PADDING
	var tag_col := _tag_column_width()
	var tag_box_width := tag_col - TAG_GAP
	var right_edge := size.x - CONTENT_PADDING - 1.0
	for row in rows:
		var gap := float(row.get("gap_before", 0.0))
		if bool(row.get("separator", false)) and gap > 0.0:
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
		if kind == "bonus" or kind == "secondary":
			var lines: Array = row.get("lines", [])
			for i in range(lines.size()):
				_draw_text_shadow(Vector2(x, baseline + float(i) * LINE_HEIGHT), str(lines[i]), color, font_size)
			if kind == "bonus":
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
