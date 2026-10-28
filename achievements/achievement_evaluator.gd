extends RefCounted
## AchievementEvaluator - detects earned achievements from live run state.
##
## Poll-based: mod_main calls poll(run) on every poll. Returns an Array of newly
## earned achievement dictionaries (empty most polls). The caller owns persistence
## (achievement_store) and display (achievement_panel).
##
## First real achievement: "Oh Yeah!"
##   Trainer: Twins
##   Trigger: a level-2 Beetbud evolves into Beetdown at level 3. Twins doubles the
##   leveled unit, so the evolution produces two level-3 Beetdowns ("two kool aid mans").
##
## Detection is transition-based: we keep the previous team+bench species/level state
## and award when a level-2 Beetbud was present and the Beetdown count rose by at
## least 2 (the Twins double). This avoids awarding on a plain Beetdown purchase.

const TWINS_TRAINER_ID := "twins"
const BEETBUD_KEY := "monster.name.beetbud"
const BEETDOWN_KEY := "monster.name.beetdown"
const BEETBUD_EVOLVE_LEVEL := 2  # Beetbud at this level is the pre-evolution state

const OH_YEAH := {
	"id": "oh_yeah",
	"title": "Oh Yeah!",
	"description": "Made double kool aid man level 3s at once !",
}

var _prev_beetbud_lvl2 := 0
var _prev_beetdown_count := 0
var _has_prev := false


## Poll the run for newly earned achievements. Returns an Array of achievement dicts.
func poll(run) -> Array:
	if run == null or not is_instance_valid(run):
		_reset()
		return []

	var trainer_id := str(run.get("trainer_id")) if _has_property(run, "trainer_id") else ""
	if trainer_id != TWINS_TRAINER_ID:
		_reset()
		return []

	var counts := _count_species(run)
	var beetbud_lvl2: int = int(counts.get("beetbud_lvl2", 0))
	var beetdown_count: int = int(counts.get("beetdown", 0))

	var earned: Array = []
	if _has_prev:
		# Evolution signature: a level-2 Beetbud was present and the Beetdown count
		# rose by at least 2 (Twins doubles the leveled unit).
		if _prev_beetbud_lvl2 > 0 and beetdown_count >= _prev_beetdown_count + 2:
			earned.append(OH_YEAH.duplicate(true))

	_prev_beetbud_lvl2 = beetbud_lvl2
	_prev_beetdown_count = beetdown_count
	_has_prev = true
	return earned


func _reset() -> void:
	_prev_beetbud_lvl2 = 0
	_prev_beetdown_count = 0
	_has_prev = false


## Count level-2 Beetbuds and all Beetdowns across team + bench.
func _count_species(run) -> Dictionary:
	var beetbud_lvl2 := 0
	var beetdown := 0
	for list_name in ["team", "bench"]:
		if not _has_property(run, list_name):
			continue
		var list = run.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			if monster == null or not is_instance_valid(monster):
				continue
			var data = monster.get("data") if _has_property(monster, "data") else null
			if data == null:
				continue
			var key := str(data.get("name_key")) if _has_property(data, "name_key") else ""
			var level := int(monster.get("level")) if _has_property(monster, "level") else 1
			if key == BEETBUD_KEY and level == BEETBUD_EVOLVE_LEVEL:
				beetbud_lvl2 += 1
			elif key == BEETDOWN_KEY:
				beetdown += 1
	return {"beetbud_lvl2": beetbud_lvl2, "beetdown": beetdown}


func _has_property(obj, property: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	for prop in obj.get_property_list():
		if str(prop.name) == property:
			return true
	return false
