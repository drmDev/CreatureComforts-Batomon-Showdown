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
## - A buffed Common blocks the stone outright, so the reminder names how many
##   and asks the player to sell them. This only matters before the shop is
##   locked: once the stone is locked the player keeps access to it, so buffs
##   gained afterwards are part of the plan and must not re-trigger the rule.
## - A tier-1 monster at level 4 or higher also keeps the stone out of the shop
##   (`green_stone_effect.gd`), so the reminder names that blocker too.
## - The shop "lock" is the game's freeze state (`is_shop_frozen`).

const NodeUtils = preload("../core/node_utils.gd")
const ModConfig = preload("../core/mod_config.gd")

const GREEN_STONE_ID := "green_stone"
const RATACOMB_ID := "ratacomb"
const RULE_ID := "ratacomb_stoner"

const STAGE_FIND := "find"
const STAGE_FOUND := "found"
const STAGE_LOCKED := "locked"
const STAGE_BLOCKED := "blocked"

## Tier 1 is "Common" in the game's rarity ladder (`monster_species_data.gd`).
const COMMON_TIER := 1
## A tier-1 monster at this level or higher also keeps the stone out of the shop.
const COMMON_LEVEL_BLOCK := 4

## One message per stage. BLOCKED is a format template because it carries the
## number of buffed Commons; `message_for()` fills it in.
const STAGE_MESSAGES := {
	STAGE_FIND: "Ratacomb: Find Green Stone before using an item!",
	STAGE_FOUND: "Green Stone found! Lock it before battle.",
	STAGE_LOCKED: "Keep Green Stone locked while building Multicast.",
	STAGE_BLOCKED: "Green Stone blocked: %d Common units have permanent buffs - sell them.",
}
## Singular form, so a lone blocker does not read "1 Common units".
const BLOCKED_MESSAGE_ONE := "Green Stone blocked: 1 Common unit has a permanent buff - sell it."
## Second blocker reason, shown alongside the buff line when both apply.
const LEVEL_BLOCKED_MESSAGE := "Level 4+ Commons prevent Green Stone from appearing. Sell them."

var _context = null
var _label = null
var _last_stage := ""
var _last_message := ""
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
	var message := message_for(stage, run)
	if _context.logger != null and _context.logger.debug_logging:
		_context.logger.log_message(_debug_line(run, manager, stage))
	if stage.is_empty():
		_last_stage = ""
		_last_message = ""
		_label_shown = false
		_label.clear_source(RULE_ID)
		return
	# Polls run every 500ms; only touch the label when the stage or its text
	# changed. The text can change within a stage when the buffed-Common count
	# moves. Chime only when the stone is discovered: FIND is a hint and LOCKED
	# is a confirmation, so neither should replay the discovery sound.
	if stage == _last_stage and message == _last_message and _label_shown:
		return
	if stage != _last_stage:
		_last_stage = stage
		if _context.logger != null:
			_context.logger.log_event("RATACOMB REMINDER | %s" % stage)
		if stage == STAGE_FOUND:
			_context.chimes.queue_strategy()
			_context.chimes.try_play(gate)
	_last_message = message
	_label.set_reminders({RULE_ID: message}, RULE_ID)
	_label_shown = true


## Drop this source's reminder (phase leave, run change).
func clear() -> void:
	_last_stage = ""
	_last_message = ""
	_label_shown = false
	if _label != null:
		_label.clear_source(RULE_ID)


## The stage the reminder is currently showing, or "" when the feature is off or
## nothing applies. Read by the field indicators so they follow the same gate.
func current_stage() -> String:
	if not _enabled():
		return ""
	return _last_stage


func _enabled() -> bool:
	if _context == null or not _context.feature_enabled(ModConfig.KEY_ITEM_USAGE_TRACKER):
		return false
	return _context.ratacomb_stoner_enabled()


## One diagnostic line per shop poll (Debug Logging only) listing every fact the
## stage decision uses, so a missing reminder can be traced to its cause.
func _debug_line(run, manager, stage: String) -> String:
	return "RATACOMB | stage=%s ratacomb=%s stone=%s frozen=%s unbuffed=%s buffed_commons=%d level4_commons=%d" % [
		"none" if stage.is_empty() else stage,
		has_ratacomb(run),
		green_stone_in_shop(manager),
		shop_locked(manager),
		unbuffed_ratacomb(run),
		buffed_common_count(run),
		level4_common_count(run),
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
	# A buffed Common or a level 4+ Common keeps the stone out of the shop, so
	# name the blockers before suggesting the player hunt for a stone that cannot
	# appear. A locked shop is excluded: the stone is already secured (or the
	# player has committed), so buffs gained while locked are expected and must
	# not nag.
	if not shop_locked(manager) and roster_blocks_stone(run):
		return STAGE_BLOCKED
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


## The message for a stage. BLOCKED carries the buffed-Common count and can name
## both blocker reasons, so it is built here rather than read straight from
## STAGE_MESSAGES.
static func message_for(stage: String, run) -> String:
	if stage == STAGE_BLOCKED:
		return _blocked_message(run)
	return str(STAGE_MESSAGES.get(stage, ""))


## One line per blocker reason that applies, so both show when both are true.
static func _blocked_message(run) -> String:
	var lines: Array = []
	var buffed := buffed_common_count(run)
	if buffed > 0:
		lines.append(BLOCKED_MESSAGE_ONE if buffed == 1 else str(STAGE_MESSAGES[STAGE_BLOCKED]) % buffed)
	if level4_common_count(run) > 0:
		lines.append(LEVEL_BLOCKED_MESSAGE)
	return "\n".join(lines)


## True when the roster holds a Common that keeps the Green Stone out of the
## shop: a permanent buff or a level 4+ unit.
static func roster_blocks_stone(run) -> bool:
	return buffed_common_count(run) > 0 or level4_common_count(run) > 0


## True when a single unit is a tier-1 Common carrying permanent buffs. The
## game's Green Stone refuses to appear while any such unit exists
## (`green_stone_effect.gd`), so each one is a blocker to sell.
static func is_buffed_common(monster) -> bool:
	if monster == null or not is_instance_valid(monster):
		return false
	if _tier(monster) != COMMON_TIER:
		return false
	if not monster.has_method("has_any_permanent_buffs"):
		return false
	return bool(monster.has_any_permanent_buffs())


## Tier-1 (Common) units in the team or bench carrying permanent buffs.
static func buffed_common_count(run) -> int:
	var count := 0
	for monster in _roster(run):
		if is_buffed_common(monster):
			count += 1
	return count


## Tier-1 (Common) units at level 4 or higher. The game's Green Stone also
## refuses to appear while any of these exist (`green_stone_effect.gd`).
static func level4_common_count(run) -> int:
	var count := 0
	for monster in _roster(run):
		if monster == null:
			continue
		if _tier(monster) != COMMON_TIER:
			continue
		if _level(monster) >= COMMON_LEVEL_BLOCK:
			count += 1
	return count


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


static func _tier(monster) -> int:
	var data = NodeUtils.field_or(monster, "data", null)
	var value = NodeUtils.field_or(data, "tier", 0)
	if value == null:
		return 0
	return int(value)


static func _level(monster) -> int:
	return NodeUtils.int_or(monster, "level", 0)
