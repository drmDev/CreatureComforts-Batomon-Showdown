extends Node
## Creature Comforts - Trainer Advice System
## Inspects game state objects during Shop and Battle phases with configurable detail levels.

const VERSION := "0.9024"
const MOD_ID := "creature_comforts"
const MOD_ID_OLD := "np_brainrot"  # Legacy ID for settings migration (one-time)
const OUTPUT_DIR := "user://creature_comforts"
const LOG_FILE := "inspect.log"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

# Polling and state tracking
const POLL_INTERVAL_MS := 500

# Battle result labels (from simulation.data.player_health)
const BATTLE_RESULT_VICTORY := "VICTORY"

# Advice display modes come from trainer_rules.gd BaseRule (single source)
const TrainerRules = preload("advice/trainer_rules.gd")

# Shop card highlight overlay (outlines shop cards matching active highlight-mode advice)
var _shop_highlight = null

# Overlay gate: hides reminders/highlights while the shop is not on screen or not interactive
const GATE_NOT_SHOP := "not in shop"
const GATE_SETTLING := "shop settling after transition"
const GATE_SEARCH := "opponent search (CancelButton visible)"
const GATE_BATTLE_STARTING := "battle starting (BattleButton hidden)"
const SHOP_SETTLE_MS := 1200  # Overlay stays hidden this long after the shop state appears (transition fade-in)

var _overlay_gate_reason := ""
var _shop_since_ms := 0  # When the current shop state first appeared (0 = not in shop)

var _next_poll := 0
var _last_phase := ""
var _last_snapshot = null  # ShopSnapshot from previous poll
var _battle_logged := false

# Battle-scoped trinket gains.
# IMPORTANT: this is an autobattler - the whole fight is simulated before the mod's 500ms poll
# first sees the battle state, so the first battle poll already contains the battle-granted
# trinkets. We therefore keep a rolling snapshot of the last NON-battle state (shop/event) and use
# it as the "before battle" baseline. The end snapshot is frozen at battle_over.
#
# The panel is shown only after the battle state ends AND only for a VICTORY, never on the results
# screen. The game applies battle-end trinket effects (Locked Box, Mysterious Chest) to
# run.trinket_ids during the battle simulation, before battle_over is observable, so those gifts are
# already in the battle snapshot and cannot be separated from real gains by timing. They only fire
# on a defeat, so suppress the panel for non-victories; gains are still logged. The snapshot stays
# frozen at battle_over so later event rewards never leak into the diff.
var _pre_battle_trinket_state = null  # Dictionary: last trinket inventory seen outside battle
var _battle_trinket_start = null      # Dictionary: baseline used for the current battle
var _battle_trinket_end = null        # Dictionary: trinket inventory frozen at battle_over
var _battle_trinket_tracking := false
var _battle_over_seen := false     # battle_over observed; end snapshot is frozen at this point
var _battle_gains_logged := false  # Battle gains already logged this battle
var _battle_result := ""           # VICTORY / DEFEAT / DRAW / UNKNOWN for the tracked battle
var _initialization_started := false
var _initialized := false

# Settings (defaults match mod.json)
var _debug_logging := true
var _deep_inspection := true
var _achievement_notifications := false
var _settings_load_attempted := false
var _settings_warning_shown := false

# Logging
var _log_path := ""
var _formatter = null

# Trainer advice system
var _advisor = null
var _advice_context_builder = null

# Snapshot system
var _snapshot_builder = null
var _changes_comparer = null

# Reminder label system (compact top-bar)
var _reminder_label = null
var _reminder_layer: CanvasLayer = null
var _pika_player: AudioStreamPlayer = null

# Chime queue: rule_ids whose day reminder fired since the last play
var _pending_chime_rule_ids: Dictionary = {}

# Trainer display names (built from the trainer catalog)
var _trainer_display_names: Dictionary = {}

# Trinket gain panel (right-center, auto-hides after 5s)
var _trinket_panel = null

# Shop income panel (near bottom-center, shop-only, shows daily income)
var _shop_income_panel = null

# Daily income schedule (user-verified: Day 1 base income is 35, +5 per day).
# Trinket/passive gold_gain bonuses are added on top.
const BASE_INCOME := 35
const INCOME_PER_DAY := 5

# Player HUD (battle-only HP / Wins / Day line, ported from NP_QoL)
var _player_hud = null
var _player_hud_layer: CanvasLayer = null

# Achievement system: poll-based detection + JSON persistence + bottom-right panel
var _battle_completion = null
var _achievement_evaluator = null
var _achievement_store = null
var _achievement_panel = null
var _achievement_layer: CanvasLayer = null


func mod_ready() -> void:
	_initialize_mod()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_loaded_by_mod_loader():
		_initialize_mod()


