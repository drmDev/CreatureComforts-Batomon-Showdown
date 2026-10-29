extends "test_runner.gd"
## Unit tests for achievements/achievement_evaluator.gd.

const AchievementEvaluator = preload("../achievements/achievement_evaluator.gd")
const TestHelpers = preload("test_helpers.gd")

const GENTLEMAN := "gentleman"
const TWINS := "twins"
const OTHER := "musician"

const RHIZUKA := "monster.name.rhizuka"
const BEETBUD := "monster.name.beetbud"
const BEETDOWN := "monster.name.beetdown"
const FRILLET := "monster.name.frillet"
const DEWLOTL := "monster.name.dewlotl"
const CINNABARK := "monster.name.cinnabark"


func _new_evaluator():
	return AchievementEvaluator.new(func(obj, prop): return TestHelpers.probe(obj, prop))


# --- poll: null / trainer gating ---

func test_poll_null_run_returns_empty() -> void:
	var evaluator = _new_evaluator()
	assert_empty(evaluator.poll(null))


func test_poll_other_trainer_returns_empty() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(RHIZUKA, 2)])
	assert_empty(evaluator.poll(run))


# --- Gentleman: "So I started blasting" ---

func test_gentleman_level2_rhizuka_on_day5_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(GENTLEMAN, 5, [TestHelpers.monster(RHIZUKA, 2)])
	var earned: Array = evaluator.poll(run)
	assert_eq(earned.size(), 1)
	assert_eq(earned[0]["id"], "so_i_started_blasting")


func test_gentleman_rhizuka_on_bench_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(GENTLEMAN, 2, [], [TestHelpers.monster(RHIZUKA, 2)])
	var earned: Array = evaluator.poll(run)
	assert_eq(earned.size(), 1)
	assert_eq(earned[0]["id"], "so_i_started_blasting")


func test_gentleman_rhizuka_after_day5_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(GENTLEMAN, 6, [TestHelpers.monster(RHIZUKA, 2)])
	assert_empty(evaluator.poll(run))


func test_gentleman_level1_rhizuka_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(GENTLEMAN, 3, [TestHelpers.monster(RHIZUKA, 1)])
	assert_empty(evaluator.poll(run))


func test_gentleman_awards_only_once() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(GENTLEMAN, 3, [TestHelpers.monster(RHIZUKA, 2)])
	assert_eq(evaluator.poll(run).size(), 1)
	assert_empty(evaluator.poll(run))


# --- Twins: evolution achievements ---

func test_twins_same_poll_double_beetdown_awards_oh_yeah() -> void:
	var evaluator = _new_evaluator()
	# Poll 1: level-2 Beetbud present, no Beetdown yet -> arms.
	var run1 = TestHelpers.run(TWINS, 3, [TestHelpers.monster(BEETBUD, 2)])
	assert_empty(evaluator.poll(run1))
	# Poll 2: two level-3 Beetdowns appear -> award.
	var run2 = TestHelpers.run(TWINS, 3, [
		TestHelpers.monster(BEETDOWN, 3),
		TestHelpers.monster(BEETDOWN, 3),
	])
	var earned: Array = evaluator.poll(run2)
	assert_eq(earned.size(), 1)
	assert_eq(earned[0]["id"], "oh_yeah")


func test_twins_multi_poll_double_dewlotl_awards_mudkipz() -> void:
	var evaluator = _new_evaluator()
	var run1 = TestHelpers.run(TWINS, 3, [TestHelpers.monster(FRILLET, 2)])
	assert_empty(evaluator.poll(run1))
	# First Dewlotl appears on the next poll.
	var run2 = TestHelpers.run(TWINS, 3, [
		TestHelpers.monster(FRILLET, 2),
		TestHelpers.monster(DEWLOTL, 3),
	])
	assert_empty(evaluator.poll(run2))
	# Second Dewlotl appears on the following poll -> award.
	var run3 = TestHelpers.run(TWINS, 3, [
		TestHelpers.monster(DEWLOTL, 3),
		TestHelpers.monster(DEWLOTL, 3),
	])
	var earned: Array = evaluator.poll(run3)
	assert_eq(earned.size(), 1)
	assert_eq(earned[0]["id"], "herd_u_liek_mudkipz")


func test_twins_no_pre_evolution_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(TWINS, 3, [
		TestHelpers.monster(DEWLOTL, 3),
		TestHelpers.monster(DEWLOTL, 3),
	])
	assert_empty(evaluator.poll(run))


func test_twins_pre_evolution_without_evolution_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(TWINS, 3, [TestHelpers.monster(BEETBUD, 2)])
	assert_empty(evaluator.poll(run))


func test_twins_single_evolution_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run1 = TestHelpers.run(TWINS, 3, [TestHelpers.monster(BEETBUD, 2)])
	assert_empty(evaluator.poll(run1))
	var run2 = TestHelpers.run(TWINS, 3, [TestHelpers.monster(BEETDOWN, 3)])
	assert_empty(evaluator.poll(run2))


# --- poll_battle: "Big Dog, Best Dog" ---

func test_big_dog_over_threshold_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([
		TestHelpers.battle_unit(0, 0, 1000001.0),
	])
	var earned: Array = evaluator.poll_battle(state, run)
	assert_eq(earned.size(), 1)
	assert_eq(earned[0]["id"], "big_dog_best_dog")


func test_big_dog_at_threshold_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([
		TestHelpers.battle_unit(0, 0, 1000000.0),
	])
	assert_empty(evaluator.poll_battle(state, run))


func test_big_dog_sums_shield_per_slot() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([
		TestHelpers.battle_unit(0, 0, 600000.0),
		TestHelpers.battle_unit(0, 0, 600000.0),
	])
	var earned: Array = evaluator.poll_battle(state, run)
	assert_eq(earned.size(), 1)


func test_big_dog_non_cinnabark_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(RHIZUKA, 3)])
	var state = TestHelpers.battle_state([
		TestHelpers.battle_unit(0, 0, 2000000.0),
	])
	assert_empty(evaluator.poll_battle(state, run))


func test_big_dog_enemy_side_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([
		TestHelpers.battle_unit(1, 0, 2000000.0),
	])
	assert_empty(evaluator.poll_battle(state, run))


func test_big_dog_requires_battle_over() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([
		TestHelpers.battle_unit(0, 0, 2000000.0),
	], false)
	assert_empty(evaluator.poll_battle(state, run))


func test_big_dog_awards_once_per_battle_state() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([
		TestHelpers.battle_unit(0, 0, 2000000.0),
	])
	assert_eq(evaluator.poll_battle(state, run).size(), 1)
	assert_empty(evaluator.poll_battle(state, run))


func test_big_dog_new_battle_state_can_award_again() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state1 = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 2000000.0)])
	assert_eq(evaluator.poll_battle(state1, run).size(), 1)
	var state2 = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 2000000.0)])
	assert_eq(evaluator.poll_battle(state2, run).size(), 1)


func test_reset_battle_allows_reward_again() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run(OTHER, 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 2000000.0)])
	assert_eq(evaluator.poll_battle(state, run).size(), 1)
	evaluator.reset_battle()
	assert_eq(evaluator.poll_battle(state, run).size(), 1)
