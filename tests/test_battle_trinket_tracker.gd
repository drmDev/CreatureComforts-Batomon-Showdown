extends "test_runner.gd"
## Unit tests for core/battle_trinket_tracker.gd and hud/trinket_gain_presenter.gd.

const BattleTrinketTracker = preload("../core/battle_trinket_tracker.gd")
const TrinketGainPresenter = preload("../hud/trinket_gain_presenter.gd")
const RuntimeContext = preload("../core/runtime_context.gd")


class FakeRun:
	extends RefCounted
	var trinket_ids: Array = []
	var trinkets_gained_total := 0
	var used_trinket_ids: Array = []


class FakeSim:
	extends RefCounted
	var data = null


class FakeState:
	extends RefCounted
	var simulation = null


class FakeLogger:
	extends RefCounted
	var deep_inspection := false
	var events: Array = []
	var messages: Array = []

	func log_event(message: String) -> void:
		events.append(message)

	func log_message(message: String) -> void:
		messages.append(message)

	func log_lines(lines: Array) -> void:
		for line in lines:
			messages.append(line)


class FakeFormatter:
	extends RefCounted

	func format_battle_trinket_gains(gains: Dictionary) -> Array:
		return ["gains:%s" % str(gains["ids"])]

	func format_trinket_name(tid: String) -> String:
		return "N:" + tid


class FakePanel:
	extends RefCounted
	var visible := false
	var entries: Array = []
	var hide_calls := 0

	func show_gains(rows: Array) -> void:
		entries = rows
		visible = true

	func hide_panel() -> void:
		hide_calls += 1
		entries = []
		visible = false


func _run(ids: Array, total := 0, used: Array = []) -> FakeRun:
	var run := FakeRun.new()
	run.trinket_ids = ids
	run.trinkets_gained_total = total
	run.used_trinket_ids = used
	return run


func _state(battle_over: bool) -> FakeState:
	var state := FakeState.new()
	var sim := FakeSim.new()
	sim.data = {"battle_over": battle_over}
	state.simulation = sim
	return state


func test_capture_state_copies_lists() -> void:
	var run := _run(["a"], 1, ["x"])
	var snapshot := BattleTrinketTracker.capture_state(run)
	run.trinket_ids.append("b")
	assert_eq(snapshot["trinket_ids"], ["a"])
	assert_eq(snapshot["trinkets_gained_total"], 1)
	assert_eq(snapshot["used_trinket_ids"], ["x"])


func test_start_prefers_pre_battle_baseline() -> void:
	var tracker := BattleTrinketTracker.new()
	tracker.note_non_battle(_run(["a"]))
	tracker.start(_run(["a", "b"]))
	var gains := tracker.finalize(_run(["a", "b"]), FakeLogger.new(), FakeFormatter.new())
	# No battle_over observed yet, so nothing is reported.
	assert_empty(gains)


func test_finalize_reports_gains_after_battle_over() -> void:
	var tracker := BattleTrinketTracker.new()
	tracker.note_non_battle(_run(["a"]))
	tracker.start(_run(["a", "b"]))
	tracker.poll(_state(true), _run(["a", "b", "c"]))
	var logger := FakeLogger.new()
	var gains := tracker.finalize(_run(["a", "b", "c"]), logger, FakeFormatter.new())
	assert_eq(gains["ids"], ["b", "c"])
	assert_eq(logger.events.size(), 2)


func test_finalize_logs_gains_only_once() -> void:
	var tracker := BattleTrinketTracker.new()
	tracker.note_non_battle(_run([]))
	tracker.start(_run(["a"]))
	tracker.poll(_state(true), _run(["a"]))
	var logger := FakeLogger.new()
	tracker.finalize(_run(["a"]), logger, FakeFormatter.new())
	tracker.finalize(_run(["a"]), logger, FakeFormatter.new())
	assert_eq(logger.events.size(), 1)


func test_start_without_baseline_uses_current_inventory() -> void:
	var tracker := BattleTrinketTracker.new()
	tracker.start(_run(["a"]))
	tracker.poll(_state(true), _run(["a", "b"]))
	var gains := tracker.finalize(_run(["a", "b"]), FakeLogger.new(), FakeFormatter.new())
	assert_eq(gains["ids"], ["b"])


