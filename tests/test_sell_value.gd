extends "test_runner.gd"
## Unit tests for the sell-value helper, badge, and slot controller.

const SellValue = preload("../core/sell_value.gd")
const SellValueBadge = preload("../hud/sell_value_badge.gd")
const SellValueIndicators = preload("../hud/sell_value_indicators.gd")


func test_value_of_reads_the_game_method() -> void:
	var monster = FakeMonster.new(7)
	assert_true(SellValue.is_sellable(monster))
	assert_eq(SellValue.value_of(monster), 7)


func test_value_of_rejects_null_and_unsellable() -> void:
	assert_false(SellValue.is_sellable(null))
	assert_eq(SellValue.value_of(null), 0)
	var plain = FakePlain.new()
	assert_false(SellValue.is_sellable(plain))
	assert_eq(SellValue.value_of(plain), 0)


func test_text_for_clamps_negative_values() -> void:
	assert_eq(SellValue.text_for(12), "12")
	assert_eq(SellValue.text_for(0), "0")
	assert_eq(SellValue.text_for(-3), "0")


func test_badge_reads_the_slot_monster() -> void:
	var slot = FakeSlot.new()
	var badge = SellValueBadge.new()
	badge.slot = slot
	slot.add_child(badge)
	slot.current_monster = FakeMonster.new(7)
	badge._refresh()
	assert_true(badge.visible)
	assert_eq(badge._text, "7")
	slot.current_monster = null
	badge._refresh()
	assert_false(badge.visible)
	slot.free()


func test_badge_shows_zero_for_a_zero_value_monster() -> void:
	var slot = FakeSlot.new()
	var badge = SellValueBadge.new()
	badge.slot = slot
	slot.add_child(badge)
	slot.current_monster = FakeMonster.new(0)
	badge._refresh()
	assert_true(badge.visible)
	assert_eq(badge._text, "0")
	slot.free()


func test_badge_shows_zero_for_a_monster_without_sell_value() -> void:
	var slot = FakeSlot.new()
	var badge = SellValueBadge.new()
	badge.slot = slot
	slot.add_child(badge)
	slot.current_monster = FakePlain.new()
	badge._refresh()
	assert_true(badge.visible)
	assert_eq(badge._text, "0")
	slot.free()


func test_badge_hides_when_disabled() -> void:
	var slot = FakeSlot.new()
	var badge = SellValueBadge.new()
	badge.slot = slot
	slot.add_child(badge)
	slot.current_monster = FakeMonster.new(4)
	badge._refresh()
	assert_true(badge.visible)
	badge.set_enabled(false)
	assert_false(badge.visible)
	badge.set_enabled(true)
	assert_true(badge.visible)
	slot.free()


func test_controller_attaches_one_badge_per_slot() -> void:
	var view = FakeView.new()
	var team_ui = FakeTeamUi.new()
	var slot = FakeSlot.new()
	slot.current_monster = FakeMonster.new(3)
	team_ui.team_slots = [slot]
	view.monster_team_ui = team_ui
	var controller = SellValueIndicators.new()
	controller.setup(null)
	controller.update_team(view)
	assert_eq(slot.get_child_count(), 1)
	assert_eq(controller._attached.size(), 1)
	controller.update_team(view)
	assert_eq(slot.get_child_count(), 1)
	assert_eq(controller._attached.size(), 1)
	controller.free()
	slot.free()
	team_ui.free()
	view.free()


func test_controller_skips_non_control_slots() -> void:
	var view = FakeView.new()
	var team_ui = FakeTeamUi.new()
	team_ui.team_slots = [RefCounted.new()]
	view.monster_team_ui = team_ui
	var controller = SellValueIndicators.new()
	controller.setup(null)
	controller.update_team(view)
	assert_true(controller._attached.is_empty())
	controller.free()
	team_ui.free()
	view.free()


func test_controller_hosts_container_badges_on_a_canvas_layer() -> void:
	# The real ShopUI is a CanvasLayer, not a Control; the fallback must still
	# host the badge there instead of dropping it.
	var view = FakeCanvasView.new()
	var team_ui = FakeTeamUi.new()
	var slot = FakeContainerSlot.new()
	slot.current_monster = FakeMonster.new(5)
	team_ui.team_slots = [slot]
	view.monster_team_ui = team_ui
	var controller = SellValueIndicators.new()
	controller.setup(null)
	controller.update_team(view)
	assert_eq(slot.get_child_count(), 0)
	assert_eq(view.get_child_count(), 1)
	var badge = view.get_child(0)
	assert_true(badge.follow_slot)
	assert_true(badge.top_level)
	controller.free()
	view.free()
	slot.free()
	team_ui.free()


func test_controller_frees_badges_on_exit_tree() -> void:
	var view = FakeCanvasView.new()
	var team_ui = FakeTeamUi.new()
	var slot = FakeContainerSlot.new()
	slot.current_monster = FakeMonster.new(5)
	team_ui.team_slots = [slot]
	view.monster_team_ui = team_ui
	var controller = SellValueIndicators.new()
	controller.setup(null)
	controller.update_team(view)
	assert_eq(view.get_child_count(), 1)
	controller._exit_tree()
	assert_eq(view.get_child_count(), 0)
	assert_true(controller._attached.is_empty())
	controller.free()
	view.free()
	slot.free()
	team_ui.free()


func test_controller_prunes_a_freed_slot() -> void:
	var view = FakeView.new()
	var team_ui = FakeTeamUi.new()
	var slot = FakeSlot.new()
	team_ui.team_slots = [slot]
	view.monster_team_ui = team_ui
	var controller = SellValueIndicators.new()
	controller.setup(null)
	controller.update_team(view)
	assert_eq(controller._attached.size(), 1)
	slot.free()
	controller.update_team(view)
	assert_true(controller._attached.is_empty())
	controller.free()
	team_ui.free()
	view.free()


func test_controller_no_ops_without_team_ui() -> void:
	var view = FakeView.new()
	var controller = SellValueIndicators.new()
	controller.setup(null)
	controller.update_team(view)
	assert_true(controller._attached.is_empty())
	controller.free()
	view.free()


class FakeMonster extends RefCounted:
	var value := 0

	func _init(p_value: int) -> void:
		value = p_value

	func get_sell_value() -> int:
		return value


class FakePlain extends RefCounted:
	pass


class FakeSlot extends Control:
	var current_monster = null


class FakeContainerSlot extends Container:
	var current_monster = null


class FakeTeamUi extends Control:
	var team_slots: Array = []
	var bench_slots: Array = []


class FakeView extends Control:
	var monster_team_ui = null


class FakeCanvasView extends CanvasLayer:
	var monster_team_ui = null
