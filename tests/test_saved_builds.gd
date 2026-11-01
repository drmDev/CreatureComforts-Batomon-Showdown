extends "test_runner.gd"
## Unit tests for the saved watchlist builds (core/saved_builds.gd).

const SavedBuilds = preload("../core/saved_builds.gd")

const DAY_ONE := 1793404800  # 2026-10-31T00:00:00Z
const DAY_TWO := 1793491200  # 2026-11-01T00:00:00Z


func test_create_build_numbers_increment() -> void:
	var store := SavedBuilds.empty_store()
	var first := SavedBuilds.create_build(store, ["a"], [], DAY_ONE)
	var second := SavedBuilds.create_build(store, [], ["b"], DAY_ONE)
	assert_eq(int(first["number"]), 1)
	assert_eq(int(second["number"]), 2)
	assert_eq(int(store["next_number"]), 3)
	assert_eq(store["builds"].size(), 2)


func test_create_build_sorts_and_dedupes_ids() -> void:
	var store := SavedBuilds.empty_store()
	var build := SavedBuilds.create_build(store, ["b", "a", "b", " "], ["z", "y"], DAY_ONE)
	assert_eq(build["monsters"], ["a", "b"])
	assert_eq(build["items"], ["y", "z"])


func test_deleted_number_is_never_reused() -> void:
	var store := SavedBuilds.empty_store()
	SavedBuilds.create_build(store, ["a"], [], DAY_ONE)
	var newest := SavedBuilds.create_build(store, ["b"], [], DAY_ONE)
	assert_true(SavedBuilds.delete_build(store, str(newest["id"])))
	var next := SavedBuilds.create_build(store, ["c"], [], DAY_TWO)
	assert_eq(int(next["number"]), 3)


func test_delete_does_not_renumber_remaining_builds() -> void:
	var store := SavedBuilds.empty_store()
	var one := SavedBuilds.create_build(store, ["a"], [], DAY_ONE)
	var two := SavedBuilds.create_build(store, ["b"], [], DAY_ONE)
	var three := SavedBuilds.create_build(store, ["c"], [], DAY_ONE)
	assert_true(SavedBuilds.delete_build(store, str(two["id"])))
	assert_eq(store["builds"].size(), 2)
	assert_eq(int(store["builds"][0]["number"]), int(one["number"]))
	assert_eq(int(store["builds"][1]["number"]), int(three["number"]))
	assert_eq(int(store["next_number"]), 4)


func test_delete_unknown_id_is_a_no_op() -> void:
	var store := SavedBuilds.empty_store()
	SavedBuilds.create_build(store, ["a"], [], DAY_ONE)
	assert_false(SavedBuilds.delete_build(store, "nope"))
	assert_eq(store["builds"].size(), 1)


func test_display_name_shows_date_only() -> void:
	var store := SavedBuilds.empty_store()
	var build := SavedBuilds.create_build(store, ["a"], [], DAY_ONE)
	assert_eq(SavedBuilds.display_name(build), "Build 1 (2026-10-31)")
	assert_eq(SavedBuilds.creation_date(build), "2026-10-31")


func test_sorted_newest_first() -> void:
	var store := SavedBuilds.empty_store()
	SavedBuilds.create_build(store, ["a"], [], DAY_ONE)
	SavedBuilds.create_build(store, ["b"], [], DAY_ONE)
	SavedBuilds.create_build(store, ["c"], [], DAY_TWO)
	var ordered := SavedBuilds.sorted_newest_first(store)
	assert_eq(ordered.size(), 3)
	assert_eq(int(ordered[0]["number"]), 3)
	assert_eq(int(ordered[1]["number"]), 2)
	assert_eq(int(ordered[2]["number"]), 1)


func test_preview_orders_monsters_by_rarity_then_name_then_items() -> void:
	var catalog := {
		"monster:legend": {"name": "Zeta", "tier": 5, "icon": null},
		"monster:common_b": {"name": "Beta", "tier": 1, "icon": null},
		"monster:common_a": {"name": "Alpha", "tier": 1, "icon": null},
		"monster:mythic": {"name": "Omega", "tier": 6, "icon": null},
		"item:z_item": {"name": "Zinc", "tier": 1, "icon": null},
		"item:a_item": {"name": "Amber", "tier": 5, "icon": null},
	}
	var lookup := func(kind, key):
		return catalog.get("%s:%s" % [kind, key], null)
	var build := {
		"monsters": ["legend", "common_b", "common_a", "mythic"],
		"items": ["z_item", "a_item"],
	}
	var preview := SavedBuilds.preview_entries(build, lookup)
	var names: Array = []
	for entry in preview["entries"]:
		names.append(entry["name"])
	assert_eq(names, ["Alpha", "Beta", "Zeta", "Omega", "Amber", "Zinc"])
	assert_eq(int(preview["monster_count"]), 4)
	assert_eq(int(preview["item_count"]), 2)
	assert_eq(int(preview["overflow"]), 0)


