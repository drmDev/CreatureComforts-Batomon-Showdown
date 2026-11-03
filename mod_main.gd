extends Node
## Creature Comforts - QOL
const VERSION := "2.205"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

const POLL_INTERVAL_MS := 500

# Advice display modes come from trainer_rules.gd BaseRule (single source)
const TrainerRules = preload("advice/trainer_rules.gd")
# Junk trinket id lives in the formatter (single source for the panel filter + log)
const LogFormatterScript = preload("core/log_formatter.gd")
const JUNK_TRINKET_ID := LogFormatterScript.JUNK_TRINKET_ID
const TrinketGains = preload("core/trinket_gains.gd")
const ShopIncome = preload("core/shop_income.gd")
const TrackedTrinkets = preload("core/tracked_trinkets.gd")
const BattleMonitor = preload("core/battle_monitor.gd")
const BattleCompletionReporter = preload("core/battle_completion_reporter.gd")
const NodeUtils = preload("core/node_utils.gd")
const ModLogger = preload("core/mod_logger.gd")
const DevHotkeys = preload("core/dev_hotkeys.gd")
const Diagnostics = preload("core/diagnostics.gd")
const RunData = preload("core/run_data.gd")
const UiSound = preload("core/ui_sound.gd")
const ShopHighlight = preload("hud/shop_highlight.gd")
const ModConfig = preload("core/mod_config.gd")

var _next_poll := 0
var _last_phase := ""
var _last_snapshot = null
var _battle_logged := false

# Battle-scoped trinket gains.
# IMPORTANT: this is an autobattler - the whole fight is simulated before the mod's 500ms poll
# first sees the battle state, so the first battle poll already contains the battle-granted
# trinkets. We therefore keep a rolling snapshot of the last NON-battle state (shop/event) and use
# it as the "before battle" baseline. The end snapshot is frozen at battle_over.
#
# The panel shows mid-combat gains for any result. Gift content from a consumed Locked Box /
# Mysterious Chest is applied after the frozen battle_over snapshot, so it never appears in the
# ids diff and cannot be spoiled; legitimate gains are still shown.
# The snapshot stays frozen at battle_over so later event rewards never leak into the diff.
var _pre_battle_trinket_state = null
var _battle_trinket_start = null
var _battle_trinket_end = null
var _battle_trinket_tracking := false
var _battle_over_seen := false     # battle_over observed; end snapshot is frozen at this point
var _battle_gains_logged := false
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

var _advisor = null
var _advice_context_builder = null

var _snapshot_builder = null
var _changes_comparer = null

var _reminder_label = null
var _reminder_layer: CanvasLayer = null
var _shop_overlay_gate = null
var _pika_sound = null
var _poke_sound = null

# Chime queue: rule_ids whose day reminder fired since the last play
var _pending_chime_rule_ids: Dictionary = {}
# Trinket-reminder sound queued until the overlay gate opens
var _pending_trinket_reminder_sound := false

var _trainer_display_names: Dictionary = {}

var _trinket_panel = null

var _shop_income_panel = null

var _trinket_reminders_panel = null
var _trinket_reminders_alerted := false
var _last_trinket_reminder_entries: Dictionary = {}  # name -> display line, for change-only logging

var _rank_odds_panel = null
var _rank_odds_popup_open := false
var _watchlist_panel = null
var _shop_highlight = null
var _last_reminder_rule_ids: Dictionary = {}  # rule id -> display line, for change-only logging

var _player_hud = null

# Results layer: hosts the trinket-gain panel so it can show over the battle results screen.
var _results_layer: CanvasLayer = null

