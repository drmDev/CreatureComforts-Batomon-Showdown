extends "slot_badge_controller.gd"
## Attaches red-X "blocked" badges to the fielded and bench slots of the shop's
## My Team grid while the Ratacomb blocked stage is active. Shop-phase only: the
## shop controller calls update_team(view, active) on each poll and hide_all()
## when the phase leaves or the gate closes.

const BlockedBadge = preload("blocked_badge.gd")


func _badge_script():
	return BlockedBadge


func _badge_group() -> String:
	return BlockedBadge.BADGE_GROUP


func _diag_prefix() -> String:
	return "BLOCKED DIAG"
