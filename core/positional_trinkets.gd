extends RefCounted
## Positional trinket catalog and summary helpers.
##
## The game's trinket definitions are packed in the game's .pck, so the
## positional trinkets are catalogued here by their snake_case ids. Each entry
## keeps the official description for reference and a structured effect list so
## duplicate copies can be added together without parsing text.
##
## Positions:
##   "left"       - leftmost column
##   "top_middle" - top-middle monster
##   "right"      - rightmost column
##   ""           - not positional (kept for reference, ignored by summarize)

const TRINKETS := {
	"quick_flag": {
		"name": "Quick Flag",
		"description": "Your monsters in the leftmost column have +4% Cooldown Speed.",
		"position": "left",
		"passive": [{"stat": "cooldown_speed", "value": 4, "percent": true}],
		"permanent": [],
	},
	"rally_flag": {
		"name": "Rally Flag",
		"description": "On Battle Start Your monsters in the leftmost column gain +12 Damage permanently.",
		"position": "left",
		"passive": [],
		"permanent": [{"stat": "damage", "value": 12, "percent": false}],
	},
	"momentum_flag": {
		"name": "Momentum Flag",
		"description": "On Battle Start Your monsters in the leftmost column gain +8% Cooldown Speed permanently.",
		"position": "left",
		"passive": [],
		"permanent": [{"stat": "cooldown_speed", "value": 8, "percent": true}],
	},
	"earth_crest": {
		"name": "Earth Crest",
		"description": "On Battle Start Your monsters in the rightmost column gain +10% Shield permanently.",
		"position": "right",
		"passive": [],
		"permanent": [{"stat": "shield", "value": 10, "percent": true}],
	},
	"sea_crest": {
		"name": "Sea Crest",
		"description": "On Battle Start Your monsters in the rightmost column gain +10% Heal permanently.",
		"position": "right",
		"passive": [],
		"permanent": [{"stat": "heal", "value": 10, "percent": true}],
	},
	"speed_crest": {
		"name": "Speed Crest",
		"description": "Your monsters in the rightmost column have +15% Cooldown Speed.",
		"position": "right",
		"passive": [{"stat": "cooldown_speed", "value": 15, "percent": true}],
		"permanent": [],
	},
	"power_crown": {
		"name": "Power Crown",
		"description": "Your top middle monster has +20 Damage.",
		"position": "top_middle",
		"passive": [{"stat": "damage", "value": 20, "percent": false}],
		"permanent": [],
	},
	"haste_crown": {
		"name": "Haste Crown",
		"description": "Your top middle monster has +20% Cooldown Speed.",
		"position": "top_middle",
		"passive": [{"stat": "cooldown_speed", "value": 20, "percent": true}],
		"permanent": [],
	},
	"winged_crown": {
		"name": "Winged Crown",
		"description": "Your top middle monster has +1 Multicast.",
		"position": "top_middle",
		"passive": [{"stat": "multicast", "value": 1, "percent": false}],
		"permanent": [],
	},
	"alpha_crown": {
		"name": "Alpha Crown",
		"description": "On Battle Start Your monsters' Damage is set to your top-middle monster's Damage for this battle.",
		"position": "top_middle",
		"passive": [],
		"permanent": [{"text": "Damage set to top-middle's Damage"}],
	},
	"master_crown": {
		"name": "Master Crown",
		"description": "Your top middle monster has +80% stats (except Cooldown and Multicast).",
		"position": "top_middle",
		"passive": [{"stat": "stats", "value": 80, "percent": true, "note": "except Cooldown/Multicast"}],
		"permanent": [],
	},
	"link_cable": {
		"name": "Link Cable",
		"description": "All of your team's monsters are now considered adjacent to each other.",
		"position": "",
		"passive": [],
		"permanent": [],
	},
}

const POSITIONS := ["left", "top_middle", "right"]
const TIMINGS := ["passive", "permanent"]

## The summary is only shown once the player holds at least this many trinkets.
const MIN_TRINKETS := 20

