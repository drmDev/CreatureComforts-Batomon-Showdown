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
					offer.price = int(item.get_gold_cost())
				"item":
					offer.type = "item"
					offer.item_id = str(item.id)
					if has_property_func.call(item, "cost"):
						offer.price = int(item.get("cost"))
				_:
					offer.type = "unknown"

			snapshot.shop_offers.append(offer)

	if has_property_func.call(manager, "is_shop_frozen"):
		snapshot.shop_frozen = bool(manager.is_shop_frozen)

	# Capture team state
	if has_property_func.call(run, "team"):
		snapshot.team_monsters = _capture_monster_list(run.team, has_property_func, type_resolver)

	# Capture bench state
	if has_property_func.call(run, "bench"):
		snapshot.bench_monsters = _capture_monster_list(run.bench, has_property_func, type_resolver)

	return snapshot


## Classify a live shop entry: "monster", "item", "unknown", or "empty" (null)
static func classify_shop_entry(item, has_property_fn: Callable) -> String:
	if item == null:
		return "empty"
	if is_monster_offer(item, has_property_fn):
		return "monster"
	if has_property_fn.call(item, "id"):
		return "item"
	return "unknown"


## Is this live shop entry a monster offer?
static func is_monster_offer(item, has_property_fn: Callable) -> bool:
	if item == null:
		return false
	return item.has_method("get_gold_cost") and has_property_fn.call(item, "data")


## Capture a list of monsters (team/bench) into plain-value records
func _capture_monster_list(monster_list: Array, has_property_func: Callable, type_resolver: Callable) -> Array:
	var monsters: Array = []
	for i in range(monster_list.size()):
		var monster_obj = monster_list[i]
		if monster_obj == null:
			monsters.append(null)
		else:
			monsters.append(_extract_monster(monster_obj, i, has_property_func, type_resolver))
	return monsters


## Copy species identity (name_key + types) into a target record
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


## Extract monster data into plain values
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
