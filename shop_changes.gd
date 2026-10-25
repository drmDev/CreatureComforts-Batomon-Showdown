extends RefCounted
## ShopChanges - Compare shop snapshots and return structured changes
## Moves change detection and event classification out of log_formatter.gd

# Load formatter for consistent name formatting
const LogFormatter = preload("log_formatter.gd")

## Represents a single change with area, slot/property, before, and after values
class Change:
	var area: String = ""  # "run", "shop", "team", "bench"
	var property: String = ""  # "gold", "slot_0", "team_slot_2", etc.
	var before: Variant = null
	var after: Variant = null
	var label: String = ""  # Human-readable label for logging
	
	func _init(p_area: String, p_property: String, p_before: Variant, p_after: Variant, p_label: String = "") -> void:
		area = p_area
		property = p_property
		before = p_before
		after = p_after
		label = p_label if not p_label.is_empty() else p_property


## Result of comparing two snapshots
class ComparisonResult:
	var changes: Array = []  # Array of Change
	var event_type: String = ""  # "SHOP REROLL", "TEAM CHANGED", etc.
	
	func _init() -> void:
		pass
	
	func has_changes() -> bool:
		return not changes.is_empty()
	
	func get_run_changes() -> Array:
		return changes.filter(func(c): return c.area == "run")
	
	func get_shop_changes() -> Array:
		return changes.filter(func(c): return c.area == "shop")
	
	func get_team_changes() -> Array:
		return changes.filter(func(c): return c.area == "team")
	
	func get_bench_changes() -> Array:
		return changes.filter(func(c): return c.area == "bench")


## Compare two snapshots and return structured changes
func compare(previous, current) -> ComparisonResult:
	var result = ComparisonResult.new()
	
	if previous == null or current == null:
		return result
	
	# Detect run state changes
	_detect_run_changes(previous, current, result)
	
	# Detect shop changes
	_detect_shop_changes(previous, current, result)
	
	# Detect team changes
	_detect_team_changes(previous, current, result)
	
	# Detect bench changes
	_detect_bench_changes(previous, current, result)
	
	# Classify event type based on changes
	result.event_type = _classify_event(result)
	
	return result


## Detect run state changes
func _detect_run_changes(previous, current, result: ComparisonResult) -> void:
	var props := {
		"current_round": {"label": "Day", "old": previous.day, "new": current.day},
		"shop_rank": {"label": "Rank", "old": previous.shop_rank, "new": current.shop_rank},
		"lives": {"label": "Lives", "old": previous.lives, "new": current.lives},
		"player_hp": {"label": "HP", "old": previous.player_hp, "new": current.player_hp},
		"gold": {"label": "Gold", "old": previous.gold, "new": current.gold},
		"current_wins": {"label": "Wins", "old": previous.wins, "new": current.wins}
	}
	
	for prop_name in props:
		var prop = props[prop_name]
		if prop.old != prop.new:
			var change = Change.new("run", prop_name, prop.old, prop.new, prop.label)
			result.changes.append(change)


## Detect shop changes (offers and freeze state)
func _detect_shop_changes(previous, current, result: ComparisonResult) -> void:
	# Compare shop offers
	var max_size: int = max(previous.shop_offers.size(), current.shop_offers.size())
	for i in range(max_size):
		var old_offer: Variant = previous.shop_offers[i] if i < previous.shop_offers.size() else null
		var new_offer: Variant = current.shop_offers[i] if i < current.shop_offers.size() else null
		
		if not _offers_equal(old_offer, new_offer):
			var old_desc: String = _describe_offer(old_offer)
			var new_desc: String = _describe_offer(new_offer)
			var change: Change = Change.new("shop", "slot_%d" % i, old_offer, new_offer, "Slot %d" % i)
			result.changes.append(change)
	
	# Compare freeze state
	if previous.shop_frozen != current.shop_frozen:
		var label := "Shop Locked" if current.shop_frozen else "Shop Unlocked"
		var change = Change.new("shop", "frozen", previous.shop_frozen, current.shop_frozen, label)
		result.changes.append(change)


