extends RefCounted
## TrinketGains - pure battle-scoped trinket diff logic.
##
## Compares two captured trinket states (trinket_ids, trinkets_gained_total, used_trinket_ids)
## and reports gained ids, the counter delta, and one-shot trinkets consumed during the span.
## No game objects or scene-tree access, so it is unit-testable.

# One-shot trinkets that generate a gift when consumed. The game applies the gift to
# trinket_ids during the battle simulation but reveals it later, so the trinket-gain panel
# must not show it. run.used_trinket_ids records the consumption.
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
