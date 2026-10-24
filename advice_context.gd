extends RefCounted
## AdviceContext - Safe game data extraction into plain-value records
## Provides stable data snapshots for rule evaluation without retaining live game objects.

class_name AdviceContext


## Represents a shop item with stable identification
class ShopItem:
	var slot: int
	var name_key: String
	var item_id: String
	var is_monster: bool
	
	func _init(p_slot: int, p_name_key: String, p_item_id: String, p_is_monster: bool) -> void:
		slot = p_slot
		name_key = p_name_key
		item_id = p_item_id
		is_monster = p_is_monster


## Represents a team/bench monster with stable identification
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


## Main context data
var trainer_id: String = ""
var day: int = 0
var shop_items: Array = []
var team_monsters: Array = []
# bench_monsters removed - no rules currently use bench data


## Create context from game objects
func from_game_state(run, manager, has_property_func: Callable, formatter):
	var context = get_script().new()
	
	# Extract trainer ID
	if has_property_func.call(run, "trainer_id"):
		context.trainer_id = str(run.get("trainer_id"))
	
	# Extract day (current_round)
	if has_property_func.call(run, "current_round"):
		context.day = int(run.get("current_round"))
	
	# Extract shop items
	if has_property_func.call(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		for i in range(items.size()):
			var item = items[i]
			if item == null:
				continue
			
			var name_key := ""
			var item_id := ""
			var is_monster := false
			
			# Check if it's a monster
			if item.has_method("get_gold_cost") and has_property_func.call(item, "data"):
				var data = item.data
				if data != null and has_property_func.call(data, "name_key"):
					name_key = str(data.name_key)
					is_monster = true
			
			# Check if it's an item
			if has_property_func.call(item, "id"):
				item_id = str(item.id)
			
			if not name_key.is_empty() or not item_id.is_empty():
				context.shop_items.append(ShopItem.new(i, name_key, item_id, is_monster))
	
	# Extract team monsters
	if has_property_func.call(run, "team"):
		var team: Array = run.team
		for i in range(team.size()):
			var monster = team[i]
			if monster == null:
				continue
			
			var monster_data = _extract_monster_data(monster, i, has_property_func, formatter)
			if monster_data != null:
				context.team_monsters.append(monster_data)
	
	# Bench extraction removed - no rules currently use bench data
	
	return context


## Extract monster data into plain values
func _extract_monster_data(monster, slot: int, has_property_func: Callable, formatter):
	if not has_property_func.call(monster, "data"):
		return null
	
	var data = monster.data
	if data == null:
		return null
	
	var name_key := ""
	if has_property_func.call(data, "name_key"):
		name_key = str(data.name_key)
	
	if name_key.is_empty():
		return null
	
	var level: int = 1
	if has_property_func.call(monster, "level"):
		level = int(monster.get("level"))
	
	var types: Array = []
	if has_property_func.call(data, "types"):
		var type_resources = data.types
		if type_resources is Array:
			for type_resource in type_resources:
				var type_name: String = formatter.resolve_type_name(type_resource)
				if not type_name.is_empty():
					types.append(type_name.to_lower())
	
	return Monster.new(slot, name_key, level, types)
