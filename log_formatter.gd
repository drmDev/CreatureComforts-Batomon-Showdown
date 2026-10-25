# log_formatter.gd
extends RefCounted
## Formatting helper for Brainrot Edition diagnostic logger
## Returns formatted text/arrays of lines instead of writing directly

const STAT_NAMES := {1: "Dmg", 2: "Heal", 3: "Shield", 4: "Burn", 5: "Poison", 6: "Shock", 7: "Multi"}

var _has_prop: Callable

func _init(has_property_fn: Callable) -> void:
	_has_prop = has_property_fn


# --- Pure formatting helpers ---

func format_monster_name(monster) -> String:
	"""Format a readable monster name from name_key."""
	if not _has_prop.call(monster, "data"):
		return "Unknown"
	
	var data = monster.data
	if data == null or not _has_prop.call(data, "name_key"):
		return "Unknown"
	
	var name_key: String = str(data.name_key)
	
	# Try TranslationServer if available
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(name_key)
		if translated != name_key:
			return translated
	
	# Fallback: capitalize the name_key
	# "lamplet" -> "Lamplet"
	# "monster.name.lamplet" -> "Lamplet"
	if "." in name_key:
		name_key = name_key.split(".")[-1]
	
	return name_key.capitalize()


func format_species_name(species_key: String) -> String:
	"""Format a species name from captured name_key string."""
	return format_species_name_static(species_key)


static func format_species_name_static(species_key: String) -> String:
	"""Static version for use without instance. Format a species name from captured name_key string."""
	if species_key.is_empty():
		return "Unknown"
	
	# Try TranslationServer if available
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(species_key)
		if translated != species_key:
			return translated
	
	# Fallback: capitalize the name_key
	# "monster.name.lamplet" -> "Lamplet"
	var name_key := species_key
	if "." in name_key:
		name_key = name_key.split(".")[-1]
	
	return name_key.capitalize()


func format_monster_compact(monster) -> String:
	var parts := []
	
	# Get name and level
	var name := format_monster_name(monster)
	if _has_prop.call(monster, "level"):
		name += " Lv%s" % monster.level
	if _has_prop.call(monster, "is_shiny") and monster.is_shiny:
		name += " Shiny"
	parts.append(name)
	
	# Get types (always show, not just in deep inspection)
	if _has_prop.call(monster, "data"):
		var data = monster.data
		if data != null and _has_prop.call(data, "types"):
			var types = data.types
			if types is Array and types.size() > 0:
				var type_names := []
				for type_resource in types:
					type_names.append(resolve_type_name(type_resource))
				parts.append("| %s" % "/".join(type_names))
	
	# Get stats
	if monster.has_method("get_stat"):
		var stats := []
		for stat_id in [1, 2, 3, 4, 5, 6, 7]:
			var value = monster.get_stat(stat_id)
			if value != 0 and (stat_id != 7 or value > 1):
				stats.append("%s %s" % [STAT_NAMES.get(stat_id, str(stat_id)), value])
		if not stats.is_empty():
			parts.append("| %s" % " ".join(stats))
	
	return " ".join(parts) if not parts.is_empty() else "Unknown"


func format_array_contents(arr: Array) -> String:
	if arr.is_empty():
		return "[]"
	
	var items := []
	for item in arr:
		if item is String or item is int or item is float or item is bool:
			items.append(str(item))
		elif item is Object:
			items.append(get_object_info(item))
		else:
			items.append(typeof(item))
	
	return "[%s]" % ", ".join(items)


func format_slot_name(slot: Dictionary) -> String:
	"""Format a shop slot fingerprint into a readable name."""
	if slot.is_empty() or slot.get("type") == "empty":
		return "Empty"
	
	var slot_type: String = slot.get("type", "unknown")
	if slot_type == "creature":
		var name: String = str(slot.get("id", "Unknown")).capitalize()
		if slot.has("level"):
			name += " Lv%s" % slot.get("level")
		if slot.get("shiny", false):
			name += " Shiny"
		return name
	elif slot_type == "item":
		return "%s (Item)" % str(slot.get("id", "Unknown"))
	
	return "Unknown"


func resolve_type_name(type_resource) -> String:
	"""Resolve a monster type Resource into a readable name."""
	if type_resource == null or not is_instance_valid(type_resource):
		return "Unknown"
	
	# Try to find a name or id property
	if _has_prop.call(type_resource, "id"):
		return str(type_resource.id).capitalize()
	if _has_prop.call(type_resource, "name"):
		return str(type_resource.name).capitalize()
	if _has_prop.call(type_resource, "type_name"):
		return str(type_resource.type_name).capitalize()
	
	# Fallback: extract from resource path
	# res://game/monsters/type_data/fire.tres -> Fire
	if type_resource.has_method("get_path"):
		var path: String = type_resource.get_path()
		if path.contains("/type_data/"):
			var filename := path.get_file().get_basename()
			return filename.capitalize()
	
	# Last resort: use resource_path
	var script: Script = type_resource.get_script()
	if script != null:
		var path := str(type_resource.resource_path)
		if path.contains("/type_data/"):
			var filename := path.get_file().get_basename()
			return filename.capitalize()
	
	return "Unknown"