# Battle completion logging: report each battle's result exactly once.
var _battle_completion = null


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
	_setup_mod_config()
	
	var ShopSnapshot = load(_base_dir().path_join("core/shop_snapshot.gd"))
	_snapshot_builder = ShopSnapshot.new()
	
	var ShopChanges = load(_base_dir().path_join("core/shop_changes.gd"))
	_changes_comparer = ShopChanges.new()
	
	_setup_advisor()
	_setup_reminder_panel()
	_setup_shop_highlight()
	# Owns the shop-overlay gate: visibility checks, transition listeners, timers, view cache
	_setup_shop_overlay_gate()
	_setup_player_hud()
	_setup_results_panel()
	_setup_notification_sounds()
	# The UI is live and the overlay gate must run even if the log file cannot be
	# opened; the logger no-ops when its file handle is null.
	_initialized = true
	
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
	_mod_config.changed.connect(_on_feature_toggled)


## True when a user-facing feature is enabled. Defaults to enabled when the
## configuration module is unavailable (e.g. standalone run).
func _feature_enabled(key: String) -> bool:
	if _mod_config == null:
		return true
	return _mod_config.is_enabled(key)


func _setup_advisor() -> void:
	var TrainerAdvisor = load(_base_dir().path_join("advice/trainer_advisor.gd"))
	var TrainerCatalog = load(_base_dir().path_join("advice/trainer_catalog.gd"))
	var RuleFactory = load(_base_dir().path_join("advice/rule_factory.gd"))
	
	_advisor = TrainerAdvisor.new()
	
	# Cache AdviceContext builder (rules consume snapshot data as plain records)
	_advice_context_builder = load(_base_dir().path_join("advice/advice_context.gd")).new()
	
	var definitions: Array = TrainerCatalog.TRAINER_DEFINITIONS
	for trainer_def in definitions:
		_trainer_display_names[str(trainer_def.get("id", ""))] = str(trainer_def.get("display_name", ""))
	
	var factory = RuleFactory.new(_formatter)
	for rule in factory.build_all(definitions):
		_advisor.register_rule(rule)
	
	# Trainer-independent reminders (empty trainer id applies to every trainer).
	for rule in factory.build_trainer({"id": "", "rules": TrainerCatalog.GLOBAL_RULES}):
		_advisor.register_rule(rule)


func _setup_reminder_panel() -> void:
	var ReminderLabel = load(_base_dir().path_join("hud/reminder_label.gd"))
	
	_reminder_layer = CanvasLayer.new()
	_reminder_layer.layer = 100  # Above game UI but below debug overlays
	_reminder_layer.name = "CreatureComforts_Reminders"
	add_child(_reminder_layer)
	
	_reminder_label = ReminderLabel.new()
	_reminder_label.name = "ReminderLabel"
	_reminder_layer.add_child(_reminder_label)
	
	# Bottom-center income readout; the reminder layer's shop gate controls visibility.
	var ShopIncomePanel = load(_base_dir().path_join("hud/shop_income_panel.gd"))
	_shop_income_panel = ShopIncomePanel.new()
	_shop_income_panel.name = "ShopIncomePanel"
	_reminder_layer.add_child(_shop_income_panel)

	# Left-aligned trinket reminders ~10% down the screen; shop-gated. Added after the label
	# so it draws on top while visible.
	var TrinketRemindersPanel = load(_base_dir().path_join("hud/trinket_reminders_panel.gd"))
	_trinket_reminders_panel = TrinketRemindersPanel.new()
	_trinket_reminders_panel.name = "TrinketRemindersPanel"
	_trinket_reminders_panel.layout_debug.connect(_on_trinket_panel_layout_debug)
	_reminder_layer.add_child(_trinket_reminders_panel)

	var RankOddsPanel = load(_base_dir().path_join("hud/rank_odds_panel.gd"))
	_rank_odds_panel = RankOddsPanel.new()
	_rank_odds_panel.name = "RankOddsPanel"
	_rank_odds_panel.log_line.connect(_logger.log_event)
	_rank_odds_panel.popup_visibility_changed.connect(_on_rank_odds_popup_visibility_changed)
	_reminder_layer.add_child(_rank_odds_panel)

	# Watchlist button + popup; shop-gated with the rest of the reminder layer.
	var WatchlistPanel = load(_base_dir().path_join("hud/watchlist_panel.gd"))
	_watchlist_panel = WatchlistPanel.new()
	_watchlist_panel.name = "WatchlistPanel"
	_watchlist_panel.setup(_formatter, _sounds_enabled)
	_reminder_layer.add_child(_watchlist_panel)


