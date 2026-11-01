extends RefCounted
## Rules return structured advice without side effects (no printing, file writing, or retaining live objects).
## Every advice dictionary uses a shared contract so consumers can route by field instead of rule-id strings:
##   rule_id, trainer_id, severity, message, display, reminder, chime, plus rule-specific extras.

const AdviceContext = preload("advice_context.gd")


class BaseRule:
	# Display modes tell the UI layer how this rule should be shown.
	const DISPLAY_NONE := "none"
	const DISPLAY_LABEL := "label"
	const DISPLAY_HIGHLIGHT := "highlight"
	const DISPLAY_BOTH := "both"

	var rule_id: String
	var trainer_id: String  # Empty = any trainer
	var display_mode: String
	var reminder_text: String  # Empty = no label entry
	var chime: bool

	func _init(p_rule_id: String, p_trainer_id: String, p_display_mode: String, p_reminder_text: String, p_chime: bool) -> void:
		rule_id = p_rule_id
		trainer_id = p_trainer_id
		display_mode = p_display_mode
		reminder_text = p_reminder_text
		chime = p_chime

	func evaluate(_context: AdviceContext) -> Dictionary:
		return {}

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

	func _matches_trainer(context: AdviceContext) -> bool:
		return trainer_id.is_empty() or context.trainer_id == trainer_id


class ShopTargetsRule extends BaseRule:
	var target_monsters: Array
	var target_items: Array
	var target_types: Array
	var severity: String
	var message_template: String
	var formatter

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

		for shop_item in context.shop_items:
			var display_name := ""
			if shop_item.is_monster and (shop_item.name_key in target_monsters or _matches_target_type(shop_item.types)):
				display_name = formatter.format_species_name(shop_item.name_key)
			elif not shop_item.item_id.is_empty() and shop_item.item_id in target_items:
				display_name = formatter.format_item_name(shop_item.item_id)
			if display_name.is_empty():
				continue
			matches.append("[%d] %s" % [shop_item.slot, display_name])

		if matches.is_empty():
			return {}

		return _make_advice(severity, message_template % ", ".join(matches))

	func _matches_target_type(types: Array) -> bool:
		if target_types.is_empty():
			return false
		for type_name in types:
			if str(type_name) in target_types:
				return true
		return false

## Two modes:
##   Anchor mode (monster_key set): "the anchor monster must be the only monster of a given type"
##     (e.g., Beetdown must be the team's only fighter).
##   Count mode (monster_key empty): warn when the active team has more than max_count monsters
##     of the required type, without naming specific units (e.g., Musician and Electric monsters).
class TeamCompositionRule extends BaseRule:
	var severity: String
	var formatter
	var monster_key: String
	var min_level: int
	var required_type: String
	var message: String
	var max_count: int

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

		if monster_key.is_empty():
			var count := 0
			for monster in context.team_monsters:
				if required_type in monster.types:
					count += 1
			if count <= max_count:
				return {}
			return _make_advice(severity, message % str(count))

		var anchor_slot := -1
		for monster in context.team_monsters:
			if monster.name_key == monster_key and monster.level >= min_level:
				anchor_slot = monster.slot
				break

		if anchor_slot == -1:
			return {}

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

		if context.day != target_day:
			return {}

		return _make_advice(severity, message)
