extends RefCounted
## Pure helpers for coordinating mod-added buttons on the game's shop HUD bar.
##
## Brain Rot and Creature Comforts both add a button to the shop's `HudButtons`
## HBoxContainer. These helpers implement the shared, deterministic rules so the
## two mods (and any future mods) can extend the bar without clobbering each
## other, regardless of load order:
##   - insert each button in name-sorted order instead of always at index 0, and
##   - recompute the bar's left edge from the total width of its children rather
##     than decrementing it.
##
## The functions are static and take plain arrays/floats so they can be unit
## tested without an in-game scene.


## Index where `target_name` sorts among `child_names` (already in visual order,
## left to right, excluding the button being inserted). Children whose name sorts
## strictly before `target_name` stay to its left.
static func sorted_insert_index(child_names: Array, target_name: String) -> int:
	var index := 0
	for i in range(child_names.size()):
		if str(child_names[i]) < target_name:
			index = i + 1
	return index


## Left offset for a right-anchored bar given the minimum width of each child
## (left to right; pass 0.0 for non-Control children) and the separation between
## neighbours. Keeps the right edge fixed and extends leftward. Idempotent.
static func widened_left_offset(child_min_widths: Array, separation: float, right_edge: float) -> float:
	var total := 0.0
	for i in range(child_min_widths.size()):
		total += float(child_min_widths[i])
		if i > 0:
			total += separation
	return right_edge - total
