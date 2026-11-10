extends "comfort_panel.gd"
## Bottom-right sell-value badge attached to a fielded or bench slot.
##
## Reads the slot's live `current_monster` at 10 Hz and draws the game's own
## sell value (MonsterInstance.get_sell_value()) as a compact gold-coin pill.
## A monster with no sell value (or a 0 value) still shows the coin and 0; only
## an empty slot hides the badge. Non-blocking and layout-neutral: it ignores
## the mouse and never changes the slot's minimum size.

const SellValue = preload("../core/sell_value.gd")

const BADGE_NAME := "CreatureComfortsSellValue"
const BADGE_GROUP := "cc_sell_value_badge"
const ICON_PATH := "../assets/icons/gold.png"

# 25% smaller than the original 8/7/1/2/1/2 values.
const FONT_SIZE := 6
const ICON_SIZE := 5.25
const GAP := 0.75
const PAD_X := 1.5
const PAD_Y := 0.75
const MARGIN := 1.5
const PROCESS_INTERVAL := 0.1

## The slot this badge reports on. Set by hud/sell_value_indicators.gd.
var slot = null
## True when the badge lives outside the slot (Container fallback) and must
## follow the slot's global rect instead of using anchors.
var follow_slot := false
var enabled := true

var _phase_visible := true
var _text := ""
var _boosted := false
var _icon: Texture2D = null
var _box: StyleBoxFlat = null
var _accum := 0.0


func _init() -> void:
	name = BADGE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 3
	visible = false
	_text_font = _build_panel_font()
	_box = _build_hud_box(1, 1)
	add_to_group(BADGE_GROUP)


func _ready() -> void:
	_icon = _load_texture(ICON_PATH)
	if not _text.is_empty():
		_resize_to_text()
	set_process(enabled and _phase_visible)
	_refresh()


## Feature toggle. Disabling hides the badge and stops its polling.
func set_enabled(on: bool) -> void:
	enabled = on
	set_process(on and _phase_visible)
	_refresh()


## Shop-phase gate. The controller hides every badge when the shop is not
## interactive and re-shows them on the next poll.
func set_phase_visible(on: bool) -> void:
	_phase_visible = on
	set_process(on and enabled)
	_refresh()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < PROCESS_INTERVAL:
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	if not enabled or not _phase_visible:
		visible = false
		return
	var monster = _current_monster()
	if monster == null or not is_instance_valid(monster):
		visible = false
		return
	# A monster with no sell value (or a 0 value) still shows the coin and 0;
	# only an empty slot hides the badge.
	var value := SellValue.value_of(monster)
	var boosted := SellValue.is_boosted(monster, value)
	var text := SellValue.text_for(value, boosted)
	if text != _text:
		_text = text
		_resize_to_text()
		queue_redraw()
	if boosted != _boosted:
		_boosted = boosted
		queue_redraw()
	if not visible:
		visible = true
	if follow_slot:
		_place_at_slot()


func _current_monster():
	if slot == null or not is_instance_valid(slot):
		return null
	if not ("current_monster" in slot):
		return null
	return slot.get("current_monster")


func _resize_to_text() -> void:
	var text_w := 0.0
	if _text_font != null:
		text_w = _text_font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var icon_w := ICON_SIZE + GAP if _icon != null else 0.0
	var w := ceilf(PAD_X * 2.0 + icon_w + text_w)
	var h := ceilf(PAD_Y * 2.0 + maxf(ICON_SIZE, float(FONT_SIZE)))
	size = Vector2(w, h)
	if follow_slot:
		_place_at_slot()
	else:
		_anchor_bottom_right()


func _anchor_bottom_right() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -size.x - MARGIN
	offset_right = -MARGIN
	offset_top = -size.y - MARGIN
	offset_bottom = -MARGIN


## Container fallback: the badge is hosted outside the slot, so place it at the
## slot's bottom-right corner in the shared canvas space.
func _place_at_slot() -> void:
	if slot == null or not is_instance_valid(slot) or not (slot is Control):
		return
	var rect: Rect2 = slot.get_global_rect()
	global_position = Vector2(
		rect.position.x + rect.size.x - size.x - MARGIN,
		rect.position.y + rect.size.y - size.y - MARGIN
	)


func _draw() -> void:
	if _box == null or _text_font == null or _text.is_empty():
		return
	_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var x := PAD_X
	if _icon != null:
		var icon_y := (size.y - ICON_SIZE) * 0.5
		draw_texture_rect(_icon, Rect2(Vector2(x, icon_y), Vector2(ICON_SIZE, ICON_SIZE)), false)
		x += ICON_SIZE + GAP
	var baseline := (size.y + float(FONT_SIZE)) * 0.5 - 1.0
	var color := Style.SELL_VALUE_BOOSTED if _boosted else VALUE_COLOR
	_draw_text_shadow(Vector2(x, baseline), _text, color, FONT_SIZE)
