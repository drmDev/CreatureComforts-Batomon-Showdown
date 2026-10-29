extends "test_runner.gd"
## Unit tests for core/trinket_gains.gd (battle-scoped trinket diff logic).

const TrinketGains = preload("../core/trinket_gains.gd")


# --- diff_id_lists ---

func test_diff_id_lists_returns_new_ids() -> void:
	assert_eq(TrinketGains.diff_id_lists(["a", "b"], ["a", "b", "c"]), ["c"])


func test_diff_id_lists_handles_duplicates() -> void:
	assert_eq(TrinketGains.diff_id_lists(["a"], ["a", "a"]), ["a"])


func test_diff_id_lists_ignores_removed_ids() -> void:
	assert_eq(TrinketGains.diff_id_lists(["a", "b"], ["a"]), [])


func test_diff_id_lists_empty_inputs() -> void:
	assert_eq(TrinketGains.diff_id_lists([], []), [])
	assert_eq(TrinketGains.diff_id_lists([], ["a"]), ["a"])


# --- diff_states ---

func test_diff_states_reports_gains_and_counter() -> void:
	var before := {"trinket_ids": ["a"], "trinkets_gained_total": 1, "used_trinket_ids": []}
	var after := {"trinket_ids": ["a", "b"], "trinkets_gained_total": 2, "used_trinket_ids": []}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["b"])
	assert_eq(gains["counter"], 1)
	assert_empty(gains["newly_used"])


func test_diff_states_reports_newly_used_one_shots() -> void:
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": ["mini_duplicator"]}
	var after := {"trinket_ids": ["zenith_stone"], "trinkets_gained_total": 1, "used_trinket_ids": ["mini_duplicator", "locked_box"]}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["zenith_stone"])
	assert_eq(gains["newly_used"], ["locked_box"])


func test_diff_states_tolerates_missing_keys() -> void:
	var gains := TrinketGains.diff_states({}, {})
	assert_empty(gains["ids"])
	assert_eq(gains["counter"], 0)
	assert_empty(gains["newly_used"])


# --- has_gift_trinket ---

func test_has_gift_trinket_detects_locked_box() -> void:
	assert_true(TrinketGains.has_gift_trinket(["locked_box"]))


func test_has_gift_trinket_detects_mysterious_chest() -> void:
	assert_true(TrinketGains.has_gift_trinket(["mysterious_chest"]))


func test_has_gift_trinket_ignores_other_one_shots() -> void:
	assert_false(TrinketGains.has_gift_trinket(["mini_duplicator", "treasure_map", "upgrade_disc"]))


func test_has_gift_trinket_empty() -> void:
	assert_false(TrinketGains.has_gift_trinket([]))


# --- Battle scenarios ---

func test_defeat_gift_scenario_is_suppressed() -> void:
	# Day 13-style defeat: a Locked Box was consumed and its gift (zenith_stone) appeared.
	var before := {
		"trinket_ids": ["sapphire_ring", "gold_trophy"],
		"trinkets_gained_total": 10,
		"used_trinket_ids": ["mini_duplicator"],
	}
	var after := {
		"trinket_ids": ["sapphire_ring", "gold_trophy", "zenith_stone"],
		"trinkets_gained_total": 11,
		"used_trinket_ids": ["mini_duplicator", "locked_box"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["zenith_stone"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))


func test_defeat_standard_reward_scenario_is_shown() -> void:
	# Day 1-style defeat: gold_trophy + junk, no gift-generating one-shot consumed.
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": []}
	var after := {"trinket_ids": ["gold_trophy", "junk"], "trinkets_gained_total": 2, "used_trinket_ids": []}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["gold_trophy", "junk"])
	assert_false(TrinketGains.has_gift_trinket(gains["newly_used"]))


func test_victory_mid_combat_gain_scenario_is_shown() -> void:
	# Victory with a normal trinket gain and no gift one-shot.
	var before := {"trinket_ids": ["gold_trophy"], "trinkets_gained_total": 3, "used_trinket_ids": []}
	var after := {"trinket_ids": ["gold_trophy", "quick_bell"], "trinkets_gained_total": 4, "used_trinket_ids": []}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["quick_bell"])
	assert_false(TrinketGains.has_gift_trinket(gains["newly_used"]))


func test_gift_plus_mid_combat_gain_is_suppressed() -> void:
	# A gift and a normal gain in the same battle: the panel is suppressed because the
	# new trinkets cannot be attributed individually.
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": []}
	var after := {
		"trinket_ids": ["quick_bell", "zenith_stone"],
		"trinkets_gained_total": 2,
		"used_trinket_ids": ["locked_box"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["quick_bell", "zenith_stone"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
