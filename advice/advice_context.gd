extends RefCounted

class Monster:
	var slot: int
	var name_key: String
	var level: int
	var types: Array
	
	func _init(p_slot: int, p_name_key: String, p_level: int, p_types: Array) -> void:
		slot = p_slot
		name_key = p_name_key
		level = p_level
		types = p_types


var trainer_id: String = ""
var day: int = 0
var team_monsters: Array = []


func from_snapshot(snapshot):
	var context = get_script().new()

	context.trainer_id = snapshot.trainer_id
	context.day = snapshot.day

	for i in range(snapshot.team_monsters.size()):
		var monster_data = snapshot.team_monsters[i]
		if monster_data == null:
			continue
		
		context.team_monsters.append(Monster.new(
			monster_data.slot,
			monster_data.species_key,
			monster_data.level,
			monster_data.types
		))
	
	return context


