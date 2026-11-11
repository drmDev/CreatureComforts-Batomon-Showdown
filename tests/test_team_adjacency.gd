extends "test_runner.gd"
## Tests for core/team_adjacency.gd and the Petrirex/Shikitsune reminder rule.
##
## Slot numbers in these tests are the 1-based visual grid the player sees:
##   [1] [2] [3]
##   [4] [5] [6]
## The advice context stores monsters in game order (bottom-right to top-left),
## so helpers here convert a visual slot back to its storage index.

const TeamAdjacency = preload("../core/team_adjacency.gd")
const TrainerRules = preload("../advice/trainer_rules.gd")
const TrainerAdvisor = preload("../advice/trainer_advisor.gd")
const TrainerCatalog = preload("../advice/trainer_catalog.gd")
const RuleFactory = preload("../advice/rule_factory.gd")
const TestHelpers = preload("test_helpers.gd")

const TEAM_SIZE := 6
const PETRIREX := "monster.name.petrirex"
const SHIKITSUNE := "monster.name.shikitsune"
const RULE_ID := "petrirex_skikitsune_adjacency"
const REMINDER := "Shikitsune is adjacent to Petrirex! Move it to avoid being knocked out."
const MESSAGE := "Shikitsune is adjacent to Petrirex! Move it to avoid being knocked out."


func _rule():
	return TrainerRules.PetrirexAdjacencyRule.new(RULE_ID, "", "WARNING", MESSAGE, REMINDER)


func _storage_for_visual(visual_slot: int) -> int:
	return TEAM_SIZE - visual_slot


## Context whose active team places the given name keys at visual slots.
func _context(placements: Dictionary):
	var monsters: Array = []
	for visual_slot in placements:
		monsters.append(TestHelpers.team_monster(
			_storage_for_visual(int(visual_slot)), str(placements[visual_slot]), 1
		))
	var context = TestHelpers.context("", 1, monsters)
	context.team_size = TEAM_SIZE
	return context


func _advice_for(placements: Dictionary) -> Dictionary:
	return _rule().evaluate(_context(placements))


# ---------------------------------------------------------------------------
# Adjacency helper
# ---------------------------------------------------------------------------

func test_adjacency_matches_spec_table() -> void:
	var expected := {
		1: [2, 4],
		2: [1, 3, 5],
		3: [2, 6],
		4: [1, 5],
		5: [2, 4, 6],
		6: [3, 5],
	}
	for slot in expected:
		for other in range(1, 7):
			assert_eq(
				TeamAdjacency.are_slots_adjacent(slot, other),
				expected[slot].has(other),
				"slot %d vs %d" % [slot, other]
			)


func test_diagonal_slots_are_not_adjacent() -> void:
	assert_false(TeamAdjacency.are_slots_adjacent(1, 5), "top-left vs middle-right")
	assert_false(TeamAdjacency.are_slots_adjacent(3, 4), "top-right vs bottom-left")
	assert_false(TeamAdjacency.are_slots_adjacent(2, 6), "top-middle vs bottom-right")


func test_invalid_and_identical_slots_are_not_adjacent() -> void:
	assert_false(TeamAdjacency.are_slots_adjacent(0, 1))
	assert_false(TeamAdjacency.are_slots_adjacent(1, 7))
	assert_false(TeamAdjacency.are_slots_adjacent(-1, 2))
	assert_false(TeamAdjacency.are_slots_adjacent(3, 3))


func test_slot_to_row_col_grid_positions() -> void:
	assert_eq(TeamAdjacency.slot_to_row_col(1), Vector2i(0, 0))
	assert_eq(TeamAdjacency.slot_to_row_col(3), Vector2i(0, 2))
	assert_eq(TeamAdjacency.slot_to_row_col(4), Vector2i(1, 0))
	assert_eq(TeamAdjacency.slot_to_row_col(6), Vector2i(1, 2))
	assert_eq(TeamAdjacency.slot_to_row_col(0), Vector2i(-1, -1))
	assert_eq(TeamAdjacency.slot_to_row_col(7), Vector2i(-1, -1))


func test_find_unsafe_pairs_dedupes_and_skips_invalid() -> void:
	var pairs = TeamAdjacency.find_unsafe_pairs([1, 1, 0], [2, 7])
	assert_eq(pairs.size(), 1)
	assert_eq(pairs[0], Vector2i(1, 2))


