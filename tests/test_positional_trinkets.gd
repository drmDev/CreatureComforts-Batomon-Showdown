extends "test_runner.gd"
## Unit tests for core/positional_trinkets.gd.

const PositionalTrinkets = preload("../core/positional_trinkets.gd")


func test_empty_held_list_has_no_any() -> void:
	var summary := PositionalTrinkets.summarize([])
	assert_false(summary["has_any"])
	assert_empty(summary["left"]["passive"])
	assert_empty(summary["left"]["permanent"])
	assert_empty(summary["top_middle"]["passive"])
	assert_empty(summary["top_middle"]["permanent"])
	assert_empty(summary["right"]["passive"])
	assert_empty(summary["right"]["permanent"])


func test_unknown_ids_are_ignored() -> void:
	var summary := PositionalTrinkets.summarize(["not_a_trinket"])
	assert_false(summary["has_any"])


func test_quick_flag_passive_left_cooldown() -> void:
	var summary := PositionalTrinkets.summarize(["quick_flag"])
	assert_true(summary["has_any"])
	assert_eq(summary["left"]["passive"].size(), 1)
	assert_eq(summary["left"]["passive"][0]["stat"], "cooldown_speed")
	assert_eq(summary["left"]["passive"][0]["value"], 4)
	assert_true(summary["left"]["passive"][0]["percent"])
	assert_empty(summary["left"]["permanent"])


func test_rally_flag_permanent_left_damage() -> void:
	var summary := PositionalTrinkets.summarize(["rally_flag"])
	assert_eq(summary["left"]["permanent"].size(), 1)
	assert_eq(summary["left"]["permanent"][0]["stat"], "damage")
	assert_eq(summary["left"]["permanent"][0]["value"], 12)
	assert_false(summary["left"]["permanent"][0]["percent"])


func test_momentum_flag_permanent_left_cooldown() -> void:
	var summary := PositionalTrinkets.summarize(["momentum_flag"])
	assert_eq(summary["left"]["permanent"].size(), 1)
	assert_eq(summary["left"]["permanent"][0]["stat"], "cooldown_speed")
	assert_eq(summary["left"]["permanent"][0]["value"], 8)
	assert_true(summary["left"]["permanent"][0]["percent"])


func test_duplicates_sum_values() -> void:
	var summary := PositionalTrinkets.summarize(["quick_flag", "quick_flag", "quick_flag"])
	assert_eq(summary["left"]["passive"].size(), 1)
	assert_eq(summary["left"]["passive"][0]["value"], 12)
	assert_eq(summary["left"]["passive"][0]["count"], 3)


func test_sections_are_always_present() -> void:
	var summary := PositionalTrinkets.summarize(["quick_flag"])
	assert_has(summary, "left")
	assert_has(summary, "top_middle")
	assert_has(summary, "right")
	assert_empty(summary["top_middle"]["passive"])
	assert_empty(summary["top_middle"]["permanent"])
	assert_empty(summary["right"]["passive"])
	assert_empty(summary["right"]["permanent"])


func test_effects_sorted_by_stat_order() -> void:
	var summary := PositionalTrinkets.summarize(["winged_crown", "haste_crown", "power_crown"])
	var passive: Array = summary["top_middle"]["passive"]
	assert_eq(passive.size(), 3)
	assert_eq(passive[0]["stat"], "damage")
	assert_eq(passive[1]["stat"], "cooldown_speed")
	assert_eq(passive[2]["stat"], "multicast")


func test_alpha_crown_text_effect() -> void:
	var summary := PositionalTrinkets.summarize(["alpha_crown"])
	var permanent: Array = summary["top_middle"]["permanent"]
	assert_eq(permanent.size(), 1)
	assert_eq(permanent[0]["text"], "Damage set to top-middle's Damage")
	assert_eq(permanent[0]["count"], 1)


func test_master_crown_stats_effect() -> void:
	var summary := PositionalTrinkets.summarize(["master_crown"])
	var passive: Array = summary["top_middle"]["passive"]
	assert_eq(passive.size(), 1)
	assert_eq(passive[0]["stat"], "stats")
	assert_eq(passive[0]["value"], 80)
	assert_true(passive[0]["percent"])
	assert_eq(passive[0]["note"], "except Cooldown/Multicast")