func get_object_info(obj) -> String:
	if obj == null:
		return "null"
	if not is_instance_valid(obj):
		return "invalid"
	
	var obj_class: String = obj.get_class()
	var script: Script = obj.get_script()
	if script != null:
		return "%s @ %s" % [obj_class, str(script.resource_path)]
	return obj_class


func get_timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]


func get_time_short() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]


func inspect_shop_item_deep(item) -> String:
	var lines := []
	
	# Check if it's a creature
	if item.has_method("get_gold_cost") and _has_prop.call(item, "data"):
		var data = item.data
		if data != null:
			lines.append("Creature: %s" % get_object_info(data))
			
			# Inspect species data
			var props := ["name_key", "tier", "cost", "types", "added_keywords", "ability_script"]
			for prop in props:
				if _has_prop.call(data, prop):
					var value = data.get(prop)
					if value is Array:
						lines.append("  %s: %s" % [prop, format_array_contents(value)])
					elif value is Script or (value is Object and value.has_method("get_class")):
						lines.append("  %s: %s" % [prop, get_object_info(value)])
					else:
						lines.append("  %s: %s" % [prop, str(value)])
	
	return "\n    ".join(lines) if not lines.is_empty() else "Unknown item"


func get_monster_name(monster_id) -> String:
	# monster_id is either an instance ID (int) or an object
	if monster_id is int:
		return "Monster"
	
	var monster = monster_id
	if monster == null:
		return "Empty"
	
	if _has_prop.call(monster, "data"):
		var data = monster.data
		if data != null and _has_prop.call(data, "name_key"):
			var name := str(data.name_key)
			if _has_prop.call(monster, "level"):
				name += " Lv%s" % monster.level
			return name
	
	return "Unknown"


# --- Multi-line formatters (return Array[String]) ---

func format_phase_entry(phase: String, run, manager, debug_logging: bool) -> Array[String]:
	var lines := []
	var timestamp := "[%s] " % get_time_short() if debug_logging else ""
	lines.append("\n%s%s PHASE" % [timestamp, phase])
	
	# Log trainer
	var trainer: Variant = run.get("trainer_id") if _has_prop.call(run, "trainer_id") else "?"
	lines.append("  Trainer: %s" % trainer)
	
	# Log concise run state
	var day: Variant = run.get("current_round") if _has_prop.call(run, "current_round") else "?"
	var wins: Variant = run.get("current_wins") if _has_prop.call(run, "current_wins") else "?"
	var lives: Variant = run.get("lives") if _has_prop.call(run, "lives") else "?"
	var gold: Variant = run.get("gold") if _has_prop.call(run, "gold") else "?"
	var rank: Variant = run.get("shop_rank") if _has_prop.call(run, "shop_rank") else "?"
	var battle_hp: Variant = run.get("player_hp") if _has_prop.call(run, "player_hp") else "?"
	
	lines.append("  Day %s | Rank %s | Lives %s | Battle HP %s | Wins %s | Gold %s" % [day, rank, lives, battle_hp, wins, gold])
	
	# Log shop offers if in shop phase
	if phase == "SHOP" and manager != null:
		lines.append("")
		lines.append_array(format_shop_offers(manager, run, false))
	
	# Log team and bench
	lines.append_array(format_team_compact(run))
	lines.append_array(format_bench_compact(run))
	
	return lines


func format_shop_offers(manager, run, include_context: bool) -> Array[String]:
	"""Format current shop offers with prices."""
	var lines := []
	
	if not _has_prop.call(manager, "current_shop_items"):
		return lines
	
	var items: Array = manager.current_shop_items
	
	if include_context:
		var gold: Variant = run.get("gold") if _has_prop.call(run, "gold") else "?"
		var day: Variant = run.get("current_round") if _has_prop.call(run, "current_round") else "?"
		lines.append("  Day %s | Gold %s" % [day, gold])
	
	lines.append("\n  SHOP:")
	
	for i in range(items.size()):
		var item = items[i]
		if item == null:
			lines.append("    [%d] Empty" % i)
		elif item.has_method("get_gold_cost") and _has_prop.call(item, "data"):
			# Creature
			var name := format_monster_name(item)
			var level := ""
			if _has_prop.call(item, "level"):
				level = " Lv%s" % item.level
			var price := ""
			if item.has_method("get_gold_cost"):
				price = " | %sg" % item.get_gold_cost()
			lines.append("    [%d] %s%s%s" % [i, name, level, price])
		elif _has_prop.call(item, "id"):
			# Item
			var item_name := str(item.id)
			var price := ""
			if _has_prop.call(item, "cost"):
				price = " | %sg" % item.cost
			lines.append("    [%d] %s (Item)%s" % [i, item_name, price])
		else:
			lines.append("    [%d] Unknown" % i)
	
	return lines


