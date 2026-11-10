extends RefCounted
## Pure sell-value helpers for the fielded and bench indicators.
##
## The game owns the formula: MonsterInstance.get_sell_value() already includes
## level, shiny, and bonus_sell_value modifiers. This module only guards the
## reflection call and formats the result, so no game classes are preloaded and
## the helpers stay unit-testable.

## True when `monster` is a live object that can report a sell value.
static func is_sellable(monster) -> bool:
	if monster == null:
		return false
	if not is_instance_valid(monster):
		return false
	return monster.has_method("get_sell_value")


## Gold gained by selling `monster`, or 0 when it cannot be sold.
static func value_of(monster) -> int:
	if not is_sellable(monster):
		return 0
	return int(monster.get_sell_value())


## Badge text for a sell value. Kept separate so the badge and tests share it.
static func text_for(value: int) -> String:
	return str(maxi(value, 0))
