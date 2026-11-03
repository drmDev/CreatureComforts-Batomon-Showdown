extends RefCounted
## Reports each battle's completion exactly once.
##
## Extracted from mod_main.gd. Tracks the current battle state instance id so a
## new battle re-arms the report, and battle_over is only reported once.

const BattleMonitor = preload("battle_monitor.gd")

var _state_id := 0
var _reported := false


## True when this poll should report a completion (first time battle_over is seen).
func check(state) -> bool:
	if state == null or not is_instance_valid(state):
		reset()
		return false
	var instance_id: int = state.get_instance_id()
	if instance_id != _state_id:
		_state_id = instance_id
		_reported = false
	if _reported:
		return false
	if not BattleMonitor.is_over(state):
		return false
	_reported = true
	return true


func reset() -> void:
	_state_id = 0
	_reported = false
