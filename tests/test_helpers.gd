extends RefCounted
## FakeObject exists because the rules guard with is_instance_valid(), which returns
## false for Dictionaries. Fakes must be Object instances (RefCounted).

const AdviceContext = preload("../advice/advice_context.gd")


class FakeObject:
	extends RefCounted
	var _props: Dictionary

	func _init(props: Dictionary = {}) -> void:
		_props = props

	func _get(property: StringName):
		return _props.get(property)

	func _has(property: StringName) -> bool:
		return _props.has(property)

	func set_prop(property: String, value) -> void:
		_props[property] = value


static func probe(obj, property: String) -> bool:
	if obj == null:
		return false
	return property in obj


class FakeFormatter:
	extends RefCounted

	func format_species_name(species_key: String) -> String:
		if species_key.is_empty():
			return "Unknown"
		var name := species_key
		if "." in name:
			name = name.split(".")[-1]
		return name.capitalize()

	func format_item_name(item_id: String) -> String:
		return item_id.replace("_", " ").capitalize()


static func context(trainer_id: String, day: int, shop_items: Array = [], team_monsters: Array = []):
	var ctx := AdviceContext.new()
	ctx.trainer_id = trainer_id
	ctx.day = day
	ctx.shop_items = shop_items
	ctx.team_monsters = team_monsters
	return ctx


static func shop_monster(slot: int, name_key: String, types: Array = [], instance_id: int = 0):
	return AdviceContext.ShopItem.new(slot, name_key, "", true, instance_id, types)


static func shop_item(slot: int, item_id: String, instance_id: int = 0):
	return AdviceContext.ShopItem.new(slot, "", item_id, false, instance_id, [])


static func team_monster(slot: int, name_key: String, level: int, types: Array = []):
	return AdviceContext.Monster.new(slot, name_key, level, types)