## Detect team changes (including in-place level/species changes)
func _detect_team_changes(previous, current, result: ComparisonResult) -> void:
	var max_size: int = max(previous.team_monsters.size(), current.team_monsters.size())
	for i in range(max_size):
		var old_monster: Variant = previous.team_monsters[i] if i < previous.team_monsters.size() else null
		var new_monster: Variant = current.team_monsters[i] if i < current.team_monsters.size() else null
		
		# Calculate visual slot (reversed from storage order)
		var visual_slot: int = previous.team_monsters.size() - 1 - i if old_monster != null else current.team_monsters.size() - 1 - i
		
		if not _monsters_equal(old_monster, new_monster):
			var old_desc: String = _describe_monster(old_monster)
			var new_desc: String = _describe_monster(new_monster)
			var change: Change = Change.new("team", "slot_%d" % i, old_monster, new_monster, "Team[%d]" % visual_slot)
			result.changes.append(change)


## Detect bench changes
func _detect_bench_changes(previous, current, result: ComparisonResult) -> void:
	var max_size: int = max(previous.bench_monsters.size(), current.bench_monsters.size())
	for i in range(max_size):
		var old_monster: Variant = previous.bench_monsters[i] if i < previous.bench_monsters.size() else null
		var new_monster: Variant = current.bench_monsters[i] if i < current.bench_monsters.size() else null
		
		# Calculate visual slot (reversed from storage order)
		var visual_slot: int = previous.bench_monsters.size() - 1 - i if old_monster != null else current.bench_monsters.size() - 1 - i
		
		if not _monsters_equal(old_monster, new_monster):
			var old_desc: String = _describe_monster(old_monster)
			var new_desc: String = _describe_monster(new_monster)
			var change: Change = Change.new("bench", "slot_%d" % i, old_monster, new_monster, "Bench[%d]" % visual_slot)
			result.changes.append(change)


## Compare two shop offers for equality
func _offers_equal(a, b) -> bool:
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	
	# Compare type and identity
	if a.type != b.type:
		return false
	
	if a.is_monster():
		# For monsters, compare species, level, and shiny status
		return a.species_key == b.species_key and a.level == b.level and a.is_shiny == b.is_shiny
	elif a.is_item():
		# For items, compare item ID
		return a.item_id == b.item_id
	
	return true


## Compare two monsters for equality (including in-place changes)
func _monsters_equal(a, b) -> bool:
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	
	# Compare instance ID (identity), species (evolution), and level (level-up)
	return a.instance_id == b.instance_id and a.species_key == b.species_key and a.level == b.level


## Describe a shop offer for display
func _describe_offer(offer) -> String:
	if offer == null or offer.is_empty():
		return "Empty"
	
	if offer.is_monster():
		var name: String = LogFormatter.format_species_name_static(offer.species_key)
		if offer.level > 1:
			name += " Lv%d" % offer.level
		if offer.is_shiny:
			name += " Shiny"
		return name
	elif offer.is_item():
		return "%s (Item)" % offer.item_id
	
	return "Unknown"


## Describe a monster for display
func _describe_monster(monster) -> String:
	if monster == null:
		return "Empty"
	
	var name: String = LogFormatter.format_species_name_static(monster.species_key)
	if monster.level > 1:
		name += " Lv%d" % monster.level
	
	return name


## Classify event type based on changes
## Documents the existing reroll heuristic: 4+ slot changes = reroll
func _classify_event(result: ComparisonResult) -> String:
	if not result.has_changes():
		return ""
	
	var parts := []
	var run_changes := result.get_run_changes()
	var shop_changes := result.get_shop_changes()
	var team_changes := result.get_team_changes()
	var bench_changes := result.get_bench_changes()
	
	# Check for day change
	var has_day_change := false
	var has_gold_change := false
	for change in run_changes:
		if change.property == "current_round":
			has_day_change = true
		if change.property == "gold":
			has_gold_change = true
	
	if has_day_change:
		parts.append("DAY CHANGED")
	
	# Check for shop changes
	if not shop_changes.is_empty():
		# Count slot changes (excluding freeze changes)
		var slot_changes := 0
		for change in shop_changes:
			if change.property.begins_with("slot_"):
				slot_changes += 1
		
		# Reroll heuristic: 4+ slot changes indicates a reroll
		if slot_changes >= 4:
			parts.append("SHOP REROLL")
		elif slot_changes > 0:
			parts.append("SHOP CHANGED")
		else:
			# Only freeze change
			parts.append("SHOP CHANGED")
	
	# Check for team/bench changes
	if not team_changes.is_empty():
		parts.append("TEAM CHANGED")
	
	if not bench_changes.is_empty():
		parts.append("BENCH CHANGED")
	
	return " + ".join(parts) if not parts.is_empty() else "STATE CHANGED"
