extends RefCounted

class ShopItem:
	var slot: int
	var name_key: String
	var item_id: String
	var is_monster: bool
	var types: Array = []
	
	func _init(p_slot: int, p_name_key: String, p_item_id: String, p_is_monster: bool, p_types: Array = []) -> void:
		slot = p_slot
		name_key = p_name_key
		item_id = p_item_id
		is_monster = p_is_monster
		types = p_types


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
var shop_items: Array = []
var team_monsters: Array = []


func from_snapshot(snapshot):
	var context = get_script().new()
	
	context.trainer_id = snapshot.trainer_id
	context.day = snapshot.day
	
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
			context.shop_items.append(ShopItem.new(offer.slot, name_key, item_id, is_monster, offer.types))
	
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


