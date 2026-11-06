extends "test_runner.gd"
## Unit tests for core/run_region.gd helpers.

const RunRegion = preload("../core/run_region.gd")


func test_build_region_map_translates_ids() -> void:
	# sets_db is an Array; species_packs_db is exercised as a Dictionary too.
	var db := {
		"sets_db": [
			{"id": "oshima", "name": "Jinto"},
			{"id": "set_pantra", "name_key": "Pantra"},
		],
		"species_packs_db": {"pack_extra": {"id": "pack_extra", "name": "Verdant"}},
	}
	var regions = RunRegion.build_region_map(db)
	assert_eq(regions.size(), 3)
	assert_eq(str(regions.get("oshima", "")), "Jinto")
	assert_eq(str(regions.get("set_pantra", "")), "Pantra")
	assert_eq(str(regions.get("pack_extra", "")), "Verdant")


func test_build_region_map_ignores_incomplete_entries() -> void:
	var db := {"sets_db": [{"id": "", "name": "Nameless"}, {"id": "set_a"}, null]}
	assert_empty(RunRegion.build_region_map(db))


func test_build_species_region_map_groups_by_set() -> void:
	var db := {
		"sets_db": [
			{"id": "starter", "name": "Pantra"},
			{"id": "oshima", "name": "Jinto"},
		],
		"species_packs_db": [
			{"id": "starter_pack", "set_id": "starter", "species_ids": ["cairnage", "gemwing"]},
			{"id": "oshima_pack", "set_id": "oshima", "species_ids": ["gemwing", "dracana"]},
		],
	}
	var map = RunRegion.build_species_region_map(db)
	assert_eq(map.get("cairnage", []), ["Pantra"])
	assert_eq(map.get("gemwing", []), ["Pantra", "Jinto"])
	assert_eq(map.get("dracana", []), ["Jinto"])


func test_build_species_region_map_handles_dictionary_packs() -> void:
	var db := {
		"sets_db": [{"id": "starter", "name": "Pantra"}],
		"species_packs_db": {
			"pack_a": {"id": "pack_a", "set_id": "starter", "species_ids": ["cairnage"]},
		},
	}
	var map = RunRegion.build_species_region_map(db)
	assert_eq(map.get("cairnage", []), ["Pantra"])


## A species can belong to a set's dex without appearing in any shop pack
## (Onsetra in Jinto). The dex helper must win over the pack-only map.
func test_build_species_region_map_uses_dex_membership() -> void:
	var db := DexDb.new()
	var map = RunRegion.build_species_region_map(db)
	assert_eq(map.get("onsetra", []), ["Jinto"])
	assert_eq(map.get("gemwing", []), ["Jinto"])


## When the dex helper returns nothing, the pack-derived map is still used.
func test_build_species_region_map_falls_back_to_packs() -> void:
	var db := DexDb.new()
	db.has_dex = false
	var map = RunRegion.build_species_region_map(db)
	assert_eq(map.get("gemwing", []), ["Jinto"])
	assert_eq(map.get("onsetra", []), [])


func test_build_species_region_map_empty_db() -> void:
	assert_empty(RunRegion.build_species_region_map({}))


func test_normalize_value_keeps_plain_names() -> void:
	assert_eq(RunRegion.normalize_value("Jinto", {}), "Jinto")
	assert_eq(RunRegion.normalize_value("  Pantra  ", {}), "Pantra")
	assert_eq(RunRegion.normalize_value("", {}), "")
	assert_eq(RunRegion.normalize_value(null, {}), "")


func test_normalize_value_maps_catalog_ids() -> void:
	var regions := {"oshima": "Jinto"}
	assert_eq(RunRegion.normalize_value("oshima", regions), "Jinto")
	assert_eq(RunRegion.normalize_value("OSHIMA", regions), "Jinto")
	assert_eq(RunRegion.normalize_value(["", "oshima"], regions), "Jinto")


func test_normalize_value_matches_display_names() -> void:
	var regions := {"oshima": "Jinto", "set_pantra": "Pantra"}
	assert_eq(RunRegion.normalize_value("jinto", regions), "Jinto")
	assert_eq(RunRegion.normalize_value("set_pantra", regions), "Pantra")
	assert_eq(RunRegion.normalize_value("jinto_variant", regions), "Jinto")
	# Unknown values pass through unchanged.
	assert_eq(RunRegion.normalize_value("verdant", regions), "verdant")


func test_active_set_id_is_probed() -> void:
	# RunManager.data carries the active region in `active_set_id`.
	assert_true(RunRegion.CANDIDATE_KEYS.has("active_set_id"))


func test_normalize_value_ignores_unsupported_types() -> void:
	assert_eq(RunRegion.normalize_value(7, {}), "")
	assert_eq(RunRegion.normalize_value([], {}), "")
	assert_eq(RunRegion.normalize_value([1, 2], {}), "")


func test_detect_reports_no_region_headless() -> void:
	# No RunManager in the test tree, so detection must fail softly.
	var result = RunRegion.detect()
	assert_true(result.has("region"))
	assert_eq(str(result.get("region", "")), "")
	assert_true(result.get("report") is Array)


## Minimal GameDatabase stand-in exposing the dex helper. `has_dex` lets a test
## exercise the pack-only fallback without a second class.
class DexDb extends RefCounted:
	var has_dex := true
	var sets_db := [{"id": "oshima", "name": "Jinto"}]
	var species_packs_db := [
		{"id": "pack_a", "set_id": "oshima", "species_ids": ["gemwing"]},
	]

	func get_dex_species_for_set(set_id: String) -> Array:
		if not has_dex or set_id != "oshima":
			return []
		return [{"id": "onsetra"}, {"id": "gemwing"}]
