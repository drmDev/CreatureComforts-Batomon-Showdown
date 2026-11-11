extends RefCounted
## Holds the last battle's replay inputs so the shop can replay it later.
##
## The game's battle state keeps `_replay_p1_data` and `_replay_p2_data` as
## stable TEMPLATE copies for its own Replay button. This store keeps references
## to those copies (the replay path never mutates them) plus the result context
## the end screen needs. It is cleared when the run or trainer changes.

const BattleMonitor = preload("battle_monitor.gd")

var _p1 = null
var _p2 = null
var _battle_id := 0
var _wins := 0
var _lives := 0
var _loss_cost := 1
var _result := ""


## Capture the current battle's replay inputs. `meta` carries battle_id, wins,
## lives, and loss_cost. A new battle_id clears the previous result; the same
## battle keeps it so a later poll cannot erase the completion.
func capture(p1, p2, meta: Dictionary) -> bool:
	if p1 == null or p2 == null:
		return false
	var battle_id := int(meta.get("battle_id", 0))
	if battle_id != _battle_id:
		_battle_id = battle_id
		_result = ""
	_p1 = p1
	_p2 = p2
	_wins = int(meta.get("wins", 0))
	_lives = int(meta.get("lives", 0))
	_loss_cost = int(meta.get("loss_cost", 1))
	return true


## Record the visual battle's result once it is over.
func set_result(result: String) -> void:
	if not has_replay():
		return
	_result = result


func has_replay() -> bool:
	return _p1 != null and _p2 != null


## Plain payload for the replay controller. The p1/p2 objects are the game's
## TEMPLATE copies; the controller only reads them.
func payload() -> Dictionary:
	if not has_replay():
		return {}
	return {
		"p1": _p1,
		"p2": _p2,
		"battle_id": _battle_id,
		"wins": _wins,
		"lives": _lives,
		"loss_cost": _loss_cost,
		"result": _result,
		"context": result_context(),
	}


## End-screen context for the replay. A draw loses no life; a defeat uses the
## loss cost captured from the live battle.
func result_context() -> Dictionary:
	if not has_replay():
		return {}
	var is_victory := _result == BattleMonitor.RESULT_VICTORY
	var lives_to_lose := 0
	if _result == BattleMonitor.RESULT_DEFEAT:
		lives_to_lose = _loss_cost
	return {
		"is_victory": is_victory,
		"lives_to_lose": lives_to_lose,
		"current_wins": _wins,
		"current_lives": _lives,
	}


func clear() -> void:
	_p1 = null
	_p2 = null
	_battle_id = 0
	_wins = 0
	_lives = 0
	_loss_cost = 1
	_result = ""
