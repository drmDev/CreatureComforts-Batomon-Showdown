extends "test_runner.gd"
## Unit tests for the Ratacomb / Green Stone stage detection.

const RatacombStoner = preload("../hud/ratacomb_stoner_controller.gd")


class FakeMonster:
	extends RefCounted
	var data := {}
	var buffed := false
	var level := 1

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


func _monster(id: String, buffed := false, tier := 1, level := 1) -> FakeMonster:
	var monster := FakeMonster.new()
	monster.data = {"id": id, "tier": tier}
	monster.buffed = buffed
	monster.level = level
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


func test_no_ratacomb_means_no_reminder_ever() -> void:
	# Reported bug: Day 1 Pipskull with Green Stone in the shop showed
	# "Green Stone found! Lock it before battle."
	var run := _run([_monster("pipskull"), _monster("emberpaw")])
	assert_eq(RatacombStoner.stage_for(run, _manager([])), "")
	assert_eq(RatacombStoner.stage_for(run, _manager(["green_stone"])), "")
	assert_eq(RatacombStoner.stage_for(run, _manager(["green_stone"], true)), "")
	assert_false(RatacombStoner.has_ratacomb(run))


func test_pipskull_is_not_a_ratacomb_stage() -> void:
	# A near-evolution Pipskull still owns no Ratacomb, so nothing is shown.
	var run := _run([_monster("pipskull")])
	assert_eq(RatacombStoner.stage_for(run, _manager(["green_stone"])), "")
	assert_eq(RatacombStoner.stage_for(_run([_monster("pipskull")]), _manager([])), "")


func test_unbuffed_ratacomb_asks_for_green_stone() -> void:
	var run := _run([_monster("ratacomb", false)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager([])),
		RatacombStoner.STAGE_FIND)
	# A buffed Ratacomb cannot take Green Stone; the stone is blocked instead.
	var buffed := _run([_monster("ratacomb", true)])
	assert_eq(RatacombStoner.stage_for(buffed, _manager([])), RatacombStoner.STAGE_BLOCKED)


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
	# A buffed Ratacomb contributes only the BLOCKED stage, so this isolates the
	# LOCKED-before-FOUND precedence.
	var run := _run([_monster("ratacomb", true)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true)),
		RatacombStoner.STAGE_LOCKED)
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], false)),
		RatacombStoner.STAGE_FOUND)


func test_bench_counts_as_owned_and_empty_slots_are_skipped() -> void:
	var run := _run([null], [_monster("ratacomb", false)])
	assert_true(RatacombStoner.has_ratacomb(run), "bench Ratacomb is owned")
	assert_eq(
		RatacombStoner.stage_for(run, _manager([])),
		RatacombStoner.STAGE_FIND)
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"])),
		RatacombStoner.STAGE_FOUND)


func test_resource_species_data_is_detected() -> void:
	# Mirrors production: MonsterInstance.data is a MonsterSpeciesData Resource.
	var monster := ResourceMonster.new()
	monster.data = FakeSpecies.new()
	var run := FakeRun.new()
	run.team = [monster]
	assert_eq(RatacombStoner._species_id(monster), "ratacomb")
	assert_true(RatacombStoner.has_ratacomb(run), "Resource species is recognised")
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"])),
		RatacombStoner.STAGE_FOUND)


func test_each_stage_has_a_message() -> void:
	for stage in [
		RatacombStoner.STAGE_FIND,
		RatacombStoner.STAGE_FOUND,
		RatacombStoner.STAGE_LOCKED,
		RatacombStoner.STAGE_BLOCKED,
	]:
		assert_true(RatacombStoner.STAGE_MESSAGES.has(stage), stage)
	# The prepare and multicast-ready stages were removed; nothing may
	# reintroduce a stage that fires before a Ratacomb is owned.
	assert_eq(RatacombStoner.STAGE_MESSAGES.size(), 4)
	assert_false(RatacombStoner.STAGE_MESSAGES.has("prepare"))
	assert_false(RatacombStoner.STAGE_MESSAGES.has("ready"))


func test_buffed_common_blocks_green_stone() -> void:
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", true)])
	assert_eq(RatacombStoner.buffed_common_count(run), 1)
	assert_eq(RatacombStoner.stage_for(run, _manager([])), RatacombStoner.STAGE_BLOCKED)
	assert_eq(
		RatacombStoner.message_for(RatacombStoner.STAGE_BLOCKED, run),
		"Green Stone blocked: 1 Common unit has a permanent buff - sell it.")


