extends Node
## Creature Comforts - QOL
const VERSION := "3.103"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

const POLL_INTERVAL_MS := 500

const AdviceController = preload("advice/advice_controller.gd")
const LogFormatterScript = preload("core/log_formatter.gd")
const ShopIncome = preload("core/shop_income.gd")
const ShopSnapshot = preload("core/shop_snapshot.gd")
const ShopChanges = preload("core/shop_changes.gd")
const ShopOverlayGate = preload("hud/shop_overlay_gate.gd")
const BattleMonitor = preload("core/battle_monitor.gd")
const OpponentInfo = preload("core/opponent_info.gd")
const BattleCompletionReporter = preload("core/battle_completion_reporter.gd")
const BattleTrinketTracker = preload("core/battle_trinket_tracker.gd")
const ChimeQueue = preload("core/chime_queue.gd")
const TrinketGainPresenter = preload("hud/trinket_gain_presenter.gd")
const TrinketRemindersController = preload("hud/trinket_reminders_controller.gd")
const TrinketIcons = preload("core/trinket_icons.gd")
const ComfortUi = preload("hud/comfort_ui.gd")
const NodeUtils = preload("core/node_utils.gd")
const ModLogger = preload("core/mod_logger.gd")
const DevHotkeys = preload("core/dev_hotkeys.gd")
const Diagnostics = preload("core/diagnostics.gd")
const RunData = preload("core/run_data.gd")
const ModConfig = preload("core/mod_config.gd")
const AutoUpdater = preload("core/auto_updater.gd")

var _next_poll := 0
var _last_phase := ""
var _last_snapshot = null
var _battle_logged := false

# Battle-scoped trinket gains (core/battle_trinket_tracker.gd) and the results panel.
var _battle_trinkets = null
var _trinket_gains = null
var _initialization_started := false
var _initialized := false

# User-facing feature toggles (centralized in core/mod_config.gd).
var _mod_config = null

# Debug-gated diagnostics dumps (core/diagnostics.gd).
var _diagnostics = null

# Session log + dev flags (core/mod_logger.gd) and Ctrl+Shift hotkeys.
var _logger = null
var _dev_hotkeys = null
var _formatter = null

var _advice = null

var _snapshot_builder = null
var _changes_comparer = null

# Owns the CanvasLayers and panels (hud/comfort_ui.gd).
var _ui = null
var _shop_overlay_gate = null

# Queued reminder sounds (core/chime_queue.gd).
var _chimes = null

var _trinket_reminders = null

# Resolves the game's trinket icons for the reminder and gains panels.
var _trinket_icons = null

# Self-updater: checks the GitHub release manifest and swaps files (core/auto_updater.gd).
var _updater = null

# Battle completion logging: report each battle's result exactly once.
var _battle_completion = null

# Opponent transition data (core/opponent_info.gd): the signal carries the
# RunData with the matched MMR, which the battle state's copy does not keep.
var _captured_opponent = null
var _captured_at := 0
var _opponent_battle_id := 0
var _opponent_info: Dictionary = {}


func mod_ready() -> void:
	_initialize_mod()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_loaded_by_mod_loader():
		_initialize_mod()


func _exit_tree() -> void:
	# Drop the loader subscription so a freed mod node is never called back.
	if _mod_config != null:
		_mod_config.teardown()
		_mod_config = null
	if _logger != null:
		_logger.close()


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	
	_formatter = LogFormatterScript.new(NodeUtils.has_property)
	_logger = ModLogger.new(_formatter)
	_dev_hotkeys = DevHotkeys.new()
	_diagnostics = Diagnostics.new(_logger)
	_battle_completion = BattleCompletionReporter.new()
	_battle_trinkets = BattleTrinketTracker.new()
	_setup_mod_config()
	_chimes = ChimeQueue.new()
	_chimes.setup(self, _sounds_enabled)
	
	_snapshot_builder = ShopSnapshot.new()
	_changes_comparer = ShopChanges.new()
	
	_ui = ComfortUi.new()
	_ui.name = "ComfortUi"
	add_child(_ui)
	_ui.setup(_formatter, _logger, _feature_enabled, _sounds_enabled)

	_setup_advisor()
	_advice.set_reminder_label(_ui.reminder_label)
	_trinket_icons = TrinketIcons.new()
	_trinket_reminders = TrinketRemindersController.new()
	_trinket_reminders.setup(_ui.trinket_reminders_panel, _formatter, _logger, _chimes, _feature_enabled, _trinket_icons)
	# Owns the shop-overlay gate: visibility checks, transition listeners, timers, view cache
	_setup_shop_overlay_gate()
	_setup_auto_updater()
	_setup_transition_capture()
	_trinket_gains = TrinketGainPresenter.new()
	_trinket_gains.setup(_ui.trinket_panel, _formatter, _feature_enabled, _trinket_icons)
	# The UI is live and the overlay gate must run even if the log file cannot be
	# opened; the logger no-ops when its file handle is null.
	_initialized = true
	# Connect only after every subsystem exists, so an early config change
	# cannot dereference a null panel.
	_mod_config.changed.connect(_on_feature_toggled)
	
	var abs_log_path: String = _logger.open(VERSION)
	if abs_log_path.is_empty():
		return
	
	if _logger.debug_logging:
		# Catalog overview for troubleshooting; deferred so autoloads such as
		# GameDatabase exist.
		_diagnostics.call_deferred("log_catalog")
	
	print("Creature Comforts %s loaded - logging to %s" % [VERSION, abs_log_path])