func test_has_unsafe_pair_requires_an_adjacent_pair() -> void:
	assert_true(TeamAdjacency.has_unsafe_pair([2], [1]))
	assert_false(TeamAdjacency.has_unsafe_pair([2], [4]))
	assert_false(TeamAdjacency.has_unsafe_pair([], [1]))


# ---------------------------------------------------------------------------
# Visual slot conversion
# ---------------------------------------------------------------------------

func test_visual_slot_conversion_from_storage_order() -> void:
	assert_eq(TrainerRules.PetrirexAdjacencyRule.visual_slot_for(6, 5), 1, "top-left")
	assert_eq(TrainerRules.PetrirexAdjacencyRule.visual_slot_for(6, 3), 3, "top-right")
	assert_eq(TrainerRules.PetrirexAdjacencyRule.visual_slot_for(6, 2), 4, "bottom-left")
	assert_eq(TrainerRules.PetrirexAdjacencyRule.visual_slot_for(6, 0), 6, "bottom-right")


func test_helper_is_the_shared_slot_source() -> void:
	# The battle slot log and the rule must use the same conversion, including
	# for a smaller team array.
	for team_size in [6, 5, 4]:
		for storage in range(team_size):
			assert_eq(
				TrainerRules.PetrirexAdjacencyRule.visual_slot_for(team_size, storage),
				TeamAdjacency.visual_slot_for(team_size, storage),
				"team_size %d storage %d" % [team_size, storage]
			)


func test_species_keys_shared_between_helper_and_rule() -> void:
	assert_eq(TrainerRules.PetrirexAdjacencyRule.PETRIREX_KEY, TeamAdjacency.PETRIREX_KEY)
	assert_eq(TrainerRules.PetrirexAdjacencyRule.SHIKITSUNE_KEY, TeamAdjacency.SHIKITSUNE_KEY)
	assert_eq(TeamAdjacency.PETRIREX_KEY, PETRIREX)
	assert_eq(TeamAdjacency.SHIKITSUNE_KEY, SHIKITSUNE)


## Guards the exact game species keys with literals. Constants alone cannot catch
## a typo (e.g. "skikitsune" vs the real "shikitsune"), which would silently
## disable the warning in-game.
func test_rule_matches_verified_game_species_keys() -> void:
	var context = TestHelpers.context("", 1, [
		TestHelpers.team_monster(_storage_for_visual(2), "monster.name.petrirex", 1),
		TestHelpers.team_monster(_storage_for_visual(1), "monster.name.shikitsune", 1),
	])
	context.team_size = TEAM_SIZE
	assert_not_empty(_rule().evaluate(context))
	assert_eq(SHIKITSUNE, "monster.name.shikitsune")


# ---------------------------------------------------------------------------
# Unsafe positioning (spec scenarios)
# ---------------------------------------------------------------------------

func test_unsafe_slot_2_shikitsune_1_warns() -> void:
	var advice := _advice_for({2: PETRIREX, 1: SHIKITSUNE})
	assert_not_empty(advice)
	assert_eq(advice["rule_id"], RULE_ID)
	assert_eq(advice["display"], "label")
	assert_eq(advice["reminder"], REMINDER)
	assert_false(advice["chime"])


func test_unsafe_slot_2_shikitsune_3_warns() -> void:
	assert_not_empty(_advice_for({2: PETRIREX, 3: SHIKITSUNE}))


func test_unsafe_slot_2_shikitsune_5_warns() -> void:
	assert_not_empty(_advice_for({2: PETRIREX, 5: SHIKITSUNE}))


func test_unsafe_slot_4_shikitsune_1_warns() -> void:
	assert_not_empty(_advice_for({4: PETRIREX, 1: SHIKITSUNE}))


func test_unsafe_slot_5_shikitsune_6_warns() -> void:
	assert_not_empty(_advice_for({5: PETRIREX, 6: SHIKITSUNE}))


# ---------------------------------------------------------------------------
# Safe positioning (spec scenarios)
# ---------------------------------------------------------------------------

func test_safe_slot_2_shikitsune_4_is_quiet() -> void:
	assert_empty(_advice_for({2: PETRIREX, 4: SHIKITSUNE}))


func test_safe_slot_2_shikitsune_6_is_quiet() -> void:
	assert_empty(_advice_for({2: PETRIREX, 6: SHIKITSUNE}))


