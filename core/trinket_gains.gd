extends RefCounted
## TrinketGains - pure battle-scoped trinket diff logic.
##
## Compares two captured trinket states (trinket_ids, trinkets_gained_total, used_trinket_ids)
## and reports gained ids, the counter delta, and one-shot trinkets consumed during the span.
## No game objects or scene-tree access, so it is unit-testable.

# One-shot trinkets that generate a gift when consumed. The gift is applied after the frozen
# battle_over snapshot, so it never appears in the ids diff; run.used_trinket_ids records the
# consumption and has_gift_trinket() is used for diagnostics only.
const GIFT_TRINKET_IDS := ["locked_box", "mysterious_chest"]


## Ids present in `after` but not matched in `before` (count-based, handles duplicates).
static func diff_id_lists(before: Array, after: Array) -> Array:
	var before_counts := {}
	for tid in before:
		before_counts[tid] = before_counts.get(tid, 0) + 1
	var added: Array = []
	for tid in after:
		var remaining = before_counts.get(tid, 0)
		if remaining > 0:
			before_counts[tid] = remaining - 1
		else:
			added.append(tid)
	return added


## Diff two captured states. Returns {"ids": [], "counter": int, "newly_used": []}.
static func diff_states(before: Dictionary, after: Dictionary) -> Dictionary:
	var counter_delta: int = int(after.get("trinkets_gained_total", 0)) - int(before.get("trinkets_gained_total", 0))
	return {
		"ids": diff_id_lists(before.get("trinket_ids", []), after.get("trinket_ids", [])),
		"counter": counter_delta,
		"newly_used": diff_id_lists(before.get("used_trinket_ids", []), after.get("used_trinket_ids", [])),
	}


## Did the span consume a gift-generating one-shot trinket?
static func has_gift_trinket(newly_used: Array, gift_ids: Array = GIFT_TRINKET_IDS) -> bool:
	for tid in newly_used:
		if str(tid) in gift_ids:
			return true
	return false


## Acquisitions counted by the counter that are not present in the frozen inventory diff.
## A consumed Locked Box / Mysterious Chest gift is applied after battle_over, so it shows up
## here as a positive gap and is never rendered by the panel. Clamped at 0.
static func withheld_count(gains: Dictionary) -> int:
	var ids: Array = gains.get("ids", [])
	return maxi(0, int(gains.get("counter", 0)) - ids.size())


## Ids the trinket-gain panel may render: everything except junk, order preserved.
static func displayable_ids(ids: Array, junk_id: String) -> Array:
	var shown: Array = []
	for tid in ids:
		if str(tid) != junk_id:
			shown.append(tid)
	return shown
