extends "test_runner.gd"
## Unit tests for the Ratacomb / Green Stone stage detection.

const RatacombStoner = preload("../hud/ratacomb_stoner_controller.gd")


class FakeMonster:
	extends RefCounted
	var data := {}
	var blackboard := {}
	var buffed := false

	func has_any_permanent_buffs() -> bool:
		return buffed


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


class FakeRun:
	extends RefCounted
	var team: Array = []
	var bench: Array = []


class FakeManager:
	extends RefCounted
	var current_shop_items: Array = []
	var is_shop_frozen := false


func _monster(id: String, buffed := false, ko_count := 0) -> FakeMonster:
	var monster := FakeMonster.new()
	monster.data = {"id": id}
	monster.buffed = buffed
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
	assert_eq(RatacombStoner.stage_for(run, _manager([])), "")
	# A visible Green Stone is still worth flagging once the player opted in.
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"])),
		RatacombStoner.STAGE_FOUND)


func test_pipskull_near_evolution_prepares() -> void:
	assert_eq(
		RatacombStoner.stage_for(_run([_monster("pipskull", false, 2)]), _manager([])),
		RatacombStoner.STAGE_PREPARE)
	# Fewer knockouts: not yet the transformation day.
	assert_eq(
		RatacombStoner.stage_for(_run([_monster("pipskull", false, 1)]), _manager([])),
		"")


func test_unbuffed_ratacomb_asks_for_green_stone() -> void:
	var run := _run([_monster("ratacomb", false)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager([])),
		RatacombStoner.STAGE_FIND)
	# A buffed Ratacomb cannot take Green Stone, so the prompt is not shown.
	var buffed := _run([_monster("ratacomb", true)])
	assert_eq(RatacombStoner.stage_for(buffed, _manager([])), "")


func test_green_stone_in_shop_reports_found() -> void:
	var run := _run([_monster("ratacomb", false)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"])),
		RatacombStoner.STAGE_FOUND)
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["red_stone"])),
		RatacombStoner.STAGE_FIND)


func test_frozen_shop_with_stone_reports_locked() -> void:
	var run := _run([_monster("ratacomb", false)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true)),
		RatacombStoner.STAGE_LOCKED)


func test_locked_stone_wins_over_found() -> void:
	# A buffed Ratacomb contributes no roster stage, so this isolates the
	# LOCKED-before-FOUND precedence.
	var run := _run([_monster("ratacomb", true)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true)),
		RatacombStoner.STAGE_LOCKED)
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], false)),
		RatacombStoner.STAGE_FOUND)


func test_roster_includes_bench_and_skips_empty_slots() -> void:
	var run := _run([null], [_monster("pipskull", false, 2)])
	assert_true(RatacombStoner.has_stone_target(run))
	assert_eq(
		RatacombStoner.stage_for(run, _manager([])),
		RatacombStoner.STAGE_PREPARE)


func test_resource_species_data_is_detected() -> void:
	# Mirrors production: MonsterInstance.data is a MonsterSpeciesData Resource.
	var monster := ResourceMonster.new()
	monster.data = FakeSpecies.new()
	var run := FakeRun.new()
	run.team = [monster]
	assert_eq(RatacombStoner._species_id(monster), "ratacomb")
	assert_true(RatacombStoner.has_stone_target(run), "Resource species is recognised")
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"])),
		RatacombStoner.STAGE_FOUND)


func test_each_stage_has_a_message() -> void:
	for stage in [
		RatacombStoner.STAGE_PREPARE,
		RatacombStoner.STAGE_FIND,
		RatacombStoner.STAGE_FOUND,
		RatacombStoner.STAGE_LOCKED,
	]:
		assert_true(RatacombStoner.STAGE_MESSAGES.has(stage), stage)
	# The multicast-ready stage was removed; nothing may reintroduce it silently.
	assert_eq(RatacombStoner.STAGE_MESSAGES.size(), 4)
	assert_false(RatacombStoner.STAGE_MESSAGES.has("ready"))