## Node-attached shop highlighting. Shares the watchlist panel's selection
## dictionary by reference, so selection changes apply on the next frame.
func _setup_shop_highlight() -> void:
	_shop_highlight = ShopHighlight.new()
	_shop_highlight.name = "ShopHighlight"
	add_child(_shop_highlight)
	_shop_highlight.setup(_watchlist_panel.selection)
	var enabled := _feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS)
	_shop_highlight.set_enabled(enabled)
	_watchlist_panel.visible = enabled


func _setup_shop_overlay_gate() -> void:
	var ShopOverlayGate = load(_base_dir().path_join("hud/shop_overlay_gate.gd"))
	_shop_overlay_gate = ShopOverlayGate.new()
	_shop_overlay_gate.name = "ShopOverlayGate"
	add_child(_shop_overlay_gate)
	_shop_overlay_gate.visibility_changed.connect(_on_shop_visibility_changed)
	_shop_overlay_gate.setup(NodeUtils.has_property, NodeUtils.script_is)


func _on_shop_visibility_changed(allowed: bool, _reason: String) -> void:
	if _reminder_layer == null:
		return
	_reminder_layer.visible = allowed
	if allowed:
		_try_play_chime()
	elif _watchlist_panel != null:
		# The layer is hidden, so a still-open popup would reappear on the next
		# shop visit. Close it with the rest of the shop UI.
		_watchlist_panel.close_popup()


## The rank-odds popup is a full-screen modal drawn by a sibling panel. The
## watchlist panel is added after it, so its button would otherwise float above
## the dim layer. Hide the watchlist while the rank-odds popup is open.
func _on_rank_odds_popup_visibility_changed(open: bool) -> void:
	_rank_odds_popup_open = open
	if _watchlist_panel == null:
		return
	_watchlist_panel.visible = not open and _feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS)


func _on_trinket_panel_layout_debug(message: String) -> void:
	if not _logger.debug_logging:
		return
	for line in message.split("\n"):
		_logger.log_message(line)


func _setup_player_hud() -> void:
	var PlayerHud = load(_base_dir().path_join("hud/player_hud.gd"))
	
	var layer := CanvasLayer.new()
	layer.layer = 110  # Above game UI, matching NP_QoL's HUD layer
	layer.name = "CreatureComforts_PlayerHud"
	add_child(layer)
	
	_player_hud = PlayerHud.new()
	_player_hud.name = "PlayerHud"
	layer.add_child(_player_hud)


func _setup_results_panel() -> void:
	# Separate layer from _reminder_layer: the overlay gate hides reminders outside the
	# shop, but the trinket panel must be visible after battles (over the results screen).
	_results_layer = CanvasLayer.new()
	_results_layer.layer = 100
	_results_layer.name = "CreatureComforts_Results"
	add_child(_results_layer)
	
	var TrinketPanel = load(_base_dir().path_join("hud/trinket_panel.gd"))
	_trinket_panel = TrinketPanel.new()
	_trinket_panel.name = "TrinketPanel"
	_results_layer.add_child(_trinket_panel)


## Every sound the mod plays (reminders and UI feedback) is gated by the same
## setting, so one toggle mutes all of them.
func _sounds_enabled() -> bool:
	return _feature_enabled(ModConfig.KEY_NOTIFICATION_SOUNDS)


func _setup_notification_sounds() -> void:
	_pika_sound = UiSound.new()
	_pika_sound.setup(self, "pika.ogg", _sounds_enabled)
	_poke_sound = UiSound.new()
	_poke_sound.setup(self, "poke_item_found.ogg", _sounds_enabled)


