extends "shop_modal_panel.gd"
## Compact informational popup for the Green Stone / Ratacomb strategy.
##
## Uses the shared shop modal scaffolding (dim backdrop, gold frame, title bar,
## close box, Escape/outside-click dismissal) without drawing its own icon
## button: the Items Used panel hosts the "?" button that toggles this popup.
##
## Text is word-wrapped to the popup width here, so the bullets use the full
## panel instead of being hand-wrapped into short fixed lines.

const TextWrap = preload("../core/text_wrap.gd")

const TIPS_WIDTH := 440.0
const LINE_H := 10.0
const BODY_FONT_SIZE := 7
const HEADING_FONT_SIZE := 8
const BULLET_INDENT := 9.0
const BULLET_RADIUS := 1.5
const HEADING_GAP := 4.0

const SECTIONS := [
	{"heading": "GREEN STONE ELIGIBILITY"},
	{"bullet": "After Day 2: at least one Common in your team, and no Common may have permanent buffs."},
	{"bullet": "Permanent buffs on higher tiers do not matter."},
	{"bullet": "A freshly evolved Ratacomb has no permanent buffs, so Green Stone can still appear. It only counts as buffed once it gains Multicast from knockouts, so lock Green Stone first."},
	{"heading": "RATACOMB STRATEGY"},
	{"bullet": "On the Ratacomb day, avoid using items."},
	{"bullet": "Roll the shop until Green Stone appears."},
	{"bullet": "Lock Green Stone before entering battle."},
	{"bullet": "Battle and relock Green Stone while Ratacomb builds Multicast."},
	{"bullet": "Use Green Stone at x7 Multicast (x5 may be enough when facing elimination)."},
]

var _lines: Array = []
var _lines_width := -1.0


func _init() -> void:
	super._init()
	# The panel beside this popup owns the "?" button.
	use_external_button()


func _popup_title() -> String:
	return "Green Stone Tips"


func _popup_width() -> float:
	return TIPS_WIDTH


func _popup_height() -> float:
	var height := TITLE_H + POPUP_PADDING * 2.0
	for line in _layout_lines():
		height += float(line.get("gap", 0.0)) + LINE_H
	return height


func _draw_content(rect: Rect2) -> void:
	if _text_font == null:
		return
	var x := rect.position.x + POPUP_PADDING
	var baseline := rect.position.y + TITLE_H + POPUP_PADDING
	for line in _layout_lines():
		baseline += float(line.get("gap", 0.0)) + LINE_H
		var text := str(line.get("text", ""))
		if bool(line.get("heading", false)):
			_draw_text_shadow(Vector2(x, baseline), text, BORDER_COLOR, HEADING_FONT_SIZE)
			continue
		if bool(line.get("bullet", false)):
			draw_circle(Vector2(x + BULLET_RADIUS + 1.0, baseline - 2.5), BULLET_RADIUS, BORDER_COLOR)
		_draw_text_shadow(Vector2(x + BULLET_INDENT, baseline), text, LABEL_COLOR, BODY_FONT_SIZE)


## Wrapped display lines for the current popup width, rebuilt only on resize.
func _layout_lines() -> Array:
	var width := _content_width()
	if is_equal_approx(width, _lines_width) and not _lines.is_empty():
		return _lines
	_lines_width = width
	_lines = []
	var first_heading := true
	for entry in SECTIONS:
		if entry.has("heading"):
			_lines.append({
				"text": str(entry["heading"]),
				"heading": true,
				"bullet": false,
				"gap": 0.0 if first_heading else HEADING_GAP,
			})
			first_heading = false
			continue
		var wrapped := TextWrap.wrap(_text_font, str(entry["bullet"]), BODY_FONT_SIZE, width - BULLET_INDENT)
		for index in range(wrapped.size()):
			_lines.append({
				"text": wrapped[index],
				"heading": false,
				"bullet": index == 0,
				"gap": 0.0,
			})
	return _lines


func _content_width() -> float:
	return _popup_width() - POPUP_PADDING * 2.0


