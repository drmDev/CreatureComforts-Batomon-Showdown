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
