extends "slot_badge_controller.gd"
## Attaches sell-value badges to the fielded and bench slots of the shop's
## My Team grid. The badge reads the live monster itself, so team edits,
## level-ups, and shiny swaps update without a re-attach.

const ModConfig = preload("../core/mod_config.gd")
const SellValueBadge = preload("sell_value_badge.gd")


func _badge_script():
	return SellValueBadge


func _badge_group() -> String:
	return SellValueBadge.BADGE_GROUP


func _initial_enabled(context) -> bool:
	return context.feature_enabled(ModConfig.KEY_SELL_VALUE_INDICATORS) if context != null else true


func _diag_prefix() -> String:
	return "SELL DIAG"