## Apply a live settings change. Disabling a feature hides its UI immediately and
## drops any queued sound; enabling lets the next poll re-show it. Panels are
## created once at startup, so toggling never duplicates UI or subscriptions.
func _on_feature_toggled(key: String, value: bool) -> void:
	# Shop highlighting has no poll-driven re-show, so handle both states here.
	if key == ModConfig.KEY_SHOP_HIGHLIGHTS:
		if _shop_highlight != null:
			_shop_highlight.set_enabled(value)
		if _watchlist_panel != null:
			_watchlist_panel.visible = value and not _rank_odds_popup_open
			if not value:
				_watchlist_panel.close_popup()
		return
	if value:
		return
	if key == ModConfig.KEY_DAY_REMINDERS:
		if _reminder_label != null:
			_reminder_label.hide_all_reminders()
		_last_reminder_rule_ids.clear()
		_pending_chime_rule_ids.clear()
	elif key == ModConfig.KEY_TRINKET_REMINDERS:
		if _trinket_reminders_panel != null:
			_trinket_reminders_panel.hide_panel()
		_pending_trinket_reminder_sound = false
	elif key == ModConfig.KEY_NOTIFICATION_SOUNDS:
		_pending_chime_rule_ids.clear()
		_pending_trinket_reminder_sound = false
	elif key == ModConfig.KEY_BATTLE_STATUS_PANEL:
		if _player_hud != null:
			_player_hud.visible = false
	elif key == ModConfig.KEY_TRINKETS_GAINED_PANEL:
		_hide_trinket_panel()
	elif key == ModConfig.KEY_SHOP_INCOME:
		if _shop_income_panel != null:
			_shop_income_panel.hide_panel()
	elif key == ModConfig.KEY_RANK_ODDS_PREVIEW:
		if _rank_odds_panel != null:
			_rank_odds_panel.hide_panel()


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
	_update_player_hud(state, is_battle)
	# Defensive fallback: the income and trinket-reminder panels are normally hidden by the
	# reminder layer's shop gate, but hide them directly whenever the shop is not the current phase.
	if not NodeUtils.script_is(state, SHOP_SCRIPT):
		if _shop_income_panel != null:
			_shop_income_panel.hide_panel()
		if _trinket_reminders_panel != null:
			_trinket_reminders_panel.hide_panel()
		if _rank_odds_panel != null:
			_rank_odds_panel.hide_panel()
		if _watchlist_panel != null:
			_watchlist_panel.close_popup()
	if not is_battle:
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _last_phase == "battle":
			_battle_completion.reset()
		_finalize_battle_trinket_tracking()
		# Keep a rolling "last state outside battle" snapshot. The battle is simulated before the
		# first poll sees the battle state, so this is the only reliable pre-battle baseline.
		var pre_run = _get_run_data()
		if pre_run != null and is_instance_valid(pre_run):
			_pre_battle_trinket_state = _capture_trinket_state(pre_run)
	
	if NodeUtils.script_is(state, SHOP_SCRIPT):
		_handle_shop_phase(state)
	elif is_battle:
		_handle_battle_phase(state)
	else:
		if _last_phase != "":
			_last_phase = ""
			_battle_logged = false
			_reset_transient_state(true, true, true)  # Drop stale chimes when leaving the shop


func _update_player_hud(state, is_battle: bool) -> void:
	if _player_hud == null:
		return
	if not _feature_enabled(ModConfig.KEY_BATTLE_STATUS_PANEL):
		_player_hud.visible = false
		return
	if not is_battle:
		_player_hud.visible = false
		return
	
	var player_run = state.get("_replay_p1_data") if NodeUtils.has_property(state, "_replay_p1_data") else null
	if player_run == null:
		_player_hud.visible = false
		return
	
	_player_hud.update_stats(_build_player_stats(player_run))
	var is_active: bool = state.get("is_battle_active") if NodeUtils.has_property(state, "is_battle_active") else false
	_player_hud.visible = is_active


