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


func format_shop_changes(run, manager, old_run: Dictionary, old_shop: Dictionary, old_team: Dictionary, old_bench: Dictionary, debug_logging: bool) -> Array[String]:
	var lines := []
	var changes := []
	var timestamp := "[%s] " % get_time_short() if debug_logging else ""
	
	# Detect run state changes
	var run_changes := detect_run_changes(run, old_run)
	if not run_changes.is_empty():
		changes.append_array(run_changes)
	
	# Detect shop changes
	var shop_changes := detect_shop_changes(manager, old_shop)
	if not shop_changes.is_empty():
		changes.append_array(shop_changes)
	
	# Detect team changes
	var team_changes := detect_team_changes(run, old_team)
	if not team_changes.is_empty():
		changes.append_array(team_changes)
	
	# Detect bench changes
	var bench_changes := detect_bench_changes(run, old_bench)
	if not bench_changes.is_empty():
		changes.append_array(bench_changes)
	
	if changes.is_empty():
		return lines
	
	# Determine event type
	var event_type := infer_event_type(run_changes, shop_changes, team_changes, bench_changes)
	
	lines.append("\n%s%s" % [timestamp, event_type])
	for change in changes:
		lines.append("  %s" % change)
	
	# If shop changed, log current offers
	if not shop_changes.is_empty():
		lines.append("")
		lines.append_array(format_shop_offers(manager, run, true))
	
	return lines


func detect_run_changes(run, old_state: Dictionary) -> Array:
	var changes := []
	
	var props := ["current_round", "shop_rank", "lives", "player_hp", "gold", "current_wins"]
	var labels := {"current_round": "Day", "shop_rank": "Rank", "lives": "Lives", 
		"player_hp": "HP", "gold": "Gold", "current_wins": "Wins"}
	
	for prop in props:
		if not _has_prop.call(run, prop):
			continue
		var new_val = run.get(prop)
		var old_val = old_state.get(prop, null)
		if old_val != null and new_val != old_val:
			changes.append("%s: %s -> %s" % [labels.get(prop, prop), old_val, new_val])
	
	return changes