func test_buffed_common_count_pluralises() -> void:
	var run := _run([
		_monster("ratacomb", false),
		_monster("emberpaw", true),
		_monster("mossling", true),
	])
	assert_eq(RatacombStoner.buffed_common_count(run), 2)
	assert_eq(
		RatacombStoner.message_for(RatacombStoner.STAGE_BLOCKED, run),
		"Green Stone blocked: 2 Common units have permanent buffs - sell them.")


func test_higher_tier_buffs_do_not_block() -> void:
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", true, 3)])
	assert_eq(RatacombStoner.buffed_common_count(run), 0)
	assert_eq(RatacombStoner.stage_for(run, _manager([])), RatacombStoner.STAGE_FIND)


func test_bench_buffed_common_counts() -> void:
	var run := _run([_monster("ratacomb", false)], [_monster("emberpaw", true)])
	assert_eq(RatacombStoner.buffed_common_count(run), 1)
	assert_eq(RatacombStoner.stage_for(run, _manager([])), RatacombStoner.STAGE_BLOCKED)


func test_stone_in_shop_wins_over_blocked() -> void:
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", true)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"])),
		RatacombStoner.STAGE_FOUND)
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true)),
		RatacombStoner.STAGE_LOCKED)


func test_no_ratacomb_means_no_blocked_reminder() -> void:
	var run := _run([_monster("emberpaw", true)])
	assert_eq(RatacombStoner.buffed_common_count(run), 1)
	assert_eq(RatacombStoner.stage_for(run, _manager([])), "")


func test_locked_shop_silences_blocked_rule() -> void:
	# Locking the shop means the stone is already secured, so buffs gained while
	# locked are part of the plan and must not re-trigger the blocked rule.
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", true)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true)),
		RatacombStoner.STAGE_LOCKED)
	# Locked without the stone: the stone cannot appear until the shop is
	# unlocked, so the blocked rule stays quiet and the existing FIND rule
	# takes over.
	assert_eq(
		RatacombStoner.stage_for(run, _manager([], true)),
		RatacombStoner.STAGE_FIND)
	# A buffed Ratacomb with a locked, stone-less shop shows nothing at all.
	var buffed := _run([_monster("ratacomb", true)])
	assert_eq(RatacombStoner.stage_for(buffed, _manager([], true)), "")


func test_level4_common_blocks_green_stone() -> void:
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", false, 1, 4)])
	assert_eq(RatacombStoner.level4_common_count(run), 1)
	assert_eq(RatacombStoner.stage_for(run, _manager([])), RatacombStoner.STAGE_BLOCKED)
	assert_eq(
		RatacombStoner.message_for(RatacombStoner.STAGE_BLOCKED, run),
		"Level 4+ Commons prevent Green Stone from appearing. Sell them.")


func test_level3_common_does_not_block() -> void:
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", false, 1, 3)])
	assert_eq(RatacombStoner.level4_common_count(run), 0)
	assert_eq(RatacombStoner.stage_for(run, _manager([])), RatacombStoner.STAGE_FIND)


func test_higher_tier_level4_does_not_block() -> void:
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", false, 3, 4)])
	assert_eq(RatacombStoner.level4_common_count(run), 0)
	assert_eq(RatacombStoner.stage_for(run, _manager([])), RatacombStoner.STAGE_FIND)


func test_both_blocker_reasons_show_together() -> void:
	var run := _run([
		_monster("ratacomb", false),
		_monster("emberpaw", true),
		_monster("mossling", false, 1, 4),
	])
	assert_eq(RatacombStoner.buffed_common_count(run), 1)
	assert_eq(RatacombStoner.level4_common_count(run), 1)
	assert_eq(
		RatacombStoner.message_for(RatacombStoner.STAGE_BLOCKED, run),
		"Green Stone blocked: 1 Common unit has a permanent buff - sell it.\n"
		+ "Level 4+ Commons prevent Green Stone from appearing. Sell them.")


func test_locked_shop_silences_level4_rule() -> void:
	var run := _run([_monster("ratacomb", false), _monster("emberpaw", false, 1, 4)])
	assert_eq(
		RatacombStoner.stage_for(run, _manager(["green_stone"], true)),
		RatacombStoner.STAGE_LOCKED)
	assert_eq(
		RatacombStoner.stage_for(run, _manager([], true)),
		RatacombStoner.STAGE_FIND)


func test_is_buffed_common() -> void:
	# The field badge uses this per-unit check, so it must match the count logic.
	assert_true(RatacombStoner.is_buffed_common(_monster("emberpaw", true)))
	assert_false(RatacombStoner.is_buffed_common(_monster("emberpaw", false)))
	assert_false(RatacombStoner.is_buffed_common(_monster("emberpaw", true, 3)))
	assert_false(RatacombStoner.is_buffed_common(null))