func _build_player_stats(player_run) -> Dictionary:
	var stats := {
		"hp": "?",
		"wins": "?",
		"day": "?",
	}
	
	for pair in [
		["hp", "lives"],
		["wins", "current_wins"],
		["day", "current_round"],
	]:
		var value = player_run.get(pair[1])
		if value != null:
			stats[pair[0]] = str(value)
	
	return stats


func _evaluate_trainer_advice(snapshot) -> void:
	if _advisor == null or _advice_context_builder == null:
		return
	
	var context = _advice_context_builder.from_snapshot(snapshot)
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
		if advice.get("chime", false) and _feature_enabled(ModConfig.KEY_DAY_REMINDERS):
			_pending_chime_rule_ids[advice.get("rule_id", "")] = true
			_logger.log_event("DAY REMINDER | %s | %s" % [advice.get("rule_id", ""), message])
	
	if _reminder_label != null and _feature_enabled(ModConfig.KEY_DAY_REMINDERS):
		var reminders_to_show: Dictionary = {}
		
		for advice in all_active:
			var display: String = advice.get("display", TrainerRules.BaseRule.DISPLAY_NONE)
			if display == TrainerRules.BaseRule.DISPLAY_LABEL or display == TrainerRules.BaseRule.DISPLAY_BOTH:
				var reminder_text: String = advice.get("reminder", "")
				if not reminder_text.is_empty():
					reminders_to_show[advice.get("rule_id", "")] = reminder_text
		
		# Replace all reminders at once (single update, single render)
		_reminder_label.set_reminders(reminders_to_show)
		_log_reminder_changes(reminders_to_show)
	
	_try_play_chime()


func _log_reminder_changes(reminders: Dictionary) -> void:
	var current := {}
	for rule_id in reminders.keys():
		current[rule_id] = "%s | %s" % [rule_id, str(reminders[rule_id])]
	_logger.log_keyed_changes("REMINDER", _last_reminder_rule_ids, current)
	_last_reminder_rule_ids = current


func _try_play_chime() -> void:
	if _pending_chime_rule_ids.is_empty() and not _pending_trinket_reminder_sound:
		return
	if _shop_overlay_gate == null or _shop_overlay_gate.is_allowed():
		if not _pending_chime_rule_ids.is_empty():
			if _pika_sound != null:
				_pika_sound.play()
			_pending_chime_rule_ids.clear()
		if _pending_trinket_reminder_sound:
			if _poke_sound != null:
				_poke_sound.play()
			_pending_trinket_reminder_sound = false


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
		if _shop_overlay_gate != null:
			_shop_overlay_gate.reset_for_shop()
		_log_phase_entry("SHOP", run, manager)
		_diagnostics.on_shop_entered(state)
		if _logger.deep_inspection:
			_logger.log_lines(_formatter.format_deep_inspect_shop(manager))
		# Trinket gains are battle-scoped now (tracked during the battle state only), so no
		# shop-to-shop inventory diff happens here; the trinket panel shows on the results screen.
		_reset_transient_state(true, false, false)  # Reset suppression for new shop visit
		if _rank_odds_panel != null:
			_rank_odds_panel.reset_for_shop()
	elif _last_snapshot != null and _logger.deep_inspection:
		# Full snapshot diffs are troubleshooting detail, not regular event logging.
		var comparison = _changes_comparer.compare(_last_snapshot, current_snapshot)
		if comparison.has_changes():
			_logger.log_lines(_formatter.format_snapshot_changes(comparison, run, manager, _logger.debug_logging))
	
	if trainer_changed:
		if _advisor != null:
			_advisor.reset_suppression()
		_finalize_battle_trinket_tracking(false)  # Prevent false gains/panel from a previous run
		if _trinket_reminders_panel != null:
			_trinket_reminders_panel.reset_collapsed()
		_trinket_reminders_alerted = false
		_last_trinket_reminder_entries.clear()
		_last_reminder_rule_ids.clear()
		_pending_trinket_reminder_sound = false
	
	_evaluate_trainer_advice(current_snapshot)
	
	_update_shop_income(run)
	_update_trinket_reminders(run)
	_update_rank_odds(run)

	# (overlay visibility is handled every frame by the shop overlay gate)
	
	_last_phase = "shop"
	_last_snapshot = current_snapshot