func test_preview_caps_at_ten_icons_and_reports_overflow() -> void:
	var catalog := {}
	var monsters: Array = []
	for i in range(12):
		var key := "m%02d" % i
		monsters.append(key)
		catalog["monster:" + key] = {"name": "Mon %02d" % i, "tier": 1, "icon": null}
	var lookup := func(kind, key):
		return catalog.get("%s:%s" % [kind, key], null)
	var preview := SavedBuilds.preview_entries({"monsters": monsters, "items": []}, lookup)
	assert_eq(preview["entries"].size(), 10)
	assert_eq(int(preview["overflow"]), 2)


func test_preview_exactly_ten_has_no_overflow() -> void:
	var catalog := {}
	var monsters: Array = []
	for i in range(10):
		var key := "m%02d" % i
		monsters.append(key)
		catalog["monster:" + key] = {"name": "Mon %02d" % i, "tier": 1, "icon": null}
	var lookup := func(kind, key):
		return catalog.get("%s:%s" % [kind, key], null)
	var preview := SavedBuilds.preview_entries({"monsters": monsters, "items": []}, lookup)
	assert_eq(preview["entries"].size(), 10)
	assert_eq(int(preview["overflow"]), 0)


func test_preview_unresolved_ids_sort_last_but_still_count() -> void:
	var catalog := {
		"monster:known": {"name": "Known", "tier": 3, "icon": null},
	}
	var lookup := func(kind, key):
		return catalog.get("%s:%s" % [kind, key], null)
	var build := {"monsters": ["ghost_id", "known"], "items": []}
	var preview := SavedBuilds.preview_entries(build, lookup)
	assert_eq(preview["entries"].size(), 2)
	assert_eq(preview["entries"][0]["name"], "Known")
	assert_eq(preview["entries"][1]["key"], "ghost_id")
	assert_false(preview["entries"][1]["resolved"])
	assert_eq(int(preview["monster_count"]), 2)


func test_parse_empty_and_corrupt_falls_back_to_empty_store() -> void:
	assert_eq(SavedBuilds.parse("")["builds"].size(), 0)
	assert_eq(SavedBuilds.parse("   ")["builds"].size(), 0)
	assert_eq(SavedBuilds.parse("{not json")["builds"].size(), 0)
	assert_eq(SavedBuilds.parse("[1, 2, 3]")["builds"].size(), 0)
	assert_eq(SavedBuilds.parse("{\"builds\": 5}")["builds"].size(), 0)
	assert_eq(int(SavedBuilds.parse("")["next_number"]), 1)


func test_parse_drops_malformed_entries_and_repairs_next_number() -> void:
	var text := JSON.stringify({
		"next_number": 1,
		"builds": [
			{"id": "a", "number": 4, "created": "2026-10-31 10:00:00", "monsters": ["x"], "items": []},
			{"id": "b", "number": 0},
			"junk",
			{"number": 2, "monsters": "not-an-array"},
		],
	})
	var store := SavedBuilds.parse(text)
	assert_eq(store["builds"].size(), 2)
	# next_number was stale (1) but build 4 exists, so the next number is 5.
	assert_eq(int(store["next_number"]), 5)
	assert_eq(store["builds"][1]["monsters"], [])


func test_serialize_parse_round_trip() -> void:
	var store := SavedBuilds.empty_store()
	SavedBuilds.create_build(store, ["monster.name.cairnage"], ["black_sludge"], DAY_ONE)
	SavedBuilds.create_build(store, [], ["gem"], DAY_TWO)
	var restored := SavedBuilds.parse(SavedBuilds.serialize(store))
	assert_eq(int(restored["next_number"]), int(store["next_number"]))
	assert_eq(restored["builds"].size(), 2)
	assert_eq(restored["builds"][0]["monsters"], ["monster.name.cairnage"])
	assert_eq(restored["builds"][0]["items"], ["black_sludge"])
	assert_eq(restored["builds"][1]["items"], ["gem"])
	assert_eq(SavedBuilds.display_name(restored["builds"][1]), "Build 2 (2026-11-01)")
