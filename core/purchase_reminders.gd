extends RefCounted
## Pure helpers for the shop monster purchase reminders.
##
## Maps held trinket ids to the short reminder lines shown when hovering a shop
## monster. power_band only applies to the first purchase of the day, so it is
## suppressed once a purchase has happened.

const PURCHASE_DESCRIPTIONS := {
	"upgrade_disc": "Next monster purchase: +1 level",
	"speed_whistle": "Next monster purchase: +12% CD",
	"power_band": "First monster purchase each day: +20 dmg",
}


## Build the reminder lines for the held trinket ids. `bought_today` suppresses
## the power_band line (it only applies to the first purchase of the day).
static func build_lines(held_ids, bought_today: bool) -> Array:
	var lines: Array = []
	if held_ids == null:
		return lines
	for tid in PURCHASE_DESCRIPTIONS.keys():
		if tid in held_ids:
			if tid == "power_band" and bought_today:
				continue
			lines.append(PURCHASE_DESCRIPTIONS[tid])
	return lines