func test_link_cable_is_not_positional() -> void:
	var summary := PositionalTrinkets.summarize(["link_cable"])
	assert_false(summary["has_any"])


func test_example_scenario() -> void:
	var held := [
		"quick_flag", "quick_flag", "quick_flag",
		"rally_flag", "momentum_flag",
		"power_crown", "haste_crown", "winged_crown",
		"speed_crest", "speed_crest",
		"earth_crest",
	]
	var summary := PositionalTrinkets.summarize(held)
	assert_true(summary["has_any"])

	# Left column: three Quick Flags, Rally Flag, Momentum Flag.
	assert_eq(summary["left"]["passive"].size(), 1)
	assert_eq(summary["left"]["passive"][0]["value"], 12)
	assert_eq(summary["left"]["permanent"].size(), 2)
	assert_eq(summary["left"]["permanent"][0]["stat"], "damage")
	assert_eq(summary["left"]["permanent"][0]["value"], 12)
	assert_eq(summary["left"]["permanent"][1]["stat"], "cooldown_speed")
	assert_eq(summary["left"]["permanent"][1]["value"], 8)

	# Top middle: Power Crown, Haste Crown, Winged Crown.
	assert_eq(summary["top_middle"]["passive"].size(), 3)
	assert_eq(summary["top_middle"]["passive"][0]["stat"], "damage")
	assert_eq(summary["top_middle"]["passive"][0]["value"], 20)
	assert_eq(summary["top_middle"]["passive"][1]["stat"], "cooldown_speed")
	assert_eq(summary["top_middle"]["passive"][1]["value"], 20)
	assert_eq(summary["top_middle"]["passive"][2]["stat"], "multicast")
	assert_eq(summary["top_middle"]["passive"][2]["value"], 1)
	assert_empty(summary["top_middle"]["permanent"])

	# Right column: two Speed Crests and Earth Crest.
	assert_eq(summary["right"]["passive"].size(), 1)
	assert_eq(summary["right"]["passive"][0]["stat"], "cooldown_speed")
	assert_eq(summary["right"]["passive"][0]["value"], 30)
	assert_eq(summary["right"]["permanent"].size(), 1)
	assert_eq(summary["right"]["permanent"][0]["stat"], "shield")
	assert_eq(summary["right"]["permanent"][0]["value"], 10)


func test_format_effect_percent() -> void:
	assert_eq(
		PositionalTrinkets.format_effect({"stat": "cooldown_speed", "value": 12, "percent": true}),
		"+12% Cooldown Speed"
	)


func test_format_effect_flat() -> void:
	assert_eq(
		PositionalTrinkets.format_effect({"stat": "damage", "value": 12, "percent": false}),
		"+12 Damage"
	)


func test_format_effect_text() -> void:
	assert_eq(
		PositionalTrinkets.format_effect({"text": "Damage set to top-middle's Damage", "count": 1}),
		"Damage set to top-middle's Damage"
	)
	assert_eq(
		PositionalTrinkets.format_effect({"text": "Damage set to top-middle's Damage", "count": 2}),
		"Damage set to top-middle's Damage x2"
	)


func test_format_effect_note() -> void:
	assert_eq(
		PositionalTrinkets.format_effect({
			"stat": "stats", "value": 80, "percent": true,
			"note": "except Cooldown/Multicast",
		}),
		"+80% Stats (except Cooldown/Multicast)"
	)


func test_catalog_entries_have_descriptions() -> void:
	for tid in PositionalTrinkets.TRINKETS.keys():
		assert_true(PositionalTrinkets.TRINKETS[tid].has("description"), str(tid))


func test_catalog_ids_are_snake_case() -> void:
	for tid in PositionalTrinkets.TRINKETS.keys():
		assert_eq(str(tid), str(tid).to_lower(), str(tid))
		assert_false(str(tid).contains(" "), str(tid))


func test_summary_does_not_mutate_catalog() -> void:
	var before := str(PositionalTrinkets.TRINKETS)
	PositionalTrinkets.summarize(["quick_flag", "quick_flag"])
	assert_eq(str(PositionalTrinkets.TRINKETS), before)


func test_duplicate_text_effect_counts() -> void:
	var summary := PositionalTrinkets.summarize(["alpha_crown", "alpha_crown"])
	var permanent: Array = summary["top_middle"]["permanent"]
	assert_eq(permanent.size(), 1)
	assert_eq(permanent[0]["count"], 2)
