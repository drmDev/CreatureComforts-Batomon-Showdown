extends Node
## Creature Comforts - Trainer Advice System
## Inspects game state objects during Shop and Battle phases with configurable detail levels.

const VERSION := "0.9066"
const MOD_ID := "creature_comforts"
const OUTPUT_DIR := "user://creature_comforts"
const LOG_FILE := "inspect.log"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

# Polling and state tracking
const POLL_INTERVAL_MS := 500

# Battle result labels (from simulation.data.player_health)
const BATTLE_RESULT_VICTORY := "VICTORY"
const BATTLE_RESULT_DEFEAT := "DEFEAT"
const BATTLE_RESULT_DRAW := "DRAW"
const BATTLE_RESULT_UNKNOWN := "UNKNOWN"

# Advice display modes come from trainer_rules.gd BaseRule (single source)
const TrainerRules = preload("advice/trainer_rules.gd")
# Junk trinket id lives in the formatter (single source for the panel filter + log)
const LogFormatterScript = preload("core/log_formatter.gd")
const JUNK_TRINKET_ID := LogFormatterScript.JUNK_TRINKET_ID
# Pure battle-scoped trinket diff logic (unit-tested)
const TrinketGains = preload("core/trinket_gains.gd")
# Dev-only toggle defaults (not user-facing settings)
const DevConfig = preload("dev/dev_config.gd")

# Overlay gate: hides reminders while the shop is not on screen or not interactive
const GATE_NOT_SHOP := "not in shop"
const GATE_SETTLING := "shop settling after transition"
const GATE_SEARCH := "opponent search (CancelButton visible)"
const GATE_BATTLE_STARTING := "battle starting (BattleButton hidden)"
const GATE_OVERLAY := "ui overlay open"
const GATE_PAUSED := "game paused"
const GATE_VIEW_NOT_READY := "shop view not ready"
const GATE_VIEW_HIDDEN := "shop view hidden"
const GATE_TRANSITION := "transition hold"
const SHOP_SETTLE_MS := 1200  # Overlay stays hidden this long after the shop state appears (transition fade-in)

# Candidate overlay node names checked as direct children of the shop view and the
# main scene. Missing names are harmless. The UI diagnostics log which candidates
# exist (and their paths) so the real Settings/Batopedia node names can be confirmed.
# Confirmed modal overlay nodes (the interaction-lock check is the primary gate;
# this list is a fallback for overlays that do not set the lock).
const OVERLAY_NODE_NAMES := ["DexUI", "SettingsMenu"]

var _overlay_gate_reason := ""
var _shop_since_ms := 0  # When the current shop state first appeared (0 = not in shop)
var _gate_hold_until_ms := 0  # Transition signal hold: keep the overlay hidden until this tick
var _search_end_hold_until_ms := 0  # Brief hold after search ends, before the battle transition fires
var _view_member_cache: Dictionary = {}  # "view_id:name" -> resolved node (or null)
var _transition_nodes: Dictionary = {}  # instance ids of nodes already connected to transition_requested

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
# The panel shows mid-combat gains for any result. Gift content from a consumed Locked Box /
# Mysterious Chest is applied after the frozen battle_over snapshot, so it never appears in the
# ids diff and cannot be spoiled; legitimate gains are still shown.
# The snapshot stays frozen at battle_over so later event rewards never leak into the diff.
var _pre_battle_trinket_state = null  # Dictionary: last trinket inventory seen outside battle
var _battle_trinket_start = null      # Dictionary: baseline used for the current battle
var _battle_trinket_end = null        # Dictionary: trinket inventory frozen at battle_over
var _battle_trinket_tracking := false
var _battle_over_seen := false     # battle_over observed; end snapshot is frozen at this point
var _battle_gains_logged := false  # Battle gains already logged this battle
var _initialization_started := false
var _initialized := false

# Dev-only toggles (not user-facing settings). Startup defaults come from
# dev/dev_config.gd; flip them live with the key combos in _handle_dev_toggles().
var _debug_logging := DevConfig.DEBUG_LOGGING
var _deep_inspection := DevConfig.DEEP_INSPECTION
# Rising-edge state for the Ctrl+Shift dev toggle keys (Input has no key "just pressed" query).
var _dev_toggle_debug_was_down := false
var _dev_toggle_inspect_was_down := false

