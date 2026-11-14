extends "test_runner.gd"
## Unit tests for the Rank Odds panel's trinket probability helpers.

const RankOddsPanel = preload("../hud/rank_odds_panel.gd")


func test_rank_4_base_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [false, false, false, false]), [67, 30, 3, 0, 0])


func test_rank_4_plain_lure_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [true, false, false, false]), [73, 25, 3, 0, 0])


func test_rank_4_sweet_lure_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [false, true, false, false]), [62, 36, 2, 0, 0])


func test_rank_4_research_notes_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [false, false, true, false]), [52, 23, 2, 0, 23])


func test_rank_4_all_trinkets_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [true, true, true, false]), [55, 26, 2, 0, 17])


func test_rank_1_plain_lure_stays_100_common() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[0]
	assert_eq(RankOddsPanel._row_percentages(row, [true, false, false, false]), [100, 0, 0, 0, 0])


func test_rank_1_sweet_lure_adds_uncommon() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[0]
	# Common 100 -> 110, Uncommon 0 -> 15, total 125.
	assert_eq(RankOddsPanel._row_percentages(row, [false, true, false, false]), [88, 12, 0, 0, 0])


func test_rank_1_research_notes_adds_legendary() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[0]
	# Common 100, Legendary 0 -> 30, total 130.
	assert_eq(RankOddsPanel._row_percentages(row, [false, false, true, false]), [77, 0, 0, 0, 23])


func test_vip_pass_only_matches_reference_table() -> void:
	var expected := [
		[0, 0, 100, 0, 0],
		[0, 0, 100, 0, 0],
		[0, 0, 100, 0, 0],
		[0, 0, 100, 0, 0],
		[0, 0, 100, 0, 0],
		[0, 0, 87, 13, 0],
		[0, 0, 83, 17, 0],
		[0, 0, 78, 22, 0],
		[0, 0, 69, 27, 4],
		[0, 0, 62, 31, 8],
		[0, 0, 50, 36, 14],
		[0, 0, 38, 44, 19],
		[0, 0, 34, 44, 22],
		[0, 0, 21, 48, 31],
	]
	for i in range(RankOddsPanel.RANK_ODDS.size()):
		assert_eq(RankOddsPanel._row_percentages(RankOddsPanel.RANK_ODDS[i], [false, false, false, true]), expected[i], "rank %d" % (i + 1))


func test_vip_pass_with_research_notes() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [false, false, true, true]), [0, 0, 9, 0, 91])


func test_vip_pass_blocks_plain_and_sweet_common_uncommon() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [true, false, false, true]), [0, 0, 100, 0, 0])
	assert_eq(RankOddsPanel._row_percentages(row, [false, true, false, true]), [0, 0, 100, 0, 0])


func test_vip_pass_all_trinkets() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, [true, true, true, true]), [0, 0, 9, 0, 91])


func test_trinkets_do_not_mutate_base_data() -> void:
	var before: Array = RankOddsPanel.RANK_ODDS[3].duplicate(true)
	RankOddsPanel._row_percentages(RankOddsPanel.RANK_ODDS[3], [true, true, true, true])
	assert_eq(RankOddsPanel.RANK_ODDS[3], before)


func test_repeated_toggles_do_not_accumulate() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	var first: Array = RankOddsPanel._row_percentages(row, [true, true, true, true])
	var second: Array = RankOddsPanel._row_percentages(row, [true, true, true, true])
	assert_eq(first, second)
	assert_eq(RankOddsPanel._row_percentages(row, [false, false, false, false]), [67, 30, 3, 0, 0])
	assert_eq(RankOddsPanel._row_percentages(row, [true, false, false, false]), [73, 25, 3, 0, 0])
	assert_eq(RankOddsPanel._row_percentages(row, [false, true, false, false]), [62, 36, 2, 0, 0])
	assert_eq(RankOddsPanel._row_percentages(row, [false, false, true, false]), [52, 23, 2, 0, 23])
	assert_eq(RankOddsPanel._row_percentages(row, [false, false, false, true]), [0, 0, 100, 0, 0])


func test_owns_trinket_detects_held_ids() -> void:
	assert_true(RankOddsPanel._owns_trinket(["plain_lure"], "plain_lure"))
	assert_true(RankOddsPanel._owns_trinket(["trinket_vip_pass"], "vip_pass"))
	assert_false(RankOddsPanel._owns_trinket(["plain_lure"], "sweet_lure"))
	assert_false(RankOddsPanel._owns_trinket([], "plain_lure"))


func test_all_base_rows_sum_to_100() -> void:
	for row in RankOddsPanel.RANK_ODDS:
		var total := 0
		for i in range(1, row.size()):
			total += int(row[i])
		assert_eq(total, 100, "rank %s" % str(row[0]))