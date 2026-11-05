extends RefCounted

# One-shot trinkets that generate a gift when consumed. The gift is applied after the frozen
# battle_over snapshot, so it never appears in the ids diff; run.used_trinket_ids records the
# consumption and has_gift_trinket() is used for diagnostics only.
const GIFT_TRINKET_IDS := ["locked_box", "mysterious_chest"]

# Some callers pass trinket ids with the game's "trinket_" prefix; the database ids do not.
const TRINKET_PREFIX := "trinket_"


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


static func diff_states(before: Dictionary, after: Dictionary) -> Dictionary:
	var counter_delta: int = int(after.get("trinkets_gained_total", 0)) - int(before.get("trinkets_gained_total", 0))
	return {
		"ids": diff_id_lists(before.get("trinket_ids", []), after.get("trinket_ids", [])),
		"counter": counter_delta,
		"newly_used": diff_id_lists(before.get("used_trinket_ids", []), after.get("used_trinket_ids", [])),
	}


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


static func displayable_ids(ids: Array, junk_id: String) -> Array:
	var shown: Array = []
	for tid in ids:
		if str(tid) != junk_id:
			shown.append(tid)
	return shown


## Resolve a trinket icon through `lookup`, a `Callable(trinket_id) -> Texture2D` (or null).
## Tries the exact id first, then the id with the "trinket_" prefix stripped, then prefixed,
## so both the game's database ids and prefixed ids resolve. Returns null when nothing matches.
static func icon_for(trinket_id: String, lookup: Callable) -> Texture2D:
	var id := str(trinket_id)
	if id.is_empty():
		return null
	var icon = _lookup_icon(lookup, id)
	if icon != null:
		return icon
	if id.begins_with(TRINKET_PREFIX):
		var bare := id.substr(TRINKET_PREFIX.length())
		if not bare.is_empty():
			return _lookup_icon(lookup, bare)
		return null
	return _lookup_icon(lookup, TRINKET_PREFIX + id)


static func _lookup_icon(lookup: Callable, id: String) -> Texture2D:
	var icon = lookup.call(id)
	return icon if icon is Texture2D else null


## Quantity text for a panel row: empty for a single copy, otherwise the count.
static func qty_text(count: int) -> String:
	return "" if count <= 1 else str(count)


## Attach the game's trinket icon to each entry (null when the provider cannot resolve it).
static func attach_icons(entries: Array, provider) -> void:
	if provider == null:
		return
	for entry in entries:
		entry["icon"] = provider.icon(str(entry.get("id", "")))
