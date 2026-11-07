extends RefCounted
## Battle-scoped trinket gain tracking.
##
## Extracted from mod_main.gd. This is an autobattler: the whole fight is
## simulated before the mod's 500ms poll first sees the battle state, so the
## first battle poll already contains the battle-granted trinkets. A rolling
## snapshot of the last NON-battle state is the "before battle" baseline; the
## end snapshot is frozen at battle_over so later event rewards never leak in.
##
## Gift content from a consumed Locked Box / Mysterious Chest is applied after
## the frozen battle_over snapshot, so it never appears in the ids diff and
## cannot be spoiled; legitimate gains are still shown.

const NodeUtils = preload("node_utils.gd")
const TrinketGains = preload("trinket_gains.gd")
const BattleMonitor = preload("battle_monitor.gd")

var _pre_battle_state = null
var _start = null
var _end = null
var _tracking := false
var _over_seen := false
var _gains_logged := false


## Capture the trinket-relevant fields of a run into a plain dictionary.
static func capture_state(run) -> Dictionary:
	var snapshot := {}
	var ids = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	# Copy the lists so the battle_over snapshot stays frozen if the game mutates the live data.
	snapshot["trinket_ids"] = ids.duplicate() if ids != null else []
	snapshot["trinkets_gained_total"] = int(run.get("trinkets_gained_total")) if NodeUtils.has_property(run, "trinkets_gained_total") else 0
	var used = run.get("used_trinket_ids") if NodeUtils.has_property(run, "used_trinket_ids") else []
	snapshot["used_trinket_ids"] = used.duplicate() if used != null else []
	return snapshot


## Keep a rolling "last state outside battle" snapshot.
func note_non_battle(run) -> void:
	if run != null and is_instance_valid(run):
		_pre_battle_state = capture_state(run)


## Drop all tracking state without reporting gains (new run / trainer change).
func reset() -> void:
	_pre_battle_state = null
	_start = null
	_end = null
	_tracking = false
	_over_seen = false
	_gains_logged = false


## Start tracking when the battle becomes active.
func start(run) -> void:
	if _pre_battle_state != null:
		_start = _pre_battle_state
	else:
		_start = capture_state(run)
	# Provisional end = current; it is frozen the first time battle_over is observed.
	_end = capture_state(run)
	_tracking = true
	_over_seen = false
	_gains_logged = false


## Freeze the end snapshot the first time battle_over is observed.
func poll(state, run) -> void:
	if not _tracking or _over_seen:
		return
	if not BattleMonitor.is_over(state):
		return
	if run != null and is_instance_valid(run):
		_end = capture_state(run)
	_over_seen = true


## Stop tracking and return the gains to display ({} when there are none).
## Acquisitions are logged once; `show_panel` gates the gift diagnostic only.
func finalize(run, logger, formatter, show_panel := true) -> Dictionary:
	if not _tracking and _start == null:
		return {}
	var gains := {}
	if _start != null and _end != null and _over_seen:
		if run != null and is_instance_valid(run):
			gains = TrinketGains.diff_states(_start, _end)
			if not _gains_logged and (not gains["ids"].is_empty() or int(gains["counter"]) != 0):
				_gains_logged = true
				for tid in gains["ids"]:
					logger.log_event("TRINKET ACQUIRED | %s" % str(tid))
				if logger.deep_inspection:
					logger.log_lines(formatter.format_battle_trinket_gains(gains))
			if logger.deep_inspection:
				# Diagnostic: changes applied after the freeze (e.g. event rewards) are excluded.
				var live := capture_state(run)
				var post := TrinketGains.diff_states(_end, live)
				if not post["ids"].is_empty():
					logger.log_message("BATTLE TRINKET GAINS | excluded post-battle additions: %s" % str(post["ids"]))
			if show_panel and logger.deep_inspection and TrinketGains.has_gift_trinket(gains["newly_used"]):
				logger.log_message("BATTLE TRINKET GAINS | gift pending (%s), %d trinket(s) withheld; showing %d gained" % [
					str(gains["newly_used"]), TrinketGains.withheld_count(gains), gains["ids"].size()
				])

	_start = null
	_end = null
	_tracking = false
	_over_seen = false
	_gains_logged = false
	return gains