func _load_settings() -> void:
	if not is_inside_tree():
		return
	
	if _settings_load_attempted:
		return
	
	var mod_loader = get_node_or_null("/root/ModLoader")
	if mod_loader == null:
		return
	
	_settings_load_attempted = true
	
	if mod_loader.has_method("get_config"):
		# Try loading from the new mod ID first
		_debug_logging = mod_loader.get_config(MOD_ID, "debug_logging", true)
		_deep_inspection = mod_loader.get_config(MOD_ID, "deep_inspection", true)
		_achievement_notifications = mod_loader.get_config(MOD_ID, "achievement_notifications", false)
		
		# One-time migration: if settings under the old mod ID exist, prefer them
		# and save them under the new ID.
		var old_debug = mod_loader.get_config(MOD_ID_OLD, "debug_logging", true)
		var old_deep = mod_loader.get_config(MOD_ID_OLD, "deep_inspection", true)
		var old_achievement = mod_loader.get_config(MOD_ID_OLD, "achievement_notifications", false)
		
		var needs_migration := false
		if _debug_logging != old_debug:
			_debug_logging = old_debug
			needs_migration = true
		if _deep_inspection != old_deep:
			_deep_inspection = old_deep
			needs_migration = true
		if _achievement_notifications != old_achievement:
			_achievement_notifications = old_achievement
			needs_migration = true
		
		if needs_migration and mod_loader.has_method("set_config"):
			mod_loader.set_config(MOD_ID, "debug_logging", _debug_logging)
			mod_loader.set_config(MOD_ID, "deep_inspection", _deep_inspection)
			mod_loader.set_config(MOD_ID, "achievement_notifications", _achievement_notifications)
			print("Creature Comforts: migrated settings from '%s' to '%s'" % [MOD_ID_OLD, MOD_ID])
		
		# Connect to config_changed signal for live updates
		if mod_loader.has_signal("config_changed") and not mod_loader.is_connected("config_changed", _on_config_changed):
			mod_loader.connect("config_changed", _on_config_changed)
	elif not _settings_warning_shown:
		# Fallback if ModLoader doesn't support config API - keep defaults
		_settings_warning_shown = true
		push_warning("Creature Comforts: ModLoader.get_config() not available, using defaults")


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	
	# Load settings if not already loaded
	_load_settings()
	
	# Create formatter
	var LogFormatter = load("res://mods/CreatureComforts/core/log_formatter.gd")
	_formatter = LogFormatter.new(_has_property)
	
	# Create snapshot builder
	var ShopSnapshot = load("res://mods/CreatureComforts/core/shop_snapshot.gd")
	_snapshot_builder = ShopSnapshot.new()
	
	# Create changes comparer
	var ShopChanges = load("res://mods/CreatureComforts/core/shop_changes.gd")
	_changes_comparer = ShopChanges.new()
	
	# Create advisor and register rules
	_setup_advisor()
	
	# Create reminder label system
	_setup_reminder_panel()
	
	# Create battle player HUD
	_setup_player_hud()
	
	# Create achievement panel system (Phase 1)
	_setup_achievement_panel()
	
	# Setup notification sound
	_setup_pika_sound()
	
	# Create output directory
	var dir_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_error("Creature Comforts: Failed to create directory %s: %s" % [dir_path, error_string(dir_result)])
		return
	
	_log_path = OUTPUT_DIR.path_join(LOG_FILE)
	var abs_log_path := ProjectSettings.globalize_path(_log_path)
	
	# Create log file if it doesn't exist
	if not FileAccess.file_exists(_log_path):
		var file := FileAccess.open(_log_path, FileAccess.WRITE)
		if file == null:
			push_error("Creature Comforts: Cannot create log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
			return
		file.close()
	
	_initialized = true
	
	_log_message("=".repeat(80))
	_log_message("Creature Comforts %s - Trainer Advice System" % VERSION)
	_log_message("Initialized at %s" % _formatter.get_timestamp())
	_log_message("Settings: Debug Logging: %s | Deep Inspection: %s | Achievement Notifications: %s" % [_debug_logging, _deep_inspection, _achievement_notifications])
	_log_message("Log file: %s" % abs_log_path)
	_log_message("=".repeat(80))
	
	print("Creature Comforts %s loaded - logging to %s" % [VERSION, abs_log_path])


func _on_config_changed(mod_id: String, key: String, value) -> void:
	"""Handle live config changes from ModLoader."""
	# Accept both old and new mod IDs during the migration window
	if mod_id != MOD_ID and mod_id != MOD_ID_OLD:
		return
	
	match key:
		"debug_logging":
			if value is bool:
				_debug_logging = value
				_log_message("Setting changed: Debug Logging = %s" % _debug_logging)
		"deep_inspection":
			if value is bool:
				_deep_inspection = value
				_log_message("Setting changed: Deep Inspection = %s" % _deep_inspection)
		"achievement_notifications":
			if value is bool:
				_achievement_notifications = value
				_log_message("Setting changed: Achievement Notifications = %s" % _achievement_notifications)
				if not _achievement_notifications and _achievement_panel != null:
					_achievement_panel.hide_panel()
func _setup_advisor() -> void:
	"""Initialize advisor and register all rules from the trainer catalog."""
	var TrainerAdvisor = load("res://mods/CreatureComforts/advice/trainer_advisor.gd")
	var TrainerCatalog = load("res://mods/CreatureComforts/advice/trainer_catalog.gd")
	var RuleFactory = load("res://mods/CreatureComforts/advice/rule_factory.gd")
	
	_advisor = TrainerAdvisor.new()
	
	# Cache AdviceContext builder (rules consume snapshot data as plain records)
	_advice_context_builder = load("res://mods/CreatureComforts/advice/advice_context.gd").new()
	
	# Build trainer display-name map and register rules from the catalog
	var definitions: Array = TrainerCatalog.TRAINER_DEFINITIONS
	for trainer_def in definitions:
		_trainer_display_names[str(trainer_def.get("id", ""))] = str(trainer_def.get("display_name", ""))
	
	var factory = RuleFactory.new(_formatter)
	for rule in factory.build_all(definitions):
		_advisor.register_rule(rule)


func _setup_reminder_panel() -> void:
	"""Initialize reminder label UI layer."""
	var ReminderLabel = load("res://mods/CreatureComforts/hud/reminder_label.gd")
	
	_reminder_layer = CanvasLayer.new()
	_reminder_layer.layer = 100  # Above game UI but below debug overlays
	_reminder_layer.name = "CreatureComforts_Reminders"
	add_child(_reminder_layer)
	
	_reminder_label = ReminderLabel.new()
	_reminder_label.name = "ReminderLabel"
	_reminder_layer.add_child(_reminder_label)
	
	var ShopHighlight = load("res://mods/CreatureComforts/hud/shop_highlight.gd")
	_shop_highlight = ShopHighlight.new()
	_shop_highlight.name = "ShopHighlight"
	_shop_highlight.setup(_resolve_highlight_rects)
	_reminder_layer.add_child(_shop_highlight)
	
	# Bottom-center income readout; the reminder layer's shop gate controls visibility.
	var ShopIncomePanel = load("res://mods/CreatureComforts/hud/shop_income_panel.gd")
	_shop_income_panel = ShopIncomePanel.new()
	_shop_income_panel.name = "ShopIncomePanel"
	_reminder_layer.add_child(_shop_income_panel)
	
func _setup_player_hud() -> void:
	"""Initialize the battle-only player HUD (HP / Wins / Day)."""
	var PlayerHud = load("res://mods/CreatureComforts/hud/player_hud.gd")
	
	_player_hud_layer = CanvasLayer.new()
	_player_hud_layer.layer = 110  # Above game UI, matching NP_QoL's HUD layer
	_player_hud_layer.name = "CreatureComforts_PlayerHud"
	add_child(_player_hud_layer)
	
	_player_hud = PlayerHud.new()
	_player_hud.name = "PlayerHud"
	_player_hud_layer.add_child(_player_hud)


func _setup_achievement_panel() -> void:
	"""Initialize the achievement detection, persistence, and panel system."""
	var BattleCompletionDetector = load("res://mods/CreatureComforts/achievements/battle_completion_detector.gd")
	_battle_completion = BattleCompletionDetector.new()
	
	var AchievementEvaluator = load("res://mods/CreatureComforts/achievements/achievement_evaluator.gd")
	_achievement_evaluator = AchievementEvaluator.new()
	
	# Pass the mod root so achievements.json stays at the mod root even though the
	# store script now lives in achievements/.
	var AchievementStore = load("res://mods/CreatureComforts/achievements/achievement_store.gd")
	_achievement_store = AchievementStore.new(str(get_script().resource_path).get_base_dir())
	
	# Separate layer from _reminder_layer: the overlay gate hides reminders outside the
	# shop, but the achievement panel must be visible after battles (over the results screen).
	_achievement_layer = CanvasLayer.new()
	_achievement_layer.layer = 100
	_achievement_layer.name = "CreatureComforts_Achievements"
	add_child(_achievement_layer)
	
	var AchievementPanel = load("res://mods/CreatureComforts/achievements/achievement_panel.gd")
	_achievement_panel = AchievementPanel.new()
	_achievement_panel.name = "AchievementPanel"
	_achievement_layer.add_child(_achievement_panel)

	# Collapsible trinket-gain panel lives on the achievement layer so it shows on the
	# battle results screen (same timing as the achievement toast), above it.
	var TrinketPanel = load("res://mods/CreatureComforts/hud/trinket_panel.gd")
	_trinket_panel = TrinketPanel.new()
	_trinket_panel.name = "TrinketPanel"
	# Route panel position/drag/toggle diagnostics into the mod log as well as the console.
	_trinket_panel.set_logger(Callable(self, "_log_message"))
	_achievement_layer.add_child(_trinket_panel)


func _setup_pika_sound() -> void:
	"""Initialize notification sound for new reminders."""
	var base_dir := str(get_script().resource_path).get_base_dir()
	var path := base_dir.path_join("assets/sounds/pika.ogg")
	
	_pika_player = AudioStreamPlayer.new()
	_pika_player.stream = AudioStreamOggVorbis.load_from_file(path)
	_pika_player.volume_db = -6.0
	add_child(_pika_player)
	
	if _pika_player.stream == null:
		push_warning("Creature Comforts: Failed to load notification sound: " + path)


func _play_pika() -> void:
	"""Play notification sound for new reminders."""
	if _pika_player != null and _pika_player.stream != null:
		_pika_player.play()


func _process(_delta: float) -> void:
	if not _initialized:
		return
	_update_overlay_gate()
	
	var now := Time.get_ticks_msec()
	if now < _next_poll:
		return
	_next_poll = now + POLL_INTERVAL_MS
	_inspect_current_phase()


func _inspect_current_phase() -> void:
	var main = get_tree().current_scene
	var state = main.get("current_state") if _has_property(main, "current_state") else null
	
	var is_battle := _script_is(state, BATTLE_SCRIPT)
	_update_player_hud(state, is_battle)
	_poll_achievements()
	if not is_battle:
		if _battle_completion != null:
			_battle_completion.reset()
		if _achievement_evaluator != null:
			_achievement_evaluator.reset_battle()
		# Leaving the battle state (event, shop, or other): stop battle trinket tracking.
		_finalize_battle_trinket_tracking()
		# Keep a rolling "last state outside battle" snapshot. The battle is simulated before the
		# first poll sees the battle state, so this is the only reliable pre-battle baseline.
		var pre_run = _get_run_data()
		if pre_run != null and is_instance_valid(pre_run):
			_pre_battle_trinket_state = _capture_trinket_state(pre_run)
	
	if _script_is(state, SHOP_SCRIPT):
		_handle_shop_phase(state)
	elif is_battle:
		_handle_battle_phase(state)
	else:
		if _last_phase != "":
			_last_phase = ""
			_battle_logged = false
			_reset_transient_state(true, true, true)  # Drop stale chimes when leaving the shop


func _update_player_hud(state, is_battle: bool) -> void:
	"""Show the player HUD only during an active battle; hide it everywhere else."""
	if _player_hud == null:
		return
	if not is_battle:
		_player_hud.visible = false
		return
	
	var player_run = state.get("_replay_p1_data") if _has_property(state, "_replay_p1_data") else null
	if player_run == null:
		_player_hud.visible = false
		return
	
	_player_hud.update_stats(_build_player_stats(player_run))
	var is_active: bool = state.get("is_battle_active") if _has_property(state, "is_battle_active") else false
	_player_hud.visible = is_active


func _build_player_stats(player_run) -> Dictionary:
	"""Read HP / Wins / Day from the battle's player run data (same fields as NP_QoL)."""
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
	"""Evaluate trainer advice using the advisor system."""
	if _advisor == null or _advice_context_builder == null:
		return
	
	# Create context from snapshot using cached builder
	var context = _advice_context_builder.from_snapshot(snapshot)
	
	# Evaluate all rules
	var result: Dictionary = _advisor.evaluate(context)
	var new_or_changed: Array = result.get("new_or_changed", [])
	var all_active: Array = result.get("all_active", [])
	
	# Emit new or changed advice to console (suppression works here)
	for advice in new_or_changed:
		var severity: String = advice.get("severity", "NOTICE")
		var message: String = advice.get("message", "")
		
		if not message.is_empty():
			# Trainers are namespaced by their own id, so no prefix inference is needed
			var prefix: String = _trainer_display_names.get(advice.get("trainer_id", ""), "")
			
			var full_message := ""
			if not prefix.is_empty():
				full_message = "*** COMFORTS %s | %s | %s" % [severity, prefix, message]
			else:
				full_message = "*** COMFORTS %s | %s" % [severity, message]
			
			_print_notice(full_message)
		
		# Queue the chime for chime-flagged rules (day reminders); played once the overlay is showing
		if advice.get("chime", false):
			_pending_chime_rule_ids[advice.get("rule_id", "")] = true
	
	# Update on-screen reminder label
	if _reminder_label != null:
		var reminders_to_show: Dictionary = {}
		
		for advice in all_active:
			var display: String = advice.get("display", TrainerRules.BaseRule.DISPLAY_NONE)
			if display == TrainerRules.BaseRule.DISPLAY_LABEL or display == TrainerRules.BaseRule.DISPLAY_BOTH:
				var reminder_text: String = advice.get("reminder", "")
				if not reminder_text.is_empty():
					reminders_to_show[advice.get("rule_id", "")] = reminder_text
		
		# Replace all reminders at once (single update, single render)
		_reminder_label.set_reminders(reminders_to_show)
	
	_try_play_chime()
	
	# Outline shop cards matching active highlight-mode advice
	_update_shop_highlights(all_active)


func _try_play_chime() -> void:
	"""Play the notification sound once, only when the overlay is on screen and a chime-flagged (day) reminder is queued."""
	if _pending_chime_rule_ids.is_empty():
		return
	if _overlay_gate_reason.is_empty():
		_play_pika()
		_pending_chime_rule_ids.clear()


func _handle_shop_phase(state) -> void:
	var run = _get_run_data()
	var manager = state.get("manager") if _has_property(state, "manager") else null
	
	if run == null or manager == null:
		return
	
	# Capture current snapshot once per poll
	var current_snapshot = _snapshot_builder.capture(run, manager, _has_property, _formatter.resolve_type_name)
	
	# Detect changes
	var phase_changed := _last_phase != "shop"
	
	# Check for trainer identity changes (not just gold/shop offers)
	var trainer_changed := false
	if _last_snapshot != null:
		trainer_changed = _last_snapshot.trainer_id != current_snapshot.trainer_id
	
	if phase_changed:
		_battle_logged = false
		_log_phase_entry("SHOP", run, manager)
		if _deep_inspection:
			_log_lines(_formatter.format_deep_inspect_shop(manager, run))
		# Trinket gains are battle-scoped now (tracked during the battle state only), so no
		# shop-to-shop inventory diff happens here; the trinket panel shows on the results screen.
		_reset_transient_state(true, false, false)  # Reset suppression + highlights for new shop visit
	elif _last_snapshot != null:
		# Compare snapshots and log changes
		var comparison = _changes_comparer.compare(_last_snapshot, current_snapshot)
		if comparison.has_changes():
			_log_lines(_formatter.format_snapshot_changes(comparison, run, manager, _debug_logging))
	
	# Reset suppression and battle trinket tracking on trainer identity changes (new run)
	if trainer_changed and _advisor != null:
		_advisor.reset_suppression()
		_finalize_battle_trinket_tracking(false)  # Prevent false gains/panel from a previous run
	
	# Evaluate trainer advice (after logging, before updating snapshot)
	_evaluate_trainer_advice(current_snapshot)
	
	_update_shop_income(run)
	
	# (overlay visibility is handled every frame by _update_overlay_gate)
	
	_last_phase = "shop"
	_last_snapshot = current_snapshot


## Current day's income: base schedule plus passive gold_gain bonuses (e.g. Gold Nugget +3).
func _compute_daily_income(run) -> int:
	var day := int(run.get("current_round")) if _has_property(run, "current_round") else 1
	var income := BASE_INCOME + INCOME_PER_DAY * maxi(day - 1, 0)
	
	if _has_property(run, "_active_passives"):
		var passives = run.get("_active_passives")
		if passives is Array:
			for passive in passives:
				if passive != null and is_instance_valid(passive) and _has_property(passive, "gold_gain"):
					income += int(passive.get("gold_gain"))
	
	return income


func _update_shop_income(run) -> void:
	"""Refresh the bottom-center income panel while the shop is active."""
	if _shop_income_panel == null:
		return
	_shop_income_panel.set_income(_compute_daily_income(run))


func _handle_battle_phase(state) -> void:
	# Battle completion detection (win/loss/draw) - independent of replay logging
	_check_battle_completion(state)
	# Battle-scoped achievements (Big Dog, Best Dog) - read from the battle simulation
	_poll_battle_achievements(state)
	
	# Check if replay data is ready
	var player = state.get("_replay_p1_data") if _has_property(state, "_replay_p1_data") else null
	var opponent = state.get("_replay_p2_data") if _has_property(state, "_replay_p2_data") else null
	
	if player == null or opponent == null:
		return
	
	# Only log once per battle when battle is actually active
	var is_active: bool = state.get("is_battle_active") if _has_property(state, "is_battle_active") else false
	
	if not _battle_logged and is_active:
		_log_phase_entry("BATTLE", player)
		
		if _deep_inspection:
			_log_lines(_formatter.format_deep_inspect_battle(state, player, opponent))
			# Trinket state at battle entry
			_log_lines(_formatter.format_battle_trinket_state(_get_run_data()))
		
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
		_battle_result = ""
		
		_battle_logged = true
	
	# Freeze the battle-end snapshot the FIRST time battle_over is observed. The game pre-computes
	# the following event's rewards during the results screen, applying them to run.trinket_ids
	# before the event UI appears; continuing to refresh the end snapshot would leak those future
	# event trinkets into the battle diff. The panel itself is displayed later, when the battle
	# state ends (see _finalize_battle_trinket_tracking).
	if _battle_trinket_tracking:
		if not _battle_over_seen and _battle_is_over(state):
			var run = _get_run_data()
			if run != null and is_instance_valid(run):
				_battle_trinket_end = _capture_trinket_state(run)
			_battle_over_seen = true
			_log_message("BATTLE TRINKET GAINS | end snapshot frozen at battle_over: %s" % str(_battle_trinket_end.get("trinket_ids", [])))
	
	# Reset transient overlay/suppression state on battle entry
	_reset_transient_state(false, true, true)
	_last_phase = "battle"


func _check_battle_completion(state) -> void:
	"""Detect battle completion once and log the result."""
	if _battle_completion == null:
		return
	if not _battle_completion.poll(state):
		return
	
	var sim = state.get("simulation") if _has_property(state, "simulation") else null
	var battle_data = sim.get("data") if sim != null and _has_property(sim, "data") else null
	
	_battle_result = _log_battle_result(battle_data)


## Poll the run for newly earned achievements, persist them, and show the panel.
## Runs every poll (the Twins transformation happens in the shop, but polling all
## phases keeps the team-state baseline current).
func _poll_achievements() -> void:
	if _achievement_evaluator == null:
		return
	var run = _get_run_data()
	if run == null or not is_instance_valid(run):
		return
	
	_award_achievements(_achievement_evaluator.poll(run))


## Poll the active battle for battle-scoped achievements (Big Dog, Best Dog).
func _poll_battle_achievements(state) -> void:
	if _achievement_evaluator == null:
		return
	var run = _get_run_data()
	if run == null or not is_instance_valid(run):
		return
	
	_award_achievements(_achievement_evaluator.poll_battle(state, run))


## Persist and display newly earned achievements (deduplicated by the store).
func _award_achievements(earned: Array) -> void:
	if _achievement_store == null or _achievement_panel == null:
		return
	for achievement in earned:
		var id := str(achievement.get("id", ""))
		if id.is_empty() or _achievement_store.is_completed(id):
			continue
		var title := str(achievement.get("title", ""))
		var description := str(achievement.get("description", ""))
		if title.is_empty() or description.is_empty():
			continue
		
		_achievement_store.mark_completed(id)
		_log_message("ACHIEVEMENT EARNED | %s | %s" % [id, title])
		if _achievement_notifications:
			_achievement_panel.show_achievement(title, description)
		else:
			_log_message("ACHIEVEMENT NOTIFICATION | suppressed (Achievement Notifications off)")


## Log how the battle ended and return the result label.
func _log_battle_result(battle_data) -> String:
	if battle_data == null:
		_log_message("BATTLE COMPLETE | result=UNKNOWN")
		return "UNKNOWN"
	
	var player_health = battle_data.get("player_health")
	if player_health == null or player_health.size() < 2:
		_log_message("BATTLE COMPLETE | result=UNKNOWN | player_health unavailable")
		return "UNKNOWN"
	
	var player_hp := int(player_health[0])
	var enemy_hp := int(player_health[1])
	
	var result := "DRAW"
	if player_hp > 0 and enemy_hp <= 0:
		result = BATTLE_RESULT_VICTORY
	elif player_hp <= 0 and enemy_hp > 0:
		result = "DEFEAT"
	_log_message("BATTLE COMPLETE | result=%s | player_hp=%d enemy_hp=%d" % [result, player_hp, enemy_hp])
	return result


const JUNK_TRINKET_ID := "junk"  # Verified in runtime log: trinket_ids contain "junk"


## Capture the trinket inventory (ids + gained counter) as a plain snapshot dict.
func _capture_trinket_state(run) -> Dictionary:
	var snapshot := {}
	snapshot["trinket_ids"] = run.get("trinket_ids") if _has_property(run, "trinket_ids") else []
	snapshot["trinkets_gained_total"] = int(run.get("trinkets_gained_total")) if _has_property(run, "trinkets_gained_total") else 0
	return snapshot


## Diff trinkets gained between two captured states (inventory diff + counter delta).
## Handles duplicates via count-based matching. Returns {"ids": [], "counter": int}.
func _diff_trinket_states(before: Dictionary, after: Dictionary) -> Dictionary:
	var gained_ids: Array = []
	var counter_delta := 0

	var before_counts := {}
	for tid in before.get("trinket_ids", []):
		before_counts[tid] = before_counts.get(tid, 0) + 1

	var after_ids: Array = after.get("trinket_ids", [])
	for tid in after_ids:
		var remaining = before_counts.get(tid, 0)
		if remaining > 0:
			before_counts[tid] = remaining - 1
		else:
			gained_ids.append(tid)

	var before_total: int = int(before.get("trinkets_gained_total", 0))
	var after_total: int = int(after.get("trinkets_gained_total", 0))
	counter_delta = after_total - before_total

	return {"ids": gained_ids, "counter": counter_delta}


## Is this trinket id a Junk trinket (hidden from the player)?
func _is_junk_trinket(tid) -> bool:
	return str(tid) == JUNK_TRINKET_ID


## Update the trinket panel from a gains dict, showing only non-junk trinkets.
## Hides the panel when nothing non-junk was earned (1 or 10 junk alone => no panel).
func _update_trinket_panel(gains: Dictionary) -> void:
	if _trinket_panel == null:
		return
	var ids: Array = gains.get("ids", [])
	var shown_ids: Array = []
	for tid in ids:
		if not _is_junk_trinket(tid):
			shown_ids.append(tid)
	if shown_ids.is_empty():
		_hide_trinket_panel()
		return
	_trinket_panel.show_gains(_summarize_trinket_gains(shown_ids))


func _hide_trinket_panel() -> void:
	"""Hide the trinket gain panel."""
	if _trinket_panel != null:
		_trinket_panel.hide_panel()


func _summarize_trinket_gains(ids: Array) -> Array:
	"""Group trinket ids by count and format names. Returns Array of {name, count}."""
	var counts := {}
	for tid in ids:
		var key := str(tid)
		counts[key] = counts.get(key, 0) + 1
	
	var entries: Array = []
	for tid in counts.keys():
		var name: String = _formatter.format_trinket_name(tid)
		entries.append({"name": name, "count": int(counts[tid])})
	
	return entries


## Is the battle currently marked over (battle_over flag on simulation.data)?
func _battle_is_over(state) -> bool:
	if state == null or not is_instance_valid(state):
		return false
	var sim = state.get("simulation") if _has_property(state, "simulation") else null
	if sim == null or not is_instance_valid(sim):
		return false
	var data = sim.get("data") if _has_property(sim, "data") else null
	if data == null:
		return false
	return bool(data.get("battle_over"))


## Stop battle trinket tracking. Called when leaving the battle state and on trainer/run changes.
## Gains are always logged once. The panel is shown only for a VICTORY: defeat-triggered gift
## trinkets (Locked Box, Mysterious Chest) apply their rewards to run.trinket_ids during the
## battle simulation, so those rewards are already in the battle_over snapshot and would be
## spoiled if the panel displayed them on a defeat.
func _finalize_battle_trinket_tracking(show_panel := true) -> void:
	if not _battle_trinket_tracking and _battle_trinket_start == null:
		return
	var panel_updated := false

	# Use the frozen battle_over snapshot only; do NOT re-read the live inventory here because the
	# game may already have applied the following event's rewards.
	if _battle_trinket_start != null and _battle_trinket_end != null and _battle_over_seen:
		var run = _get_run_data()
		if run != null and is_instance_valid(run):
			var gains := _diff_trinket_states(_battle_trinket_start, _battle_trinket_end)
			if not _battle_gains_logged and (not gains["ids"].is_empty() or int(gains["counter"]) != 0):
				_battle_gains_logged = true
				_log_lines(_formatter.format_battle_trinket_gains(gains))
			# Diagnostic: changes applied after the freeze (e.g. event rewards) are excluded.
			var live := _capture_trinket_state(run)
			var post := _diff_trinket_states(_battle_trinket_end, live)
			if not post["ids"].is_empty():
				_log_message("BATTLE TRINKET GAINS | excluded post-battle additions: %s" % str(post["ids"]))
			if show_panel and _battle_result != BATTLE_RESULT_VICTORY:
				_log_message("BATTLE TRINKET GAINS | panel suppressed (result=%s)" % (_battle_result if not _battle_result.is_empty() else "UNKNOWN"))
			elif show_panel:
				# Shows only non-junk gains; hides itself when nothing eligible remains.
				_update_trinket_panel(gains)
				panel_updated = true

	if not panel_updated:
		_hide_trinket_panel()

	_battle_trinket_start = null
	_battle_trinket_end = null
	_battle_trinket_tracking = false
	_battle_over_seen = false
	_battle_gains_logged = false
	_battle_result = ""


func _update_overlay_gate() -> void:
	"""Every frame: hide the whole reminder/highlight layer unless the shop is on screen and interactive."""
	if _reminder_layer == null:
		return
	
	var reason := _compute_overlay_gate_reason()
	if reason == _overlay_gate_reason:
		return
	
	_overlay_gate_reason = reason
	_reminder_layer.visible = reason.is_empty()
	if reason.is_empty():
		_try_play_chime()


func _compute_overlay_gate_reason() -> String:
	"""Empty string = overlay allowed. Cheap checks only (runs every frame)."""
	var main = get_tree().current_scene
	if main == null:
		_shop_since_ms = 0
		return GATE_NOT_SHOP
	var state = main.get("current_state")
	if not _script_is(state, SHOP_SCRIPT):
		_shop_since_ms = 0
		return GATE_NOT_SHOP
	
	# The shop state exists before the transition has finished fading in; wait for it to settle
	var now := Time.get_ticks_msec()
	if _shop_since_ms == 0:
		_shop_since_ms = now
	if now - _shop_since_ms < SHOP_SETTLE_MS:
		return GATE_SETTLING
	
	# While searching for an opponent the shop's Cancel button replaces the Battle button
	var view = state.get("view")
	if view is Node and is_instance_valid(view):
		var cancel = view.get_node_or_null("CancelButton")
		if cancel is CanvasItem and cancel.is_visible_in_tree():
			return GATE_SEARCH
		# After the search succeeds the shop stays up while the game transitions to battle
		var battle_button = view.get_node_or_null("BattleButton")
		if battle_button is CanvasItem and not battle_button.is_visible_in_tree():
			return GATE_BATTLE_STARTING
	return ""


func _update_shop_highlights(all_active: Array) -> void:
	"""Convert active highlight-mode advice into highlight targets (slot index + offer instance id)."""
	if _shop_highlight == null:
		return
	
	var targets: Array = []
	var seen := {}
	for advice in all_active:
		var display: String = advice.get("display", TrainerRules.BaseRule.DISPLAY_NONE)
		if display != TrainerRules.BaseRule.DISPLAY_HIGHLIGHT and display != TrainerRules.BaseRule.DISPLAY_BOTH:
			continue
		var slots: Array = advice.get("matched_indices", [])
		var ids: Array = advice.get("matched_ids", [])
		for i in range(mini(slots.size(), ids.size())):
			var slot_index := int(slots[i])
			if seen.has(slot_index):
				continue
			seen[slot_index] = true
			targets.append({"slot": slot_index, "id": int(ids[i])})
	_shop_highlight.set_targets(targets)


func _clear_shop_highlights() -> void:
	if _shop_highlight != null:
		_shop_highlight.clear_targets()


func _reset_transient_state(clear_suppression: bool, clear_reminders: bool, clear_chimes: bool) -> void:
	"""Reset overlay/suppression state shared across phase transitions."""
	_clear_shop_highlights()
	if clear_reminders:
		if _reminder_label != null:
			_reminder_label.hide_all_reminders()
		# Trinket panel lives on the achievement layer and is shown when leaving the battle
		# state by _finalize_battle_trinket_tracking (not on the results screen), so this
		# reset leaves it alone.
	if clear_chimes:
		_pending_chime_rule_ids.clear()
	if clear_suppression and _advisor != null:
		_advisor.reset_suppression()


func _resolve_highlight_rects(targets: Array) -> Array:
	"""Called every frame by the overlay: current rects for cards still showing the recorded offer.
	Reads state.view.shop_slots[slot_index].current_content and compares instance ids, retaining nothing."""
	var rects: Array = []
	if targets.is_empty():
		return rects
	
	var main = get_tree().current_scene
	if main == null:
		return rects
	var state = main.get("current_state")
	if not _script_is(state, SHOP_SCRIPT):
		return rects
	
	var view = state.get("view")
	if view == null or not is_instance_valid(view) or not view is Node:
		return rects
	
	# Do not draw over the Dex overlay
	var dex = view.get_node_or_null("DexUI")
	if dex is CanvasItem and dex.is_visible_in_tree():
		return rects
	
	var slots = view.get("shop_slots")
	if not slots is Array:
		return rects
	
	for target in targets:
		var slot_index: int = target["slot"]
		if slot_index < 0 or slot_index >= slots.size():
			continue
		var slot = slots[slot_index]
		if not is_instance_valid(slot) or not slot is Control:
			continue
		if not slot.is_visible_in_tree():
			continue
		var content = slot.get("current_content")
		if typeof(content) != TYPE_OBJECT or not is_instance_valid(content):
			continue
		if content.get_instance_id() != int(target["id"]):
			continue
		rects.append(slot.get_global_rect())
	return rects


func _log_phase_entry(phase: String, run, manager = null) -> void:
	var lines: Array = _formatter.format_phase_entry(phase, run, manager, _debug_logging)
	_log_lines(lines)


func _print_notice(message: String) -> void:
	"""Print notice to console and log file."""
	print(message)
	_log_message(message)


func _log_lines(lines: Array) -> void:
	"""Log multiple lines from formatter."""
	for line in lines:
		_log_message(line)


# Utility functions

func _has_property(obj, property: String) -> bool:
	if not is_instance_valid(obj):
		return false
	for prop in obj.get_property_list():
		if str(prop.name) == property:
			return true
	return false


func _script_is(obj, script_path: String) -> bool:
	if not is_instance_valid(obj):
		return false
	var script: Script = obj.get_script()
	while script != null:
		if str(script.resource_path) == script_path:
			return true
		script = script.get_base_script()
	return false


func _get_run_data():
	"""Return RunManager.data (the run) or null."""
	var run_manager = get_node_or_null("/root/RunManager")
	if run_manager == null or not _has_property(run_manager, "data"):
		return null
	return run_manager.get("data")


func _log_message(message: String) -> void:
	if _log_path.is_empty():
		return
	
	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file == null:
		push_warning("Creature Comforts: Cannot open log file: " + error_string(FileAccess.get_open_error()))
		return
	
	file.seek_end()
	file.store_line(message)
	file.close()


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
