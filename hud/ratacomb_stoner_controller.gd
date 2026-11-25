extends RefCounted
## Ratacomb / Green Stone strategy reminders.
##
## Detects only states that can be read reliably from the run roster and the
## shop, then shows at most one line through the shared reminder label. Sound
## follows the existing reminder convention and plays once per stage change.
##
## Every stage requires a Ratacomb in the team or on the bench: the strategy
## starts with the Pipskull evolution, so a Green Stone seen earlier is ignored.
##
## Stage detection (game facts):
## - Pipskull evolves into Ratacomb at 3 knockouts (`pipskull_ability.gd`).
## - Green Stone needs a tier-1 monster and, after Day 2, no permanent buffs on
##   any tier-1 monster (`green_stone_effect.gd`).
## - The shop "lock" is the game's freeze state (`is_shop_frozen`).

const NodeUtils = preload("../core/node_utils.gd")
const ModConfig = preload("../core/mod_config.gd")

const GREEN_STONE_ID := "green_stone"
const RATACOMB_ID := "ratacomb"
const RULE_ID := "ratacomb_stoner"

const STAGE_FIND := "find"
const STAGE_FOUND := "found"
const STAGE_LOCKED := "locked"

const STAGE_MESSAGES := {
	STAGE_FIND: "Ratacomb: Find Green Stone before using an item!",
	STAGE_FOUND: "Green Stone found! Lock it before battle.",
	STAGE_LOCKED: "Keep Green Stone locked while building Multicast.",
}

var _context = null
var _label = null
var _last_stage := ""
var _label_shown := false
var _was_enabled := false


func setup(context, reminder_label) -> void:
	_context = context
	_label = reminder_label


## Refresh the reminder for the current shop state. `gate` is the shop overlay
## gate used by the queued reminder sound.
func update(run, manager, gate) -> void:
	if _label == null:
		return
	if not _enabled():
		if _was_enabled and _context.logger != null and _context.logger.debug_logging:
			_context.logger.log_message("RATACOMB | reminders off (tracker setting or checkbox)")
		_was_enabled = false
		clear()
		return
	_was_enabled = true
	var stage := stage_for(run, manager)
	if _context.logger != null and _context.logger.debug_logging:
		_context.logger.log_message(_debug_line(run, manager, stage))
	if stage.is_empty():
		_last_stage = ""
		_label_shown = false
		_label.clear_source(RULE_ID)
		return
	# Polls run every 500ms; only touch the label when the stage or visibility
	# changed, and chime only on a stage change.
	if stage == _last_stage and _label_shown:
		return
	if stage != _last_stage:
		_last_stage = stage
		if _context.logger != null:
			_context.logger.log_event("RATACOMB REMINDER | %s" % stage)
		_context.chimes.queue_strategy()
		_context.chimes.try_play(gate)
	_label.set_reminders({RULE_ID: str(STAGE_MESSAGES[stage])}, RULE_ID)
	_label_shown = true


## Drop this source's reminder (phase leave, run change).
func clear() -> void:
	_label_shown = false
	if _label != null:
		_label.clear_source(RULE_ID)


func _enabled() -> bool:
	if _context == null or not _context.feature_enabled(ModConfig.KEY_ITEM_USAGE_TRACKER):
		return false
	return _context.ratacomb_stoner_enabled()


## One diagnostic line per shop poll (Debug Logging only) listing every fact the
## stage decision uses, so a missing reminder can be traced to its cause.
func _debug_line(run, manager, stage: String) -> String:
	return "RATACOMB | stage=%s ratacomb=%s stone=%s frozen=%s unbuffed=%s" % [
		"none" if stage.is_empty() else stage,
		has_ratacomb(run),
		green_stone_in_shop(manager),
		shop_locked(manager),
		unbuffed_ratacomb(run),
	]


# --- Detection (pure helpers, unit-tested) ------------------------------------------------------

## The single relevant stage, or "" when nothing applies. Later stages win, so
## the player always sees the next action.
##
## Owning a Ratacomb gates every stage: before the evolution there is no
## Ratacomb to stone, so a Green Stone in the shop is not this rule's business.
static func stage_for(run, manager) -> String:
	if not has_ratacomb(run):
		return ""
	var stone := green_stone_in_shop(manager)
	if stone and shop_locked(manager):
		return STAGE_LOCKED
	if stone:
		return STAGE_FOUND
	if unbuffed_ratacomb(run):
		return STAGE_FIND
	return ""


## A Ratacomb in the team or on the bench (a benched one can still be swapped in
## for the transformation).
static func has_ratacomb(run) -> bool:
	for monster in _roster(run):
		if _species_id(monster) == RATACOMB_ID:
			return true
	return false


static func unbuffed_ratacomb(run) -> bool:
	for monster in _roster(run):
		if _species_id(monster) != RATACOMB_ID:
			continue
		if not monster.has_method("has_any_permanent_buffs"):
			continue
		if not bool(monster.has_any_permanent_buffs()):
			return true
	return false


static func green_stone_in_shop(manager) -> bool:
	var items = NodeUtils.get_or(manager, "current_shop_items", null)
	if not (items is Array):
		return false
	for item in items:
		# string_field covers both ItemData resources and plain dictionaries.
		if NodeUtils.string_field(item, "id") == GREEN_STONE_ID:
			return true
	return false


static func shop_locked(manager) -> bool:
	return bool(NodeUtils.get_or(manager, "is_shop_frozen", false))


static func _roster(run) -> Array:
	var units: Array = []
	for key in ["team", "bench"]:
		var list = NodeUtils.get_or(run, key, null)
		if list is Array:
			units.append_array(list)
	return units


static func _species_id(monster) -> String:
	if monster == null:
		return ""
	var data = NodeUtils.get_or(monster, "data", null)
	return NodeUtils.string_field(data, "id")
