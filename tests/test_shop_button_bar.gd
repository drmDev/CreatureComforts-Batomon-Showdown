extends "test_runner.gd"

const ShopButtonBar = preload("../core/shop_button_bar.gd")


func test_sorted_insert_index_empty() -> void:
	assert_eq(ShopButtonBar.sorted_insert_index([], "CreatureComfortsReplayButton"), 0)


func test_sorted_insert_index_leftmost() -> void:
	var names := ["DexButton", "SettingsButton", "QuitButton"]
	assert_eq(ShopButtonBar.sorted_insert_index(names, "CreatureComfortsReplayButton"), 0)


func test_sorted_insert_index_after_brain_rot() -> void:
	var names := ["BrainRotButton", "DexButton", "SettingsButton", "QuitButton"]
	assert_eq(ShopButtonBar.sorted_insert_index(names, "CreatureComfortsReplayButton"), 1)


func test_sorted_insert_index_brain_rot_leftmost() -> void:
	var names := ["CreatureComfortsReplayButton", "DexButton", "SettingsButton", "QuitButton"]
	assert_eq(ShopButtonBar.sorted_insert_index(names, "BrainRotButton"), 0)


func test_widened_left_offset_empty() -> void:
	assert_eq(ShopButtonBar.widened_left_offset([], 4.0, 636.0), 636.0)


func test_widened_left_offset_single() -> void:
	assert_eq(ShopButtonBar.widened_left_offset([24.0], 4.0, 636.0), 612.0)


func test_widened_left_offset_three() -> void:
	# 24 + 4 + 24 + 4 + 24 = 80
	assert_eq(ShopButtonBar.widened_left_offset([24.0, 24.0, 24.0], 4.0, 636.0), 556.0)
