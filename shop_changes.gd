extends RefCounted
## ShopChanges - Compare shop snapshots and return structured changes
## Moves change detection and event classification out of log_formatter.gd

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
			var change: Change = Change.new("shop", "slot_%d" % i, old_offer, new_offer, "Slot %d" % i)
			result.changes.append(change)
	
	# Compare freeze state
	if previous.shop_frozen != current.shop_frozen:
		var label := "Shop Locked" if current.shop_frozen else "Shop Unlocked"
		var change = Change.new("shop", "frozen", previous.shop_frozen, current.shop_frozen, label)
		result.changes.append(change)


## Detect team changes (including in-place level/species changes)
func _detect_team_changes(previous, current, result: ComparisonResult) -> void:
	_detect_list_changes("team", "Team", previous.team_monsters, current.team_monsters, _monsters_equal, result)


## Detect bench changes
func _detect_bench_changes(previous, current, result: ComparisonResult) -> void:
	_detect_list_changes("bench", "Bench", previous.bench_monsters, current.bench_monsters, _monsters_equal, result)


## Detect changes across an indexed list (team/bench), labeling slots in visual (reversed) order
func _detect_list_changes(area: String, label_prefix: String, prev_list: Array, cur_list: Array, equal_fn: Callable, result: ComparisonResult) -> void:
	var max_size: int = max(prev_list.size(), cur_list.size())
	for i in range(max_size):
		var old_entry: Variant = prev_list[i] if i < prev_list.size() else null
		var new_entry: Variant = cur_list[i] if i < cur_list.size() else null
		
		# Calculate visual slot (reversed from storage order)
		var visual_slot: int = prev_list.size() - 1 - i if old_entry != null else cur_list.size() - 1 - i
		
		if not equal_fn.call(old_entry, new_entry):
			var change: Change = Change.new(area, "slot_%d" % i, old_entry, new_entry, "%s[%d]" % [label_prefix, visual_slot])
			result.changes.append(change)


## Compare two shop offers for equality
func _offers_equal(a, b) -> bool:
	if a == null or b == null:
		return a == b
	
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
	if a == null or b == null:
		return a == b
	
	# Compare instance ID (identity), species (evolution), and level (level-up)
	return a.instance_id == b.instance_id and a.species_key == b.species_key and a.level == b.level


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
	for change in run_changes:
		if change.property == "current_round":
			has_day_change = true
	
	if has_day_change:
		parts.append("DAY CHANGED")
	
	# Check for shop changes
	if not shop_changes.is_empty():
		# Count slot changes (excluding freeze changes)
		var slot_changes := 0
		for change in shop_changes:
			if change.property.begins_with("slot_"):
				slot_changes += 1
		
		# Reroll heuristic: 4+ slot changes indicates a reroll; otherwise report a shop change
		if slot_changes >= 4:
			parts.append("SHOP REROLL")
		else:
			parts.append("SHOP CHANGED")
	
	# Check for team/bench changes
	if not team_changes.is_empty():
		parts.append("TEAM CHANGED")
	
	if not bench_changes.is_empty():
		parts.append("BENCH CHANGED")
	
	return " + ".join(parts) if not parts.is_empty() else "STATE CHANGED"