func format_team_compact(run) -> Array[String]:
	var lines := []
	
	if not _has_prop.call(run, "team"):
		return lines
	
	var team: Array = run.team
	lines.append("\n  TEAM:")
	
	# Reverse order for visual display (game stores bottom-right to top-left)
	for i in range(team.size()):
		var visual_slot := team.size() - 1 - i
		var monster = team[i]
		if monster != null:
			lines.append("    [%d] %s" % [visual_slot, format_monster_compact(monster)])
		else:
			lines.append("    [%d] Empty" % visual_slot)
	
	return lines


func format_bench_compact(run) -> Array[String]:
	var lines := []
	
	if not _has_prop.call(run, "bench"):
		return lines
	
	var bench: Array = run.bench
	lines.append("\n  BENCH:")
	
	# Reverse order for visual display
	for i in range(bench.size()):
		var visual_slot := bench.size() - 1 - i
		var monster = bench[i]
		if monster != null:
			lines.append("    [%d] %s" % [visual_slot, format_monster_compact(monster)])
		else:
			lines.append("    [%d] Empty" % visual_slot)
	
	return lines


func format_deep_inspect_shop(manager, run) -> Array[String]:
	var lines := []
	lines.append("\n--- DEEP INSPECTION: SHOP ---")
	
	# Inspect shop items in detail
	if _has_prop.call(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		lines.append("\nShop Items:")
		for i in range(items.size()):
			var item = items[i]
			if item != null:
				lines.append("  [%d] %s" % [i, inspect_shop_item_deep(item)])
	
	return lines


func format_deep_inspect_battle(state, player, opponent) -> Array[String]:
	var lines := []
	lines.append("\n--- DEEP INSPECTION: BATTLE ---")
	lines.append("Player: %s" % get_object_info(player))
	lines.append("Opponent: %s" % get_object_info(opponent))
	
	if _has_prop.call(state, "is_battle_active"):
		lines.append("Battle Active: %s" % state.is_battle_active)
	
	return lines


func format_snapshot_changes(comparison, run, manager, debug_logging: bool) -> Array[String]:
	"""Format changes from ShopChanges comparison result."""
	var lines := []
	var timestamp := "[%s] " % get_time_short() if debug_logging else ""
	
	if not comparison.has_changes():
		return lines
	
	# Log event type and changes
	lines.append("\n%s%s" % [timestamp, comparison.event_type])
	
	# Format each change
	for change in comparison.changes:
		var change_text := ""
		if change.area == "run":
			# Run changes: "Gold: 10 -> 5"
			change_text = "%s: %s -> %s" % [change.label, change.before, change.after]
		elif change.area == "shop":
			if change.property == "frozen":
				# Freeze change: "Shop Locked" or "Shop Unlocked"
				change_text = change.label
			else:
				# Slot change: "Slot 0: Lamplet -> Empty"
				var old_desc := _describe_snapshot_offer(change.before)
				var new_desc := _describe_snapshot_offer(change.after)
				change_text = "%s: %s -> %s" % [change.label, old_desc, new_desc]
		elif change.area == "team" or change.area == "bench":
			# Team/bench change: "Team[2]: Lamplet Lv2 -> Swoonet"
			var old_desc := _describe_snapshot_monster(change.before)
			var new_desc := _describe_snapshot_monster(change.after)
			change_text = "%s: %s -> %s" % [change.label, old_desc, new_desc]
		
		if not change_text.is_empty():
			lines.append("  %s" % change_text)
	
	# If shop changed, log current offers
	var shop_changes: Array = comparison.get_shop_changes()
	if not shop_changes.is_empty():
		lines.append("")
		lines.append_array(format_shop_offers(manager, run, true))
	
	return lines


func _describe_snapshot_offer(offer) -> String:
	"""Describe a shop offer from snapshot for display."""
	if offer == null or offer.is_empty():
		return "Empty"
	
	if offer.is_monster():
		var name := format_species_name(offer.species_key)
		if offer.level > 1:
			name += " Lv%d" % offer.level
		if offer.is_shiny:
			name += " Shiny"
		return name
	elif offer.is_item():
		return "%s (Item)" % offer.item_id
	
	return "Unknown"


func _describe_snapshot_monster(monster) -> String:
	"""Describe a monster from snapshot for display."""
	if monster == null:
		return "Empty"
	
	var name := format_species_name(monster.species_key)
	if monster.level > 1:
		name += " Lv%d" % monster.level
	
	return name


