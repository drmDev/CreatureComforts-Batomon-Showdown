extends RefCounted
## Base max HP per day, mirroring the game's _calculate_base_max_hp.
##
## The game scales the base HP with a cubic curve and then applies a +10% per
## day multiplier from day 10 onward. Keep this in sync with the game's formula
## if a patch changes it. Pure helper so the panel can be unit-tested.

const BASE_HP := 300
const LATE_HP_START_ROUND := 10
const LATE_HP_STEP := 0.1
const MAX_DAY := 17

const CUBIC_B := 15.0
const LIN := 100.0
# Derived once from the game's constants: (26400 - 1331 * 15 - 11 * 100) / 121.
const CUBIC_A := (26400.0 - 1331.0 * CUBIC_B - 11.0 * LIN) / 121.0


## Base maximum HP for a given day. Days <= 0 return the day-1 value.
static func for_day(day: int) -> int:
	if day <= 0:
		return BASE_HP
	var c := float(day - 1)
	var raw := BASE_HP + CUBIC_A * c * c + CUBIC_B * c * c * c + LIN * c
	if day >= LATE_HP_START_ROUND:
		var late_steps := float(day - LATE_HP_START_ROUND + 1)
		raw *= 1.0 + LATE_HP_STEP * late_steps
	return int(round(raw / 100.0)) * 100


## Flat HP bonus from the current run on top of the base curve. `total_hp` is the
## run's player_hp, which already includes the game's trinket/trainer HP.
static func bonus(total_hp: int, day: int) -> int:
	return maxi(total_hp - for_day(day), 0)


## Base HP for `day` plus a flat bonus. The panel projects the current run's
## bonus across every day, matching the income model.
static func with_bonus(day: int, bonus_hp: int) -> int:
	return for_day(day) + maxi(bonus_hp, 0)