func test_safe_slot_1_shikitsune_5_is_quiet() -> void:
	assert_empty(_advice_for({1: PETRIREX, 5: SHIKITSUNE}))


func test_safe_slot_3_shikitsune_4_is_quiet() -> void:
	assert_empty(_advice_for({3: PETRIREX, 4: SHIKITSUNE}))


# ---------------------------------------------------------------------------
# Multiples, empty slots, and benched units
# ---------------------------------------------------------------------------

func test_multiple_copies_warn_once_per_rule() -> void:
	# Two adjacent Petrirex copies make two unsafe pairs, but the rule returns a
	# single advice dictionary, so only one reminder is ever shown.
	assert_eq(TeamAdjacency.find_unsafe_pairs([1, 3], [2]).size(), 2)
	var advice := _advice_for({1: PETRIREX, 2: SHIKITSUNE, 3: PETRIREX})
	assert_not_empty(advice)
	assert_eq(advice["rule_id"], RULE_ID)
	assert_eq(advice["reminder"], REMINDER)


func test_multiple_shikitsune_warns_when_any_copy_is_adjacent() -> void:
	assert_not_empty(_advice_for({2: PETRIREX, 4: SHIKITSUNE, 1: SHIKITSUNE}))
	assert_empty(_advice_for({2: PETRIREX, 4: SHIKITSUNE, 6: SHIKITSUNE}))


func test_empty_slots_do_not_warn() -> void:
	assert_empty(_advice_for({2: PETRIREX}))
	assert_empty(_advice_for({1: SHIKITSUNE}))


func test_benched_shikitsune_is_ignored() -> void:
	# A benched Shikitsune never reaches team_monsters, so only the fielded
	# Petrirex is inspected.
	assert_empty(_advice_for({2: PETRIREX}))


func test_missing_team_size_is_quiet() -> void:
	var context = TestHelpers.context("", 1, [TestHelpers.team_monster(5, PETRIREX, 1)])
	context.team_size = 0
	assert_empty(_rule().evaluate(context))


# ---------------------------------------------------------------------------
# Advisor lifecycle: appears, clears, and returns
# ---------------------------------------------------------------------------

func test_advisor_shows_clears_and_reshows() -> void:
	var advisor = TrainerAdvisor.new()
	advisor.register_rule(_rule())

	var unsafe: Dictionary = advisor.evaluate(_context({2: PETRIREX, 1: SHIKITSUNE}))
	assert_eq(unsafe["all_active"].size(), 1)
	assert_eq(unsafe["new_or_changed"].size(), 1)

	var safe: Dictionary = advisor.evaluate(_context({2: PETRIREX, 4: SHIKITSUNE}))
	assert_empty(safe["all_active"])
	assert_empty(safe["new_or_changed"])

	var again: Dictionary = advisor.evaluate(_context({2: PETRIREX, 1: SHIKITSUNE}))
	assert_eq(again["all_active"].size(), 1)
	assert_eq(again["new_or_changed"].size(), 1, "re-appears after being safe")


# ---------------------------------------------------------------------------
# Catalog + factory wiring
# ---------------------------------------------------------------------------

func test_catalog_entry_builds_the_rule() -> void:
	var factory = RuleFactory.new(TestHelpers.FakeFormatter.new())
	var rules: Array = factory.build_trainer({"id": "", "rules": TrainerCatalog.GLOBAL_RULES})
	var found = null
	for rule in rules:
		if rule.rule_id == RULE_ID:
			found = rule
	assert_true(found != null, "catalog must register %s" % RULE_ID)
	if found == null:
		return
	assert_eq(found.display_mode, TrainerRules.BaseRule.DISPLAY_LABEL)
	assert_eq(found.reminder_text, REMINDER)
	assert_false(found.chime)


func test_catalog_rule_evaluates_adjacency() -> void:
	var factory = RuleFactory.new(TestHelpers.FakeFormatter.new())
	var rules: Array = factory.build_trainer({"id": "", "rules": TrainerCatalog.GLOBAL_RULES})
	for rule in rules:
		if rule.rule_id != RULE_ID:
			continue
		assert_not_empty(rule.evaluate(_context({5: PETRIREX, 6: SHIKITSUNE})))
		assert_empty(rule.evaluate(_context({5: PETRIREX, 1: SHIKITSUNE})))
