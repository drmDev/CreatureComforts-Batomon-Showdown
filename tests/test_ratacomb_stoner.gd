extends "test_runner.gd"
## Unit tests for the Ratacomb / Green Stone stage detection.

const RatacombStoner = preload("../hud/ratacomb_stoner_controller.gd")

## Any non-null key works: FakeMonster.get_stat ignores it.
const CTRL_KEY := 7


class FakeMonster:
	extends RefCounted
	var data := {}
	var blackboard := {}
	var buffed := false
	var multicast := 1

	func has_any_permanent_buffs() -> bool:
		return buffed

	func get_stat(_key) -> float:
		return float(multicast)


## Production species data is a Resource with an `id` var, not a Dictionary.
class FakeSpecies:
	extends Resource
	var id := "ratacomb"


class ResourceMonster:
	extends RefCounted
	var data: Resource = null
	var buffed := false

	func has_any_permanent_buffs() -> bool:
		return buffed

	func get_stat(_key) -> float:
		return 1.0


class FakeRun:
	extends RefCounted
	var team: Array = []
	var bench: Array = []


class FakeManager:
	extends RefCounted
	var current_shop_items: Array = []
	var is_shop_frozen := false


func _monster(id: String, buffed := false, multicast := 1, ko_count := 0) -> FakeMonster:
	var monster := FakeMonster.new()
	monster.data = {"id": id}
	monster.buffed = buffed
	monster.multicast = multicast
	monster.blackboard = {"ko_count": ko_count}
	return monster


func _run(monsters: Array, bench: Array = []) -> FakeRun:
	var run := FakeRun.new()
	run.team = monsters
	run.bench = bench
	return run


func _manager(shop_ids: Array, frozen := false) -> FakeManager:
	var manager := FakeManager.new()
	for id in shop_ids:
		manager.current_shop_items.append({"id": id})
	manager.is_shop_frozen = frozen
	return manager


func test_no_pipskull_or_ratacomb_means_no_roster_reminder() -> void:
	var run := _run([_monster("emberpaw")])
	assert_eq(RatacombStoner.stage_for(run, _manager([]), CTRL_KEY), "")
	# A visible Green Stone is still worth flagging once the player opted in.
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"]), CTRL_KEY),
		RatacombStoner.STAGE_FOUND)


func test_pipskull_near_evolution_prepares() -> void:
	assert_eq(
		RatacombStoner.stage_for(_run([_monster("pipskull", false, 1, 2)]), _manager([]), CTRL_KEY),
		RatacombStoner.STAGE_PREPARE)
	# Fewer knockouts: not yet the transformation day.
	assert_eq(
		RatacombStoner.stage_for(_run([_monster("pipskull", false, 1, 1)]), _manager([]), CTRL_KEY),
		"")


func test_unbuffed_ratacomb_asks_for_green_stone() -> void:
	var run := _run([_monster("ratacomb", false)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager([]), CTRL_KEY),
		RatacombStoner.STAGE_FIND)
	# A buffed Ratacomb cannot take Green Stone, so the prompt is not shown.
	var buffed := _run([_monster("ratacomb", true)])
	assert_eq(RatacombStoner.stage_for(buffed, _manager([]), CTRL_KEY), "")


func test_green_stone_in_shop_reports_found() -> void:
	var run := _run([_monster("ratacomb", false)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"]), CTRL_KEY),
		RatacombStoner.STAGE_FOUND)
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["red_stone"]), CTRL_KEY),
		RatacombStoner.STAGE_FIND)


func test_frozen_shop_with_stone_reports_locked() -> void:
	var run := _run([_monster("ratacomb", false)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true), CTRL_KEY),
		RatacombStoner.STAGE_LOCKED)


func test_multicast_target_wins_once_reached() -> void:
	var run := _run([_monster("ratacomb", true, 7)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true), CTRL_KEY),
		RatacombStoner.STAGE_READY)
	var below := _run([_monster("ratacomb", true, 6)])
	assert_eq(
		RatacombStoner.stage_for(below, _manager(["green_stone"], true), CTRL_KEY),
		RatacombStoner.STAGE_LOCKED)


func test_ready_stage_needs_a_visible_stone() -> void:
	var run := _run([_monster("ratacomb", true, 9)])
	assert_eq(RatacombStoner.stage_for(run, _manager([]), CTRL_KEY), "")


func test_roster_includes_bench_and_skips_empty_slots() -> void:
	var run := _run([null], [_monster("pipskull", false, 1, 2)])
	assert_true(RatacombStoner.has_stone_target(run))
	assert_eq(
		RatacombStoner.stage_for(run, _manager([]), CTRL_KEY),
		RatacombStoner.STAGE_PREPARE)


func test_multicast_is_unknown_without_a_stat_key() -> void:
	# Headless runs have no game stat script, so the helper must degrade safely.
	assert_eq(RatacombStoner.ratacomb_multicast(_run([_monster("ratacomb")])), -1)


func test_resource_species_data_is_detected() -> void:
	# Mirrors production: MonsterInstance.data is a MonsterSpeciesData Resource.
	var monster := ResourceMonster.new()
	monster.data = FakeSpecies.new()
	var run := FakeRun.new()
	run.team = [monster]
	assert_eq(RatacombStoner._species_id(monster), "ratacomb")
	assert_true(RatacombStoner.has_stone_target(run), "Resource species is recognised")
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"]), CTRL_KEY),
		RatacombStoner.STAGE_FOUND)


func test_each_stage_has_a_message() -> void:
	for stage in [
		RatacombStoner.STAGE_PREPARE,
		RatacombStoner.STAGE_FIND,
		RatacombStoner.STAGE_FOUND,
		RatacombStoner.STAGE_LOCKED,
		RatacombStoner.STAGE_READY,
	]:
		assert_true(RatacombStoner.STAGE_MESSAGES.has(stage), stage)
	assert_eq(
		RatacombStoner.STAGE_MESSAGES[RatacombStoner.STAGE_READY],
		"Ratacomb x7 Multicast - ready to transform!")
