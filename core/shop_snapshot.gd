extends RefCounted

class ShopOffer:
	var slot: int = -1
	var instance_id: int = 0  # Lets UI overlays validate identity; 0 when empty
	var type: String = "empty"
	var species_key: String = ""
	var item_id: String = ""
	var level: int = 1
	var is_shiny: bool = false
	var types: Array = []

	func is_empty() -> bool:
		return type == "empty"

	func is_monster() -> bool:
		return type == "monster"

	func is_item() -> bool:
		return type == "item"


class Monster:
	var slot: int = -1
	var instance_id: int = 0
	var species_key: String = ""
	var level: int = 1
	var is_shiny: bool = false
	var types: Array = []


var trainer_id: String = ""
var day: int = 0
var shop_rank: int = 0
var lives: int = 0
var player_hp: int = 0
var gold: int = 0
var wins: int = 0

var shop_offers: Array = []
var shop_frozen: bool = false

## Team state (stored in game order, not visual order)
var team_monsters: Array = []

## Bench state (stored in game order, not visual order)
var bench_monsters: Array = []


func capture(run, manager, has_property_func: Callable, type_resolver: Callable):
	var snapshot = get_script().new()

	if has_property_func.call(run, "trainer_id"):
		snapshot.trainer_id = str(run.get("trainer_id"))

	if has_property_func.call(run, "current_round"):
		snapshot.day = int(run.get("current_round"))

	if has_property_func.call(run, "shop_rank"):
		snapshot.shop_rank = int(run.get("shop_rank"))

	if has_property_func.call(run, "lives"):
		snapshot.lives = int(run.get("lives"))

	if has_property_func.call(run, "player_hp"):
		snapshot.player_hp = int(run.get("player_hp"))

	if has_property_func.call(run, "gold"):
		snapshot.gold = int(run.get("gold"))

	if has_property_func.call(run, "current_wins"):
		snapshot.wins = int(run.get("current_wins"))

	if has_property_func.call(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		for i in range(items.size()):
			var item = items[i]
			var offer = ShopOffer.new()
			offer.slot = i
			if item != null:
				offer.instance_id = item.get_instance_id()

			match classify_shop_entry(item, has_property_func):
				"empty":
					offer.type = "empty"
				"monster":
					offer.type = "monster"
					_apply_species_data(offer, item.data, has_property_func, type_resolver)
					if has_property_func.call(item, "level"):
						offer.level = int(item.get("level"))
					if has_property_func.call(item, "is_shiny"):
						offer.is_shiny = bool(item.get("is_shiny"))
				"item":
					offer.type = "item"
					offer.item_id = str(item.id)
				_:
					offer.type = "unknown"

			snapshot.shop_offers.append(offer)

	if has_property_func.call(manager, "is_shop_frozen"):
		snapshot.shop_frozen = bool(manager.is_shop_frozen)

	if has_property_func.call(run, "team"):
		snapshot.team_monsters = _capture_monster_list(run.team, has_property_func, type_resolver)

	if has_property_func.call(run, "bench"):
		snapshot.bench_monsters = _capture_monster_list(run.bench, has_property_func, type_resolver)

	return snapshot


static func classify_shop_entry(item, has_property_fn: Callable) -> String:
	if item == null:
		return "empty"
	if is_monster_offer(item, has_property_fn):
		return "monster"
	if has_property_fn.call(item, "id"):
		return "item"
	return "unknown"


static func is_monster_offer(item, has_property_fn: Callable) -> bool:
	if item == null:
		return false
	return item.has_method("get_gold_cost") and has_property_fn.call(item, "data")


func _capture_monster_list(monster_list: Array, has_property_func: Callable, type_resolver: Callable) -> Array:
	var monsters: Array = []
	for i in range(monster_list.size()):
		var monster_obj = monster_list[i]
		if monster_obj == null:
			monsters.append(null)
		else:
			monsters.append(_extract_monster(monster_obj, i, has_property_func, type_resolver))
	return monsters


func _apply_species_data(target, data, has_property_func: Callable, type_resolver: Callable) -> void:
	if data == null:
		return
	if has_property_func.call(data, "name_key"):
		target.species_key = str(data.name_key)
	if has_property_func.call(data, "types"):
		var type_resources = data.types
		if type_resources is Array:
			for type_resource in type_resources:
				var type_name: String = type_resolver.call(type_resource)
				if not type_name.is_empty():
					target.types.append(type_name.to_lower())


func _extract_monster(monster_obj, slot: int, has_property_func: Callable, type_resolver: Callable) -> Monster:
	var monster = Monster.new()
	monster.slot = slot
	monster.instance_id = monster_obj.get_instance_id()

	if has_property_func.call(monster_obj, "data"):
		_apply_species_data(monster, monster_obj.data, has_property_func, type_resolver)

	if has_property_func.call(monster_obj, "level"):
		monster.level = int(monster_obj.get("level"))

	if has_property_func.call(monster_obj, "is_shiny"):
		monster.is_shiny = bool(monster_obj.get("is_shiny"))

	return monster
