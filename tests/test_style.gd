extends "test_runner.gd"
## Unit tests for the shared palette (core/style.gd).

const Style = preload("../core/style.gd")

## Types the watchlist filter expects to colour (lowercased keys).
const EXPECTED_TYPES := [
	"bug", "curio", "dragon", "electric", "fighting", "fire", "flying",
	"ghost", "grass", "rock", "steel", "toxic", "water",
]


func test_every_type_has_a_color() -> void:
	for type_name in EXPECTED_TYPES:
		assert_true(Style.TYPE_COLORS.has(type_name), "missing color for '%s'" % type_name)


func test_type_colors_are_distinct() -> void:
	var seen := {}
	for type_name in EXPECTED_TYPES:
		var color = Style.TYPE_COLORS[type_name]
		assert_false(seen.has(color), "duplicate color for '%s'" % type_name)
		seen[color] = type_name


func test_type_color_lookup_is_case_insensitive() -> void:
	assert_eq(Style.type_color("Fire"), Style.TYPE_COLORS["fire"])
	assert_eq(Style.type_color("FIRE"), Style.TYPE_COLORS["fire"])
	assert_eq(Style.type_color("water"), Style.TYPE_COLORS["water"])


func test_unknown_type_falls_back_to_neutral() -> void:
	assert_eq(Style.type_color("nonsense"), Color.TRANSPARENT)
	assert_eq(Style.type_color(""), Color.TRANSPARENT)


func test_action_palette_differs_from_filter_palette() -> void:
	# Snapshot Team must not look like an ordinary filter control.
	assert_ne(Style.ACTION_BG, Style.BG_COLOR)
	assert_ne(Style.ACTION_BORDER, Style.BORDER_COLOR)
