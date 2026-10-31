extends "test_runner.gd"

const TrainerRules = preload("../advice/trainer_rules.gd")
const TestHelpers = preload("test_helpers.gd")

const BEETDOWN := "monster.name.beetdown"
const LAMPLET := "monster.name.lamplet"
const BASIC_BAIT := "basic_bait"


func _formatter():
	return TestHelpers.FakeFormatter.new()


func test_shop_targets_matches_monster_by_name() -> void:
	var rule = TrainerRules.ShopTargetsRule.new(
		"r1", "musician", [LAMPLET], [], "info", "Buy %s", _formatter()
	)
	var ctx = TestHelpers.context("musician", 1, [
		TestHelpers.shop_monster(0, LAMPLET, [], 111),
	])
	var advice: Dictionary = rule.evaluate(ctx)
	assert_not_empty(advice)
	assert_eq(advice["rule_id"], "r1")
	assert_eq(advice["trainer_id"], "musician")
	assert_eq(advice["severity"], "info")
	assert_eq(advice["display"], "highlight")
	assert_eq(advice["matched_indices"], [0])
	assert_eq(advice["matched_ids"], [111])
	assert_true(str(advice["message"]).contains("Lamplet"))


func test_shop_targets_matches_item() -> void:
	var rule = TrainerRules.ShopTargetsRule.new(
		"r2", "musician", [], [BASIC_BAIT], "info", "Buy %s", _formatter()
	)
	var ctx = TestHelpers.context("musician", 1, [
		TestHelpers.shop_item(2, BASIC_BAIT, 222),
	])
	var advice: Dictionary = rule.evaluate(ctx)
	assert_not_empty(advice)
	assert_eq(advice["matched_indices"], [2])
	assert_eq(advice["matched_ids"], [222])
	assert_true(str(advice["message"]).contains("Basic Bait"))


func test_shop_targets_matches_monster_by_type() -> void:
	var rule = TrainerRules.ShopTargetsRule.new(
		"r3", "musician", [], [], "info", "Buy %s", _formatter(), ["fire"]
	)
	var ctx = TestHelpers.context("musician", 1, [
		TestHelpers.shop_monster(1, LAMPLET, ["fire", "flying"], 333),
	])
	var advice: Dictionary = rule.evaluate(ctx)
	assert_not_empty(advice)
	assert_eq(advice["matched_indices"], [1])


func test_shop_targets_no_match_returns_empty() -> void:
	var rule = TrainerRules.ShopTargetsRule.new(
		"r4", "musician", [LAMPLET], [], "info", "Buy %s", _formatter()
	)
	var ctx = TestHelpers.context("musician", 1, [
		TestHelpers.shop_monster(0, BEETDOWN, [], 1),
	])
	assert_empty(rule.evaluate(ctx))


func test_shop_targets_trainer_mismatch_returns_empty() -> void:
	var rule = TrainerRules.ShopTargetsRule.new(
		"r5", "musician", [LAMPLET], [], "info", "Buy %s", _formatter()
	)
	var ctx = TestHelpers.context("gentleman", 1, [
		TestHelpers.shop_monster(0, LAMPLET, [], 1),
	])
	assert_empty(rule.evaluate(ctx))


func test_shop_targets_empty_trainer_applies_to_any() -> void:
	var rule = TrainerRules.ShopTargetsRule.new(
		"r6", "", [LAMPLET], [], "info", "Buy %s", _formatter()
	)
	var ctx = TestHelpers.context("gentleman", 1, [
		TestHelpers.shop_monster(0, LAMPLET, [], 1),
	])
	assert_not_empty(rule.evaluate(ctx))


func test_team_anchor_flags_offender() -> void:
	var rule = TrainerRules.TeamCompositionRule.new(
		"r7", "musician", "warn", _formatter(), BEETDOWN, 3, "fighter",
		"Offenders: %s", "Beetdown only", 1
	)
	var ctx = TestHelpers.context("musician", 1, [], [
		TestHelpers.team_monster(0, BEETDOWN, 3, ["fighter"]),
		TestHelpers.team_monster(1, LAMPLET, 2, ["fighter"]),
	])
	var advice: Dictionary = rule.evaluate(ctx)
	assert_not_empty(advice)
	assert_eq(advice["display"], "label")
	assert_eq(advice["reminder"], "Beetdown only")
	assert_true(str(advice["message"]).contains("Lamplet"))


