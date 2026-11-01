extends RefCounted

const AdviceContext = preload("advice_context.gd")


var _rules: Array = []

var _last_emitted: Dictionary = {}


func register_rule(rule) -> void:
	_rules.append(rule)


func evaluate(context: AdviceContext) -> Dictionary:
	var new_active: Dictionary = {}
	var new_or_changed: Array = []
	
	for rule in _rules:
		var advice: Dictionary = rule.evaluate(context)
		
		if not advice.is_empty():
			var rule_id: String = advice.get("rule_id", "")
			if not rule_id.is_empty():
				new_active[rule_id] = advice
				
				var last_message: String = _last_emitted.get(rule_id, "")
				var current_message: String = advice.get("message", "")
				
				if current_message != last_message:
					new_or_changed.append(advice)
					_last_emitted[rule_id] = current_message
	
	for rule_id in _last_emitted.keys():
		if not new_active.has(rule_id):
			_last_emitted.erase(rule_id)
	
	return {
		"all_active": new_active.values(),
		"new_or_changed": new_or_changed
	}


func reset_suppression() -> void:
	_last_emitted.clear()


