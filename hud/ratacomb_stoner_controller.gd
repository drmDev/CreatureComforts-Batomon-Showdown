extends RefCounted
## Ratacomb / Green Stone strategy reminders.
##
## Detects only states that can be read reliably from the run roster and the
## shop, then shows at most one line through the shared reminder label. Sound
## follows the existing reminder convention and plays once per stage change.
##
## Stage detection (game facts):
## - Pipskull evolves into Ratacomb at 3 knockouts (`pipskull_ability.gd`).
## - Ratacomb gains a permanent Multicast (Stat.CAST_CT) buff per knockout.
## - Green Stone needs a tier-1 monster and, after Day 2, no permanent buffs on
##   any tier-1 monster (`green_stone_effect.gd`).
## - The shop "lock" is the game's freeze state (`is_shop_frozen`).

const NodeUtils = preload("../core/node_utils.gd")
const ModConfig = preload("../core/mod_config.gd")

const GREEN_STONE_ID := "green_stone"
const RATACOMB_ID := "ratacomb"
const PIPSKULL_ID := "pipskull"
const PIPSKULL_KO_THRESHOLD := 3  # game's pipskull_ability.gd ko_threshold
const MULTICAST_READY := 7
const RULE_ID := "ratacomb_stoner"
const STAT_SCRIPT_PATH := "res://game/monsters/stat.gd"

const STAGE_PREPARE := "prepare"
const STAGE_FIND := "find"
const STAGE_FOUND := "found"
const STAGE_LOCKED := "locked"
const STAGE_READY := "ready"

const STAGE_MESSAGES := {
	STAGE_PREPARE: "Ratacomb: Prepare to roll for Green Stone.",
	STAGE_FIND: "Ratacomb: Find Green Stone before using an item!",
	STAGE_FOUND: "Green Stone found! Lock it before battle.",
	STAGE_LOCKED: "Keep Green Stone locked while building Multicast.",
	STAGE_READY: "Ratacomb x7 Multicast - ready to transform!",
}

var _context = null
var _label = null
var _last_stage := ""
var _label_shown := false
var _was_enabled := false

static var _cast_ct_key = null


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
	return "RATACOMB | stage=%s target=%s stone=%s frozen=%s unbuffed=%s pipskull=%s multicast=%d" % [
		"none" if stage.is_empty() else stage,
		has_stone_target(run),
		green_stone_in_shop(manager),
		shop_locked(manager),
		unbuffed_ratacomb(run),
		pipskull_near_evolution(run),
		ratacomb_multicast(run),
	]


# --- Detection (pure helpers, unit-tested) ------------------------------------------------------

## The single relevant stage, or "" when nothing applies. Later stages win, so
## the player always sees the next action.
##
## The shop stages do not require the roster: the player opted in with the
## Ratacomb Stoner checkbox, and "Green Stone visible in shop" is useful on its
## own. FIND/PREPARE inherently need the roster check, and READY requires the
## Ratacomb multicast count.
static func stage_for(run, manager, cast_ct_key = null) -> String:
	var stone := green_stone_in_shop(manager)
	if stone and ratacomb_multicast(run, cast_ct_key) >= MULTICAST_READY:
		return STAGE_READY
	if stone and shop_locked(manager):
		return STAGE_LOCKED
	if stone:
		return STAGE_FOUND
	if unbuffed_ratacomb(run):
		return STAGE_FIND
	if pipskull_near_evolution(run):
		return STAGE_PREPARE
	return ""


static func has_stone_target(run) -> bool:
	for monster in _roster(run):
		var id := _species_id(monster)
		if id == PIPSKULL_ID or id == RATACOMB_ID:
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


static func pipskull_near_evolution(run) -> bool:
	for monster in _roster(run):
		if _species_id(monster) != PIPSKULL_ID:
			continue
		var blackboard = NodeUtils.get_or(monster, "blackboard", {})
		if blackboard is Dictionary and int(blackboard.get("ko_count", 0)) >= PIPSKULL_KO_THRESHOLD - 1:
			return true
	return false


## Highest Ratacomb Multicast stat, or -1 when the stat key cannot be resolved
## (so the ready stage is skipped rather than guessed).
static func ratacomb_multicast(run, cast_ct_key = null) -> int:
	var key = cast_ct_key if cast_ct_key != null else _resolve_cast_ct_key()
	if key == null:
		return -1
	var best := -1
	for monster in _roster(run):
		if _species_id(monster) != RATACOMB_ID:
			continue
		if not monster.has_method("get_stat"):
			continue
		best = maxi(best, int(monster.get_stat(key)))
	return best


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


## Stat.CAST_CT from the game script, resolved by path so this mod file still
## parses standalone (the check script has no game class names).
static func _resolve_cast_ct_key():
	if _cast_ct_key != null:
		return _cast_ct_key
	# Retry on failure: the game script may not be loadable yet on an early call.
	if ResourceLoader.exists(STAT_SCRIPT_PATH):
		var script = load(STAT_SCRIPT_PATH)
		if script is Script:
			_cast_ct_key = script.get_script_constant_map().get("CAST_CT", null)
	return _cast_ct_key
