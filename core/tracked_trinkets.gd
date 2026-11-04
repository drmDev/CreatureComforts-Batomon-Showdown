extends RefCounted
## Pure helpers for the held one-shot trinket reminders.
##
## Extracted from mod_main.gd. The panel shows a count and description for each
## tracked trinket the player is holding; one-shot trinkets are removed from
## run.trinket_ids when consumed, so a plain count is enough.

# IDs follow the game's snake_case convention (e.g. "treasure_map").
const TRACKED_DESCRIPTIONS := {
	"mini_duplicator": "Next non-unique trinket gift: +1 copy",
	"mega_duplicator": "Next non-unique trinket gift: +2 copies",
	"treasure_map": "Next trinket gift: +1 rarity tier",
	"upgrade_disc": "Next monster purchase: +1 level",
	"mega_upgrade_disc": "Monster reaches level 3: level it again",
	"greedy_gloves": "Next Trinket gift: take all choices",
	"speed_whistle": "Next monster purchase: +12% CD",
	"ancient_plume": "Only have 1 mon: gain +1 Multicast",
	"power_band": "First monster purchase each day: +20 dmg",
	"candy_jar": "On battle start: common and uncommons level to 3"
}


## Build panel entries for the tracked ids present in `held_ids`.
## `name_resolver` is called with each trinket id (e.g. formatter.format_trinket_name).
## Entries follow TRACKED_DESCRIPTIONS order and omit zero counts.
static func build_entries(held_ids, name_resolver: Callable) -> Array:
	var counts := {}
	for tid in held_ids:
		var key := str(tid)
		if TRACKED_DESCRIPTIONS.has(key):
			counts[key] = counts.get(key, 0) + 1

	var entries: Array = []
	for tid in TRACKED_DESCRIPTIONS.keys():
		var count: int = int(counts.get(tid, 0))
		if count <= 0:
			continue
		entries.append({
			"name": name_resolver.call(tid),
			"count": count,
			"desc": TRACKED_DESCRIPTIONS[tid],
		})
	return entries