# Logging
var _log_path := ""
var _log_file: FileAccess = null  # Kept open for the session; avoids open/close per line
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
var _poke_item_player: AudioStreamPlayer = null

# Chime queue: rule_ids whose day reminder fired since the last play
var _pending_chime_rule_ids: Dictionary = {}
# Trinket-reminder sound queued until the overlay gate opens
var _pending_trinket_reminder_sound := false

# Trainer display names (built from the trainer catalog)
var _trainer_display_names: Dictionary = {}

# Trinket gain panel (bottom-right of the results screen, auto-hides after 8s)
var _trinket_panel = null

# Shop income panel (near bottom-center, shop-only, shows daily income)
var _shop_income_panel = null

# Shop-only trinket reminders panel (top-left; shows unused one-shot trinkets)
var _trinket_reminders_panel = null
var _trinket_reminders_alerted := false  # True while the current non-empty list has been announced
var _last_trinket_reminder_entries: Dictionary = {}  # name -> count, for change-only logging

# Shop-only rank odds button + popup (bottom-left; shows rarity odds for all ranks)
var _rank_odds_panel = null
# Label reminders currently shown (rule_id -> text), for change-only logging
var _last_reminder_rule_ids: Dictionary = {}

# Daily income schedule (user-verified: Day 1 base income is 35, +5 per day).
# Trinket/passive gold_gain bonuses are added on top.
const BASE_INCOME := 35
const INCOME_PER_DAY := 5

# One-shot trinkets worth reminding about while still held (id -> short description).
# IDs follow the game's snake_case convention (e.g. "treasure_map").
const TRACKED_TRINKET_DESCRIPTIONS := {
	"mini_duplicator": "Next non-unique trinket gift: +1 copy",
	"mega_duplicator": "Next non-unique trinket gift: +2 copies",
	"treasure_map": "Next trinket gift: +1 rarity tier",
	"upgrade_disc": "Next monster purchase: +1 level",
}

# Player HUD (battle-only HP / Wins / Day line, ported from NP_QoL)
var _player_hud = null

# Results layer: hosts the trinket-gain panel so it can show over the battle results screen.
var _results_layer: CanvasLayer = null

# Battle completion logging: report each battle's result exactly once.
var _battle_completion_state_id := 0
var _battle_completion_reported := false


