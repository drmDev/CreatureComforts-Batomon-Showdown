extends RefCounted
## Pure combat statistics capture and aggregation.
##
## Reads the game's own battle statistics (simulation.data.battle_units) into
## plain Dictionaries, so no live game object is retained after capture. Team
## totals are always computed from the captured unit values, which keeps
## "totals equal the sum of their units" true by construction.
##
## Snapshot shape:
##   {
##     "player_team": team,
##     "opponent_team": team,
##   }
##   team:
##   {
##     "units": [unit, ...],
##     "totals": {metric: float or null, ..., "additional_metrics": {...}},
##   }
##   unit:
##   {
##     "unit_name": String, "unit_id": String, "slot_index": int or null,
##     "species_key": String, "damage": float or null,
##     "status_damage": float or null,
##     "healing": float or null, "shield": float or null, "casts": int or null,
##     "additional_metrics": {"burn_inflicted": ..., "poison_inflicted": ...,
##                            "shock_inflicted": ...},
##   }
##
## A missing metric is null, never 0: an unavailable value and a real zero are
## different. Per-unit status damage is the sum of the unit's burn, poison, and
## shock inflicted counters (the same numbers the game's battle stats show).
##
## Ported from BatoStats++ (core/combat_stats.gd) when that mod was merged into
## Creature Comforts.

const NodeUtils = preload("node_utils.gd")

const TEAM_PLAYER := 0
const TEAM_OPPONENT := 1

const METRIC_KEYS := ["damage", "status_damage", "healing", "shield", "casts"]
const ADDITIONAL_METRIC_KEYS := ["burn_inflicted", "poison_inflicted", "shock_inflicted"]

const METRIC_LABELS := {
	"damage": "Damage",
	"status_damage": "Status Damage",
	"healing": "Healing",
	"shield": "Shield",
	"casts": "Casts",
}


## Capture a battle snapshot from simulation.data. Returns {} when the data is
## unusable (null, or no battle_units array).
static func capture(battle_data) -> Dictionary:
	if battle_data == null:
		return {}
	if not NodeUtils.has_property(battle_data, "battle_units"):
		return {}
	var units = battle_data.get("battle_units")
	if not (units is Array):
		return {}

	var player_units: Array = []
	var opponent_units: Array = []
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		var team_id = _read_int(unit, "team_id")
		if team_id == null:
			continue
		var entry := _read_unit(unit)
		if team_id == TEAM_PLAYER:
			player_units.append(entry)
		elif team_id == TEAM_OPPONENT:
			opponent_units.append(entry)

	return {
		"player_team": _team_snapshot(player_units),
		"opponent_team": _team_snapshot(opponent_units),
	}


## Display label for a metric key.
static func metric_label(key: String) -> String:
	return str(METRIC_LABELS.get(key, key.capitalize()))


## Comparison operator between the player's and opponent's totals. "?" when
## either side is unavailable.
static func compare(player_value, opponent_value) -> String:
	if player_value == null or opponent_value == null:
		return "?"
	var p := float(player_value)
	var o := float(opponent_value)
	if is_equal_approx(p, o):
		return "="
	return ">" if p > o else "<"


## Format a metric value for display: thousands separators, no trailing ".0" for
## whole numbers, and "-" for an unavailable (null) value.
static func format_value(value) -> String:
	if value == null:
		return "-"
	var number := float(value)
	var rounded := roundf(number)
	if is_equal_approx(number, rounded):
		return _group_thousands(str(int(rounded)))
	return _group_thousands("%.1f" % number)


static func _read_unit(unit) -> Dictionary:
	var burn = _read_float(unit, "burn_inflicted")
	var poison = _read_float(unit, "poison_inflicted")
	var shock = _read_float(unit, "shock_inflicted")
	return {
		"unit_name": _read_name(unit),
		"unit_id": _read_unit_id(unit),
		"slot_index": _read_int(unit, "slot_index"),
		"species_key": _read_species_key(unit),
		"damage": _read_float(unit, "damage_dealt"),
		"status_damage": _sum_optional([burn, poison, shock]),
		"healing": _read_float(unit, "healing_done"),
		"shield": _read_float(unit, "shield_granted"),
		"casts": _read_int(unit, "cast_count"),
		"additional_metrics": {
			"burn_inflicted": burn,
			"poison_inflicted": poison,
			"shock_inflicted": shock,
		},
	}


