extends RefCounted
## TrainerRules - Reusable rule classes for trainer advice
## Rules return structured advice without side effects (no printing, file writing, or retaining live objects).

const AdviceContext = preload("advice_context.gd")


## Base class for all rules
class BaseRule:
	var rule_id: String
	
	func _init(p_rule_id: String) -> void:
		rule_id = p_rule_id
	
	## Evaluate rule against context, return advice or null
	func evaluate(context: AdviceContext) -> Dictionary:
		return {}


## Rule that checks for specific shop targets
class ShopTargetsRule extends BaseRule:
	var trainer_filter: String  # Empty string means any trainer
	var target_monsters: Array  # monster name_keys
	var target_items: Array  # item IDs
	var severity: String
	var message_template: String
	
	func _init(p_rule_id: String, p_trainer_filter: String, p_target_monsters: Array, p_target_items: Array, p_severity: String, p_message_template: String) -> void:
		super._init(p_rule_id)
		trainer_filter = p_trainer_filter
		target_monsters = p_target_monsters
		target_items = p_target_items
		severity = p_severity
		message_template = p_message_template
	
	func evaluate(context: AdviceContext) -> Dictionary:
		# Check trainer filter
		if not trainer_filter.is_empty() and context.trainer_id != trainer_filter:
			return {}
		
		var matches: Array = []
		
		# Check for target monsters
		for shop_item in context.shop_items:
			if shop_item.is_monster and shop_item.name_key in target_monsters:
				var monster_name := _format_monster_name(shop_item.name_key)
				matches.append("[%d] %s" % [shop_item.slot, monster_name])
			elif not shop_item.item_id.is_empty() and shop_item.item_id in target_items:
				var item_name := _format_item_name(shop_item.item_id)
				matches.append("[%d] %s" % [shop_item.slot, item_name])
		
		if matches.is_empty():
			return {}
		
		return {
			"rule_id": rule_id,
			"severity": severity,
			"message": message_template % ", ".join(matches),
			"matched_slots": matches
		}
	
	func _format_monster_name(name_key: String) -> String:
		# Extract readable name from name_key (e.g., "monster.name.lamplet" -> "Lamplet")
		var parts := name_key.split(".")
		if parts.size() > 0:
			return parts[-1].capitalize()
		return name_key
	
	func _format_item_name(item_id: String) -> String:
		# Format item ID (e.g., "basic_bait" -> "Basic Bait")
		return item_id.replace("_", " ").capitalize()


## Rule that checks for compound team conditions
class BeetdownCompanyRule extends BaseRule:
	var trainer_filter: String
	var severity: String
	
	func _init(p_rule_id: String, p_trainer_filter: String, p_severity: String) -> void:
		super._init(p_rule_id)
		trainer_filter = p_trainer_filter
		severity = p_severity
	
	func evaluate(context: AdviceContext) -> Dictionary:
		# Check trainer filter
		if not trainer_filter.is_empty() and context.trainer_id != trainer_filter:
			return {}
		
		# Find Level 3+ Beetdown in team
		var has_beetdown_lv3_plus := false
		var beetdown_slot := -1
		
		for monster in context.team_monsters:
			if monster.name_key == "monster.name.beetdown" and monster.level >= 3:
				has_beetdown_lv3_plus = true
				beetdown_slot = monster.slot
				break
		
		if not has_beetdown_lv3_plus:
			return {}
		
		# Find other Fighting-type monsters in team (excluding the Beetdown)
		var other_fighters: Array = []
		
		for monster in context.team_monsters:
			if monster.slot == beetdown_slot:
				continue
			
			if "fighting" in monster.types:
				var monster_name := _format_monster_name(monster.name_key)
				other_fighters.append("[%d] %s" % [monster.slot, monster_name])
		
		if other_fighters.is_empty():
			return {}
		
		return {
			"rule_id": rule_id,
			"severity": severity,
			"message": "Beetdown needs to be your only fighter. Other fighters: %s" % ", ".join(other_fighters),
			"matched_slots": other_fighters
		}
	
	func _format_monster_name(name_key: String) -> String:
		var parts := name_key.split(".")
		if parts.size() > 0:
			return parts[-1].capitalize()
		return name_key


## Rule that triggers on specific days
class DayReminderRule extends BaseRule:
	var trainer_filter: String  # Empty string means any trainer
	var target_day: int
	var severity: String
	var message: String
	
	func _init(p_rule_id: String, p_trainer_filter: String, p_target_day: int, p_severity: String, p_message: String) -> void:
		super._init(p_rule_id)
		trainer_filter = p_trainer_filter
		target_day = p_target_day
		severity = p_severity
		message = p_message
	
	func evaluate(context: AdviceContext) -> Dictionary:
		# Check trainer filter
		if not trainer_filter.is_empty() and context.trainer_id != trainer_filter:
			return {}
		
		# Check day
		if context.day != target_day:
			return {}
		
		return {
			"rule_id": rule_id,
			"severity": severity,
			"message": message,
			"matched_day": target_day
		}
