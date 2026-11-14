extends "test_runner.gd"
## Unit tests for the Rank Odds panel's trinket probability helpers.

const RankOddsPanel = preload("../hud/rank_odds_panel.gd")


func test_rank_4_base_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, false, false, false), [67, 30, 3, 0, 0])


func test_rank_4_plain_lure_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, true, false, false), [73, 25, 3, 0, 0])


func test_rank_4_sweet_lure_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, false, true, false), [62, 36, 2, 0, 0])


func test_rank_4_research_notes_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, false, false, true), [52, 23, 2, 0, 23])


func test_rank_4_all_trinkets_percentages() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	assert_eq(RankOddsPanel._row_percentages(row, true, true, true), [55, 26, 2, 0, 17])


func test_rank_1_plain_lure_stays_100_common() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[0]
	assert_eq(RankOddsPanel._row_percentages(row, true, false, false), [100, 0, 0, 0, 0])


func test_rank_1_sweet_lure_adds_uncommon() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[0]
	# Common 100 -> 110, Uncommon 0 -> 15, total 125.
	assert_eq(RankOddsPanel._row_percentages(row, false, true, false), [88, 12, 0, 0, 0])


func test_rank_1_research_notes_adds_legendary() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[0]
	# Common 100, Legendary 0 -> 30, total 130.
	assert_eq(RankOddsPanel._row_percentages(row, false, false, true), [77, 0, 0, 0, 23])


func test_trinkets_do_not_mutate_base_data() -> void:
	var before: Array = RankOddsPanel.RANK_ODDS[3].duplicate(true)
	RankOddsPanel._row_percentages(RankOddsPanel.RANK_ODDS[3], true, true, true)
	assert_eq(RankOddsPanel.RANK_ODDS[3], before)


func test_repeated_toggles_do_not_accumulate() -> void:
	var row: Array = RankOddsPanel.RANK_ODDS[3]
	var first: Array = RankOddsPanel._row_percentages(row, true, true, true)
	var second: Array = RankOddsPanel._row_percentages(row, true, true, true)
	assert_eq(first, second)
	assert_eq(RankOddsPanel._row_percentages(row, false, false, false), [67, 30, 3, 0, 0])
	assert_eq(RankOddsPanel._row_percentages(row, true, false, false), [73, 25, 3, 0, 0])
	assert_eq(RankOddsPanel._row_percentages(row, false, true, false), [62, 36, 2, 0, 0])
	assert_eq(RankOddsPanel._row_percentages(row, false, false, true), [52, 23, 2, 0, 23])


func test_all_base_rows_sum_to_100() -> void:
	for row in RankOddsPanel.RANK_ODDS:
		var total := 0
		for i in range(1, row.size()):
			total += int(row[i])
		assert_eq(total, 100, "rank %s" % str(row[0]))