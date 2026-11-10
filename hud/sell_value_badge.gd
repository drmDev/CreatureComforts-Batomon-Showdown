extends Control
## Top-right gold-coin marker for a boosted sell value.
##
## Reads the slot's live `current_monster` at 10 Hz and only appears when the
## game's own sell value (MonsterInstance.get_sell_value()) is above the unit's
## base, i.e. an item or trinket raised it. The marker is the gold coin icon
## only; hover the unit to see the exact sell value. Non-blocking and
## layout-neutral: it ignores the mouse and never changes the slot's minimum
## size.

const SellValue = preload("../core/sell_value.gd")
const PanelIcons = preload("panel_icons.gd")

const BADGE_NAME := "CreatureComfortsSellValue"
const BADGE_GROUP := "cc_sell_value_badge"
const ICON_FILE := "gold.png"

const ICON_SIZE := 5.25
const MARGIN := 1.5
const PROCESS_INTERVAL := 0.1

## The slot this marker reports on. Set by hud/sell_value_indicators.gd.
var slot = null
## True when the marker lives outside the slot (Container fallback) and must
## follow the slot's global rect instead of using anchors.
var follow_slot := false
var enabled := true

var _phase_visible := true
var _icon: Texture2D = null
var _accum := 0.0


func _init() -> void:
	name = BADGE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 3
	visible = false
	add_to_group(BADGE_GROUP)


func _ready() -> void:
	_icon = PanelIcons.load_icon(str(get_script().resource_path), ICON_FILE)
	size = Vector2(ICON_SIZE, ICON_SIZE)
	if follow_slot:
		_place_at_slot()
	else:
		_anchor_top_right()
	set_process(enabled and _phase_visible)
	_refresh()


## Feature toggle. Disabling hides the marker and stops its polling.
func set_enabled(on: bool) -> void:
	enabled = on
	set_process(on and _phase_visible)
	_refresh()


## Shop-phase gate. The controller hides every marker when the shop is not
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
	if not SellValue.is_boosted(monster):
		visible = false
		return
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


func _anchor_top_right() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -size.x - MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + size.y


## Container fallback: the marker is hosted outside the slot, so place it at the
## slot's top-right corner in the shared canvas space.
func _place_at_slot() -> void:
	if slot == null or not is_instance_valid(slot) or not (slot is Control):
		return
	var rect: Rect2 = slot.get_global_rect()
	global_position = Vector2(
		rect.position.x + rect.size.x - size.x - MARGIN,
		rect.position.y + MARGIN
	)


func _draw() -> void:
	if _icon == null:
		return
	draw_texture_rect(_icon, Rect2(Vector2.ZERO, size), false)
