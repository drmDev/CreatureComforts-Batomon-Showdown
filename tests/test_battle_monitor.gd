extends "test_runner.gd"
## Unit tests for core/battle_monitor.gd and core/battle_completion_reporter.gd.

const BattleMonitor = preload("../core/battle_monitor.gd")
const BattleCompletionReporter = preload("../core/battle_completion_reporter.gd")


class FakeSim:
	extends RefCounted
	var data = null


class FakeState:
	extends RefCounted
	var simulation = null


func _state(battle_over: bool) -> FakeState:
	var state := FakeState.new()
	var sim := FakeSim.new()
	sim.data = {"battle_over": battle_over}
	state.simulation = sim
	return state


func test_is_over_true_when_flag_set() -> void:
	assert_true(BattleMonitor.is_over(_state(true)))


func test_is_over_false_when_flag_clear() -> void:
	assert_false(BattleMonitor.is_over(_state(false)))


func test_is_over_false_without_simulation() -> void:
	assert_false(BattleMonitor.is_over(FakeState.new()))
	assert_false(BattleMonitor.is_over(null))


func test_classify_victory() -> void:
	var info := BattleMonitor.classify({"player_health": [12, 0]})
	assert_eq(info["result"], BattleMonitor.RESULT_VICTORY)
	assert_eq(info["hp"], 12)


func test_classify_defeat() -> void:
	var info := BattleMonitor.classify({"player_health": [0, 7]})
	assert_eq(info["result"], BattleMonitor.RESULT_DEFEAT)
	assert_eq(info["hp"], 0)


func test_classify_draw() -> void:
	var info := BattleMonitor.classify({"player_health": [0, 0]})
	assert_eq(info["result"], BattleMonitor.RESULT_DRAW)


func test_classify_missing_data() -> void:
	var info := BattleMonitor.classify(null)
	assert_eq(info["result"], BattleMonitor.RESULT_UNKNOWN)
	assert_eq(info["hp"], null)


func test_classify_missing_health() -> void:
	var info := BattleMonitor.classify({})
	assert_eq(info["result"], BattleMonitor.RESULT_UNKNOWN)
	assert_eq(info["detail"], "HP unavailable")


func test_reporter_fires_once_per_battle() -> void:
	var reporter := BattleCompletionReporter.new()
	var state := _state(true)
	assert_true(reporter.check(state))
	assert_false(reporter.check(state))


func test_reporter_rearms_for_new_state() -> void:
	var reporter := BattleCompletionReporter.new()
	assert_true(reporter.check(_state(true)))
	assert_true(reporter.check(_state(true)))


func test_reporter_waits_for_battle_over() -> void:
	var reporter := BattleCompletionReporter.new()
	var state := _state(false)
	assert_false(reporter.check(state))
	state.simulation.data["battle_over"] = true
	assert_true(reporter.check(state))


func test_reporter_reset() -> void:
	var reporter := BattleCompletionReporter.new()
	var state := _state(true)
	assert_true(reporter.check(state))
	reporter.reset()
	assert_true(reporter.check(state))


func test_time_elapsed_reads_simulated_time() -> void:
	assert_eq(BattleMonitor.time_elapsed({"time_elapsed": 12.34}), 12.34)


func test_time_elapsed_defaults_to_zero() -> void:
	assert_eq(BattleMonitor.time_elapsed(null), 0.0)
	assert_eq(BattleMonitor.time_elapsed({}), 0.0)


func test_time_elapsed_clamps_negative() -> void:
	assert_eq(BattleMonitor.time_elapsed({"time_elapsed": -5.0}), 0.0)


func test_format_seconds() -> void:
	assert_eq(BattleMonitor.format_seconds(12.34), "12.3s")
	assert_eq(BattleMonitor.format_seconds(0.0), "0.0s")
	assert_eq(BattleMonitor.format_seconds(-5.0), "0.0s")
