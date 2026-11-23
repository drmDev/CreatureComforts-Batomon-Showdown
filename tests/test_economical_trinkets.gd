extends "test_runner.gd"
## Unit tests for core/economical_trinkets.gd.

const EconomicalTrinkets = preload("../core/economical_trinkets.gd")


func test_empty_held_list_has_no_any() -> void:
	var summary := EconomicalTrinkets.summarize([])
	assert_false(summary["has_any"])
	assert_empty(summary["passive"])
	assert_empty(summary["victory"])
	assert_empty(summary["next_loss"])


func test_unknown_ids_are_ignored() -> void:
	var summary := EconomicalTrinkets.summarize(["not_a_trinket"])
	assert_false(summary["has_any"])


func test_gold_bracelet_passive_sell_value() -> void:
	var summary := EconomicalTrinkets.summarize(["gold_bracelet"])
	assert_true(summary["has_any"])
	assert_eq(summary["passive"].size(), 1)
	assert_eq(summary["passive"][0]["stat"], "sell_value")
	assert_eq(summary["passive"][0]["value"], 8)
	assert_eq(summary["passive"][0]["note"], "random monster")


func test_gold_trophy_victory_gold() -> void:
	var summary := EconomicalTrinkets.summarize(["gold_trophy"])
	assert_eq(summary["victory"].size(), 1)
	assert_eq(summary["victory"][0]["stat"], "gold")
	assert_eq(summary["victory"][0]["value"], 8)


func test_fools_gold_income_and_text() -> void:
	var summary := EconomicalTrinkets.summarize(["fools_gold"])
	var passive: Array = summary["passive"]
	assert_eq(passive.size(), 2)
	assert_eq(passive[0]["stat"], "income")
	assert_eq(passive[0]["value"], 15)
	assert_eq(passive[1]["text"], "No more Items")


func test_piggy_bank_scales_with_gold() -> void:
	var summary := EconomicalTrinkets.summarize(["piggy_bank"], 25)
	assert_eq(summary["passive"].size(), 1)
	assert_eq(summary["passive"][0]["stat"], "gold_per_10")
	assert_eq(summary["passive"][0]["value"], 2)
	assert_eq(summary["passive"][0]["rate"], 1)


func test_piggy_bank_rounds_down() -> void:
	var summary := EconomicalTrinkets.summarize(["piggy_bank"], 9)
	assert_eq(summary["passive"][0]["value"], 0)


func test_piggy_bank_duplicates_scale() -> void:
	var summary := EconomicalTrinkets.summarize(["piggy_bank", "piggy_bank"], 25)
	assert_eq(summary["passive"].size(), 1)
	assert_eq(summary["passive"][0]["value"], 4)
	assert_eq(summary["passive"][0]["rate"], 2)
	assert_eq(summary["passive"][0]["count"], 2)


func test_fake_diamond_next_loss() -> void:
	var summary := EconomicalTrinkets.summarize(["fake_diamond"])
	assert_eq(summary["next_loss"].size(), 1)
	assert_eq(summary["next_loss"][0]["stat"], "gold")
	assert_eq(summary["next_loss"][0]["value"], 40)


func test_holy_grail_victory_gold() -> void:
	var summary := EconomicalTrinkets.summarize(["holy_grail"])
	assert_eq(summary["victory"].size(), 1)
	assert_eq(summary["victory"][0]["value"], 100)


func test_victory_gold_sums() -> void:
	var summary := EconomicalTrinkets.summarize(["gold_trophy", "holy_grail"])
	assert_eq(summary["victory"].size(), 1)
	assert_eq(summary["victory"][0]["value"], 108)
	assert_eq(summary["victory"][0]["count"], 2)


func test_passive_effects_sorted_by_stat_order() -> void:
	var summary := EconomicalTrinkets.summarize(["piggy_bank", "fools_gold", "gold_bracelet"], 50)
	var passive: Array = summary["passive"]
	assert_eq(passive[0]["stat"], "sell_value")
	assert_eq(passive[1]["stat"], "income")
	assert_eq(passive[2]["stat"], "gold_per_10")


func test_ordered_effects_follow_timing_order() -> void:
	var summary := EconomicalTrinkets.summarize(["fake_diamond", "gold_trophy", "gold_bracelet"])
	var ordered := EconomicalTrinkets.ordered_effects(summary)
	assert_eq(ordered.size(), 3)
	assert_eq(ordered[0]["timing"], "passive")
	assert_eq(ordered[1]["timing"], "victory")
	assert_eq(ordered[2]["timing"], "next_loss")


func test_tag_labels_map_timings() -> void:
	assert_eq(EconomicalTrinkets.TAG_LABELS["passive"], "Passive")
	assert_eq(EconomicalTrinkets.TAG_LABELS["victory"], "Victory")
	assert_eq(EconomicalTrinkets.TAG_LABELS["next_loss"], "Next Loss")


func test_format_effect_sell_value() -> void:
	assert_eq(
		EconomicalTrinkets.format_effect({"stat": "sell_value", "value": 8, "note": "random monster"}),
		"+8 Sell Value (random monster)"
	)


func test_format_effect_income() -> void:
	assert_eq(
		EconomicalTrinkets.format_effect({"stat": "income", "value": 15}),
		"+$15 Income"
	)


func test_format_effect_gold() -> void:
	assert_eq(
		EconomicalTrinkets.format_effect({"stat": "gold", "value": 100}),
		"+$100"
	)
	assert_eq(
		EconomicalTrinkets.format_effect({"stat": "gold", "value": 8}, "victory"),
		"+$8 On Victory"
	)
	assert_eq(
		EconomicalTrinkets.format_effect({"stat": "gold", "value": 40}, "next_loss"),
		"+$40 On Next Loss"
	)


func test_format_effect_gold_per_10() -> void:
	assert_eq(
		EconomicalTrinkets.format_effect({"stat": "gold_per_10", "value": 2, "rate": 1, "count": 1}),
		"+$2 Income ($1 per $10 held)"
	)
	assert_eq(
		EconomicalTrinkets.format_effect({"stat": "gold_per_10", "value": 4, "rate": 2, "count": 2}),
		"+$4 Income ($2 per $10 held)"
	)


func test_format_effect_text() -> void:
	assert_eq(
		EconomicalTrinkets.format_effect({"text": "No more Items", "count": 1}),
		"No more Items"
	)
	assert_eq(
		EconomicalTrinkets.format_effect({"text": "No more Items", "count": 2}),
		"No more Items x2"
	)


func test_catalog_entries_have_descriptions() -> void:
	for tid in EconomicalTrinkets.TRINKETS.keys():
		assert_true(EconomicalTrinkets.TRINKETS[tid].has("description"), str(tid))


func test_catalog_ids_are_snake_case() -> void:
	for tid in EconomicalTrinkets.TRINKETS.keys():
		assert_eq(str(tid), str(tid).to_lower(), str(tid))
		assert_false(str(tid).contains(" "), str(tid))


func test_summary_does_not_mutate_catalog() -> void:
	var before := str(EconomicalTrinkets.TRINKETS)
	EconomicalTrinkets.summarize(["piggy_bank", "piggy_bank"], 100)
	assert_eq(str(EconomicalTrinkets.TRINKETS), before)