func _compute_daily_income(run) -> int:
	var day := int(run.get("current_round")) if NodeUtils.has_property(run, "current_round") else 1
	var passive_gains: Array = []
	if NodeUtils.has_property(run, "_active_passives"):
		var passives = run.get("_active_passives")
		if passives is Array:
			for passive in passives:
				if passive != null and is_instance_valid(passive) and NodeUtils.has_property(passive, "gold_gain"):
					passive_gains.append(int(passive.get("gold_gain")))
	return ShopIncome.compute(day, passive_gains)


func _update_shop_income(run) -> void:
	if _shop_income_panel == null:
		return
	if not _feature_enabled(ModConfig.KEY_SHOP_INCOME):
		_shop_income_panel.hide_panel()
		return
	_shop_income_panel.set_income(_compute_daily_income(run))


func _update_rank_odds(run) -> void:
	if _rank_odds_panel == null:
		return
	if not _feature_enabled(ModConfig.KEY_RANK_ODDS_PREVIEW):
		_rank_odds_panel.hide_panel()
		return
	var rank := int(run.get("shop_rank")) if NodeUtils.has_property(run, "shop_rank") else 1
	_rank_odds_panel.set_rank(rank)


## Refresh the top-left trinket reminders from the player's held one-shot trinkets.
## Runs every shop poll, so gained/consumed/sold trinkets update immediately. The reminder
## label stays visible at the top; the panel sits below it.
func _update_trinket_reminders(run) -> void:
	if _trinket_reminders_panel == null:
		return
	if not _feature_enabled(ModConfig.KEY_TRINKET_REMINDERS):
		_trinket_reminders_panel.hide_panel()
		_pending_trinket_reminder_sound = false
		return

	# Accept any iterable (Array or PackedStringArray), matching _capture_trinket_state.
	var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	if held == null:
		held = []

	var entries: Array = TrackedTrinkets.build_entries(held, _formatter.format_trinket_name)

	if entries.is_empty():
		# Zero reminders: hide and reset to collapsed so a later regain starts collapsed.
		_trinket_reminders_panel.reset_collapsed()
		_trinket_reminders_alerted = false  # A later regain re-triggers the alert
		_pending_trinket_reminder_sound = false  # Nothing left to announce
		_log_trinket_reminder_changes(entries)
		return

	_trinket_reminders_panel.show_reminders(entries)
	_log_trinket_reminder_changes(entries)
	# First appearance, or first after the list was cleared: chime once. The panel stays
	# collapsed; the player expands it manually.
	if not _trinket_reminders_alerted:
		_trinket_reminders_alerted = true
		_pending_trinket_reminder_sound = true
		_try_play_chime()


func _log_trinket_reminder_changes(entries: Array) -> void:
	var current := {}
	for entry in entries:
		var name := str(entry.get("name", ""))
		current[name] = "%s x%d" % [name, int(entry.get("count", 1))]
	_logger.log_keyed_changes("TRINKET REMINDER", _last_trinket_reminder_entries, current)
	_last_trinket_reminder_entries = current


