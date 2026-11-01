extends "test_runner.gd"
## Unit tests for the watchlist panel's pure helpers.

const WatchlistPanel = preload("../hud/watchlist_panel.gd")


func test_parse_ids_splits_and_trims() -> void:
	var parsed = WatchlistPanel._parse_ids("a, b ,,c")
	assert_eq(parsed.size(), 3)
	assert_true(parsed.has("a"))
	assert_true(parsed.has("b"))
	assert_true(parsed.has("c"))


func test_parse_ids_empty() -> void:
	assert_empty(WatchlistPanel._parse_ids(""))
	assert_empty(WatchlistPanel._parse_ids(" , , "))


func test_format_ids_sorted() -> void:
	assert_eq(WatchlistPanel._format_ids({"b": true, "a": true}), "a,b")
	assert_eq(WatchlistPanel._format_ids({}), "")


func test_is_watched() -> void:
	var panel = WatchlistPanel.new()
	panel.selection = {"monster": {"monster.name.cairnage": true}, "item": {}}
	assert_true(panel.is_watched("monster", "monster.name.cairnage"))
	assert_false(panel.is_watched("monster", "monster.name.gemwing"))
	assert_false(panel.is_watched("item", "black_sludge"))
	panel.free()


func test_team_species_keys_unique_and_skips_empty_slots() -> void:
	# Dictionary entries stand in for MonsterInstance objects with data.name_key.
	var team := [
		{"data": {"name_key": "monster.name.cairnage"}},
		null,
		{"data": {"name_key": "monster.name.cairnage"}},
		{"data": {"name_key": "monster.name.gemwing"}},
		{"data": {"name_key": "   "}},
		{"data": {}},
		{"not_a_monster": true},
		"junk",
	]
	var keys = WatchlistPanel.team_species_keys(team)
	assert_eq(keys.size(), 2)
	assert_true(keys.has("monster.name.cairnage"))
	assert_true(keys.has("monster.name.gemwing"))


func test_team_species_keys_empty_or_all_empty_slots() -> void:
	assert_empty(WatchlistPanel.team_species_keys([]))
	assert_empty(WatchlistPanel.team_species_keys([null, null]))
