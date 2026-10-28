extends RefCounted
## TrainerRules - Reusable rule classes for trainer advice.
## Rules return structured advice without side effects (no printing, file writing, or retaining live objects).
## Every advice dictionary uses a shared contract so consumers can route by field instead of rule-id strings:
##   rule_id, trainer_id, severity, message, display, reminder, chime, plus rule-specific extras.

const AdviceContext = preload("advice_context.gd")


## Base class for all rules
class BaseRule:
	# Display modes tell the UI layer how this rule should be shown.
	const DISPLAY_NONE := "none"
	const DISPLAY_LABEL := "label"
	const DISPLAY_HIGHLIGHT := "highlight"
	const DISPLAY_BOTH := "both"

	var rule_id: String
	var trainer_id: String  # Trainer this rule applies to; empty string means any trainer
	var display_mode: String
	var reminder_text: String  # Compact text for the top-bar label; empty = no label entry
	var chime: bool  # Whether a new match may play the notification sound (day reminders only)

	func _init(p_rule_id: String, p_trainer_id: String, p_display_mode: String, p_reminder_text: String, p_chime: bool) -> void:
		rule_id = p_rule_id
		trainer_id = p_trainer_id
		display_mode = p_display_mode
		reminder_text = p_reminder_text
		chime = p_chime

	## Evaluate rule against context, return advice or empty dict
	func evaluate(_context: AdviceContext) -> Dictionary:
		return {}

	## Assemble advice with the shared contract; extras are merged per rule
	func _make_advice(severity: String, message: String, extra: Dictionary = {}) -> Dictionary:
		var advice := {
			"rule_id": rule_id,
			"trainer_id": trainer_id,
			"severity": severity,
			"message": message,
			"display": display_mode,
			"reminder": reminder_text,
			"chime": chime,
		}
		for key in extra:
			advice[key] = extra[key]
		return advice

	## Does this rule apply to the given context's trainer? (empty trainer_id = any trainer)
	func _matches_trainer(context: AdviceContext) -> bool:
		return trainer_id.is_empty() or context.trainer_id == trainer_id


## Rule that flags specific shop targets (monsters by name and/or type, and/or items)
class ShopTargetsRule extends BaseRule:
	var target_monsters: Array  # monster name_keys
	var target_items: Array  # item IDs
	var target_types: Array  # lowercase type names; monster offers of these types are highlighted
	var severity: String
	var message_template: String
	var formatter  # Reference to log formatter for name formatting

	func _init(p_rule_id: String, p_trainer_id: String, p_target_monsters: Array, p_target_items: Array, p_severity: String, p_message_template: String, p_formatter, p_target_types: Array = []) -> void:
		super._init(p_rule_id, p_trainer_id, DISPLAY_HIGHLIGHT, "", false)
		target_monsters = p_target_monsters
		target_items = p_target_items
		target_types = p_target_types
		severity = p_severity
		message_template = p_message_template
		formatter = p_formatter

	func evaluate(context: AdviceContext) -> Dictionary:
		if not _matches_trainer(context):
			return {}

		var matches: Array = []
		var matched_indices: Array = []  # Shop slot indices, aligned with matched_ids
		var matched_ids: Array = []  # Live offer instance ids, so overlays can validate identity

		# Check for target monsters (by name and/or type) and items
		for shop_item in context.shop_items:
			if shop_item.is_monster and (shop_item.name_key in target_monsters or _matches_target_type(shop_item.types)):
				var monster_name: String = formatter.format_species_name(shop_item.name_key)
				matches.append("[%d] %s" % [shop_item.slot, monster_name])
				matched_indices.append(shop_item.slot)
				matched_ids.append(shop_item.instance_id)
			elif not shop_item.item_id.is_empty() and shop_item.item_id in target_items:
				var item_name: String = formatter.format_item_name(shop_item.item_id)
				matches.append("[%d] %s" % [shop_item.slot, item_name])
				matched_indices.append(shop_item.slot)
				matched_ids.append(shop_item.instance_id)

		if matches.is_empty():
			return {}

		return _make_advice(severity, message_template % ", ".join(matches), {
			"matched_indices": matched_indices,
			"matched_ids": matched_ids
		})

	## Does this monster offer carry any of the target types? (target_types empty = no type matching)
	func _matches_target_type(types: Array) -> bool:
		if target_types.is_empty():
			return false
		for type_name in types:
			if str(type_name) in target_types:
				return true
		return false

## Rule that flags a team-composition condition.
## Two modes:
##   Anchor mode (monster_key set): "the anchor monster must be the only monster of a given type"
##     (e.g., Beetdown must be the team's only fighter).
##   Count mode (monster_key empty): warn when the active team has more than max_count monsters
##     of the required type, without naming specific units (e.g., Musician and Electric monsters).
class TeamCompositionRule extends BaseRule:
	var severity: String
	var formatter  # Reference to log formatter for name formatting
	var monster_key: String  # Anchor species name_key (e.g., "monster.name.beetdown"); empty = count mode
	var min_level: int  # Anchor must be at least this level for the rule to apply (anchor mode)
	var required_type: String  # Type other monsters must have to violate the composition
	var message: String  # Console message template; %%s is replaced with the offender list (anchor) or count (count mode)
	var max_count: int  # Count mode: maximum allowed number of required_type monsters on the team

	func _init(p_rule_id: String, p_trainer_id: String, p_severity: String, p_formatter, p_monster_key: String, p_min_level: int, p_required_type: String, p_message: String, p_reminder_text: String, p_max_count: int = 1) -> void:
		super._init(p_rule_id, p_trainer_id, DISPLAY_LABEL, p_reminder_text, false)
		severity = p_severity
		formatter = p_formatter
		monster_key = p_monster_key
		min_level = p_min_level
		required_type = p_required_type
		message = p_message
		max_count = p_max_count

	func evaluate(context: AdviceContext) -> Dictionary:
		if not _matches_trainer(context):
			return {}

		# Count mode: warn only when the active team exceeds max_count required-type monsters.
		if monster_key.is_empty():
			var count := 0
			for monster in context.team_monsters:
				if required_type in monster.types:
					count += 1
			if count <= max_count:
				return {}
			return _make_advice(severity, message % str(count))

		# Anchor mode: find the anchor monster at or above the minimum level
		var anchor_slot := -1
		for monster in context.team_monsters:
			if monster.name_key == monster_key and monster.level >= min_level:
				anchor_slot = monster.slot
				break

		if anchor_slot == -1:
			return {}

		# Collect other monsters whose type violates the composition
		var offenders: Array = []
		for monster in context.team_monsters:
			if monster.slot == anchor_slot:
				continue
			if required_type in monster.types:
				var monster_name: String = formatter.format_species_name(monster.name_key)
				offenders.append("[%d] %s" % [monster.slot, monster_name])

		if offenders.is_empty():
			return {}

		return _make_advice(severity, message % ", ".join(offenders))


## Rule that triggers on a specific day
class DayReminderRule extends BaseRule:
	var target_day: int
	var severity: String
	var message: String

	func _init(p_rule_id: String, p_trainer_id: String, p_target_day: int, p_severity: String, p_message: String, p_reminder_text: String) -> void:
		super._init(p_rule_id, p_trainer_id, DISPLAY_LABEL, p_reminder_text, true)
		target_day = p_target_day
		severity = p_severity
		message = p_message

	func evaluate(context: AdviceContext) -> Dictionary:
		if not _matches_trainer(context):
			return {}

		# Check day
		if context.day != target_day:
			return {}

		return _make_advice(severity, message)
