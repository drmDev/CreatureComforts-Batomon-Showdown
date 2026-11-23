extends RefCounted
## Economical trinket catalog and summary helpers.
##
## Mirrors core/positional_trinkets.gd: the game's trinket definitions are packed
## in the game's .pck, so the economical trinkets are catalogued here by their
## snake_case ids. Each entry keeps the official description for reference and a
## structured effect list so duplicate copies can be added together without
## parsing text.
##
## Timings:
##   "passive"   - always active while held
##   "victory"   - triggers when the player wins a battle
##   "next_loss" - triggers on the player's next loss
##
## The panel renders this summary as its own "Economical Trinkets" group next to
## the positional breakdown.

const TRINKETS := {
	"gold_bracelet": {
		"name": "Gold Bracelet",
		"description": "Random monster +8 sell value",
		"timing": "passive",
		"effects": [{"stat": "sell_value", "value": 8, "note": "random monster"}],
	},
	"gold_trophy": {
		"name": "Gold Trophy",
		"description": "Victory: gain $8",
		"timing": "victory",
		"effects": [{"stat": "gold", "value": 8}],
	},
	"fools_gold": {
		"name": "Fool's Gold",
		"description": "Income +$15. No more Items",
		"timing": "passive",
		"effects": [
			{"stat": "income", "value": 15},
			{"text": "No more Items"},
		],
	},
	"piggy_bank": {
		"name": "Piggy Bank",
		"description": "Gain $1 for each $10 you have",
		"timing": "passive",
		"effects": [{"stat": "gold_per_10", "value": 1}],
	},
	"fake_diamond": {
		"name": "Fake Diamond",
		"description": "Next loss: $40",
		"timing": "next_loss",
		"effects": [{"stat": "gold", "value": 40}],
	},
	"holy_grail": {
		"name": "Holy Grail",
		"description": "Victory: gain $100",
		"timing": "victory",
		"effects": [{"stat": "gold", "value": 100}],
	},
}

const TIMINGS := ["passive", "victory", "next_loss"]

## Display labels for each effect timing, used by the panel's right-aligned tag.
const TAG_LABELS := {
	"passive": "Passive",
	"victory": "Victory",
	"next_loss": "Next Loss",
}

## Display order inside a timing. Text-only effects sort after numeric ones.
const STAT_ORDER := ["sell_value", "income", "gold", "gold_per_10"]


## Build the economical summary for the held trinket ids.
##
## Returns a dictionary with `has_any` plus one array per timing. Duplicate
## copies multiply their values; unknown ids are ignored. `gold` is the player's
## current gold, used to resolve Piggy Bank's per-$10 payout.
static func summarize(held_ids, gold: int = 0) -> Dictionary:
	var counts := {}
	for tid in held_ids:
		var key := str(tid)
		if TRINKETS.has(key):
			counts[key] = counts.get(key, 0) + 1

	var summary := {"has_any": false}
	for timing in TIMINGS:
		summary[timing] = []

	for tid in TRINKETS.keys():
		var count: int = int(counts.get(tid, 0))
		if count <= 0:
			continue
		var entry: Dictionary = TRINKETS[tid]
		var timing := str(entry.get("timing", "passive"))
		if not TIMINGS.has(timing):
			continue
		summary["has_any"] = true
		for effect in entry.get("effects", []):
			_add_effect(summary[timing], effect, count, gold)

	for timing in TIMINGS:
		summary[timing] = _sort_effects(summary[timing])
	return summary


## Flatten the summary's effects into display order, preserving TIMINGS order
## and the STAT_ORDER sort inside each timing.
static func ordered_effects(summary: Dictionary) -> Array:
	var ordered: Array = []
	for timing in TIMINGS:
		for effect in summary.get(timing, []):
			ordered.append({"effect": effect, "timing": timing})
	return ordered


## Format one summed effect for the panel.
static func format_effect(effect: Dictionary) -> String:
	if effect.has("text"):
		var text := str(effect["text"])
		var count := int(effect.get("count", 1))
		return text if count <= 1 else "%s x%d" % [text, count]

	var stat := str(effect.get("stat", ""))
	var value := int(effect.get("value", 0))
	var note := str(effect.get("note", ""))
	match stat:
		"sell_value":
			var text := "+%d Sell Value" % value
			if not note.is_empty():
				text += " (%s)" % note
			return text
		"income":
			return "+$%d Income" % value
		"gold":
			return "Gain $%d" % value
		"gold_per_10":
			# `rate` is the per-$10 payout for all held copies; `value` is the
			# payout at the player's current gold.
			var rate := int(effect.get("rate", value))
			return "Gain $%d (%d per $10 held)" % [value, rate]
	return "+%d %s" % [value, stat.capitalize()]


static func _add_effect(target: Array, effect: Dictionary, count: int, gold: int) -> void:
	if effect.has("text"):
		var text := str(effect["text"])
		for existing in target:
			if str(existing.get("text", "")) == text:
				existing["count"] = int(existing.get("count", 1)) + count
				return
		target.append({"text": text, "count": count})
		return

	var stat := str(effect.get("stat", ""))
	var note := str(effect.get("note", ""))
	var rate := int(effect.get("value", 0)) * count
	var value := rate
	if stat == "gold_per_10":
		value = int(floor(float(gold) / 10.0)) * rate
	for existing in target:
		if str(existing.get("stat", "")) == stat and str(existing.get("note", "")) == note:
			existing["value"] = int(existing.get("value", 0)) + value
			existing["rate"] = int(existing.get("rate", 0)) + rate
			existing["count"] = int(existing.get("count", 0)) + count
			return
	var entry := {
		"stat": stat,
		"value": value,
		"note": note,
		"count": count,
	}
	if stat == "gold_per_10":
		entry["rate"] = rate
	target.append(entry)


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
