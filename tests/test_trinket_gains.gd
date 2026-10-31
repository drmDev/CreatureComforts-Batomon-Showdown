extends "test_runner.gd"

const TrinketGains = preload("../core/trinket_gains.gd")


func test_diff_id_lists_returns_new_ids() -> void:
	assert_eq(TrinketGains.diff_id_lists(["a", "b"], ["a", "b", "c"]), ["c"])


func test_diff_id_lists_handles_duplicates() -> void:
	assert_eq(TrinketGains.diff_id_lists(["a"], ["a", "a"]), ["a"])


func test_diff_id_lists_ignores_removed_ids() -> void:
	assert_eq(TrinketGains.diff_id_lists(["a", "b"], ["a"]), [])


func test_diff_id_lists_empty_inputs() -> void:
	assert_eq(TrinketGains.diff_id_lists([], []), [])
	assert_eq(TrinketGains.diff_id_lists([], ["a"]), ["a"])


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


func test_has_gift_trinket_detects_locked_box() -> void:
	assert_true(TrinketGains.has_gift_trinket(["locked_box"]))


func test_has_gift_trinket_detects_mysterious_chest() -> void:
	assert_true(TrinketGains.has_gift_trinket(["mysterious_chest"]))


func test_has_gift_trinket_ignores_other_one_shots() -> void:
	assert_false(TrinketGains.has_gift_trinket(["mini_duplicator", "treasure_map", "upgrade_disc"]))


func test_has_gift_trinket_empty() -> void:
	assert_false(TrinketGains.has_gift_trinket([]))


func test_withheld_count_reports_counter_gap() -> void:
	# Real Day 7 defeat: Locked Box consumed, 11 battle gains in inventory, counter +12.
	var gains := {"ids": ["a", "b", "c"], "counter": 4, "newly_used": ["locked_box"]}
	assert_eq(TrinketGains.withheld_count(gains), 1)


func test_withheld_count_zero_when_ids_match_counter() -> void:
	var gains := {"ids": ["a", "b"], "counter": 2, "newly_used": []}
	assert_eq(TrinketGains.withheld_count(gains), 0)


func test_withheld_count_never_negative() -> void:
	var gains := {"ids": ["a", "b"], "counter": 1, "newly_used": []}
	assert_eq(TrinketGains.withheld_count(gains), 0)


func test_withheld_count_tolerates_missing_keys() -> void:
	assert_eq(TrinketGains.withheld_count({}), 0)


func test_displayable_ids_removes_junk_keeps_order() -> void:
	assert_eq(TrinketGains.displayable_ids(["junk", "metronome", "junk", "barbell"], "junk"), ["metronome", "barbell"])


func test_displayable_ids_all_junk_returns_empty() -> void:
	assert_eq(TrinketGains.displayable_ids(["junk", "junk"], "junk"), [])


func test_displayable_ids_empty_input() -> void:
	assert_eq(TrinketGains.displayable_ids([], "junk"), [])


func test_displayable_ids_keeps_duplicates() -> void:
	assert_eq(TrinketGains.displayable_ids(["quick_bell", "quick_bell"], "junk"), ["quick_bell", "quick_bell"])


func test_defeat_gift_scenario_reports_gift_and_gain() -> void:
	# Day 13-style defeat: a Locked Box was consumed and its gift (zenith_stone) appeared.
	# The diff still reports the gain; the panel is no longer suppressed.
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
	assert_eq(TrinketGains.withheld_count(gains), 0)


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