static func _read_name(unit) -> String:
	for prop in ["unit_name", "name_key", "species_key"]:
		var name := _read_string(unit, prop)
		if not name.is_empty():
			return name
	var data = unit.get("data") if NodeUtils.has_property(unit, "data") else null
	return _read_string(data, "name_key")


## The species key used to look up the monster's icon in the game database.
## Prefers data.name_key (the key the watchlist uses for team monsters), then
## the unit's own key fields, then the display name so an icon lookup is still
## attempted. Always a plain String: the snapshot retains no live objects.
static func _read_species_key(unit) -> String:
	var data = unit.get("data") if NodeUtils.has_property(unit, "data") else null
	for prop in ["name_key", "species_key"]:
		var key := _read_string(data, prop)
		if not key.is_empty():
			return key
	for prop in ["name_key", "species_key", "unit_name"]:
		var key := _read_string(unit, prop)
		if not key.is_empty():
			return key
	return ""


## Non-empty String value of `prop` on `obj`, or "" when missing or empty.
static func _read_string(obj, prop: String) -> String:
	if not NodeUtils.has_property(obj, prop):
		return ""
	var value = obj.get(prop)
	if value == null or str(value).is_empty():
		return ""
	return str(value)


static func _read_unit_id(unit) -> String:
	for prop in ["unit_id", "id"]:
		if NodeUtils.has_property(unit, prop):
			var value = unit.get(prop)
			if value != null:
				return str(value)
	var slot = _read_int(unit, "slot_index")
	var team = _read_int(unit, "team_id")
	if slot != null and team != null:
		return "t%d_s%d" % [team, slot]
	return ""


static func _read_float(obj, prop: String):
	if not NodeUtils.has_property(obj, prop):
		return null
	var value = obj.get(prop)
	if value == null or not (value is int or value is float):
		return null
	return float(value)


static func _read_int(obj, prop: String):
	if not NodeUtils.has_property(obj, prop):
		return null
	var value = obj.get(prop)
	if value == null or not (value is int or value is float):
		return null
	return int(value)


static func _team_snapshot(units: Array) -> Dictionary:
	return {
		"units": units,
		"totals": _totals(units),
	}


static func _totals(units: Array) -> Dictionary:
	var totals := {}
	for key in METRIC_KEYS:
		totals[key] = _sum_metric(units, key)
	var additional := {}
	for key in ADDITIONAL_METRIC_KEYS:
		additional[key] = _sum_additional(units, key)
	totals["additional_metrics"] = additional
	return totals


## Sum a top-level unit metric. Null when no unit exposes it; otherwise the sum
## of the available values (a null unit value contributes nothing).
static func _sum_metric(units: Array, key: String):
	var total = null
	for unit in units:
		var value = unit.get(key)
		if value == null:
			continue
		total = (0.0 if total == null else float(total)) + float(value)
	return total


static func _sum_additional(units: Array, key: String):
	var total = null
	for unit in units:
		var additional: Dictionary = unit.get("additional_metrics", {})
		var value = additional.get(key)
		if value == null:
			continue
		total = (0.0 if total == null else float(total)) + float(value)
	return total


## Sum the available values; null when every value is null.
static func _sum_optional(values: Array):
	var total = null
	for value in values:
		if value == null:
			continue
		total = (0.0 if total == null else float(total)) + float(value)
	return total


static func _group_thousands(text: String) -> String:
	var negative := text.begins_with("-")
	if negative:
		text = text.substr(1)
	var parts := text.split(".")
	var whole := parts[0]
	var grouped := ""
	var count := 0
	for i in range(whole.length() - 1, -1, -1):
		grouped = whole[i] + grouped
		count += 1
		if count % 3 == 0 and i > 0:
			grouped = "," + grouped
	var result := grouped
	if parts.size() > 1:
		result += "." + parts[1]
	return ("-" if negative else "") + result