func test_team_anchor_missing_anchor_returns_empty() -> void:
	var rule = TrainerRules.TeamCompositionRule.new(
		"r8", "musician", "warn", _formatter(), BEETDOWN, 3, "fighter",
		"Offenders: %s", "Beetdown only", 1
	)
	var ctx = TestHelpers.context("musician", 1, [], [
		TestHelpers.team_monster(1, LAMPLET, 2, ["fighter"]),
	])
	assert_empty(rule.evaluate(ctx))


func test_team_anchor_below_min_level_returns_empty() -> void:
	var rule = TrainerRules.TeamCompositionRule.new(
		"r9", "musician", "warn", _formatter(), BEETDOWN, 3, "fighter",
		"Offenders: %s", "Beetdown only", 1
	)
	var ctx = TestHelpers.context("musician", 1, [], [
		TestHelpers.team_monster(0, BEETDOWN, 2, ["fighter"]),
		TestHelpers.team_monster(1, LAMPLET, 2, ["fighter"]),
	])
	assert_empty(rule.evaluate(ctx))


func test_team_anchor_no_offenders_returns_empty() -> void:
	var rule = TrainerRules.TeamCompositionRule.new(
		"r10", "musician", "warn", _formatter(), BEETDOWN, 3, "fighter",
		"Offenders: %s", "Beetdown only", 1
	)
	var ctx = TestHelpers.context("musician", 1, [], [
		TestHelpers.team_monster(0, BEETDOWN, 3, ["fighter"]),
		TestHelpers.team_monster(1, LAMPLET, 2, ["water"]),
	])
	assert_empty(rule.evaluate(ctx))


func test_team_count_mode_flags_excess() -> void:
	var rule = TrainerRules.TeamCompositionRule.new(
		"r11", "musician", "warn", _formatter(), "", 0, "electric",
		"Too many: %s", "Electric limit", 1
	)
	var ctx = TestHelpers.context("musician", 1, [], [
		TestHelpers.team_monster(0, LAMPLET, 2, ["electric"]),
		TestHelpers.team_monster(1, LAMPLET, 2, ["electric"]),
	])
	var advice: Dictionary = rule.evaluate(ctx)
	assert_not_empty(advice)
	assert_true(str(advice["message"]).contains("2"))


func test_team_count_mode_within_limit_returns_empty() -> void:
	var rule = TrainerRules.TeamCompositionRule.new(
		"r12", "musician", "warn", _formatter(), "", 0, "electric",
		"Too many: %s", "Electric limit", 1
	)
	var ctx = TestHelpers.context("musician", 1, [], [
		TestHelpers.team_monster(0, LAMPLET, 2, ["electric"]),
	])
	assert_empty(rule.evaluate(ctx))


func test_day_reminder_matches_day() -> void:
	var rule = TrainerRules.DayReminderRule.new(
		"r13", "mad_scientist", 6, "info", "Transform today", "Day 6!"
	)
	var ctx = TestHelpers.context("mad_scientist", 6)
	var advice: Dictionary = rule.evaluate(ctx)
	assert_not_empty(advice)
	assert_eq(advice["display"], "label")
	assert_eq(advice["reminder"], "Day 6!")
	assert_true(advice["chime"])


func test_day_reminder_wrong_day_returns_empty() -> void:
	var rule = TrainerRules.DayReminderRule.new(
		"r14", "mad_scientist", 6, "info", "Transform today", "Day 6!"
	)
	var ctx = TestHelpers.context("mad_scientist", 5)
	assert_empty(rule.evaluate(ctx))


func test_day_reminder_trainer_mismatch_returns_empty() -> void:
	var rule = TrainerRules.DayReminderRule.new(
		"r15", "mad_scientist", 6, "info", "Transform today", "Day 6!"
	)
	var ctx = TestHelpers.context("gentleman", 6)
	assert_empty(rule.evaluate(ctx))
