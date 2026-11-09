extends "test_runner.gd"
## Unit tests for core/combat_stats.gd (ported from BatoStats++).

const CombatStats = preload("../core/combat_stats.gd")


class FakeUnit:
	extends RefCounted
	var team_id := 0
	var slot_index := 0
	var unit_name := ""
	var data = null
	var damage_dealt := 0.0
	var healing_done := 0.0
	var shield_granted := 0.0
	var cast_count := 0
	var burn_inflicted := 0
	var poison_inflicted := 0
	var shock_inflicted := 0


## Stand-in for a species resource: the icon lookup key lives on data.name_key.
class FakeSpeciesData:
	extends RefCounted
	var name_key := ""


## A unit that exposes only a subset of the metrics, to exercise null handling.
class SparseUnit:
	extends RefCounted
	var team_id := 0
	var slot_index := 0
	var damage_dealt := 0.0


class FakeBattleData:
	extends RefCounted
	var battle_units: Array = []


func _unit(team: int, slot: int, name: String, damage: float, healing: float, shield: float, casts: int, burn: int, poison: int, shock: int) -> FakeUnit:
	var u := FakeUnit.new()
	u.team_id = team
	u.slot_index = slot
	u.unit_name = name
	u.damage_dealt = damage
	u.healing_done = healing
	u.shield_granted = shield
	u.cast_count = casts
	u.burn_inflicted = burn
	u.poison_inflicted = poison
	u.shock_inflicted = shock
	return u


func _data(units: Array) -> FakeBattleData:
	var d := FakeBattleData.new()
	d.battle_units = units
	return d


func test_capture_returns_empty_without_battle_data() -> void:
	assert_true(CombatStats.capture(null).is_empty())
	assert_true(CombatStats.capture({}).is_empty())


func test_capture_splits_teams() -> void:
	var data := _data([
		_unit(0, 0, "Lignite", 100.0, 0.0, 10.0, 3, 0, 0, 0),
		_unit(0, 1, "Cinnabark", 200.0, 5.0, 20.0, 4, 0, 0, 0),
		_unit(1, 0, "Emberpaw", 150.0, 0.0, 0.0, 2, 0, 0, 0),
	])
	var snapshot := CombatStats.capture(data)
	assert_eq(snapshot["player_team"]["units"].size(), 2)
	assert_eq(snapshot["opponent_team"]["units"].size(), 1)


func test_totals_equal_sum_of_units() -> void:
	var data := _data([
		_unit(0, 0, "Lignite", 100.0, 10.0, 5.0, 3, 0, 0, 0),
		_unit(0, 1, "Cinnabark", 200.0, 20.0, 15.0, 4, 0, 0, 0),
	])
	var totals: Dictionary = CombatStats.capture(data)["player_team"]["totals"]
	assert_eq(totals["damage"], 300.0)
	assert_eq(totals["healing"], 30.0)
	assert_eq(totals["shield"], 20.0)
	assert_eq(totals["casts"], 7)


func test_status_damage_is_sum_of_inflicted() -> void:
	var data := _data([
		_unit(0, 0, "Lignite", 100.0, 0.0, 0.0, 0, 470, 0, 0),
		_unit(0, 1, "Cinnabark", 100.0, 0.0, 0.0, 0, 10, 20, 30),
	])
	var units: Array = CombatStats.capture(data)["player_team"]["units"]
	assert_eq(units[0]["status_damage"], 470.0)
	assert_eq(units[1]["status_damage"], 60.0)
	var totals: Dictionary = CombatStats.capture(data)["player_team"]["totals"]
	assert_eq(totals["status_damage"], 530.0)


func test_missing_metric_is_null_not_zero() -> void:
	var sparse := SparseUnit.new()
	sparse.team_id = 0
	sparse.slot_index = 0
	sparse.damage_dealt = 50.0
	var data := _data([sparse])
	var unit: Dictionary = CombatStats.capture(data)["player_team"]["units"][0]
	assert_eq(unit["healing"], null)
	assert_eq(unit["shield"], null)
	assert_eq(unit["casts"], null)
	assert_eq(unit["status_damage"], null)
	var totals: Dictionary = CombatStats.capture(data)["player_team"]["totals"]
	assert_eq(totals["healing"], null)
	assert_eq(totals["damage"], 50.0)


func test_zero_metric_is_zero() -> void:
	var data := _data([
		_unit(0, 0, "Lignite", 100.0, 0.0, 0.0, 0, 0, 0, 0),
	])
	var unit: Dictionary = CombatStats.capture(data)["player_team"]["units"][0]
	assert_eq(unit["healing"], 0.0)
	assert_eq(unit["status_damage"], 0.0)
	var totals: Dictionary = CombatStats.capture(data)["player_team"]["totals"]
	assert_eq(totals["healing"], 0.0)


func test_capture_retains_no_live_references() -> void:
	var unit := _unit(0, 0, "Lignite", 100.0, 0.0, 0.0, 3, 0, 0, 0)
	var data := _data([unit])
	var snapshot := CombatStats.capture(data)
	unit.damage_dealt = 999.0
	unit.unit_name = "Changed"
	var captured: Dictionary = snapshot["player_team"]["units"][0]
	assert_eq(captured["damage"], 100.0)
	assert_eq(captured["unit_name"], "Lignite")


func test_species_key_prefers_data_name_key() -> void:
	var unit := _unit(0, 0, "Leafleap", 0.0, 0.0, 0.0, 0, 0, 0, 0)
	var species := FakeSpeciesData.new()
	species.name_key = "monster.name.leafleap"
	unit.data = species
	var captured: Dictionary = CombatStats.capture(_data([unit]))["player_team"]["units"][0]
	assert_eq(captured["species_key"], "monster.name.leafleap")


func test_species_key_falls_back_to_unit_name() -> void:
	var unit := _unit(0, 0, "monster.name.cairnage", 0.0, 0.0, 0.0, 0, 0, 0, 0)
	var captured: Dictionary = CombatStats.capture(_data([unit]))["player_team"]["units"][0]
	assert_eq(captured["species_key"], "monster.name.cairnage")


func test_compare_operators() -> void:
	assert_eq(CombatStats.compare(10.0, 5.0), ">")
	assert_eq(CombatStats.compare(5.0, 10.0), "<")
	assert_eq(CombatStats.compare(5.0, 5.0), "=")
	assert_eq(CombatStats.compare(null, 5.0), "?")
	assert_eq(CombatStats.compare(5.0, null), "?")


func test_format_value() -> void:
	assert_eq(CombatStats.format_value(12500.0), "12,500")
	assert_eq(CombatStats.format_value(0.0), "0")
	assert_eq(CombatStats.format_value(null), "-")
	assert_eq(CombatStats.format_value(1234.5), "1,234.5")
	assert_eq(CombatStats.format_value(-1500.0), "-1,500")


func test_metric_labels() -> void:
	assert_eq(CombatStats.metric_label("damage"), "Damage")
	assert_eq(CombatStats.metric_label("status_damage"), "Status Damage")
	assert_eq(CombatStats.metric_label("casts"), "Casts")
