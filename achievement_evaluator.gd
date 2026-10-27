extends RefCounted
## AchievementEvaluator - determines whether an achievement was earned.
##
## PHASE 1 PLACEHOLDER: real metric detection (for example "Cinnabark applied more
## than 1,000,000 Shield") comes later. Until then the evaluator always emits the
## same demonstration achievement so the panel can be verified without a record battle.
##
## TEMPORARY: the demo trigger below must be removed or replaced once real metric
## detection is implemented. The shown achievement is a DEMO; the player did not
## actually earn anything, and the log says so.


# TEMPORARY: show the demo achievement after every completed battle.
# Set to false (or delete) once real metric evaluation replaces this file's logic.
const TEMP_SHOW_DEMO_ACHIEVEMENT := true

# TEMPORARY: demo achievement definition. Purely cosmetic; no persistence.
const DEMO_ACHIEVEMENT := {
	"id": "demo_good_boy",
	"title": "WHO'S A GOOD BOY?!",
	"description": "Cinnabark applied 10M+ Shield!",
	"temporary": true,
}


## Evaluate battle data and return the list of earned achievements.
## Each entry: {"id": String, "title": String, "description": String, "temporary": bool}.
## PHASE 1: returns the demo achievement when the temporary flag is enabled.
func evaluate(_battle_data) -> Array:
	if not TEMP_SHOW_DEMO_ACHIEVEMENT:
		return []
	return [DEMO_ACHIEVEMENT]