## Bind the centralized feature-toggle configuration to the Mod Loader. The
## loader persists values and emits config_changed; mod_config re-emits only
## our own keys so feature logic never touches the loader directly.
func _setup_mod_config() -> void:
	_mod_config = ModConfig.new()
	_mod_config.setup(get_node_or_null("/root/ModLoader"))


## True when a user-facing feature is enabled. Defaults to enabled when the
## configuration module is unavailable (e.g. standalone run).
func _feature_enabled(key: String) -> bool:
	if _mod_config == null:
		return true
	return _mod_config.is_enabled(key)


func _setup_advisor() -> void:
	_advice = AdviceController.new()
	_advice.setup(_formatter, _logger, _chimes, _feature_enabled)


func _setup_shop_overlay_gate() -> void:
	_shop_overlay_gate = ShopOverlayGate.new()
	_shop_overlay_gate.name = "ShopOverlayGate"
	add_child(_shop_overlay_gate)
	_shop_overlay_gate.visibility_changed.connect(_on_shop_visibility_changed)
	_shop_overlay_gate.setup(NodeUtils.has_property, NodeUtils.script_is)


## The updater lives next to the mod and edits the mod's own folder, so it gets the folder of the
## running script (not a game path). It refuses to run on a developer install by itself.
func _setup_auto_updater() -> void:
	_updater = AutoUpdater.new()
	_updater.name = "AutoUpdater"
	add_child(_updater)
	_updater.setup(VERSION, get_script().resource_path.get_base_dir(),
		_feature_enabled(ModConfig.KEY_AUTO_UPDATE))
	_updater.start()


func _on_shop_visibility_changed(allowed: bool, _reason: String) -> void:
	if _ui.apply_gate(allowed):
		_chimes.try_play(_shop_overlay_gate)


## The battle transition signal carries the opponent RunData (MMR / bot flags).
## The shop overlay gate owns the game subscription and forwards it here, so
## there is only one transition listener in the mod.
func _setup_transition_capture() -> void:
	if _shop_overlay_gate != null:
		_shop_overlay_gate.transition_requested.connect(_on_transition)


func _on_transition(target: String, data) -> void:
	if target != "battle":
		return
	if not (data is Dictionary):
		return
	var opp = data.get("opponent_data")
	if opp != null and is_instance_valid(opp):
		_captured_opponent = opp
		_captured_at = Time.get_ticks_msec()


## Every sound the mod plays (reminders and UI feedback) is gated by the same
## setting, so one toggle mutes all of them.
func _sounds_enabled() -> bool:
	return _feature_enabled(ModConfig.KEY_NOTIFICATION_SOUNDS)


## Apply a live settings change. Disabling a feature hides its UI immediately and
## drops any queued sound; enabling lets the next poll re-show it. Panels are
## created once at startup, so toggling never duplicates UI or subscriptions.
func _on_feature_toggled(key: String, value: bool) -> void:
	_ui.on_feature_toggled(key, value)
	if key == ModConfig.KEY_DAY_REMINDERS:
		_advice.on_feature_toggled(key, value)
	elif key == ModConfig.KEY_TRINKET_REMINDERS:
		_trinket_reminders.on_feature_toggled(key, value)
	elif key == ModConfig.KEY_NOTIFICATION_SOUNDS:
		_chimes.clear()
	elif key == ModConfig.KEY_TRINKETS_GAINED_PANEL:
		_trinket_gains.hide()
	elif key == ModConfig.KEY_AUTO_UPDATE:
		_updater.set_auto(value)


func _process(_delta: float) -> void:
	if not _initialized:
		return
	if _shop_overlay_gate != null:
		_shop_overlay_gate.update()
	
	_dev_hotkeys.poll(_logger)
	
	var now := Time.get_ticks_msec()
	if now < _next_poll:
		return
	_next_poll = now + POLL_INTERVAL_MS
	_inspect_current_phase()


