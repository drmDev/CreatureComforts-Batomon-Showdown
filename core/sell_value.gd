extends RefCounted
## Pure sell-value helpers for the fielded and bench indicators.
##
## The game owns the formula: MonsterInstance.get_sell_value() already includes
## level, shiny, and bonus_sell_value modifiers. This module only guards the
## reflection calls, so no game classes are preloaded and the helpers stay
## unit-testable.

## The stat the game uses for item/trinket sell-value bonuses.
const BONUS_STAT := "bonus_sell_value"

## True when `monster` is a live object that can report a sell value.
static func is_sellable(monster) -> bool:
	if not is_instance_valid(monster):
		return false
	return monster.has_method("get_sell_value")


## Gold gained by selling `monster`, or 0 when it cannot be sold.
static func value_of(monster) -> int:
	if not is_sellable(monster):
		return 0
	return int(monster.get_sell_value())


## True when the current sell value is above the unit's base because an item or
## trinket raised it. Prefers the game's base getter; otherwise a positive
## bonus_sell_value stat is the signal. A 0-value unit is never boosted.
static func is_boosted(monster) -> bool:
	if not is_sellable(monster):
		return false
	var current := value_of(monster)
	if current <= 0:
		return false
	if monster.has_method("get_base_sell_value"):
		var base = monster.call("get_base_sell_value")
		if base != null:
			return current > int(base)
	if monster.has_method("get_base_permanent_stat"):
		var bonus = monster.call("get_base_permanent_stat", BONUS_STAT)
		if bonus != null:
			return float(bonus) > 0.0
	return false


