extends "test_runner.gd"

const BattleReplayStore = preload("../core/battle_replay_store.gd")


class FakeRun:
	extends RefCounted


func _store() -> BattleReplayStore:
	return BattleReplayStore.new()


func _meta(battle_id: int, wins := 0, lives := 3, loss_cost := 1) -> Dictionary:
	return {
		"battle_id": battle_id,
		"wins": wins,
		"lives": lives,
		"loss_cost": loss_cost,
	}


func test_capture_requires_both_sides() -> void:
	var store := _store()
	assert_false(store.capture(null, FakeRun.new(), _meta(1)))
	assert_false(store.has_replay())
	assert_false(store.capture(FakeRun.new(), null, _meta(1)))
	assert_false(store.has_replay())


func test_capture_and_payload() -> void:
	var store := _store()
	var p1 := FakeRun.new()
	var p2 := FakeRun.new()
	assert_true(store.capture(p1, p2, _meta(7, 2, 1, 2)))
	assert_true(store.has_replay())
	var payload := store.payload()
	assert_eq(payload.get("p1"), p1)
	assert_eq(payload.get("p2"), p2)
	assert_eq(payload.get("battle_id"), 7)
	assert_eq(payload.get("wins"), 2)
	assert_eq(payload.get("lives"), 1)
	assert_eq(payload.get("loss_cost"), 2)


func test_new_battle_clears_result() -> void:
	var store := _store()
	store.capture(FakeRun.new(), FakeRun.new(), _meta(1))
	store.set_result("VICTORY")
	assert_eq(store.payload().get("result"), "VICTORY")
	store.capture(FakeRun.new(), FakeRun.new(), _meta(2))
	assert_eq(store.payload().get("result"), "")


func test_same_battle_keeps_result() -> void:
	var store := _store()
	store.capture(FakeRun.new(), FakeRun.new(), _meta(1))
	store.set_result("DEFEAT")
	store.capture(FakeRun.new(), FakeRun.new(), _meta(1))
	assert_eq(store.payload().get("result"), "DEFEAT")


func test_result_context_victory() -> void:
	var store := _store()
	store.capture(FakeRun.new(), FakeRun.new(), _meta(1, 1, 2, 2))
	store.set_result("VICTORY")
	var context := store.result_context()
	assert_true(context.get("is_victory"))
	assert_eq(context.get("lives_to_lose"), 0)
	assert_eq(context.get("current_wins"), 1)
	assert_eq(context.get("current_lives"), 2)


func test_result_context_defeat() -> void:
	var store := _store()
	store.capture(FakeRun.new(), FakeRun.new(), _meta(1, 1, 2, 2))
	store.set_result("DEFEAT")
	var context := store.result_context()
	assert_false(context.get("is_victory"))
	assert_eq(context.get("lives_to_lose"), 2)


func test_result_context_draw() -> void:
	var store := _store()
	store.capture(FakeRun.new(), FakeRun.new(), _meta(1, 1, 2, 2))
	store.set_result("DRAW")
	var context := store.result_context()
	assert_false(context.get("is_victory"))
	assert_eq(context.get("lives_to_lose"), 0)


func test_clear() -> void:
	var store := _store()
	store.capture(FakeRun.new(), FakeRun.new(), _meta(1))
	store.set_result("VICTORY")
	store.clear()
	assert_false(store.has_replay())
	assert_empty(store.payload())
	assert_empty(store.result_context())
