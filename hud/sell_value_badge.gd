extends "slot_badge.gd"
## Top-right gold-coin marker for a boosted sell value.
##
## Appears when the game's own sell value (MonsterInstance.get_sell_value()) is
## above the unit's base, i.e. an item or trinket raised it. The marker is the
## gold coin icon only; hover the unit to see the exact sell value.

const SellValue = preload("../core/sell_value.gd")

const BADGE_NAME := "CreatureComfortsSellValue"
const BADGE_GROUP := "cc_sell_value_badge"
const ICON_FILE := "gold.png"


func _badge_name() -> String:
	return BADGE_NAME


func _badge_group() -> String:
	return BADGE_GROUP


func _icon_file() -> String:
	return ICON_FILE


func _corner() -> String:
	return CORNER_TOP_RIGHT


func _should_show(monster) -> bool:
	return SellValue.is_boosted(monster)
