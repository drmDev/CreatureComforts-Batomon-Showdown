extends RefCounted
## Shop-phase orchestration: snapshot capture, change diffing, advice evaluation,
## and the shop HUD/panel updates.
##
## Extracted from mod_main.gd. Owns the shop snapshot pipeline and the
## shop-only presentation controllers (advice, trinket reminders, positional
## trinkets). mod_main only decides when the shop phase is current and passes
## the phase-change flag in.

const NodeUtils = preload("node_utils.gd")
const RunData = preload("run_data.gd")
const ShopSnapshot = preload("shop_snapshot.gd")
const ShopChanges = preload("shop_changes.gd")
const ShopIncome = preload("shop_income.gd")
const AdviceController = preload("../advice/advice_controller.gd")
const TrinketRemindersController = preload("../hud/trinket_reminders_controller.gd")
const PositionalTrinketsController = preload("../hud/positional_trinkets_controller.gd")
const ModConfig = preload("mod_config.gd")

var _context = null
var _ui = null
var _shop_overlay_gate = null
var _dev_tools = null
var _on_shop_entered: Callable
var _on_run_changed: Callable
var _has_replay: Callable

var _snapshot_builder = null
var _changes_comparer = null
var _last_snapshot = null
var _last_run_id := ""

var _advice = null
var _trinket_reminders = null
var _positional_trinkets = null


func setup(context, ui, shop_overlay_gate, dev_tools, on_shop_entered: Callable, on_run_changed: Callable, has_replay: Callable = Callable()) -> void:
	_context = context
	_ui = ui
	_shop_overlay_gate = shop_overlay_gate
	_dev_tools = dev_tools
	_on_shop_entered = on_shop_entered
	_on_run_changed = on_run_changed
	_has_replay = has_replay

	_snapshot_builder = ShopSnapshot.new()
	_changes_comparer = ShopChanges.new()

	_advice = AdviceController.new()
	_advice.setup(_context)
	_advice.set_reminder_label(_ui.reminder_label)

	_trinket_reminders = TrinketRemindersController.new()
	_trinket_reminders.setup(_ui.trinket_reminders_panel, _context)

	_positional_trinkets = PositionalTrinketsController.new()
	_positional_trinkets.setup(_ui.positional_trinkets_panel, _context, _ui.positional_trinkets_assistant)


## Handle one shop poll. Returns true when the shop phase was processed (so the
## caller can record the phase); false when the run/manager is not ready yet.
func handle(state, phase_changed: bool) -> bool:
	var run = RunData.get_run_data()
	var manager = state.get("manager") if NodeUtils.has_property(state, "manager") else null
	if run == null or manager == null:
		return false

	var run_id := RunData.identity(run)
	var run_changed := not _last_run_id.is_empty() and _last_run_id != run_id
	_last_run_id = run_id

	var current_snapshot = _snapshot_builder.capture(run, manager, NodeUtils.has_property, _context.formatter.resolve_type_name)

	var trainer_changed := false
	if _last_snapshot != null:
		trainer_changed = _last_snapshot.trainer_id != current_snapshot.trainer_id

	if phase_changed:
		_on_shop_entered.call()
		_ui.hide_battle_elapsed()
		if _shop_overlay_gate != null:
			_shop_overlay_gate.reset_for_shop()
		_log_phase_entry(run, manager)
		_dev_tools.on_shop_entered(state)
		if _context.logger.debug_logging:
			var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
			_dev_tools.log_trinket_icons(held if held != null else [])
		if _context.logger.deep_inspection:
			_context.logger.log_lines(_context.formatter.format_deep_inspect_shop(manager))
		# Trinket gains are battle-scoped (tracked during the battle state only), so no
		# shop-to-shop inventory diff happens here. The gains panel is shop-gated and already
		# holds this battle's gains; it simply becomes visible now that the shop is interactive.
		reset_transient(true, false)  # Reset suppression for new shop visit
		_ui.reset_shop_popups_for_shop()
	elif _last_snapshot != null and _context.logger.deep_inspection:
		# Full snapshot diffs are troubleshooting detail, not regular event logging.
		var comparison = _changes_comparer.compare(_last_snapshot, current_snapshot)
		if comparison.has_changes():
			_context.logger.log_lines(_context.formatter.format_snapshot_changes(comparison, run, manager, _context.logger.debug_logging))

	if run_changed or trainer_changed:
		_advice.on_trainer_changed()
		_on_run_changed.call()  # Clear run-scoped state (gains panel, tracking)
		_trinket_reminders.on_trainer_changed()
		_positional_trinkets.on_trainer_changed()

	_advice.evaluate(current_snapshot, _shop_overlay_gate)

	var current_day := int(run.get("current_round")) if NodeUtils.has_property(run, "current_round") else 1
	_ui.update_shop_income(_compute_daily_income(run, current_day))
	_trinket_reminders.update(run, _shop_overlay_gate)
	_positional_trinkets.update(run)
	var held_trinkets = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	_ui.update_rank_odds(int(run.get("shop_rank")) if NodeUtils.has_property(run, "shop_rank") else 1, held_trinkets if held_trinkets != null else [])
	var total_hp := int(run.get("player_hp")) if NodeUtils.has_property(run, "player_hp") else 0
	_ui.update_base_hp(current_day, total_hp)
	var view = state.get("view") if NodeUtils.has_property(state, "view") else null
	var gate_allowed: bool = _shop_overlay_gate == null or _shop_overlay_gate.is_allowed()
	_ui.update_sell_values(view, gate_allowed)
	if _has_replay.is_valid():
		_ui.update_replay_button(bool(_has_replay.call()))

	_last_snapshot = current_snapshot
	return true


## Clear the advice reminder label and/or rule suppression when leaving a phase.
func reset_transient(clear_suppression: bool, clear_reminders: bool) -> void:
	_advice.reset_transient(clear_suppression, clear_reminders)


## Forward a live settings change to the shop-only controllers.
func on_feature_toggled(key: String, value: bool) -> void:
	if key == ModConfig.KEY_DAY_REMINDERS:
		_advice.on_feature_toggled(key, value)
	elif key == ModConfig.KEY_TRINKET_REMINDERS:
		_trinket_reminders.on_feature_toggled(key, value)
	elif key == ModConfig.KEY_POSITIONAL_TRINKETS:
		_positional_trinkets.on_feature_toggled(key, value)


func _compute_daily_income(run, day: int) -> int:
	var passive_gains: Array = []
	if NodeUtils.has_property(run, "_active_passives"):
		var passives = run.get("_active_passives")
		if passives is Array:
			for passive in passives:
				if passive != null and is_instance_valid(passive) and NodeUtils.has_property(passive, "gold_gain"):
					passive_gains.append(int(passive.get("gold_gain")))
	return ShopIncome.compute(day, passive_gains)


func _log_phase_entry(run, manager) -> void:
	_context.logger.log_event(_context.formatter.format_phase_entry("SHOP", run))
	if _context.logger.deep_inspection:
		_context.logger.log_lines(_context.formatter.format_phase_snapshot("SHOP", run, manager))
