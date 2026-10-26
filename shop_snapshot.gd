extends RefCounted
## ShopSnapshot - Capture game state once per shop poll
## Provides consistent value records for change detection, advice, and log formatting.
## Uses plain values only; retains no live game objects.


## Represents a shop offer with identity, species, level, types, and price
class ShopOffer:
	var slot: int = -1
	var instance_id: int = 0  # Live offer object's instance id (0 when empty); lets UI overlays validate identity
	var type: String = "empty"  # "empty", "monster", "item", "unknown"
	var species_key: String = ""  # monster.name.lamplet
	var item_id: String = ""  # basic_bait, etc.
	var level: int = 1
	var is_shiny: bool = false
	var price: int = 0
	var types: Array = []  # Array of lowercase type names: ["fire", "flying"]
	
	func _init() -> void:
		pass
	
	func is_empty() -> bool:
		return type == "empty"
	
	func is_monster() -> bool:
		return type == "monster"
	
	func is_item() -> bool:
		return type == "item"


## Represents a team or bench monster with identity, species, level, and types
class Monster:
	var slot: int = -1
	var instance_id: int = 0  # For tracking identity across polls
	var species_key: String = ""  # monster.name.lamplet
	var level: int = 1
	var is_shiny: bool = false
	var types: Array = []  # Array of lowercase type names: ["fire", "flying"]
	
	func _init() -> void:
		pass


## Run state values
var trainer_id: String = ""
var day: int = 0
var shop_rank: int = 0
var lives: int = 0
var player_hp: int = 0
var gold: int = 0
var wins: int = 0

## Shop state
var shop_offers: Array = []  # Array of ShopOffer
var shop_frozen: bool = false

## Team state (stored in game order, not visual order)
var team_monsters: Array = []  # Array of Monster (may contain nulls for empty slots)

## Bench state (stored in game order, not visual order)
var bench_monsters: Array = []  # Array of Monster (may contain nulls for empty slots)


## Create snapshot from game objects
func capture(run, manager, has_property_func: Callable, type_resolver: Callable):
	var snapshot = get_script().new()
	
	# Capture run state
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
	
	# Capture shop state
	if has_property_func.call(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		for i in range(items.size()):
			var item = items[i]
			var offer = ShopOffer.new()
			offer.slot = i
			if item != null:
				offer.instance_id = item.get_instance_id()
			
			if item == null:
				offer.type = "empty"
			elif item.has_method("get_gold_cost") and has_property_func.call(item, "data"):
				# Monster
				offer.type = "monster"
				var data = item.data
				if data != null:
					if has_property_func.call(data, "name_key"):
						offer.species_key = str(data.name_key)
					
					# Extract types
					if has_property_func.call(data, "types"):
						var type_resources = data.types
						if type_resources is Array:
							for type_resource in type_resources:
								var type_name: String = type_resolver.call(type_resource)
								if not type_name.is_empty():
									offer.types.append(type_name.to_lower())
				
				if has_property_func.call(item, "level"):
					offer.level = int(item.get("level"))
				
				if has_property_func.call(item, "is_shiny"):
					offer.is_shiny = bool(item.get("is_shiny"))
				
				if item.has_method("get_gold_cost"):
					offer.price = int(item.get_gold_cost())
			
			elif has_property_func.call(item, "id"):
				# Item
				offer.type = "item"
				offer.item_id = str(item.id)
				
				if has_property_func.call(item, "cost"):
					offer.price = int(item.get("cost"))
			else:
				offer.type = "unknown"
			
			snapshot.shop_offers.append(offer)
	
	if has_property_func.call(manager, "is_shop_frozen"):
		snapshot.shop_frozen = bool(manager.is_shop_frozen)
	
	# Capture team state
	if has_property_func.call(run, "team"):
		var team: Array = run.team
		for i in range(team.size()):
			var monster_obj = team[i]
			if monster_obj == null:
				snapshot.team_monsters.append(null)
			else:
				var monster = _extract_monster(monster_obj, i, has_property_func, type_resolver)
				snapshot.team_monsters.append(monster)
	
	# Capture bench state
	if has_property_func.call(run, "bench"):
		var bench: Array = run.bench
		for i in range(bench.size()):
			var monster_obj = bench[i]
			if monster_obj == null:
				snapshot.bench_monsters.append(null)
			else:
				var monster = _extract_monster(monster_obj, i, has_property_func, type_resolver)
				snapshot.bench_monsters.append(monster)
	
	return snapshot


## Extract monster data into plain values
func _extract_monster(monster_obj, slot: int, has_property_func: Callable, type_resolver: Callable) -> Monster:
	var monster = Monster.new()
	monster.slot = slot
	monster.instance_id = monster_obj.get_instance_id()
	
	if has_property_func.call(monster_obj, "data"):
		var data = monster_obj.data
		if data != null:
			if has_property_func.call(data, "name_key"):
				monster.species_key = str(data.name_key)
			
			# Extract types
			if has_property_func.call(data, "types"):
				var type_resources = data.types
				if type_resources is Array:
					for type_resource in type_resources:
						var type_name: String = type_resolver.call(type_resource)
						if not type_name.is_empty():
							monster.types.append(type_name.to_lower())
	
	if has_property_func.call(monster_obj, "level"):
		monster.level = int(monster_obj.get("level"))
	
	if has_property_func.call(monster_obj, "is_shiny"):
		monster.is_shiny = bool(monster_obj.get("is_shiny"))
	
	return monster


