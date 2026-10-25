extends RefCounted
## TrainerAdvisor - Rule registration, evaluation, and duplicate suppression
## Manages active advice keyed by stable rule IDs.

const AdviceContext = preload("advice_context.gd")


## Registered rules
var _rules: Array = []

## Active advice keyed by rule_id
var _active_advice: Dictionary = {}

## Suppression state - tracks last emitted message per rule_id
var _last_emitted: Dictionary = {}


## Register a rule for evaluation
func register_rule(rule) -> void:
	_rules.append(rule)


## Evaluate all rules against context
## Returns dictionary with:
##   - "all_active": Array of all currently active advice
##   - "new_or_changed": Array of advice that should be emitted (new or changed)
func evaluate(context: AdviceContext) -> Dictionary:
	var new_active: Dictionary = {}
	var new_or_changed: Array = []
	
	# Evaluate all rules
	for rule in _rules:
		var advice: Dictionary = rule.evaluate(context)
		
		if not advice.is_empty():
			var rule_id: String = advice.get("rule_id", "")
			if not rule_id.is_empty():
				new_active[rule_id] = advice
				
				# Check if this is new or changed
				var last_message: String = _last_emitted.get(rule_id, "")
				var current_message: String = advice.get("message", "")
				
				if current_message != last_message:
					new_or_changed.append(advice)
					_last_emitted[rule_id] = current_message
	
	# Clear suppression for rules that are no longer active
	var inactive_rules: Array = []
	for rule_id in _last_emitted.keys():
		if not new_active.has(rule_id):
			inactive_rules.append(rule_id)
	
	for rule_id in inactive_rules:
		_last_emitted.erase(rule_id)
	
	_active_advice = new_active
	
	return {
		"all_active": _active_advice.values(),
		"new_or_changed": new_or_changed
	}


## Reset suppression state (call on new shop visit or trainer/run change)
func reset_suppression() -> void:
	_last_emitted.clear()


