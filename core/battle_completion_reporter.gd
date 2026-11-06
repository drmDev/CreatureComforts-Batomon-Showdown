extends RefCounted
## Reports each visual battle's completion exactly once.
##
## Extracted from mod_main.gd. Tracks the current battle state instance id so a
## new battle re-arms the report, and battle_over is only reported once per
## visual battle. A replay restarts the simulation inside the same battle state,
## so a new simulation instance (or battle_over falling back to false) re-arms
## the report for the replay's own completion.

const NodeUtils = preload("node_utils.gd")
const BattleMonitor = preload("battle_monitor.gd")

var _state_id := 0
var _sim_id := 0
var _reported := false
var _completion_count := 0


## True when this poll should report a completion (first time battle_over is
## seen for the current visual battle).
func check(state) -> bool:
	if state == null or not is_instance_valid(state):
		reset()
		return false
	var instance_id: int = state.get_instance_id()
	if instance_id != _state_id:
		_state_id = instance_id
		_sim_id = 0
		_reported = false
		_completion_count = 0
	var sim = state.get("simulation") if NodeUtils.has_property(state, "simulation") else null
	var sim_id: int = sim.get_instance_id() if sim != null and is_instance_valid(sim) else 0
	if sim_id != _sim_id:
		# A replay builds a fresh simulation inside the same battle state.
		_sim_id = sim_id
		_reported = false
	if not BattleMonitor.is_over(state):
		# The replay is running; re-arm so its end is reported too.
		_reported = false
		return false
	if _reported:
		return false
	_reported = true
	_completion_count += 1
	return true


## True when the last check() reported the first completion of this battle
## state (the initial battle, not a replay). Used to log the result once.
func is_first_completion() -> bool:
	return _completion_count == 1


func reset() -> void:
	_state_id = 0
	_sim_id = 0
	_reported = false
	_completion_count = 0
