extends "test_runner.gd"
## Unit tests for the Clippy-style Trinket Summary assistant decision logic and
## its persisted seen flag.

const TrinketAssistant = preload("../core/trinket_assistant.gd")

const TEST_STORE := "user://creature_comforts_test/trinket_assistant.cfg"


func _remove_test_store() -> void:
	if FileAccess.file_exists(TEST_STORE):
		DirAccess.remove_absolute(TEST_STORE)


func test_intro_text_is_exact() -> void:
	assert_eq(
		TrinketAssistant.INTRO_TEXT,
		"It looks like you're collecting a lot of trinkets. Would you like help making sense of them?"
	)


func test_threshold_not_met_never_shows() -> void:
	assert_false(TrinketAssistant.should_show(false, false, false, 0.0))
	assert_false(TrinketAssistant.should_show(false, false, false, 0.1))
	assert_false(TrinketAssistant.should_show(true, false, false, 0.0))


func test_already_shown_this_run_never_shows() -> void:
	assert_false(TrinketAssistant.should_show(false, true, true, 0.0))
	assert_false(TrinketAssistant.should_show(true, true, true, 0.0))


func test_first_time_threshold_always_shows() -> void:
	assert_true(TrinketAssistant.should_show(false, false, true, 0.99))
	assert_true(TrinketAssistant.should_show(false, false, true, 0.0))


func test_subsequent_run_rolls_chance() -> void:
	# The 25% window is [0, 0.25).
	assert_true(TrinketAssistant.should_show(true, false, true, 0.0))
	assert_true(TrinketAssistant.should_show(true, false, true, 0.249))
	assert_false(TrinketAssistant.should_show(true, false, true, 0.25))
	assert_false(TrinketAssistant.should_show(true, false, true, 0.99))


func test_missing_store_defaults_to_unseen() -> void:
	_remove_test_store()
	assert_false(TrinketAssistant.load_seen(TEST_STORE))


func test_seen_flag_round_trip() -> void:
	_remove_test_store()
	assert_true(TrinketAssistant.save_seen(true, TEST_STORE))
	assert_true(TrinketAssistant.load_seen(TEST_STORE))
	assert_true(TrinketAssistant.save_seen(false, TEST_STORE))
	assert_false(TrinketAssistant.load_seen(TEST_STORE))
	_remove_test_store()


func test_corrupt_store_defaults_to_unseen() -> void:
	_remove_test_store()
	DirAccess.make_dir_recursive_absolute(TEST_STORE.get_base_dir())
	var file := FileAccess.open(TEST_STORE, FileAccess.WRITE)
	file.store_string("not a valid config file")
	file.close()
	assert_false(TrinketAssistant.load_seen(TEST_STORE))
	_remove_test_store()