func _handle_battle_phase(state) -> void:
	# Battle completion detection (win/loss/draw) - independent of replay logging
	_check_battle_completion(state)
	
	var player = state.get("_replay_p1_data") if NodeUtils.has_property(state, "_replay_p1_data") else null
	var opponent = state.get("_replay_p2_data") if NodeUtils.has_property(state, "_replay_p2_data") else null
	
	if player == null or opponent == null:
		return
	
	# Only log once per battle when battle is actually active
	var is_active: bool = state.get("is_battle_active") if NodeUtils.has_property(state, "is_battle_active") else false
	
	if not _battle_logged and is_active:
		_log_phase_entry("BATTLE", player)
		
		if _logger.deep_inspection:
			_logger.log_lines(_formatter.format_deep_inspect_battle(state, player, opponent))
			_logger.log_lines(_formatter.format_battle_trinket_state(_get_run_data()))
		
		# Battle-scoped trinket baseline. The fight is simulated before our first poll sees the
		# battle state, so prefer the last snapshot taken OUTSIDE battle (shop/event); only fall
		# back to the current inventory when no pre-battle snapshot exists (e.g. mod reload mid-run).
		if _pre_battle_trinket_state != null:
			_battle_trinket_start = _pre_battle_trinket_state
		else:
			_battle_trinket_start = _capture_trinket_state(_get_run_data())
		# Provisional end = current; it is frozen the first time battle_over is observed.
		_battle_trinket_end = _capture_trinket_state(_get_run_data())
		_battle_trinket_tracking = true
		_battle_over_seen = false
		_battle_gains_logged = false
		
		_battle_logged = true
	
	# Freeze the battle-end snapshot the FIRST time battle_over is observed. The game pre-computes
	# the following event's rewards during the results screen, applying them to run.trinket_ids
	# before the event UI appears; continuing to refresh the end snapshot would leak those future
	# event trinkets into the battle diff. The panel itself is displayed later, when the battle
	# state ends (see _finalize_battle_trinket_tracking).
	if _battle_trinket_tracking:
		if not _battle_over_seen and BattleMonitor.is_over(state):
			var run = _get_run_data()
			if run != null and is_instance_valid(run):
				_battle_trinket_end = _capture_trinket_state(run)
			_battle_over_seen = true
	
	# Reset transient overlay/suppression state on battle entry (not every poll)
	if _last_phase != "battle":
		_reset_transient_state(false, true, true)
	_last_phase = "battle"


func _check_battle_completion(state) -> void:
	if not _battle_completion.check(state):
		return
	var sim = state.get("simulation") if NodeUtils.has_property(state, "simulation") else null
	var battle_data = sim.get("data") if sim != null and NodeUtils.has_property(sim, "data") else null
	_log_battle_result(battle_data)


func _log_battle_result(battle_data) -> void:
	var info := BattleMonitor.classify(battle_data)
	if info["hp"] == null:
		if str(info["detail"]).is_empty():
			_logger.log_event("BATTLE COMPLETE | %s" % info["result"])
		else:
			_logger.log_event("BATTLE COMPLETE | %s | %s" % [info["result"], info["detail"]])
		return
	_logger.log_event("BATTLE COMPLETE | %s | HP %d" % [info["result"], info["hp"]])


func _capture_trinket_state(run) -> Dictionary:
	var snapshot := {}
	var ids = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	# Copy the lists so the battle_over snapshot stays frozen if the game mutates the live data.
	snapshot["trinket_ids"] = ids.duplicate() if ids != null else []
	snapshot["trinkets_gained_total"] = int(run.get("trinkets_gained_total")) if NodeUtils.has_property(run, "trinkets_gained_total") else 0
	var used = run.get("used_trinket_ids") if NodeUtils.has_property(run, "used_trinket_ids") else []
	snapshot["used_trinket_ids"] = used.duplicate() if used != null else []
	return snapshot


func _update_trinket_panel(gains: Dictionary) -> bool:
	if _trinket_panel == null:
		return false
	if not _feature_enabled(ModConfig.KEY_TRINKETS_GAINED_PANEL):
		_hide_trinket_panel()
		return false
	var shown_ids: Array = TrinketGains.displayable_ids(gains.get("ids", []), JUNK_TRINKET_ID)
	if shown_ids.is_empty():
		_hide_trinket_panel()
		return false
	_trinket_panel.show_gains(_summarize_trinket_gains(shown_ids))
	return true


func _hide_trinket_panel() -> void:
	if _trinket_panel != null:
		_trinket_panel.hide_panel()


