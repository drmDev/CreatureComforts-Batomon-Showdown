extends "test_runner.gd"
## Unit tests for the unified Trinkets panel: tab selection, activity dots, and
## the single panel setting.

const TrinketsPanel = preload("../hud/trinkets_panel.gd")
const ModConfig = preload("../core/mod_config.gd")

const TEST_PANEL_STORE := "user://creature_comforts_test/trinkets_panel.cfg"


func _remove_store() -> void:
	if FileAccess.file_exists(TEST_PANEL_STORE):
		DirAccess.remove_absolute(TEST_PANEL_STORE)


func _reminder(name: String) -> Dictionary:
	return {"name": name, "desc": "text", "count": 1}


func _gain(id: String, name: String) -> Dictionary:
	return {"id": id, "name": name, "count": 1}


func test_tabs_and_default_selection() -> void:
	var panel = TrinketsPanel.new()
	assert_eq(TrinketsPanel.TABS.size(), 3)
	assert_eq(TrinketsPanel.TAB_LABELS[TrinketsPanel.TAB_ALERTS], "Alerts")
	assert_eq(TrinketsPanel.TAB_LABELS[TrinketsPanel.TAB_GAINED], "Gained")
	assert_eq(TrinketsPanel.TAB_LABELS[TrinketsPanel.TAB_BONUSES], "Bonuses")
	assert_eq(panel.selected_tab(), TrinketsPanel.TAB_ALERTS)
	panel.free()


func test_unknown_tab_is_ignored() -> void:
	var panel = TrinketsPanel.new()
	panel.select_tab("not_a_tab")
	assert_eq(panel.selected_tab(), TrinketsPanel.TAB_ALERTS)
	panel.select_tab(TrinketsPanel.TAB_BONUSES)
	assert_eq(panel.selected_tab(), TrinketsPanel.TAB_BONUSES)
	panel.free()


func test_selected_tab_is_persisted_and_restored() -> void:
	_remove_store()
	var config = ModConfig.new()
	config.use_store(TEST_PANEL_STORE)
	var panel = TrinketsPanel.new()
	panel.setup(config)
	assert_eq(panel.selected_tab(), TrinketsPanel.TAB_ALERTS)
	panel.select_tab(TrinketsPanel.TAB_BONUSES)
	panel.free()

	var restored = TrinketsPanel.new()
	restored.setup(config)
	assert_eq(restored.selected_tab(), TrinketsPanel.TAB_BONUSES, "tab survives a restart")
	restored.free()
	_remove_store()


func test_alerts_dot_follows_live_reminders() -> void:
	var panel = TrinketsPanel.new()
	assert_false(panel.alerts_indicator_visible())
	panel.alerts_view.show_reminders([_reminder("Treasure Map")])
	assert_true(panel.alerts_indicator_visible())
	# Viewing the tab never clears it; only the reminders ending does.
	panel.select_tab(TrinketsPanel.TAB_ALERTS)
	assert_true(panel.alerts_indicator_visible())
	panel.alerts_view.hide_panel()
	assert_false(panel.alerts_indicator_visible())
	panel.free()


func test_gained_dot_clears_when_tab_opened() -> void:
	var panel = TrinketsPanel.new()
	panel.gained_view.show_gains([_gain("map", "Treasure Map")])
	assert_true(panel.gained_indicator_visible())
	panel.select_tab(TrinketsPanel.TAB_GAINED)
	assert_false(panel.gained_indicator_visible())
	panel.free()


func test_gained_dot_does_not_reflag_viewed_rewards() -> void:
	var panel = TrinketsPanel.new()
	var gains := [_gain("map", "Treasure Map")]
	panel.gained_view.show_gains(gains)
	panel.select_tab(TrinketsPanel.TAB_GAINED)
	panel.select_tab(TrinketsPanel.TAB_ALERTS)
	panel.gained_view.show_gains(gains)
	assert_false(panel.gained_indicator_visible(), "same rewards are not re-flagged")
	panel.gained_view.show_gains([_gain("disc", "Upgrade Disc"), _gain("map", "Treasure Map")])
	assert_true(panel.gained_indicator_visible(), "new rewards flag again")
	panel.free()


func test_gained_dot_clears_when_gains_are_dropped() -> void:
	var panel = TrinketsPanel.new()
	panel.gained_view.show_gains([_gain("map", "Treasure Map")])
	assert_true(panel.gained_indicator_visible())
	panel.gained_view.hide_panel()
	assert_false(panel.gained_indicator_visible())
	panel.free()


func test_header_dot_needs_alerts_or_gained() -> void:
	var panel = TrinketsPanel.new()
	assert_false(panel.header_indicator_visible())
	panel.alerts_view.show_reminders([_reminder("Treasure Map")])
	assert_true(panel.header_indicator_visible())
	panel.alerts_view.hide_panel()
	assert_false(panel.header_indicator_visible())
	panel.gained_view.show_gains([_gain("map", "Treasure Map")])
	assert_true(panel.header_indicator_visible())
	panel.free()


func test_bonuses_never_flag_activity() -> void:
	var panel = TrinketsPanel.new()
	panel.bonuses_view.show_summary({
		"positional": {"has_any": true, "left": {}},
		"economical": {"has_any": false},
	})
	assert_false(panel.alerts_indicator_visible())
	assert_false(panel.gained_indicator_visible())
	assert_false(panel.header_indicator_visible())
	panel.free()


func test_disabled_panel_stays_hidden_but_keeps_content() -> void:
	var panel = TrinketsPanel.new()
	panel.set_enabled(false)
	panel.alerts_view.show_reminders([_reminder("Treasure Map")])
	assert_false(panel.visible, "disabled panel never shows")
	panel.set_enabled(true)
	assert_true(panel.visible, "content is still held")
	panel.free()


func test_panel_hides_when_all_tabs_are_empty() -> void:
	var panel = TrinketsPanel.new()
	panel.alerts_view.show_reminders([_reminder("Treasure Map")])
	assert_true(panel.visible)
	panel.alerts_view.hide_panel()
	assert_false(panel.visible)
	panel.free()
