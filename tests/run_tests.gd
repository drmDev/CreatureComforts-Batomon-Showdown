extends SceneTree
## Headless test entry point for Creature Comforts.
##
## Run with:
##   godot --headless --script tests/run_tests.gd
## Exits 0 when all tests pass, 1 otherwise.

var _test_scripts := {
	"trainer_rules": preload("test_trainer_rules.gd"),
	"trinket_gains": preload("test_trinket_gains.gd"),
	"shop_income": preload("test_shop_income.gd"),
	"base_hp": preload("test_base_hp.gd"),
	"tracked_trinkets": preload("test_tracked_trinkets.gd"),
	"positional_trinkets": preload("test_positional_trinkets.gd"),
	"battle_monitor": preload("test_battle_monitor.gd"),
	"combat_stats": preload("test_combat_stats.gd"),
	"species_icons": preload("test_species_icons.gd"),
	"trainer_icons": preload("test_trainer_icons.gd"),
	"opponent_info": preload("test_opponent_info.gd"),
	"battle_trinket_tracker": preload("test_battle_trinket_tracker.gd"),
	"mod_config": preload("test_mod_config.gd"),
	"reminder_label": preload("test_reminder_label.gd"),
	"watchlist": preload("test_watchlist.gd"),
	"saved_builds": preload("test_saved_builds.gd"),
	"ui_sound": preload("test_ui_sound.gd"),
	"run_region": preload("test_run_region.gd"),
	"run_data": preload("test_run_data.gd"),
	"style": preload("test_style.gd"),
	"auto_updater": preload("test_auto_updater.gd"),
}


func _initialize() -> void:
	var total_failures := 0
	var total_assertions := 0
	var total_suites := 0

	for suite_name in _test_scripts:
		var script = _test_scripts[suite_name]
		var suite = script.new()
		var failures: int = suite.run_all()
		total_failures += failures
		total_assertions += suite.assertion_count()
		total_suites += 1

		if failures == 0:
			print("PASS  %s (%d assertions)" % [suite_name, suite.assertion_count()])
		else:
			print("FAIL  %s (%d failures)" % [suite_name, failures])
			for failure in suite.failures():
				print("      %s: %s" % [failure["test"], failure["message"]])

	print("")
	print("Ran %d suites, %d assertions, %d failures." % [total_suites, total_assertions, total_failures])
	quit(0 if total_failures == 0 else 1)
