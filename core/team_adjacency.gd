extends RefCounted
## Orthogonal adjacency helpers for the shop's 3x2 My Team grid.
##
## Slots are the 1-based visual positions the player sees:
##   [1] [2] [3]
##   [4] [5] [6]
##
## Two slots are adjacent when they share a horizontal or vertical edge.
## Diagonal neighbours are NOT adjacent. Every helper is pure so the reminder
## rule and the unit tests share the exact same comparison.

const COLUMNS := 3
const ROWS := 2
const SLOT_COUNT := COLUMNS * ROWS

## Species keys used by the Petrirex/Shikitsune placement warning. Shared so the
## advice rule and the battle slot log always match the same monsters.
## Verified against a real battle log: the game key is "shikitsune" (one k).
const PETRIREX_KEY := "monster.name.petrirex"
const SHIKITSUNE_KEY := "monster.name.shikitsune"


## Convert a storage index (game order, bottom-right to top-left) into the
## 1-based visual slot of the 3x2 grid the player sees.
static func visual_slot_for(team_size: int, storage_slot: int) -> int:
	return (team_size - 1 - storage_slot) + 1


## True for the six fielded slot numbers (1..6). Benched entries never reach
## these helpers, so any other index is treated as invalid.
static func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


## Row/column of a 1-based visual slot. Invalid slots map to (-1, -1) so callers
## can reject them instead of comparing bogus coordinates.
static func slot_to_row_col(slot: int) -> Vector2i:
	if not is_valid_slot(slot):
		return Vector2i(-1, -1)
	var index := slot - 1
	@warning_ignore("integer_division")
	var row := index / COLUMNS
	var col := index % COLUMNS
	return Vector2i(row, col)


## True when both slots are valid, differ, and share a horizontal or vertical
## edge (Manhattan distance of exactly 1).
static func are_slots_adjacent(slot_a: int, slot_b: int) -> bool:
	if not is_valid_slot(slot_a) or not is_valid_slot(slot_b):
		return false
	if slot_a == slot_b:
		return false
	var a := slot_to_row_col(slot_a)
	var b := slot_to_row_col(slot_b)
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


## Every adjacent (petrirex_slot, shikitsune_slot) pair as Vector2i(x=petrirex,
## y=shikitsune). Invalid slot values are skipped, and a single pair is emitted
## once even when either list contains duplicates.
static func find_unsafe_pairs(petrirex_slots, shikitsune_slots) -> Array:
	var pairs: Array = []
	for petrirex_slot in petrirex_slots:
		var p := int(petrirex_slot)
		if not is_valid_slot(p):
			continue
		for shikitsune_slot in shikitsune_slots:
			var s := int(shikitsune_slot)
			if not is_valid_slot(s):
				continue
			if not are_slots_adjacent(p, s):
				continue
			var pair := Vector2i(p, s)
			if not pairs.has(pair):
				pairs.append(pair)
	return pairs


## True when at least one Petrirex/Shikitsune pair is orthogonally adjacent.
static func has_unsafe_pair(petrirex_slots, shikitsune_slots) -> bool:
	return not find_unsafe_pairs(petrirex_slots, shikitsune_slots).is_empty()
