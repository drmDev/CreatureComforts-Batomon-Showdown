extends RefCounted
## AdviceContext - Safe game data extraction into plain-value records
## Provides stable data snapshots for rule evaluation without retaining live game objects.
## Now consumes ShopSnapshot instead of reading game objects directly.

class_name AdviceContext


## Represents a shop item with stable identification
class ShopItem:
	var slot: int
	var name_key: String
	var item_id: String
	var is_monster: bool
	var instance_id: int  # Live offer instance id, for overlays that must validate identity
	
	func _init(p_slot: int, p_name_key: String, p_item_id: String, p_is_monster: bool, p_instance_id: int = 0) -> void:
		slot = p_slot
		name_key = p_name_key
		item_id = p_item_id
		is_monster = p_is_monster
		instance_id = p_instance_id


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


## Create context from ShopSnapshot
func from_snapshot(snapshot) -> AdviceContext:
	var context = get_script().new()
	
	# Extract trainer ID and day from snapshot
	context.trainer_id = snapshot.trainer_id
	context.day = snapshot.day
	
	# Convert shop offers to ShopItem format
	for offer in snapshot.shop_offers:
		if offer.is_empty():
			continue
		
		var name_key := ""
		var item_id := ""
		var is_monster := false
		
		if offer.is_monster():
			name_key = offer.species_key
			is_monster = true
		elif offer.is_item():
			item_id = offer.item_id
		
		if not name_key.is_empty() or not item_id.is_empty():
			context.shop_items.append(ShopItem.new(offer.slot, name_key, item_id, is_monster, offer.instance_id))
	
	# Convert team monsters to Monster format
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


