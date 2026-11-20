extends "test_runner.gd"
## Unit tests for the shop monster purchase reminder helper.

const PurchaseReminders = preload("../core/purchase_reminders.gd")


func test_no_held_trinkets_returns_empty() -> void:
	assert_empty(PurchaseReminders.build_lines([], false))


func test_upgrade_disc_and_speed_whistle_lines() -> void:
	var lines = PurchaseReminders.build_lines(["upgrade_disc", "speed_whistle"], false)
	assert_eq(lines.size(), 2)
	assert_true("Next monster purchase: +1 level" in lines)
	assert_true("Next monster purchase: +12% CD" in lines)


func test_power_band_shown_before_first_purchase() -> void:
	var lines = PurchaseReminders.build_lines(["power_band"], false)
	assert_eq(lines.size(), 1)
	assert_true("First monster purchase each day: +20 dmg" in lines)


func test_power_band_suppressed_after_first_purchase() -> void:
	assert_empty(PurchaseReminders.build_lines(["power_band"], true))


func test_power_band_suppressed_but_others_remain() -> void:
	var lines = PurchaseReminders.build_lines(["power_band", "upgrade_disc"], true)
	assert_eq(lines.size(), 1)
	assert_true("Next monster purchase: +1 level" in lines)


func test_null_held_ids_returns_empty() -> void:
	assert_empty(PurchaseReminders.build_lines(null, false))
