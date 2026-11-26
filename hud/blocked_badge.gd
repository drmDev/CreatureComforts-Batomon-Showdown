extends "slot_badge.gd"
## Top-left red-X marker for a Common that blocks the Green Stone.
##
## Appears when the slot's unit is a tier-1 Common carrying permanent buffs.
## The marker is the red-X icon only. Non-blocking and layout-neutral.

const RatacombStoner = preload("ratacomb_stoner_controller.gd")

const BADGE_NAME := "CreatureComfortsBlocked"
const BADGE_GROUP := "cc_blocked_badge"
const ICON_FILE := "redX.png"


func _badge_name() -> String:
	return BADGE_NAME


func _badge_group() -> String:
	return BADGE_GROUP


func _icon_file() -> String:
	return ICON_FILE


func _corner() -> String:
	return CORNER_TOP_LEFT


func _should_show(monster) -> bool:
	return RatacombStoner.is_buffed_common(monster)