func test_poll_ignores_battle_not_over() -> void:
	var tracker := BattleTrinketTracker.new()
	tracker.note_non_battle(_run([]))
	tracker.start(_run([]))
	tracker.poll(_state(false), _run(["a"]))
	var gains := tracker.finalize(_run(["a"]), FakeLogger.new(), FakeFormatter.new())
	assert_empty(gains)


func test_presenter_summarize_counts_duplicates() -> void:
	var entries := TrinketGainPresenter.summarize(["a", "a", "b"], FakeFormatter.new())
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["name"], "N:a")
	assert_eq(entries[0]["count"], 2)
	assert_eq(entries[1]["count"], 1)


func test_presenter_summarize_carries_the_trinket_id() -> void:
	var entries := TrinketGainPresenter.summarize(["a", "a"], FakeFormatter.new())
	assert_eq(entries[0]["id"], "a")


func test_presenter_summarize_sorts_by_count_desc() -> void:
	var entries := TrinketGainPresenter.summarize(
		["z", "y", "y", "y", "x", "x", "x", "x"], FakeFormatter.new())
	assert_eq(entries[0]["id"], "x")
	assert_eq(entries[1]["id"], "y")
	assert_eq(entries[2]["id"], "z")


class FakeConfig:
	extends RefCounted
	var enabled := true

	func is_enabled(_key: String) -> bool:
		return enabled


func _presenter(panel: FakePanel, enabled := true) -> TrinketGainPresenter:
	var presenter := TrinketGainPresenter.new()
	var config := FakeConfig.new()
	config.enabled = enabled
	var context := RuntimeContext.new(FakeFormatter.new(), FakeLogger.new(), config, null, null)
	presenter.setup(panel, context)
	return presenter


## The empty result of every non-battle poll must not wipe a panel still waiting for the shop.
func test_apply_finalized_empty_result_keeps_panel() -> void:
	var panel := FakePanel.new()
	var presenter := _presenter(panel)
	presenter.apply_finalized({"ids": ["a"], "counter": 1, "newly_used": []})
	assert_true(panel.visible)
	presenter.apply_finalized({})
	assert_true(panel.visible)
	assert_eq(panel.hide_calls, 0)
	assert_eq(panel.entries.size(), 1)


func test_apply_finalized_shows_displayable_gains() -> void:
	var panel := FakePanel.new()
	var presenter := _presenter(panel)
	var shown := presenter.apply_finalized({"ids": ["a", "a", "junk"], "counter": 3, "newly_used": []})
	assert_true(shown)
	assert_true(panel.visible)
	assert_eq(panel.entries.size(), 1)
	assert_eq(panel.entries[0]["count"], 2)


func test_apply_finalized_hides_when_nothing_displayable() -> void:
	var panel := FakePanel.new()
	var presenter := _presenter(panel)
	presenter.apply_finalized({"ids": ["a"], "counter": 1, "newly_used": []})
	assert_true(panel.visible)
	var shown := presenter.apply_finalized({"ids": ["junk"], "counter": 1, "newly_used": []})
	assert_false(shown)
	assert_false(panel.visible)


func test_apply_finalized_without_panel_shows_hides() -> void:
	var panel := FakePanel.new()
	var presenter := _presenter(panel)
	presenter.apply_finalized({"ids": ["a"], "counter": 1, "newly_used": []})
	presenter.apply_finalized({"ids": ["b"], "counter": 1, "newly_used": []}, false)
	assert_false(panel.visible)


func test_on_battle_started_hides_panel() -> void:
	var panel := FakePanel.new()
	var presenter := _presenter(panel)
	presenter.apply_finalized({"ids": ["a"], "counter": 1, "newly_used": []})
	presenter.on_battle_started()
	assert_false(panel.visible)
	assert_empty(panel.entries)


func test_apply_finalized_respects_feature_toggle() -> void:
	var panel := FakePanel.new()
	var presenter := _presenter(panel, false)
	var shown := presenter.apply_finalized({"ids": ["a"], "counter": 1, "newly_used": []})
	assert_false(shown)
	assert_false(panel.visible)