func _summarize_trinket_gains(ids: Array) -> Array:
	var counts := {}
	for tid in ids:
		var key := str(tid)
		counts[key] = counts.get(key, 0) + 1
	
	var entries: Array = []
	for tid in counts.keys():
		var name: String = _formatter.format_trinket_name(tid)
		entries.append({"name": name, "count": int(counts[tid])})
	
	return entries


## Stop battle trinket tracking. Called when leaving the battle state and on trainer/run changes.
## Gains are always logged once. The panel shows mid-combat gains for any result. Gift content from
## a consumed Locked Box / Mysterious Chest is applied after the frozen battle_over snapshot, so it
## never appears in the ids diff and cannot be spoiled; legitimate gains are still shown.
## _update_trinket_panel() filters junk.
func _finalize_battle_trinket_tracking(show_panel := true) -> void:
	if not _battle_trinket_tracking and _battle_trinket_start == null:
		return
	var panel_updated := false

	# Use the frozen battle_over snapshot only; do NOT re-read the live inventory here because the
	# game may already have applied the following event's rewards.
	if _battle_trinket_start != null and _battle_trinket_end != null and _battle_over_seen:
		var run = _get_run_data()
		if run != null and is_instance_valid(run):
			var gains := TrinketGains.diff_states(_battle_trinket_start, _battle_trinket_end)
			if not _battle_gains_logged and (not gains["ids"].is_empty() or int(gains["counter"]) != 0):
				_battle_gains_logged = true
				for tid in gains["ids"]:
					_logger.log_event("TRINKET ACQUIRED | %s" % str(tid))
				if _logger.deep_inspection:
					_logger.log_lines(_formatter.format_battle_trinket_gains(gains))
			if _logger.deep_inspection:
				# Diagnostic: changes applied after the freeze (e.g. event rewards) are excluded.
				var live := _capture_trinket_state(run)
				var post := TrinketGains.diff_states(_battle_trinket_end, live)
				if not post["ids"].is_empty():
					_logger.log_message("BATTLE TRINKET GAINS | excluded post-battle additions: %s" % str(post["ids"]))
			if show_panel:
				# Gift content is applied after the frozen battle_over snapshot, so it never
				# appears in the ids diff. Show the legitimate gains; the panel hides itself
				# when nothing non-junk remains.
				if _logger.deep_inspection and TrinketGains.has_gift_trinket(gains["newly_used"]):
					_logger.log_message("BATTLE TRINKET GAINS | gift pending (%s), %d trinket(s) withheld; showing %d gained" % [
						str(gains["newly_used"]), TrinketGains.withheld_count(gains), gains["ids"].size()
					])
				panel_updated = _update_trinket_panel(gains)

	if not panel_updated:
		_hide_trinket_panel()

	_battle_trinket_start = null
	_battle_trinket_end = null
	_battle_trinket_tracking = false
	_battle_over_seen = false
	_battle_gains_logged = false


func _reset_transient_state(clear_suppression: bool, clear_reminders: bool, clear_chimes: bool) -> void:
	if clear_reminders:
		if _reminder_label != null:
			_reminder_label.hide_all_reminders()
		_last_reminder_rule_ids.clear()
		# Trinket panel lives on the results layer and is shown when leaving the battle
		# state by _finalize_battle_trinket_tracking (not on the results screen), so this
		# reset leaves it alone.
	if clear_chimes:
		_pending_chime_rule_ids.clear()
		_pending_trinket_reminder_sound = false
	if clear_suppression and _advisor != null:
		_advisor.reset_suppression()


func _log_phase_entry(phase: String, run, manager = null) -> void:
	_logger.log_event(_formatter.format_phase_entry(phase, run))
	if _logger.deep_inspection:
		_logger.log_lines(_formatter.format_phase_snapshot(phase, run, manager))


func _base_dir() -> String:
	return str(get_script().resource_path).get_base_dir()


func _get_run_data():
	return RunData.get_run_data()


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
