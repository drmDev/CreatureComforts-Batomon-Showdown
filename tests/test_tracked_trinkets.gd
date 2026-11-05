extends "test_runner.gd"
## Unit tests for core/tracked_trinkets.gd.

const TrackedTrinkets = preload("../core/tracked_trinkets.gd")


func _resolver(tid) -> String:
	return "N:" + str(tid)


func test_empty_held_list_returns_no_entries() -> void:
	assert_empty(TrackedTrinkets.build_entries([], _resolver))


func test_untracked_ids_are_ignored() -> void:
	assert_empty(TrackedTrinkets.build_entries(["junk", "zenith_stone"], _resolver))


func test_counts_duplicates() -> void:
	var entries := TrackedTrinkets.build_entries(["mini_duplicator", "mini_duplicator"], _resolver)
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["count"], 2)
	assert_eq(entries[0]["name"], "N:mini_duplicator")


func test_entries_follow_catalog_order() -> void:
	var entries := TrackedTrinkets.build_entries(["greedy_gloves", "mini_duplicator"], _resolver)
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["name"], "N:mini_duplicator")
	assert_eq(entries[1]["name"], "N:greedy_gloves")


func test_description_is_included() -> void:
	var entries := TrackedTrinkets.build_entries(["treasure_map"], _resolver)
	assert_eq(entries[0]["desc"], TrackedTrinkets.TRACKED_DESCRIPTIONS["treasure_map"])


func test_entries_carry_the_trinket_id() -> void:
	var entries := TrackedTrinkets.build_entries(["treasure_map"], _resolver)
	assert_eq(entries[0]["id"], "treasure_map")
