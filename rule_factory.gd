extends RefCounted
## RuleFactory - builds rule instances from TrainerCatalog definitions.
## Keeps trainer data out of both the rule classes and mod_main; per-trainer custom
## evaluate() logic can be supplied via a "script" key pointing to a GDScript whose
## .new(rule_def, formatter) returns a BaseRule-compatible instance.

const TrainerRules = preload("trainer_rules.gd")

var _formatter


func _init(p_formatter) -> void:
	_formatter = p_formatter


## Build all registered trainers' rules
func build_all(trainer_definitions: Array) -> Array:
	var rules: Array = []
	for trainer_def in trainer_definitions:
		rules.append_array(build_trainer(trainer_def))
	return rules


## Build one trainer's rules from its catalog entry
func build_trainer(trainer_def: Dictionary) -> Array:
	var rules: Array = []
	var trainer_id: String = str(trainer_def.get("id", ""))
	for rule_def in trainer_def.get("rules", []):
		var rule = _build_rule(trainer_id, rule_def)
		if rule != null:
			_apply_overrides(rule, rule_def)
			if rule.rule_id.is_empty():
				push_warning("RuleFactory: rule for trainer '%s' built with empty rule_id (type '%s'); it will be skipped by the advisor" % [trainer_id, str(rule_def.get("type", "?"))])
			rules.append(rule)
	return rules


func _build_rule(trainer_id: String, rule_def: Dictionary):
	var rule_type: String = str(rule_def.get("type", ""))
	match rule_type:
		"shop_targets":
			return TrainerRules.ShopTargetsRule.new(
				str(rule_def.get("rule_id", "%s_targets" % trainer_id)),
				trainer_id,
				rule_def.get("monsters", []),
				rule_def.get("items", []),
				str(rule_def.get("severity", "NOTICE")),
				str(rule_def.get("message_template", "")),
				_formatter
			)
		"day_reminder":
			return TrainerRules.DayReminderRule.new(
				str(rule_def.get("rule_id", "")),
				trainer_id,
				int(rule_def.get("day", 0)),
				str(rule_def.get("severity", "NOTICE")),
				str(rule_def.get("message", "")),
				str(rule_def.get("reminder", rule_def.get("message", "")))
			)
		"team_composition":
			return TrainerRules.TeamCompositionRule.new(
				str(rule_def.get("rule_id", "")),
				trainer_id,
				str(rule_def.get("severity", "NOTICE")),
				_formatter,
				str(rule_def.get("monster_key", "")),
				int(rule_def.get("min_level", 1)),
				str(rule_def.get("required_type", "")),
				str(rule_def.get("message", "")),
				str(rule_def.get("reminder", ""))
			)
		"custom":
			var script_path: String = str(rule_def.get("script", ""))
			if script_path.is_empty():
				push_error("RuleFactory: custom rule missing 'script' path")
				return null
			var script = load(script_path)
			if script == null:
				push_error("RuleFactory: cannot load custom rule script %s" % script_path)
				return null
			return script.new(rule_def, _formatter)
	push_error("RuleFactory: unknown rule type '%s' (trainer '%s'); rule not registered" % [rule_type, trainer_id])
	return null


## Apply optional display/reminder/chime overrides from the catalog entry.
## An unknown display mode fails loudly instead of silently rendering nowhere.
func _apply_overrides(rule, rule_def: Dictionary) -> void:
	if rule_def.has("display"):
		var display: String = str(rule_def.get("display"))
		if _is_valid_display(display):
			rule.display_mode = display
		else:
			push_error("RuleFactory: invalid display mode '%s' for rule '%s' (use none/label/highlight/both)" % [display, rule.rule_id])
	if rule_def.has("reminder"):
		rule.reminder_text = str(rule_def.get("reminder"))
	if rule_def.has("chime"):
		rule.chime = bool(rule_def.get("chime"))


func _is_valid_display(display: String) -> bool:
	return display in [
		TrainerRules.BaseRule.DISPLAY_NONE,
		TrainerRules.BaseRule.DISPLAY_LABEL,
		TrainerRules.BaseRule.DISPLAY_HIGHLIGHT,
		TrainerRules.BaseRule.DISPLAY_BOTH
	]