func test_gift_plus_mid_combat_gain_reports_both() -> void:
	# A gift and a normal gain in the same battle: both are reported. The panel shows the
	# legitimate gain; gift content is excluded upstream by the frozen battle_over snapshot.
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": []}
	var after := {
		"trinket_ids": ["quick_bell", "zenith_stone"],
		"trinkets_gained_total": 2,
		"used_trinket_ids": ["locked_box"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["quick_bell", "zenith_stone"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 0)


func test_gift_with_counter_gap_keeps_legitimate_gains() -> void:
	# Real Day 7 defeat: Locked Box consumed, 11 battle gains in inventory, counter +12.
	# The gift is the counter gap (withheld), so the ids are legitimate and displayable.
	var before := {"trinket_ids": ["boxing_glove"], "trinkets_gained_total": 3, "used_trinket_ids": []}
	var after := {
		"trinket_ids": ["boxing_glove", "metronome", "barbell", "mighty_bell", "blitz_bell"],
		"trinkets_gained_total": 8,
		"used_trinket_ids": ["locked_box"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["metronome", "barbell", "mighty_bell", "blitz_bell"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 1)


func test_junk_plus_gift_with_counter_gap() -> void:
	# Junk reward mixed with legitimate gains while a Locked Box gift is pending.
	var before := {"trinket_ids": ["boxing_glove"], "trinkets_gained_total": 3, "used_trinket_ids": []}
	var after := {
		"trinket_ids": ["boxing_glove", "junk", "metronome", "barbell", "mighty_bell", "blitz_bell"],
		"trinkets_gained_total": 9,
		"used_trinket_ids": ["locked_box"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["junk", "metronome", "barbell", "mighty_bell", "blitz_bell"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 1)
	assert_eq(TrinketGains.displayable_ids(gains["ids"], "junk"), ["metronome", "barbell", "mighty_bell", "blitz_bell"])


func test_junk_only_with_gift_pending() -> void:
	# Only junk is visible while a gift is pending; the panel layer filters junk to nothing.
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": []}
	var after := {"trinket_ids": ["junk"], "trinkets_gained_total": 2, "used_trinket_ids": ["locked_box"]}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["junk"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 1)
	assert_empty(TrinketGains.displayable_ids(gains["ids"], "junk"))


func test_mysterious_chest_counter_gap_scenario() -> void:
	# Mysterious Chest mirrors the Locked Box behavior: gift pending, legitimate gains shown.
	var before := {"trinket_ids": ["warhorn"], "trinkets_gained_total": 2, "used_trinket_ids": []}
	var after := {
		"trinket_ids": ["warhorn", "metronome", "barbell"],
		"trinkets_gained_total": 5,
		"used_trinket_ids": ["mysterious_chest"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["metronome", "barbell"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 1)


func test_multiple_gifts_report_multiple_withheld() -> void:
	# Two gift one-shots consumed in one battle: both gifts are pending.
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": []}
	var after := {
		"trinket_ids": ["quick_bell"],
		"trinkets_gained_total": 3,
		"used_trinket_ids": ["locked_box", "mysterious_chest"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["quick_bell"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 2)


func test_gift_only_no_visible_gains() -> void:
	# Gift pending with no other gains: nothing to render, panel hides itself.
	var before := {"trinket_ids": ["gold_trophy"], "trinkets_gained_total": 1, "used_trinket_ids": []}
	var after := {"trinket_ids": ["gold_trophy"], "trinkets_gained_total": 2, "used_trinket_ids": ["locked_box"]}
	var gains := TrinketGains.diff_states(before, after)
	assert_empty(gains["ids"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 1)
	assert_empty(TrinketGains.displayable_ids(gains["ids"], "junk"))


func test_repeated_gift_use_reports_only_new_use() -> void:
	# A Locked Box already consumed in an earlier battle must not be reported again.
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": ["locked_box"]}
	var after := {"trinket_ids": [], "trinkets_gained_total": 1, "used_trinket_ids": ["locked_box", "locked_box"]}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["newly_used"], ["locked_box"])
	assert_true(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 1)


func test_counter_gap_without_gift_is_reported() -> void:
	# A counter gap can exist without a gift one-shot; withheld_count still reports it.
	var before := {"trinket_ids": ["a"], "trinkets_gained_total": 1, "used_trinket_ids": []}
	var after := {"trinket_ids": ["a"], "trinkets_gained_total": 2, "used_trinket_ids": []}
	var gains := TrinketGains.diff_states(before, after)
	assert_empty(gains["ids"])
	assert_false(TrinketGains.has_gift_trinket(gains["newly_used"]))
	assert_eq(TrinketGains.withheld_count(gains), 1)


func test_duplicate_gains_with_gift_pending() -> void:
	# Stacked legitimate gains plus a pending gift.
	var before := {"trinket_ids": [], "trinkets_gained_total": 0, "used_trinket_ids": []}
	var after := {
		"trinket_ids": ["quick_bell", "quick_bell"],
		"trinkets_gained_total": 3,
		"used_trinket_ids": ["locked_box"],
	}
	var gains := TrinketGains.diff_states(before, after)
	assert_eq(gains["ids"], ["quick_bell", "quick_bell"])
	assert_eq(TrinketGains.withheld_count(gains), 1)
	assert_eq(TrinketGains.displayable_ids(gains["ids"], "junk"), ["quick_bell", "quick_bell"])
