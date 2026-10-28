# log_formatter.gd
extends RefCounted
## Formatting helper for Creature Comforts diagnostic logger
## Returns formatted text/arrays of lines instead of writing directly

const ShopSnapshot = preload("shop_snapshot.gd")

const STAT_NAMES := {1: "Dmg", 2: "Heal", 3: "Shield", 4: "Burn", 5: "Poison", 6: "Shock", 7: "Multi"}
const JUNK_TRINKET_ID := "junk"  # Junk trinkets are hidden from the trinket-gain panel

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

	return format_species_name(str(data.name_key))


func format_species_name(species_key: String) -> String:
	"""Format a species name from a name_key string (translated or capitalized)."""
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


func format_item_name(item_id: String) -> String:
	"""Format an item id into a readable name (e.g., "basic_bait" -> "Basic Bait")."""
	return item_id.replace("_", " ").capitalize()


func format_trinket_name(trinket_id: String) -> String:
	"""Format a trinket id into a readable name.
	Strips a "trinket_" prefix if present, then reuses format_item_name."""
	var name := trinket_id
	if name.begins_with("trinket_"):
		name = name.substr(8, name.length())
	return format_item_name(name)


func _monster_display_name(monster, include_shiny := true) -> String:
	"""Species name with optional level/shininess suffixes."""
	var name := format_monster_name(monster)
	if _has_prop.call(monster, "level"):
		name += " Lv%s" % monster.level
	if include_shiny and _has_prop.call(monster, "is_shiny") and monster.is_shiny:
		name += " Shiny"
	return name


func format_monster_compact(monster) -> String:
	var parts := []
	parts.append(_monster_display_name(monster))

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


func resolve_type_name(type_resource) -> String:
	"""Resolve a monster type Resource into a readable name."""
	if not is_instance_valid(type_resource):
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
	if ShopSnapshot.classify_shop_entry(item, _has_prop) == "monster":
		var data = item.data
		if data != null:
			lines.append("Creature: %s" % get_object_info(data))

			# Inspect species data
			var props := ["name_key", "tier", "cost", "types", "added_keywords", "ability_script"]
			for prop in props:
				if _has_prop.call(data, prop):
					var value = data.get(prop)
					if value is Array:
						lines.append("  %s: %s" % [prop, _format_flat_value(value)])
					elif value is Object:
						lines.append("  %s: %s" % [prop, get_object_info(value)])
					else:
						lines.append("  %s: %s" % [prop, str(value)])

	return "\n    ".join(lines) if not lines.is_empty() else "Unknown item"


# --- Multi-line formatters (return Array[String]) ---

func _timestamp_prefix(debug_logging: bool) -> String:
	return "[%s] " % get_time_short() if debug_logging else ""


func format_phase_entry(phase: String, run, manager, debug_logging: bool) -> Array[String]:
	var lines: Array[String] = []
	var timestamp := _timestamp_prefix(debug_logging)
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
	var lines: Array[String] = []

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
		match ShopSnapshot.classify_shop_entry(item, _has_prop):
			"empty":
				lines.append("    [%d] Empty" % i)
			"monster":
				var price := " | %sg" % item.get_gold_cost()
				lines.append("    [%d] %s%s" % [i, _monster_display_name(item, false), price])
			"item":
				var item_name := format_item_name(str(item.id))
				var price := ""
				if _has_prop.call(item, "cost"):
					price = " | %sg" % item.cost
				lines.append("    [%d] %s (Item)%s" % [i, item_name, price])
			_:
				lines.append("    [%d] Unknown" % i)

	return lines


func format_team_compact(run) -> Array[String]:
	return _format_slots(run, "team", "TEAM")


func format_bench_compact(run) -> Array[String]:
	return _format_slots(run, "bench", "BENCH")


## Format an indexed monster list (team/bench), labeling slots in visual (reversed) order
func _format_slots(run, property_name: String, header: String) -> Array[String]:
	var lines: Array[String] = []

	if not _has_prop.call(run, property_name):
		return lines

	var slots: Array = run.get(property_name)
	lines.append("\n  %s:" % header)

	# Reverse order for visual display (game stores bottom-right to top-left)
	for i in range(slots.size()):
		var visual_slot := slots.size() - 1 - i
		var monster = slots[i]
		if monster != null:
			lines.append("    [%d] %s" % [visual_slot, format_monster_compact(monster)])
		else:
			lines.append("    [%d] Empty" % visual_slot)

	return lines


func format_deep_inspect_shop(manager, run) -> Array[String]:
	var lines: Array[String] = []
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
	var lines: Array[String] = []
	lines.append("\n--- DEEP INSPECTION: BATTLE ---")
	lines.append("Player: %s" % get_object_info(player))
	lines.append("Opponent: %s" % get_object_info(opponent))

	if _has_prop.call(state, "is_battle_active"):
		lines.append("Battle Active: %s" % state.is_battle_active)

	return lines