func _inspect_current_phase() -> void:
	var main = get_tree().current_scene
	var state = main.get("current_state") if NodeUtils.has_property(main, "current_state") else null
	
	var is_battle := NodeUtils.script_is(state, BATTLE_SCRIPT)
	_ui.update_player_hud(state, is_battle)
	# Defensive fallback: the income and trinket-reminder panels are normally hidden by the
	# reminder layer's shop gate, but hide them directly whenever the shop is not the current phase.
	if not NodeUtils.script_is(state, SHOP_SCRIPT):
		_ui.hide_shop_panels()
	if not is_battle:
		_ui.hide_opponent_panel()
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _last_phase == "battle":
			_battle_completion.reset()
		_finalize_battle_trinket_tracking()
		# Keep a rolling "last state outside battle" snapshot. The battle is simulated before the
		# first poll sees the battle state, so this is the only reliable pre-battle baseline.
		_battle_trinkets.note_non_battle(_get_run_data())
	
	if NodeUtils.script_is(state, SHOP_SCRIPT):
		_handle_shop_phase(state)
	elif is_battle:
		_handle_battle_phase(state)
	else:
		if _last_phase != "":
			_last_phase = ""
			_battle_logged = false
			_reset_transient_state(true, true, true)  # Drop stale chimes when leaving the shop


func _handle_shop_phase(state) -> void:
	var run = _get_run_data()
	var manager = state.get("manager") if NodeUtils.has_property(state, "manager") else null
	
	if run == null or manager == null:
		return
	
	var current_snapshot = _snapshot_builder.capture(run, manager, NodeUtils.has_property, _formatter.resolve_type_name)
	
	var phase_changed := _last_phase != "shop"
	
	var trainer_changed := false
	if _last_snapshot != null:
		trainer_changed = _last_snapshot.trainer_id != current_snapshot.trainer_id
	
	if phase_changed:
		_battle_logged = false
		_ui.hide_battle_elapsed()
		if _shop_overlay_gate != null:
			_shop_overlay_gate.reset_for_shop()
		_log_phase_entry("SHOP", run, manager)
		_diagnostics.on_shop_entered(state)
		if _logger.debug_logging:
			var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
			_diagnostics.log_trinket_icons(held if held != null else [])
		if _logger.deep_inspection:
			_logger.log_lines(_formatter.format_deep_inspect_shop(manager))
		# Trinket gains are battle-scoped (tracked during the battle state only), so no
		# shop-to-shop inventory diff happens here. The gains panel is shop-gated and already
		# holds this battle's gains; it simply becomes visible now that the shop is interactive.
		_reset_transient_state(true, false, false)  # Reset suppression for new shop visit
		_ui.reset_shop_popups_for_shop()
	elif _last_snapshot != null and _logger.deep_inspection:
		# Full snapshot diffs are troubleshooting detail, not regular event logging.
		var comparison = _changes_comparer.compare(_last_snapshot, current_snapshot)
		if comparison.has_changes():
			_logger.log_lines(_formatter.format_snapshot_changes(comparison, run, manager, _logger.debug_logging))
	
	if trainer_changed:
		_advice.on_trainer_changed()
		_finalize_battle_trinket_tracking(false)  # Prevent false gains/panel from a previous run
		_trinket_reminders.on_trainer_changed()
	
	_advice.evaluate(current_snapshot, _shop_overlay_gate)
	
	var current_day := int(run.get("current_round")) if NodeUtils.has_property(run, "current_round") else 1
	_ui.update_shop_income(_compute_daily_income(run, current_day))
	_trinket_reminders.update(run, _shop_overlay_gate)
	_ui.update_rank_odds(int(run.get("shop_rank")) if NodeUtils.has_property(run, "shop_rank") else 1)
	var total_hp := int(run.get("player_hp")) if NodeUtils.has_property(run, "player_hp") else 0
	_ui.update_base_hp(current_day, total_hp)

	# (overlay visibility is handled every frame by the shop overlay gate)
	
	_last_phase = "shop"
	_last_snapshot = current_snapshot


func _compute_daily_income(run, day: int) -> int:
	var passive_gains: Array = []
	if NodeUtils.has_property(run, "_active_passives"):
		var passives = run.get("_active_passives")
		if passives is Array:
			for passive in passives:
				if passive != null and is_instance_valid(passive) and NodeUtils.has_property(passive, "gold_gain"):
					passive_gains.append(int(passive.get("gold_gain")))
	return ShopIncome.compute(day, passive_gains)


