extends "test_runner.gd"
## Unit tests for core/item_usage_tracker.gd and the daily-usage helper.

const ItemUsageTracker = preload("../core/item_usage_tracker.gd")
const ItemsUsedController = preload("../hud/items_used_controller.gd")
const ItemsUsedPanel = preload("../hud/items_used_panel.gd")

const TEST_DIR := "user://creature_comforts_test/items_used"


class FakeFormatter:
	extends RefCounted

	func format_item_name(item_id: String) -> String:
		return item_id.replace("_", " ").capitalize()


class FakeRun:
	extends RefCounted
	var blackboard := {}

	func get_shop_item_budget() -> int:
		return int(blackboard.get("max_items_per_round", 1))


func _tracker():
	var tracker = ItemUsageTracker.new()
	tracker.use_store_dir(TEST_DIR)
	return tracker


func _clean() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)


func test_counts_aggregate_and_sort_by_count_then_name() -> void:
	_clean()
	var tracker = _tracker()
	tracker.load_run("run_sort")
	assert_true(tracker.record_use("green_stone"))
	assert_true(tracker.record_use("green_stone"))
	assert_true(tracker.record_use("red_stone"))
	assert_true(tracker.record_use("upgrade_disc"))
	var rows = tracker.entries(FakeFormatter.new())
	assert_eq(rows.size(), 3)
	assert_eq(rows[0]["id"], "green_stone")
	assert_eq(int(rows[0]["count"]), 2)
	# Equal counts fall back to the display name, ascending.
	assert_eq(rows[1]["name"], "Red Stone")
	assert_eq(rows[2]["name"], "Upgrade Disc")
	assert_eq(tracker.total_used(), 4)
	_clean()


func test_blank_item_id_is_ignored() -> void:
	var tracker = _tracker()
	tracker.load_run("run_blank")
	assert_false(tracker.record_use(""))
	assert_false(tracker.record_use("   "))
	assert_false(tracker.has_any())
	_clean()


func test_history_persists_across_instances() -> void:
	_clean()
	var tracker = _tracker()
	tracker.load_run("run_a")
	tracker.record_use("green_stone")
	tracker.record_use("red_stone")

	var restored = _tracker()
	restored.load_run("run_a")
	assert_eq(restored.count_for("green_stone"), 1)
	assert_eq(restored.count_for("red_stone"), 1)
	_clean()


func test_new_run_starts_empty_without_touching_other_runs() -> void:
	_clean()
	var tracker = _tracker()
	tracker.load_run("run_a")
	tracker.record_use("green_stone")

	tracker.load_run("run_b")
	assert_false(tracker.has_any())
	tracker.record_use("red_stone")
	assert_eq(tracker.count_for("green_stone"), 0)
	assert_eq(tracker.count_for("red_stone"), 1)

	tracker.load_run("run_a")
	assert_eq(tracker.count_for("green_stone"), 1, "the earlier run keeps its history")
	_clean()


func test_invalid_json_starts_empty() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var file := FileAccess.open(TEST_DIR.path_join("run_bad.json"), FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	var tracker = _tracker()
	tracker.load_run("run_bad")
	assert_false(tracker.has_any())
	_clean()


func test_file_from_another_run_is_not_loaded() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var file := FileAccess.open(TEST_DIR.path_join("run_foreign.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"run_id": "someone_else", "counts": {"green_stone": 3}}))
	file.close()
	var tracker = _tracker()
	tracker.load_run("run_foreign")
	assert_false(tracker.has_any())
	_clean()


func test_daily_counts_read_blackboard_and_budget() -> void:
	var run := FakeRun.new()
	run.blackboard = {"items_bought_this_round": 2, "max_items_per_round": 3}
	var daily := ItemsUsedController.daily_counts(run)
	assert_eq(int(daily["used"]), 2)
	assert_eq(int(daily["allowance"]), 3)


func test_daily_counts_default_when_state_is_missing() -> void:
	var daily := ItemsUsedController.daily_counts(null)
	assert_eq(int(daily["used"]), 0)
	assert_eq(int(daily["allowance"]), 1)


func test_panel_shows_and_draws_with_zero_uses() -> void:
	var panel = ItemsUsedPanel.new()
	assert_true(panel.draw_when_empty, "collapsed header must draw with no rows")
	panel.show_usage({"day_used": 0, "day_allowance": 1, "entries": []})
	assert_true(panel.visible, "the panel shows even at zero uses")
	assert_false(panel.has_content())
	panel.free()