## Display order inside a subdivision. Text-only effects sort after numeric ones.
const STAT_ORDER := [
	"damage", "heal", "shield", "burn", "poison", "shock",
	"cooldown_speed", "multicast", "stats",
]

const STAT_LABELS := {
	"damage": "Damage",
	"heal": "Heal",
	"shield": "Shield",
	"burn": "Burn",
	"poison": "Poison",
	"shock": "Shock",
	"cooldown_speed": "Cooldown Speed",
	"multicast": "Multicast",
	"stats": "Stats",
}


## True when the held trinket list is large enough to show the summary.
static func meets_threshold(held_ids) -> bool:
	return held_ids != null and held_ids.size() >= MIN_TRINKETS


## Build the positional summary for the held trinket ids.
##
## Returns a dictionary with `has_any` plus one entry per position. Each
## position has `passive` and `permanent` arrays of summed effects. Duplicate
## copies multiply their values; unknown and non-positional ids are ignored.
static func summarize(held_ids) -> Dictionary:
	var counts := {}
	for tid in held_ids:
		var key := str(tid)
		if TRINKETS.has(key):
			counts[key] = counts.get(key, 0) + 1

	var summary := {"has_any": false}
	for position in POSITIONS:
		summary[position] = {"passive": [], "permanent": []}

	for tid in TRINKETS.keys():
		var count: int = int(counts.get(tid, 0))
		if count <= 0:
			continue
		var entry: Dictionary = TRINKETS[tid]
		var position := str(entry.get("position", ""))
		if not POSITIONS.has(position):
			continue
		summary["has_any"] = true
		for timing in TIMINGS:
			var effects: Array = entry.get(timing, [])
			for effect in effects:
				_add_effect(summary[position][timing], effect, count)

	for position in POSITIONS:
		for timing in TIMINGS:
			summary[position][timing] = _sort_effects(summary[position][timing])
	return summary


## Format one summed effect for the panel.
static func format_effect(effect: Dictionary) -> String:
	if effect.has("text"):
		var text := str(effect["text"])
		var count := int(effect.get("count", 1))
		return text if count <= 1 else "%s x%d" % [text, count]

	var stat := str(effect.get("stat", ""))
	var value := int(effect.get("value", 0))
	var percent := bool(effect.get("percent", false))
	var label := str(STAT_LABELS.get(stat, stat.capitalize()))
	var text := "+%d%s %s" % [value, "%" if percent else "", label]
	var note := str(effect.get("note", ""))
	if not note.is_empty():
		text += " (%s)" % note
	return text


static func _add_effect(target: Array, effect: Dictionary, count: int) -> void:
	if effect.has("text"):
		var text := str(effect["text"])
		for existing in target:
			if str(existing.get("text", "")) == text:
				existing["count"] = int(existing.get("count", 1)) + count
				return
		target.append({"text": text, "count": count})
		return

	var stat := str(effect.get("stat", ""))
	var percent := bool(effect.get("percent", false))
	var note := str(effect.get("note", ""))
	for existing in target:
		if str(existing.get("stat", "")) == stat \
				and bool(existing.get("percent", false)) == percent \
				and str(existing.get("note", "")) == note:
			existing["value"] = int(existing.get("value", 0)) + int(effect.get("value", 0)) * count
			existing["count"] = int(existing.get("count", 0)) + count
			return
	target.append({
		"stat": stat,
		"value": int(effect.get("value", 0)) * count,
		"percent": percent,
		"note": note,
		"count": count,
	})


static func _sort_effects(effects: Array) -> Array:
	effects.sort_custom(func(a, b):
		var ia := STAT_ORDER.find(str(a.get("stat", "")))
		var ib := STAT_ORDER.find(str(b.get("stat", "")))
		if ia == -1:
			ia = STAT_ORDER.size()
		if ib == -1:
			ib = STAT_ORDER.size()
		if ia != ib:
			return ia < ib
		return str(a.get("text", "")) < str(b.get("text", ""))
	)
	return effects
