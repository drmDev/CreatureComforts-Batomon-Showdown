extends RefCounted
## Trainer advice evaluation and the top reminder label.
##
## Extracted from mod_main.gd. Owns the advisor, the advice context builder,
## trainer display names, the reminder label, and the change-only reminder log.

const TrainerAdvisor = preload("trainer_advisor.gd")
const TrainerCatalog = preload("trainer_catalog.gd")
const RuleFactory = preload("rule_factory.gd")
const AdviceContext = preload("advice_context.gd")
const TrainerRules = preload("trainer_rules.gd")
const ModConfig = preload("../core/mod_config.gd")

var _advisor = null
var _context_builder = null
var _trainer_display_names: Dictionary = {}
var _last_reminder_rule_ids: Dictionary = {}
var _reminder_label = null
var _logger = null
var _chimes = null
var _feature_enabled: Callable


func setup(formatter, logger, chimes, feature_enabled: Callable) -> void:
	_logger = logger
	_chimes = chimes
	_feature_enabled = feature_enabled

	_advisor = TrainerAdvisor.new()
	_context_builder = AdviceContext.new()

	var definitions: Array = TrainerCatalog.TRAINER_DEFINITIONS
	for trainer_def in definitions:
		_trainer_display_names[str(trainer_def.get("id", ""))] = str(trainer_def.get("display_name", ""))

	var factory = RuleFactory.new(formatter)
	for rule in factory.build_all(definitions):
		_advisor.register_rule(rule)

	# Trainer-independent reminders (empty trainer id applies to every trainer).
	for rule in factory.build_trainer({"id": "", "rules": TrainerCatalog.GLOBAL_RULES}):
		_advisor.register_rule(rule)


func set_reminder_label(label) -> void:
	_reminder_label = label


## Evaluate the rules for a shop snapshot, print new notices, update the
## reminder label, and queue/play chimes. `gate` is the shop overlay gate.
func evaluate(snapshot, gate) -> void:
	if _advisor == null or _context_builder == null:
		return

	var context = _context_builder.from_snapshot(snapshot)
	var result: Dictionary = _advisor.evaluate(context)
	var new_or_changed: Array = result.get("new_or_changed", [])
	var all_active: Array = result.get("all_active", [])

	for advice in new_or_changed:
		var severity: String = advice.get("severity", "NOTICE")
		var message: String = advice.get("message", "")

		if not message.is_empty():
			# Trainers are namespaced by their own id, so no prefix inference is needed
			var prefix: String = _trainer_display_names.get(advice.get("trainer_id", ""), "")
			var parts := ["*** COMFORTS %s" % severity]
			if not prefix.is_empty():
				parts.append(prefix)
			parts.append(message)
			_logger.print_notice(" | ".join(parts))

		# Queue the chime for chime-flagged rules (day reminders); played once the overlay is showing
		if advice.get("chime", false) and _feature_enabled.call(ModConfig.KEY_DAY_REMINDERS):
			_chimes.queue_day(advice.get("rule_id", ""))
			_logger.log_event("DAY REMINDER | %s | %s" % [advice.get("rule_id", ""), message])

	if _reminder_label != null and _feature_enabled.call(ModConfig.KEY_DAY_REMINDERS):
		var reminders_to_show: Dictionary = {}

		for advice in all_active:
			var display: String = advice.get("display", TrainerRules.BaseRule.DISPLAY_NONE)
			if display == TrainerRules.BaseRule.DISPLAY_LABEL:
				var reminder_text: String = advice.get("reminder", "")
				if not reminder_text.is_empty():
					reminders_to_show[advice.get("rule_id", "")] = reminder_text

		# Replace all reminders at once (single update, single render)
		_reminder_label.set_reminders(reminders_to_show)
		_log_reminder_changes(reminders_to_show)

	_chimes.try_play(gate)


func reset_suppression() -> void:
	if _advisor != null:
		_advisor.reset_suppression()


## Clear the reminder label and/or rule suppression when leaving a phase.
func reset_transient(clear_suppression: bool, clear_reminders: bool) -> void:
	if clear_reminders:
		if _reminder_label != null:
			_reminder_label.hide_all_reminders()
		_last_reminder_rule_ids.clear()
	if clear_suppression:
		reset_suppression()


## A new trainer/run starts: drop suppression and stale reminder bookkeeping.
func on_trainer_changed() -> void:
	reset_suppression()
	_last_reminder_rule_ids.clear()


func on_feature_toggled(key: String, value: bool) -> void:
	if value:
		return
	if key == ModConfig.KEY_DAY_REMINDERS:
		if _reminder_label != null:
			_reminder_label.hide_all_reminders()
		_last_reminder_rule_ids.clear()
		_chimes.clear_day()


func _log_reminder_changes(reminders: Dictionary) -> void:
	var current := {}
	for rule_id in reminders.keys():
		current[rule_id] = "%s | %s" % [rule_id, str(reminders[rule_id])]
	_logger.log_keyed_changes("REMINDER", _last_reminder_rule_ids, current)
	_last_reminder_rule_ids = current