func format_battle_trinket_state(run) -> Array[String]:
	"""Log trinket-relevant state from RunManager.data once per battle entry."""
	var lines: Array[String] = []
	lines.append("\n--- BATTLE TRINKET STATE ---")

	if not is_instance_valid(run):
		lines.append("  RunManager.data unavailable")
		return lines

	# Trinket ids
	if _has_prop.call(run, "trinket_ids"):
		var trinkets = run.get("trinket_ids")
		lines.append("  trinket_ids (%s): %s" % [type_string(typeof(trinkets)), _format_flat_value(trinkets)])
	else:
		lines.append("  trinket_ids: property not found")

	# run._active_passives: passive objects carrying source_kind/source_id trinket attribution
	if _has_prop.call(run, "_active_passives"):
		var passives = run.get("_active_passives")
		lines.append("  run._active_passives: %s" % (
			"Array (size %d)" % passives.size() if passives is Array else type_string(typeof(passives))))
		if passives is Array and not passives.is_empty():
			for pi in range(passives.size()):
				var p = passives[pi]
				if not is_instance_valid(p):
					lines.append("    [%d] null/invalid" % pi)
					continue
				var p_script: Script = p.get_script()
				var p_path := str(p_script.resource_path) if p_script != null else "(no script)"
				lines.append("    [%d] %s" % [pi, p_path])
				lines.append_array(_format_script_vars(p, "      "))

	return lines


func format_battle_trinket_gains(gains: Dictionary) -> Array[String]:
	"""Report trinkets gained during the battle (battle-scoped, computed by mod_main)."""
	var lines: Array[String] = []
	lines.append("\n  --- BATTLE TRINKET GAINS ---")

	var gained_ids: Array = gains.get("ids", [])
	var counter_gained: int = int(gains.get("counter", 0))
	var count: int = gained_ids.size()

	if count > 0 or counter_gained > 0:
		lines.append("    +%d trinket(s): %s" % [count, _format_flat_value(gained_ids)])
		if count == 0:
			lines.append("      (gained trinkets are no longer in inventory)")
		elif count != counter_gained:
			lines.append("      (total counter +%d, %d gained trinket(s) no longer in inventory)" % [counter_gained, counter_gained - count])
		# Count how many are junk (hidden from the panel)
		var junk_count := 0
		for tid in gained_ids:
			if str(tid) == JUNK_TRINKET_ID:
				junk_count += 1
		if junk_count > 0:
			lines.append("      (junk excluded from panel: %d)" % junk_count)
	else:
		lines.append("    (none)")

	return lines


func _format_flat_value(value) -> String:
	"""Format a value as a flat, one-level string (no recursion)."""
	if value is Array:
		if value.is_empty():
			return "[]"
		var items := []
		for item in value:
			if item is String or item is int or item is float or item is bool:
				items.append(str(item))
			elif item is Object:
				items.append(get_object_info(item))
			else:
				items.append(type_string(typeof(item)))
		return "[%s]" % ", ".join(items)
	elif value is Dictionary:
		if value.is_empty():
			return "{}"
		var items := []
		for key in value.keys():
			items.append("%s: %s" % [str(key), str(value.get(key))])
		return "{%s}" % ", ".join(items)
	return str(value)


func _format_script_vars(obj, indent: String) -> Array[String]:
	"""Format script-declared properties of an object as indented lines.
	Returns an empty array if the object is null or invalid."""
	var lines: Array[String] = []
	if not is_instance_valid(obj):
		return lines

	var props: Array = obj.get_property_list()
	var var_count := 0
	for prop in props:
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var_count += 1
		var prop_name := str(prop.get("name", ""))
		var prop_type := int(prop.get("type", TYPE_NIL))
		var value = obj.get(prop_name)

		# Determine actual type for untyped (Variant) properties
		var actual_type := prop_type
		if actual_type == TYPE_NIL and value != null:
			actual_type = typeof(value)

		var type_name := type_string(actual_type)
		var detail := ""

		if actual_type in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_NIL]:
			var value_str := str(value)
			# Sanitize strings: replace newlines with literal \n
			if actual_type == TYPE_STRING or actual_type == TYPE_STRING_NAME:
				value_str = value_str.replace("\n", "\\n")
			detail = " = %s" % value_str
		elif actual_type == TYPE_ARRAY:
			if value.size() <= 8:
				detail = " = %s" % _format_flat_value(value)
			else:
				detail = " (Array size %d)" % value.size()
		elif actual_type == TYPE_DICTIONARY:
			detail = " (Dictionary size %d)" % value.size()
		elif actual_type == TYPE_OBJECT and is_instance_valid(value):
			detail = " = %s" % get_object_info(value)

		lines.append("%s%s: %s%s" % [indent, prop_name, type_name, detail])

	if var_count == 0:
		lines.append("%s(no script variables)" % indent)

	return lines


func format_snapshot_changes(comparison, run, manager, debug_logging: bool) -> Array[String]:
	"""Format changes from ShopChanges comparison result."""
	var lines: Array[String] = []
	var timestamp := _timestamp_prefix(debug_logging)

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
		return _describe_species(offer.species_key, offer.level, offer.is_shiny)
	elif offer.is_item():
		return "%s (Item)" % format_item_name(offer.item_id)

	return "Unknown"


func _describe_snapshot_monster(monster) -> String:
	"""Describe a monster from snapshot for display."""
	if monster == null:
		return "Empty"

	return _describe_species(monster.species_key, monster.level, monster.is_shiny)


## Describe a species with optional level/shininess suffixes
func _describe_species(species_key: String, level: int, is_shiny: bool) -> String:
	var name := format_species_name(species_key)
	if level > 1:
		name += " Lv%d" % level
	if is_shiny:
		name += " Shiny"
	return name