func _handle_battle_phase(state) -> void:
	# On battle entry, clear the previous battle's elapsed readout before checking
	# completion, so a battle that is already over still shows its own time.
	if _last_phase != "battle":
		_ui.hide_battle_elapsed()

	# The opponent card follows the exact same visibility as the lives/wins/day HUD.
	var is_active: bool = state.get("is_battle_active") if NodeUtils.has_property(state, "is_battle_active") else false

	# Battle completion detection (win/loss/draw) - independent of replay logging
	_check_battle_completion(state)
	_update_opponent_panel(state, is_active)
	
	var player = state.get("_replay_p1_data") if NodeUtils.has_property(state, "_replay_p1_data") else null
	var opponent = state.get("_replay_p2_data") if NodeUtils.has_property(state, "_replay_p2_data") else null
	
	if player == null or opponent == null:
		return
	
	# Only log once per battle when battle is actually active (is_active is above)
	
	if not _battle_logged and is_active:
		_log_phase_entry("BATTLE", player)
		
		if _logger.deep_inspection:
			_logger.log_lines(_formatter.format_deep_inspect_battle(state, player, opponent))
			_logger.log_lines(_formatter.format_battle_trinket_state(_get_run_data()))
		
		# Battle-scoped trinket baseline (prefers the last snapshot taken OUTSIDE battle).
		# Any gains still on the panel are from the previous battle, so clear them now.
		_battle_trinkets.start(_get_run_data())
		_trinket_gains.on_battle_started()
		
		_battle_logged = true
	
	# Freeze the battle-end snapshot the FIRST time battle_over is observed. The game pre-computes
	# the following event's rewards during the results screen, applying them to run.trinket_ids
	# before the event UI appears; continuing to refresh the end snapshot would leak those future
	# event trinkets into the battle diff. The panel itself is displayed later, when the battle
	# state ends (see _finalize_battle_trinket_tracking).
	_battle_trinkets.poll(state, _get_run_data())
	
	# Reset transient overlay/suppression state on battle entry (not every poll)
	if _last_phase != "battle":
		_reset_transient_state(false, true, true)
	_last_phase = "battle"


func _update_opponent_panel(state, is_active: bool) -> void:
	var p2 = state.get("_replay_p2_data") if NodeUtils.has_property(state, "_replay_p2_data") else null
	if p2 == null:
		_ui.hide_opponent_panel()
		return
	var battle_id: int = state.get_instance_id()
	if battle_id != _opponent_battle_id or _opponent_info.is_empty():
		_opponent_battle_id = battle_id
		_opponent_info = OpponentInfo.info(p2, _captured_opponent, _captured_at)
	if is_active:
		_ui.show_opponent(str(_opponent_info.get("name", "?")), str(_opponent_info.get("mmr", "-")))
	else:
		_ui.hide_opponent_panel()


func _check_battle_completion(state) -> void:
	if not _battle_completion.check(state):
		return
	var sim = state.get("simulation") if NodeUtils.has_property(state, "simulation") else null
	var battle_data = sim.get("data") if sim != null and NodeUtils.has_property(sim, "data") else null
	_log_battle_result(battle_data)
	_ui.show_battle_elapsed(BattleMonitor.format_seconds(BattleMonitor.time_elapsed(battle_data)))


func _log_battle_result(battle_data) -> void:
	var info := BattleMonitor.classify(battle_data)
	if info["hp"] == null:
		if str(info["detail"]).is_empty():
			_logger.log_event("BATTLE COMPLETE | %s" % info["result"])
		else:
			_logger.log_event("BATTLE COMPLETE | %s | %s" % [info["result"], info["detail"]])
		return
	_logger.log_event("BATTLE COMPLETE | %s | HP %d" % [info["result"], info["hp"]])


## Stop battle trinket tracking. Called when leaving the battle state and on trainer/run changes.
## Gains are always logged once. This runs on EVERY non-battle poll, so an empty result (no
## battle was being tracked) must not hide a panel still waiting to be seen in the shop.
## The panel itself is shop-gated: it appears once the player is back in the shop and stays
## until collapsed or the next battle starts.
func _finalize_battle_trinket_tracking(show_panel := true) -> void:
	var gains: Dictionary = _battle_trinkets.finalize(_get_run_data(), _logger, _formatter, show_panel)
	_trinket_gains.apply_finalized(gains, show_panel)


func _reset_transient_state(clear_suppression: bool, clear_reminders: bool, clear_chimes: bool) -> void:
	# The trinket gains panel is shop-gated and only cleared on a battle start or a
	# trainer/run change, so this per-phase reset leaves it alone.
	_advice.reset_transient(clear_suppression, clear_reminders)
	if clear_chimes:
		_chimes.clear()


func _log_phase_entry(phase: String, run, manager = null) -> void:
	_logger.log_event(_formatter.format_phase_entry(phase, run))
	if _logger.deep_inspection:
		_logger.log_lines(_formatter.format_phase_snapshot(phase, run, manager))


func _get_run_data():
	return RunData.get_run_data()


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