func detect_shop_changes(manager, old_state: Dictionary) -> Array:
	var changes := []
	
	if _has_prop.call(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		var new_fingerprint: Array = create_shop_fingerprint(items)
		var old_fingerprint: Array = old_state.get("fingerprint", [])
		
		# Compare fingerprints - check through larger array
		var max_size := max(new_fingerprint.size(), old_fingerprint.size())
		for i in range(max_size):
			var new_slot: Dictionary = new_fingerprint[i] if i < new_fingerprint.size() else {}
			var old_slot: Dictionary = old_fingerprint[i] if i < old_fingerprint.size() else {}
			
			# Compare slot data
			if new_slot != old_slot:
				var old_name := format_slot_name(old_slot)
				var new_name := format_slot_name(new_slot)
				if old_name != new_name:
					changes.append("Slot %d: %s -> %s" % [i, old_name, new_name])
	
	if _has_prop.call(manager, "is_shop_frozen"):
		var new_frozen: bool = manager.is_shop_frozen
		var old_frozen: bool = old_state.get("frozen", false)
		if new_frozen != old_frozen:
			changes.append("Shop %s" % ("Locked" if new_frozen else "Unlocked"))
	
	return changes


func detect_team_changes(run, old_state: Dictionary) -> Array:
	var changes := []
	
	if not _has_prop.call(run, "team"):
		return changes
	
	var team: Array = run.team
	var old_monsters: Array = old_state.get("monsters", [])
	
	# Team is stored bottom-right to top-left, reverse for visual order
	# Check through larger array to detect additions/removals
	var max_size := max(team.size(), old_monsters.size())
	for i in range(max_size):
		var visual_slot := team.size() - 1 - i if i < team.size() else old_monsters.size() - 1 - i
		var new_id = team[i].get_instance_id() if i < team.size() and team[i] != null else 0
		var old_id = old_monsters[i] if i < old_monsters.size() else 0
		
		if new_id != old_id:
			var old_name := get_monster_name(old_monsters[i]) if i < old_monsters.size() and old_monsters[i] != 0 else "Empty"
			var new_name := get_monster_name(team[i]) if i < team.size() and team[i] != null else "Empty"
			if old_name != new_name:
				changes.append("Team[%d]: %s -> %s" % [visual_slot, old_name, new_name])
	
	return changes


func detect_bench_changes(run, old_state: Dictionary) -> Array:
	var changes := []
	
	if not _has_prop.call(run, "bench"):
		return changes
	
	var bench: Array = run.bench
	var old_monsters: Array = old_state.get("monsters", [])
	
	# Bench is also stored bottom-right to top-left
	# Check through larger array to detect additions/removals
	var max_size := max(bench.size(), old_monsters.size())
	for i in range(max_size):
		var visual_slot := bench.size() - 1 - i if i < bench.size() else old_monsters.size() - 1 - i
		var new_id = bench[i].get_instance_id() if i < bench.size() and bench[i] != null else 0
		var old_id = old_monsters[i] if i < old_monsters.size() else 0
		
		if new_id != old_id:
			var old_name := get_monster_name(old_monsters[i]) if i < old_monsters.size() and old_monsters[i] != 0 else "Empty"
			var new_name := get_monster_name(bench[i]) if i < bench.size() and bench[i] != null else "Empty"
			if old_name != new_name:
				changes.append("Bench[%d]: %s -> %s" % [visual_slot, old_name, new_name])
	
	return changes


func infer_event_type(run_changes: Array, shop_changes: Array, team_changes: Array, bench_changes: Array) -> String:
	# Don't try to be too clever - just describe what changed
	var parts := []
	
	if not run_changes.is_empty():
		# Check for specific run changes
		var has_day_change := false
		var has_gold_change := false
		for change in run_changes:
			if "Day:" in change:
				has_day_change = true
			if "Gold:" in change:
				has_gold_change = true
		
		if has_day_change:
			parts.append("DAY CHANGED")
		elif has_gold_change and shop_changes.is_empty():
			# Gold changed but shop didn't - might be sell or other action
			pass
	
	if not shop_changes.is_empty():
		# Check if all slots changed (likely reroll) or specific slots
		var slot_changes := 0
		for change in shop_changes:
			if "Slot" in change:
				slot_changes += 1
		
		if slot_changes >= 4:
			parts.append("SHOP REROLL")
		elif slot_changes > 0:
			parts.append("SHOP CHANGED")
		else:
			parts.append("SHOP CHANGED")
	
	if not team_changes.is_empty():
		parts.append("TEAM CHANGED")
	
	if not bench_changes.is_empty():
		parts.append("BENCH CHANGED")
	
	return " + ".join(parts) if not parts.is_empty() else "STATE CHANGED"


func create_shop_fingerprint(items: Array) -> Array:
	"""Create a deterministic fingerprint of shop offers."""
	var fingerprint := []
	
	for i in range(items.size()):
		var item = items[i]
		var slot_data := {"slot": i}
		
		if item == null:
			slot_data["type"] = "empty"
		elif item.has_method("get_gold_cost") and _has_prop.call(item, "data"):
			# Creature
			slot_data["type"] = "creature"
			if _has_prop.call(item, "data") and item.data != null:
				if _has_prop.call(item.data, "id"):
					slot_data["id"] = str(item.data.id)
			if _has_prop.call(item, "level"):
				slot_data["level"] = item.level
			if _has_prop.call(item, "is_shiny"):
				slot_data["shiny"] = item.is_shiny
		elif _has_prop.call(item, "id"):
			# Item
			slot_data["type"] = "item"
			slot_data["id"] = str(item.id)
		else:
			slot_data["type"] = "unknown"
		
		fingerprint.append(slot_data)
	
	return fingerprint
