extends RefCounted
## Pure daily-income maths for the shop income panel.
##
## Extracted from mod_main.gd. Trinket/passive gold_gain bonuses are added on
## top of the base schedule; the caller reads the run data and passes the
## passive bonuses in.

const BASE_INCOME := 35
const INCOME_PER_DAY := 5


## Income for `day` (1-based) plus any passive gold_gain bonuses.
static func compute(day: int, passive_gold_gains: Array = []) -> int:
	var income := BASE_INCOME + INCOME_PER_DAY * maxi(day - 1, 0)
	for gain in passive_gold_gains:
		income += int(gain)
	return income
