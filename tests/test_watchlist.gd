extends "test_runner.gd"
## Unit tests for the watchlist panel's pure helpers.

const WatchlistPanel = preload("../hud/watchlist_panel.gd")
const ShopHighlight = preload("../hud/shop_highlight.gd")


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


func test_region_filter_matches_any_region() -> void:
	var panel = WatchlistPanel.new()
	panel._region_filter = "Jinto"
	var entry := {"tier": 1, "types": [], "regions": ["Jinto", "Pantra"]}
	assert_true(panel._passes_monster_filters(entry))
	entry["regions"] = ["Pantra"]
	assert_false(panel._passes_monster_filters(entry))
	panel.free()


func test_rarity_and_type_filters() -> void:
	var panel = WatchlistPanel.new()
	panel._rarity_filter = "Rare"
	panel._type_filter = "Fire"
	var entry := {"tier": 3, "types": ["Fire"], "regions": []}
	assert_true(panel._passes_monster_filters(entry))
	entry["tier"] = 2
	assert_false(panel._passes_monster_filters(entry))
	panel.free()


func test_extract_regions_keeps_all_mapped_sets() -> void:
	var panel = WatchlistPanel.new()
	panel._region_map = {"jinto": "Jinto", "pantra": "Pantra"}
	var regions = panel._extract_regions({"sets": ["jinto", "pantra", "jinto"]})
	assert_eq(regions.size(), 2)
	assert_true(regions.has("Jinto"))
	assert_true(regions.has("Pantra"))
	panel.free()


func test_toggled_filter_value() -> void:
	assert_eq(WatchlistPanel.toggled_filter_value("", "Fire"), "Fire")
	assert_eq(WatchlistPanel.toggled_filter_value("Fire", "Fire"), "")
	assert_eq(WatchlistPanel.toggled_filter_value("Fire", "Water"), "Water")
	assert_eq(WatchlistPanel.toggled_filter_value("", ""), "")


func test_sort_entries_by_name() -> void:
	var entries := [
		{"name": "Zeta", "tier": 1},
		{"name": "alpha", "tier": 5},
		{"name": "Beta", "tier": 2},
	]
	WatchlistPanel.sort_entries(entries, WatchlistPanel.SORT_NAME)
	assert_eq(entries[0]["name"], "alpha")
	assert_eq(entries[1]["name"], "Beta")
	assert_eq(entries[2]["name"], "Zeta")


func test_sort_entries_by_rarity_then_name() -> void:
	var entries := [
		{"name": "Zeta", "tier": 3},
		{"name": "Beta", "tier": 1},
		{"name": "Alpha", "tier": 3},
		{"name": "Myth", "tier": 6},
	]
	WatchlistPanel.sort_entries(entries, WatchlistPanel.SORT_RARITY)
	assert_eq(entries[0]["name"], "Beta")
	assert_eq(entries[1]["name"], "Alpha")
	assert_eq(entries[2]["name"], "Zeta")
	assert_eq(entries[3]["name"], "Myth")


func test_sort_entries_descending() -> void:
	var names := [
		{"name": "Alpha"},
		{"name": "Zeta"},
		{"name": "Beta"},
	]
	WatchlistPanel.sort_entries(names, WatchlistPanel.SORT_NAME, true)
	assert_eq(names[0]["name"], "Zeta")
	assert_eq(names[1]["name"], "Beta")
	assert_eq(names[2]["name"], "Alpha")
	var tiers := [
		{"name": "Common", "tier": 1},
		{"name": "Myth", "tier": 6},
		{"name": "Rare", "tier": 3},
	]
	WatchlistPanel.sort_entries(tiers, WatchlistPanel.SORT_RARITY, true)
	assert_eq(tiers[0]["name"], "Myth")
	assert_eq(tiers[1]["name"], "Rare")
	assert_eq(tiers[2]["name"], "Common")


func test_sort_entries_descending_keeps_unknown_last() -> void:
	var entries := [
		{"name": "Common", "tier": 1},
		{"name": "Unknown", "tier": 0},
		{"name": "Myth", "tier": 6},
	]
	WatchlistPanel.sort_entries(entries, WatchlistPanel.SORT_RARITY, true)
	assert_eq(entries[0]["name"], "Myth")
	assert_eq(entries[1]["name"], "Common")
	assert_eq(entries[2]["name"], "Unknown")


func test_sort_entries_unknown_tier_sorts_last() -> void:
	var entries := [
		{"name": "Unknown", "tier": 0},
		{"name": "Common", "tier": 1},
		{"name": "Missing"},
	]
	WatchlistPanel.sort_entries(entries, WatchlistPanel.SORT_RARITY)
	assert_eq(entries[0]["name"], "Common")
	assert_eq(entries[1]["name"], "Missing")
	assert_eq(entries[2]["name"], "Unknown")


func test_is_excluded_key_uses_word_boundaries() -> void:
	var panel = WatchlistPanel.new()
	assert_true(panel._is_excluded_key("monster.name.egg"))
	assert_true(panel._is_excluded_key("monster.name.mysterious_egg"))
	assert_false(panel._is_excluded_key("monster.name.eggplant"))
	panel.free()


func test_highlight_matches_item() -> void:
	var card = FakeCard.new()
	var item = FakeItem.new()
	item.id = "black_sludge"
	card.current_content = item
	var overlay = ShopHighlight.HighlightOverlay.new()
	overlay.watchlist = {"monster": {}, "item": {"black_sludge": true}}
	card.add_child(overlay)
	assert_true(overlay._matches())
	overlay.watchlist = {"monster": {}, "item": {}}
	assert_false(overlay._matches())
	card.free()


class FakeCard extends Control:
	var current_content = null


class FakeItem extends RefCounted:
	var id := ""
