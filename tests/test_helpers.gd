extends RefCounted

const AdviceContext = preload("../advice/advice_context.gd")


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


static func context(trainer_id: String, day: int, team_monsters: Array = []):
	var ctx := AdviceContext.new()
	ctx.trainer_id = trainer_id
	ctx.day = day
	ctx.team_monsters = team_monsters
	return ctx


static func team_monster(slot: int, name_key: String, level: int, types: Array = []):
	return AdviceContext.Monster.new(slot, name_key, level, types)
