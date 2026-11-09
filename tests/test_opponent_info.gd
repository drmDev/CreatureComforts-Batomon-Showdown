extends "test_runner.gd"
## Unit tests for core/opponent_info.gd.

const OpponentInfo = preload("../core/opponent_info.gd")


func test_mmr_value_ranked() -> void:
	assert_eq(OpponentInfo.mmr_value({
		"_matched_opponent_mmr": 123, "_matched_user_id": "u1", "_matched_mmr_is_ranked": true,
	}), "123")


func test_mmr_value_casual() -> void:
	assert_eq(OpponentInfo.mmr_value({
		"_matched_opponent_mmr": 123, "_matched_user_id": "u1", "_matched_mmr_is_ranked": false,
	}), "123 (casual)")


func test_mmr_value_bot() -> void:
	assert_eq(OpponentInfo.mmr_value({"_matched_user_id": "bot_1"}), "Bot")


func test_mmr_value_unknown() -> void:
	assert_eq(OpponentInfo.mmr_value(null), OpponentInfo.MMR_UNKNOWN)
	assert_eq(OpponentInfo.mmr_value({}), OpponentInfo.MMR_UNKNOWN)


func test_display_name_uses_username() -> void:
	assert_eq(OpponentInfo.display_name({"display_name": "Ash"}, "Chef", false, true), "Ash")


func test_display_name_falls_back_to_trainer() -> void:
	assert_eq(OpponentInfo.display_name({}, "Chef", false, true), "Chef")
	assert_eq(OpponentInfo.display_name({"display_name": "Ash"}, "Chef", true, true), "Chef")
	assert_eq(OpponentInfo.display_name({"display_name": "Ash"}, "Chef", false, false), "Chef")




func test_trainer_id_reads_dictionary_and_missing() -> void:
	assert_eq(OpponentInfo.trainer_id({"trainer_id": "chef"}), "chef")
	assert_eq(OpponentInfo.trainer_id({}), "")
	assert_eq(OpponentInfo.trainer_id(null), "")


func test_same_opponent_matches_name_and_trainer() -> void:
	var p2 := {"display_name": "Ash", "trainer_id": "chef"}
	var captured := {"display_name": "Ash", "trainer_id": "chef"}
	assert_true(OpponentInfo.same_opponent(captured, p2, Time.get_ticks_msec()))


func test_same_opponent_rejects_mismatch() -> void:
	var p2 := {"display_name": "Ash", "trainer_id": "chef"}
	assert_false(OpponentInfo.same_opponent(
		{"display_name": "Misty", "trainer_id": "chef"}, p2, Time.get_ticks_msec()))
	assert_false(OpponentInfo.same_opponent(null, p2, Time.get_ticks_msec()))