func mod_ready() -> void:
	_initialize_mod()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_loaded_by_mod_loader():
		_initialize_mod()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added_transition):
		get_tree().node_added.disconnect(_on_node_added_transition)
	if _log_file != null:
		_log_file.close()
		_log_file = null


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	
	# Create formatter
	_formatter = LogFormatterScript.new(_has_property)
	
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
	
	# Listen for the game's transition signal so battle start hides the overlay immediately
	_setup_transition_listener()
	
	# Create battle player HUD
	_setup_player_hud()
	
	# Create the results layer for the trinket-gain panel
	_setup_results_panel()
	
	# Setup notification sounds
	_setup_notification_sounds()
	
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

	# Keep one append handle open for the session instead of reopening per line.
	_log_file = FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if _log_file == null:
		push_error("Creature Comforts: Cannot open log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
		return
	_log_file.seek_end()
	
	_initialized = true
	
	_log_message("=".repeat(80))
	_log_message("Creature Comforts %s - Trainer Advice System" % VERSION)
	_log_message("Initialized at %s" % _formatter.get_timestamp())
	_log_message("Dev toggles: Debug Logging: %s | Deep Inspection: %s" % [_debug_logging, _deep_inspection])
	_log_message("Log file: %s" % abs_log_path)
	_log_message("=".repeat(80))
	
	print("Creature Comforts %s loaded - logging to %s" % [VERSION, abs_log_path])


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
	
	# Bottom-center income readout; the reminder layer's shop gate controls visibility.
	var ShopIncomePanel = load("res://mods/CreatureComforts/hud/shop_income_panel.gd")
	_shop_income_panel = ShopIncomePanel.new()
	_shop_income_panel.name = "ShopIncomePanel"
	_reminder_layer.add_child(_shop_income_panel)

	# Left-aligned trinket reminders ~10% down the screen; shop-gated. Added after the label
	# so it draws on top while visible.
	var TrinketRemindersPanel = load("res://mods/CreatureComforts/hud/trinket_reminders_panel.gd")
	_trinket_reminders_panel = TrinketRemindersPanel.new()
	_trinket_reminders_panel.name = "TrinketRemindersPanel"
	_trinket_reminders_panel.layout_debug.connect(_on_trinket_panel_layout_debug)
	_reminder_layer.add_child(_trinket_reminders_panel)

	# Bottom-left rank odds button + popup; shop-gated like the other shop panels.
	var RankOddsPanel = load("res://mods/CreatureComforts/hud/rank_odds_panel.gd")
	_rank_odds_panel = RankOddsPanel.new()
	_rank_odds_panel.name = "RankOddsPanel"
	_rank_odds_panel.log_line.connect(_log_event)
	_reminder_layer.add_child(_rank_odds_panel)


## Debug Logging only: write the trinket panel's one-shot layout snapshot.
func _on_trinket_panel_layout_debug(message: String) -> void:
	if not _debug_logging:
		return
	for line in message.split("\n"):
		_log_message(line)


func _setup_player_hud() -> void:
	"""Initialize the battle-only player HUD (HP / Wins / Day)."""
	var PlayerHud = load("res://mods/CreatureComforts/hud/player_hud.gd")
	
	var layer := CanvasLayer.new()
	layer.layer = 110  # Above game UI, matching NP_QoL's HUD layer
	layer.name = "CreatureComforts_PlayerHud"
	add_child(layer)
	
	_player_hud = PlayerHud.new()
	_player_hud.name = "PlayerHud"
	layer.add_child(_player_hud)


func _setup_results_panel() -> void:
	"""Initialize the results layer that hosts the trinket-gain panel."""
	# Separate layer from _reminder_layer: the overlay gate hides reminders outside the
	# shop, but the trinket panel must be visible after battles (over the results screen).
	_results_layer = CanvasLayer.new()
	_results_layer.layer = 100
	_results_layer.name = "CreatureComforts_Results"
	add_child(_results_layer)
	
	var TrinketPanel = load("res://mods/CreatureComforts/hud/trinket_panel.gd")
	_trinket_panel = TrinketPanel.new()
	_trinket_panel.name = "TrinketPanel"
	_results_layer.add_child(_trinket_panel)


func _setup_notification_sounds() -> void:
	"""Initialize notification sounds for day reminders and trinket reminders."""
	var base_dir := str(get_script().resource_path).get_base_dir()
	var path := base_dir.path_join("assets/sounds/pika.ogg")
	
	_pika_player = AudioStreamPlayer.new()
	_pika_player.stream = AudioStreamOggVorbis.load_from_file(path)
	_pika_player.volume_db = -6.0
	add_child(_pika_player)
	
	if _pika_player.stream == null:
		push_warning("Creature Comforts: Failed to load notification sound: " + path)

	var poke_path := base_dir.path_join("assets/sounds/poke_item_found.ogg")
	_poke_item_player = AudioStreamPlayer.new()
	_poke_item_player.stream = AudioStreamOggVorbis.load_from_file(poke_path)
	_poke_item_player.volume_db = -6.0
	add_child(_poke_item_player)
	if _poke_item_player.stream == null:
		push_warning("Creature Comforts: Failed to load trinket notification sound: " + poke_path)


func _play_pika() -> void:
	"""Play notification sound for new day reminders."""
	if _pika_player != null and _pika_player.stream != null:
		_pika_player.play()


func _play_poke_item() -> void:
	"""Play notification sound for new trinket reminders."""
	if _poke_item_player != null and _poke_item_player.stream != null:
		_poke_item_player.play()


func _process(_delta: float) -> void:
	if not _initialized:
		return
	_update_overlay_gate()
	
	_handle_dev_toggles()
	
	var now := Time.get_ticks_msec()
	if now < _next_poll:
		return
	_next_poll = now + POLL_INTERVAL_MS
	_inspect_current_phase()


## Dev-only runtime toggles (not user-facing). Hold Ctrl+Shift and tap the
## configured key to flip a toggle; the change is written to the log immediately.
func _handle_dev_toggles() -> void:
	var modifier_held := Input.is_key_pressed(Key.KEY_CTRL) and Input.is_key_pressed(Key.KEY_SHIFT)
	var debug_down := modifier_held and Input.is_key_pressed(DevConfig.TOGGLE_DEBUG_KEY)
	var inspect_down := modifier_held and Input.is_key_pressed(DevConfig.TOGGLE_INSPECT_KEY)
	
	if debug_down and not _dev_toggle_debug_was_down:
		_debug_logging = not _debug_logging
		_log_message("Dev toggle: Debug Logging = %s" % _debug_logging)
	if inspect_down and not _dev_toggle_inspect_was_down:
		_deep_inspection = not _deep_inspection
		_log_message("Dev toggle: Deep Inspection = %s" % _deep_inspection)
	
	_dev_toggle_debug_was_down = debug_down
	_dev_toggle_inspect_was_down = inspect_down


func _inspect_current_phase() -> void:
	var main = get_tree().current_scene
	var state = main.get("current_state") if _has_property(main, "current_state") else null
	
	# The transition hold only needs to survive the shop→battle fade. Once the
	# phase actually leaves the shop, clear it so a later shop visit is unaffected.
	if not _script_is(state, SHOP_SCRIPT):
		_gate_hold_until_ms = 0
	
	var is_battle := _script_is(state, BATTLE_SCRIPT)
	_update_player_hud(state, is_battle)
	# Defensive fallback: the income and trinket-reminder panels are normally hidden by the
	# reminder layer's shop gate, but hide them directly whenever the shop is not the current phase.
	if not _script_is(state, SHOP_SCRIPT):
		if _shop_income_panel != null:
			_shop_income_panel.hide_panel()
		if _trinket_reminders_panel != null:
			_trinket_reminders_panel.hide_panel()
		if _rank_odds_panel != null:
			_rank_odds_panel.hide_panel()
	if not is_battle:
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _last_phase == "battle":
			_reset_battle_completion()
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
			_log_event("DAY REMINDER | %s | %s" % [advice.get("rule_id", ""), message])
	
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
		_log_reminder_changes(reminders_to_show)
	
	_try_play_chime()


## Log only label-reminder additions, updates, and removals (not repeated polls).
func _log_reminder_changes(reminders: Dictionary) -> void:
	for rule_id in reminders.keys():
		var text := str(reminders[rule_id])
		if not _last_reminder_rule_ids.has(rule_id):
			_log_event("REMINDER ADDED | %s | %s" % [rule_id, text])
		elif str(_last_reminder_rule_ids[rule_id]) != text:
			_log_event("REMINDER UPDATED | %s | %s" % [rule_id, text])
	for rule_id in _last_reminder_rule_ids.keys():
		if not reminders.has(rule_id):
			_log_event("REMINDER REMOVED | %s" % rule_id)
	_last_reminder_rule_ids = reminders.duplicate()


func _try_play_chime() -> void:
	"""Play queued notification sounds once the overlay is on screen."""
	if _pending_chime_rule_ids.is_empty() and not _pending_trinket_reminder_sound:
		return
	if _overlay_gate_reason.is_empty():
		if not _pending_chime_rule_ids.is_empty():
			_play_pika()
			_pending_chime_rule_ids.clear()
		if _pending_trinket_reminder_sound:
			_play_poke_item()
			_pending_trinket_reminder_sound = false


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
		_view_member_cache.clear()
		_log_phase_entry("SHOP", run, manager)
		if _deep_inspection:
			_log_lines(_formatter.format_deep_inspect_shop(manager, run))
		# Trinket gains are battle-scoped now (tracked during the battle state only), so no
		# shop-to-shop inventory diff happens here; the trinket panel shows on the results screen.
		_reset_transient_state(true, false, false)  # Reset suppression for new shop visit
		if _rank_odds_panel != null:
			_rank_odds_panel.reset_for_shop()
	elif _last_snapshot != null and _deep_inspection:
		# Full snapshot diffs are troubleshooting detail, not regular event logging.
		var comparison = _changes_comparer.compare(_last_snapshot, current_snapshot)
		if comparison.has_changes():
			_log_lines(_formatter.format_snapshot_changes(comparison, run, manager, _debug_logging))
	
	# Reset suppression and battle trinket tracking on trainer identity changes (new run)
	if trainer_changed:
		if _advisor != null:
			_advisor.reset_suppression()
		_finalize_battle_trinket_tracking(false)  # Prevent false gains/panel from a previous run
		if _trinket_reminders_panel != null:
			_trinket_reminders_panel.reset_for_run()
		_trinket_reminders_alerted = false
		_last_trinket_reminder_entries.clear()
		_last_reminder_rule_ids.clear()
		_pending_trinket_reminder_sound = false
	
	# Evaluate trainer advice (after logging, before updating snapshot)
	_evaluate_trainer_advice(current_snapshot)
	
	_update_shop_income(run)
	_update_trinket_reminders(run)
	_update_rank_odds(run)

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


## Refresh the bottom-left rank odds button with the current shop rank.
func _update_rank_odds(run) -> void:
	if _rank_odds_panel == null:
		return
	var rank := int(run.get("shop_rank")) if _has_property(run, "shop_rank") else 1
	_rank_odds_panel.set_rank(rank)


## Refresh the top-left trinket reminders from the player's held one-shot trinkets.
## Runs every shop poll, so gained/consumed/sold trinkets update immediately. The reminder
## label stays visible at the top; the panel sits below it.
func _update_trinket_reminders(run) -> void:
	if _trinket_reminders_panel == null:
		return

	# Accept any iterable (Array or PackedStringArray), matching _capture_trinket_state.
	var held = run.get("trinket_ids") if _has_property(run, "trinket_ids") else []
	if held == null:
		held = []

	# Count tracked ids (one-shot trinkets are removed from trinket_ids when consumed).
	var counts := {}
	for tid in held:
		var key := str(tid)
		if TRACKED_TRINKET_DESCRIPTIONS.has(key):
			counts[key] = counts.get(key, 0) + 1

	var entries: Array = []
	for tid in TRACKED_TRINKET_DESCRIPTIONS.keys():
		var count: int = int(counts.get(tid, 0))
		if count <= 0:
			continue
		entries.append({
			"name": _formatter.format_trinket_name(tid),
			"count": count,
			"desc": TRACKED_TRINKET_DESCRIPTIONS[tid],
		})

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


## Log only trinket-reminder additions, updates, and removals (not repeated polls).
func _log_trinket_reminder_changes(entries: Array) -> void:
	var current := {}
	for entry in entries:
		current[str(entry.get("name", ""))] = int(entry.get("count", 1))
	for name in current.keys():
		if not _last_trinket_reminder_entries.has(name):
			_log_event("TRINKET REMINDER ADDED | %s x%d" % [name, int(current[name])])
		elif int(_last_trinket_reminder_entries[name]) != int(current[name]):
			_log_event("TRINKET REMINDER UPDATED | %s x%d" % [name, int(current[name])])
	for name in _last_trinket_reminder_entries.keys():
		if not current.has(name):
			_log_event("TRINKET REMINDER REMOVED | %s" % name)
	_last_trinket_reminder_entries = current


func _handle_battle_phase(state) -> void:
	# Battle completion detection (win/loss/draw) - independent of replay logging
	_check_battle_completion(state)
	
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
	
	# Reset transient overlay/suppression state on battle entry (not every poll)
	if _last_phase != "battle":
		_reset_transient_state(false, true, true)
	_last_phase = "battle"


func _check_battle_completion(state) -> void:
	"""Detect battle completion once and log the result."""
	if state == null or not is_instance_valid(state):
		_reset_battle_completion()
		return
	
	var instance_id: int = state.get_instance_id()
	if instance_id != _battle_completion_state_id:
		_battle_completion_state_id = instance_id
		_battle_completion_reported = false
	
	if _battle_completion_reported:
		return
	if not _battle_is_over(state):
		return
	
	_battle_completion_reported = true
	var sim = state.get("simulation") if _has_property(state, "simulation") else null
	var battle_data = sim.get("data") if sim != null and _has_property(sim, "data") else null
	
	_log_battle_result(battle_data)


## Clear battle-completion tracking so a later battle is reported again.
func _reset_battle_completion() -> void:
	_battle_completion_state_id = 0
	_battle_completion_reported = false


## Log how the battle ended.
func _log_battle_result(battle_data) -> void:
	if battle_data == null:
		_log_event("BATTLE COMPLETE | %s" % BATTLE_RESULT_UNKNOWN)
		return
	
	var player_health = battle_data.get("player_health")
	if player_health == null or player_health.size() < 2:
		_log_event("BATTLE COMPLETE | %s | HP unavailable" % BATTLE_RESULT_UNKNOWN)
		return
	
	var player_hp := int(player_health[0])
	var enemy_hp := int(player_health[1])
	
	var result := BATTLE_RESULT_DRAW
	if player_hp > 0 and enemy_hp <= 0:
		result = BATTLE_RESULT_VICTORY
	elif player_hp <= 0 and enemy_hp > 0:
		result = BATTLE_RESULT_DEFEAT
	_log_event("BATTLE COMPLETE | %s | HP %d" % [result, player_hp])


## Capture the trinket inventory (ids, gained counter, consumed one-shots) as a plain snapshot.
func _capture_trinket_state(run) -> Dictionary:
	var snapshot := {}
	var ids = run.get("trinket_ids") if _has_property(run, "trinket_ids") else []
	# Copy the lists so the battle_over snapshot stays frozen if the game mutates the live data.
	snapshot["trinket_ids"] = ids.duplicate() if ids != null else []
	snapshot["trinkets_gained_total"] = int(run.get("trinkets_gained_total")) if _has_property(run, "trinkets_gained_total") else 0
	var used = run.get("used_trinket_ids") if _has_property(run, "used_trinket_ids") else []
	snapshot["used_trinket_ids"] = used.duplicate() if used != null else []
	return snapshot


## Diff trinkets gained between two captured states (inventory diff + counter delta + newly used).
func _diff_trinket_states(before: Dictionary, after: Dictionary) -> Dictionary:
	return TrinketGains.diff_states(before, after)


## Update the trinket panel from a gains dict, showing only non-junk trinkets.
## Hides the panel when nothing non-junk was earned (1 or 10 junk alone => no panel).
## Returns true when the panel was shown.
func _update_trinket_panel(gains: Dictionary) -> bool:
	if _trinket_panel == null:
		return false
	var shown_ids: Array = TrinketGains.displayable_ids(gains.get("ids", []), JUNK_TRINKET_ID)
	if shown_ids.is_empty():
		_hide_trinket_panel()
		return false
	_trinket_panel.show_gains(_summarize_trinket_gains(shown_ids))
	return true


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
			var gains := _diff_trinket_states(_battle_trinket_start, _battle_trinket_end)
			if not _battle_gains_logged and (not gains["ids"].is_empty() or int(gains["counter"]) != 0):
				_battle_gains_logged = true
				for tid in gains["ids"]:
					_log_event("TRINKET ACQUIRED | %s" % str(tid))
				if _deep_inspection:
					_log_lines(_formatter.format_battle_trinket_gains(gains))
			if _deep_inspection:
				# Diagnostic: changes applied after the freeze (e.g. event rewards) are excluded.
				var live := _capture_trinket_state(run)
				var post := _diff_trinket_states(_battle_trinket_end, live)
				if not post["ids"].is_empty():
					_log_message("BATTLE TRINKET GAINS | excluded post-battle additions: %s" % str(post["ids"]))
			if show_panel:
				# Gift content is applied after the frozen battle_over snapshot, so it never
				# appears in the ids diff. Show the legitimate gains; the panel hides itself
				# when nothing non-junk remains.
				if _deep_inspection and TrinketGains.has_gift_trinket(gains["newly_used"]):
					_log_message("BATTLE TRINKET GAINS | gift pending (%s), %d trinket(s) withheld; showing %d gained" % [
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


func _update_overlay_gate() -> void:
	"""Every frame: hide the whole reminder layer unless the shop is on screen and interactive."""
	if _reminder_layer == null:
		return
	
	var reason := _compute_overlay_gate_reason()
	# Opponent found: the search gate just closed and the battle transition is about
	# to fire. Keep the overlay closed briefly so the panel cannot flash in the gap.
	if reason.is_empty() and _overlay_gate_reason == GATE_SEARCH:
		_search_end_hold_until_ms = Time.get_ticks_msec() + 2000
	if reason.is_empty() and Time.get_ticks_msec() < _search_end_hold_until_ms:
		reason = GATE_TRANSITION
	if reason == _overlay_gate_reason:
		return
	
	_overlay_gate_reason = reason
	_reminder_layer.visible = reason.is_empty()
	if reason.is_empty():
		_try_play_chime()


func _compute_overlay_gate_reason() -> String:
	"""Empty string = overlay allowed. Cheap checks only (runs every frame)."""
	# A transition signal fired recently: keep the overlay closed until the state changes.
	if Time.get_ticks_msec() < _gate_hold_until_ms:
		return GATE_TRANSITION
	if get_tree().paused:
		return GATE_PAUSED
	
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
	
	var view = state.get("view") if _has_property(state, "view") else null
	if view == null or not is_instance_valid(view) or not view is Node:
		return GATE_VIEW_NOT_READY
	if not view.is_node_ready():
		return GATE_VIEW_NOT_READY
	if view is CanvasItem and not view.is_visible_in_tree():
		return GATE_VIEW_HIDDEN
	
	# The shop's own transition animation (fade to black) is the authoritative
	# "shop is leaving" signal. It can outlast the signal-based hold.
	if _is_shop_transition_active(view):
		return GATE_TRANSITION
	
	# The shop's own interaction lock covers search, opponent-found, level-up
	# choices, Dex/Settings, and other modal states.
	if _has_property(view, "_is_interaction_locked") and bool(view.get("_is_interaction_locked")):
		return GATE_OVERLAY + " (interaction locked)"
	
	# Modal overlays (Batopedia/Dex, Settings, pause) do not change current_state.
	var overlay := _find_visible_overlay(view, main)
	if not overlay.is_empty():
		return "%s (%s)" % [GATE_OVERLAY, overlay]
	
	# While searching for an opponent the shop's Cancel button replaces the Battle button.
	# Resolve via the view's properties first, then direct child, then a recursive search.
	var cancel = _get_view_member(view, ["cancel_button", "CancelButton"], "CancelButton")
	if cancel is CanvasItem and cancel.is_visible_in_tree():
		return GATE_SEARCH
	# After the search succeeds the shop stays up while the game transitions to battle
	var battle_button = _get_view_member(view, ["battle_button", "BattleButton"], "BattleButton")
	if battle_button is CanvasItem and not battle_button.is_visible_in_tree():
		return GATE_BATTLE_STARTING
	return ""


## Is the shop's own fade/transition animation currently active?
## `transition_anim` is the view's AnimationPlayer; the `Transition` node is the
## visual overlay fallback.
func _is_shop_transition_active(view) -> bool:
	if view == null or not is_instance_valid(view) or not view is Node:
		return false
	var anim = view.get("transition_anim") if _has_property(view, "transition_anim") else null
	if anim is AnimationPlayer:
		return anim.is_playing()
	var trans = view.get_node_or_null("Transition")
	if trans is CanvasItem and trans.is_visible_in_tree() and trans.modulate.a > 0.01:
		return true
	return false


## Direct-child overlay probe. Cheap enough to run every frame.
func _find_visible_overlay(view, main) -> String:
	for name in OVERLAY_NODE_NAMES:
		var node = _get_direct_child(view, name)
		if node == null:
			node = _get_direct_child(main, name)
		if _node_is_visible(node):
			return name
	# Fallback for unknown overlay names: only consider CanvasLayer/Window roots,
	# so ordinary Controls (e.g. a "SettingsButton") cannot false-positive.
	for root in [view, main]:
		if root == null or not is_instance_valid(root) or not root is Node:
			continue
		for child in root.get_children():
			if not (child is CanvasLayer or child is Window):
				continue
			if not _node_is_visible(child):
				continue
			# Ignore empty persistent layers; only a layer with visible content counts.
			if child is CanvasLayer:
				var has_visible_child := false
				for grandchild in child.get_children():
					if grandchild is CanvasItem and grandchild.is_visible_in_tree():
						has_visible_child = true
						break
				if not has_visible_child:
					continue
			var lower := str(child.name).to_lower()
			if lower.begins_with("dex") or lower.contains("batopedia") or lower.contains("settings") or lower.contains("pause"):
				return str(child.name)
	return ""


func _get_direct_child(root, name: String):
	if root == null or not is_instance_valid(root) or not root is Node:
		return null
	return root.get_node_or_null(name)


func _node_is_visible(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is CanvasLayer:
		return node.visible
	if node is Window:
		return node.visible
	if node is CanvasItem:
		return node.is_visible_in_tree()
	return false


## Resolve a shop-view member by property name, then direct child, then recursive search.
## Results (including misses) are cached per view instance and cleared on shop entry.
func _get_view_member(view, property_names: Array, node_name: String):
	if view == null or not is_instance_valid(view) or not view is Node:
		return null
	var cache_key := "%d:%s" % [view.get_instance_id(), node_name]
	if _view_member_cache.has(cache_key):
		var cached = _view_member_cache[cache_key]
		if cached != null and is_instance_valid(cached):
			return cached
		if cached == null and not view.is_node_ready():
			return null
		_view_member_cache.erase(cache_key)
	
	for prop in property_names:
		if _has_property(view, prop):
			var value = view.get(prop)
			if value != null and is_instance_valid(value):
				_view_member_cache[cache_key] = value
				return value
	
	var direct = view.get_node_or_null(node_name)
	if direct != null:
		_view_member_cache[cache_key] = direct
		return direct
	
	var found = view.find_child(node_name, true, false)
	if found != null or view.is_node_ready():
		_view_member_cache[cache_key] = found
	return found


## Connect to the game's transition signal (verified in examples/MyBattleStats) so
## battle start hides the overlay immediately, independent of button visibility.
func _setup_transition_listener() -> void:
	if get_tree() == null:
		return
	if not get_tree().node_added.is_connected(_on_node_added_transition):
		get_tree().node_added.connect(_on_node_added_transition)
	_scan_transition_nodes(get_tree().root)


func _scan_transition_nodes(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_on_node_added_transition(node)
	for child in node.get_children():
		_scan_transition_nodes(child)


func _on_node_added_transition(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.has_signal("transition_requested"):
		return
	if not node.has_method("request_transition"):
		return
	var id := node.get_instance_id()
	if _transition_nodes.has(id):
		return
	_transition_nodes[id] = true
	node.transition_requested.connect(_on_transition_requested)


func _on_transition_requested(target: String, data) -> void:
	if target == "battle":
		# The shop state can remain current for the whole fade-to-black; hold the
		# overlay closed long enough to cover the transition, then let the phase
		# change clear it (see _inspect_current_phase).
		_gate_hold_until_ms = Time.get_ticks_msec() + 5000
		if _reminder_layer != null:
			_reminder_layer.visible = false


func _reset_transient_state(clear_suppression: bool, clear_reminders: bool, clear_chimes: bool) -> void:
	"""Reset overlay/suppression state shared across phase transitions."""
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
	_log_event(_formatter.format_phase_entry(phase, run))
	if _deep_inspection:
		_log_lines(_formatter.format_phase_snapshot(phase, run, manager))


## Log a concise, timestamped event line (regular debug log).
func _log_event(message: String) -> void:
	_log_message("[%s] %s" % [_formatter.get_time_short(), message])


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
	if _log_file == null:
		return
	_log_file.store_line(message)
	_log_file.flush()


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
