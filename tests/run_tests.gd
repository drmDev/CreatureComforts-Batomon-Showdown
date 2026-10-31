extends SceneTree
## Headless test entry point for Creature Comforts.
##
## Run with:
##   godot --headless --script tests/run_tests.gd
## Exits 0 when all tests pass, 1 otherwise.

var _test_scripts := {
	"trainer_rules": preload("test_trainer_rules.gd"),
	"trinket_gains": preload("test_trinket_gains.gd"),
	"mod_config": preload("test_mod_config.gd"),
	"reminder_label": preload("test_reminder_label.gd"),
	"watchlist": preload("test_watchlist.gd"),
	"run_region": preload("test_run_region.gd"),
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
