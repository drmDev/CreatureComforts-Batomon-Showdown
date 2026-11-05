extends RefCounted
## Pure battle-state helpers.
##
## Extracted from mod_main.gd. `is_over` reads the simulation's battle_over flag;
## `classify` turns simulation.data into a result label plus player HP.

const NodeUtils = preload("node_utils.gd")

const RESULT_VICTORY := "VICTORY"
const RESULT_DEFEAT := "DEFEAT"
const RESULT_DRAW := "DRAW"
const RESULT_UNKNOWN := "UNKNOWN"


## True when the battle state's simulation reports battle_over.
static func is_over(state) -> bool:
	if not NodeUtils.has_property(state, "simulation"):
		return false
	var sim = state.get("simulation")
	if sim == null or not is_instance_valid(sim):
		return false
	if not NodeUtils.has_property(sim, "data"):
		return false
	var data = sim.get("data")
	if data == null:
		return false
	return bool(data.get("battle_over"))


## Classify a finished battle from simulation.data.
## Returns {result, hp, detail}; hp is null when the health data is unavailable.
static func classify(battle_data) -> Dictionary:
	if battle_data == null:
		return {"result": RESULT_UNKNOWN, "hp": null, "detail": ""}
	var player_health = battle_data.get("player_health")
	if player_health == null or player_health.size() < 2:
		return {"result": RESULT_UNKNOWN, "hp": null, "detail": "HP unavailable"}
	var player_hp := int(player_health[0])
	var enemy_hp := int(player_health[1])
	var result := RESULT_DRAW
	if player_hp > 0 and enemy_hp <= 0:
		result = RESULT_VICTORY
	elif player_hp <= 0 and enemy_hp > 0:
		result = RESULT_DEFEAT
	return {"result": result, "hp": player_hp, "detail": ""}


## Total simulated battle time in seconds from simulation.data. This is the
## simulation's own clock (affected by fast-forwarding), not wall-clock time.
## Returns 0.0 when the field is missing or invalid.
static func time_elapsed(battle_data) -> float:
	if battle_data == null:
		return 0.0
	var value = battle_data.get("time_elapsed")
	if value == null:
		return 0.0
	return maxf(0.0, float(value))


## Format a simulated duration for the elapsed-time panel (e.g. "12.3s").
static func format_seconds(secs: float) -> String:
	return "%.1fs" % maxf(0.0, secs)
