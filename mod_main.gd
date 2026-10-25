extends Node
## Brainrot Edition - Phase 2.3: Refactored Trainer Advice System
## Inspects game state objects during Shop and Battle phases with configurable detail levels.

const VERSION := "0.2.3"
const OUTPUT_DIR := "user://np_brainrot"
const LOG_FILE := "inspect.log"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

# Polling and state tracking
const POLL_INTERVAL_MS := 500

# Trainer display name mapping
const TRAINER_PREFIXES := {
	"scavenger": "Scavenger",
	"blackbelt": "Black Belt",
	"beetdown": "Black Belt",
	"mad_scientist": "Mad Scientist",
	"gamer": "Gamer",
	"gentleman": "Gentleman",
	"treasure_hunter": "Treasure Hunter",
	"burglar": "Burglar"
}

# Reminder message templates for day-based and team composition rules
const REMINDER_TEMPLATES := {
	"mad_scientist_day6": "Tomorrow: Legendary transformation!",
	"gamer_day8": "Tomorrow: Mythical monster!",
	"gentleman_day3": "Tomorrow: No Common/Uncommon shops!",
	"beetdown_company": "Black Belt: 2+ Fighters active!"
}

var _next_poll := 0
var _last_phase := ""
var _last_snapshot = null  # ShopSnapshot from previous poll
var _battle_logged := false
var _initialization_started := false
var _initialized := false

# Settings (defaults match mod.json)
var _debug_logging := true
var _deep_inspection := true
var _enable_trainer_reminders := true
var _settings_load_attempted := false
var _settings_warning_shown := false
var _diagnostic_logged := false

# Logging
var _log_path := ""
var _formatter = null

# Trainer advice system
var _advisor = null
var _advice_context_script = null
var _advice_context_builder = null

# Snapshot system
var _snapshot_builder = null
var _changes_comparer = null

# Reminder label system (compact top-bar)
var _reminder_label = null
var _reminder_layer: CanvasLayer = null
var _pika_player: AudioStreamPlayer = null
var _last_reminder_text := ""  # Track last displayed text to detect new reminders


func _init() -> void:
	pass


func mod_init() -> void:
	pass  # Don't access scene tree nodes during early initialization


func mod_ready() -> void:
	_initialize_mod()


func mod_bootstrap() -> void:
	pass


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
		_debug_logging = mod_loader.get_config("np_brainrot", "debug_logging", true)
		_deep_inspection = mod_loader.get_config("np_brainrot", "deep_inspection", true)
		_enable_trainer_reminders = mod_loader.get_config("np_brainrot", "enable_trainer_reminders", true)
		
		# Connect to config_changed signal for live updates
		if mod_loader.has_signal("config_changed") and not mod_loader.is_connected("config_changed", _on_config_changed):
			mod_loader.connect("config_changed", _on_config_changed)
	elif not _settings_warning_shown:
		# Fallback if ModLoader doesn't support config API - keep defaults
		_settings_warning_shown = true
		push_warning("Brainrot Edition: ModLoader.get_config() not available, using defaults")


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	
	# Load settings if not already loaded
	_load_settings()
	
	# Create formatter
	var LogFormatter = load("res://mods/NP_Brainrot/log_formatter.gd")
	_formatter = LogFormatter.new(_has_property)
	
	# Create snapshot builder
	var ShopSnapshot = load("res://mods/NP_Brainrot/shop_snapshot.gd")
	_snapshot_builder = ShopSnapshot.new()
	
	# Create changes comparer
	var ShopChanges = load("res://mods/NP_Brainrot/shop_changes.gd")
	_changes_comparer = ShopChanges.new()
	
	# Create advisor and register rules
	_setup_advisor()
	
	# Create reminder label system
	_setup_reminder_panel()
	
	# Setup notification sound
	_setup_pika_sound()
	
	# Create output directory
	var dir_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_error("Brainrot Edition: Failed to create directory %s: %s" % [dir_path, error_string(dir_result)])
		return
	
	_log_path = OUTPUT_DIR.path_join(LOG_FILE)
	var abs_log_path := ProjectSettings.globalize_path(_log_path)
	
	# Create log file if it doesn't exist
	if not FileAccess.file_exists(_log_path):
		var file := FileAccess.open(_log_path, FileAccess.WRITE)
		if file == null:
			push_error("Brainrot Edition: Cannot create log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
			return
		file.close()
	
	_initialized = true
	
	_log_message("=".repeat(80))
	_log_message("Brainrot Edition %s - Refactored Trainer Advice System" % VERSION)
	_log_message("Initialized at %s" % _formatter.get_timestamp())
	_log_message("Settings: Debug Logging: %s | Deep Inspection: %s | Trainer Reminders: %s" % [_debug_logging, _deep_inspection, _enable_trainer_reminders])
	_log_message("Log file: %s" % abs_log_path)
	_log_message("=".repeat(80))
	
	print("Brainrot Edition %s loaded - logging to %s" % [VERSION, abs_log_path])


func _on_config_changed(mod_id: String, key: String, value) -> void:
	"""Handle live config changes from ModLoader."""
	if mod_id != "np_brainrot":
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
		"enable_trainer_reminders":
			if value is bool:
				_enable_trainer_reminders = value
				_log_message("Setting changed: Trainer Reminders = %s" % _enable_trainer_reminders)
				if not _enable_trainer_reminders and _reminder_label != null:
					_reminder_label.hide_all_reminders()


func _setup_advisor() -> void:
	"""Initialize advisor and register all rules."""
	var TrainerAdvisor = load("res://mods/NP_Brainrot/trainer_advisor.gd")
	var TrainerRules = load("res://mods/NP_Brainrot/trainer_rules.gd")
	
	_advisor = TrainerAdvisor.new()
	
	# Cache AdviceContext script and builder
	_advice_context_script = load("res://mods/NP_Brainrot/advice_context.gd")
	_advice_context_builder = _advice_context_script.new()
	
	# Register shop target rules for trainers with same targets
	_register_shop_target_rule("scavenger")
	_register_shop_target_rule("treasure_hunter")
	_register_shop_target_rule("burglar")
	
	# Black Belt Beetbud shop rule
	var blackbelt_beetbud_rule = TrainerRules.ShopTargetsRule.new(
		"blackbelt_beetbud",
		"black_belt",
		["monster.name.beetbud"],
		[],
		"NOTICE",
		"Beetbud available: shop %s",
		_formatter
	)
	_advisor.register_rule(blackbelt_beetbud_rule)
	
	# Black Belt Beetdown company rule
	var beetdown_company_rule = TrainerRules.BeetdownCompanyRule.new(
		"beetdown_company",
		"black_belt",
		"WARNING",
		_formatter
	)
	_advisor.register_rule(beetdown_company_rule)
	
	# Mad Scientist Day 6 reminder
	var mad_scientist_day6_rule = TrainerRules.DayReminderRule.new(
		"mad_scientist_day6",
		"mad_scientist",
		6,
		"WARNING",
		"🧪 MAD SCIENTIST: Your active team transforms into random Legendaries on Day 7!"
	)
	_advisor.register_rule(mad_scientist_day6_rule)
	
	# Gamer Day 8 reminder
	var gamer_day8_rule = TrainerRules.DayReminderRule.new(
		"gamer_day8",
		"gamer",
		8,
		"NOTICE",
		"🎮 GAMER: A Mythical monster arrives on Day 9!"
	)
	_advisor.register_rule(gamer_day8_rule)
	
	# Gentleman Day 3 reminder
	var gentleman_day3_rule = TrainerRules.DayReminderRule.new(
		"gentleman_day3",
		"gentleman",
		3,
		"NOTICE",
		"🎩 GENTLEMAN: Common and Uncommon monsters stop appearing in shops starting Day 4!"
	)
	_advisor.register_rule(gentleman_day3_rule)


func _register_shop_target_rule(trainer_id: String) -> void:
	"""Register a shop target rule for trainers that share the same targets."""
	var TrainerRules = load("res://mods/NP_Brainrot/trainer_rules.gd")
	var rule = TrainerRules.ShopTargetsRule.new(
		"%s_targets" % trainer_id,
		trainer_id,
		["monster.name.lamplet", "monster.name.swoonet"],
		["basic_bait"],
		"NOTICE",
		"Shop targets: %s | Level-up/trinket opportunities",
		_formatter
	)
	_advisor.register_rule(rule)


func _setup_reminder_panel() -> void:
	"""Initialize reminder label UI layer."""
	var ReminderLabel = load("res://mods/NP_Brainrot/reminder_label.gd")
	
	_reminder_layer = CanvasLayer.new()
	_reminder_layer.layer = 100  # Above game UI but below debug overlays
	_reminder_layer.name = "NP_Brainrot_Reminders"
	add_child(_reminder_layer)
	
	_reminder_label = ReminderLabel.new()
	_reminder_label.name = "ReminderLabel"
	_reminder_layer.add_child(_reminder_label)


func _setup_pika_sound() -> void:
	"""Initialize notification sound for new reminders."""
	var base_dir := str(get_script().resource_path).get_base_dir()
	var path := base_dir.path_join("assets/sounds/pika.ogg")
	
	_pika_player = AudioStreamPlayer.new()
	_pika_player.stream = AudioStreamOggVorbis.load_from_file(path)
	_pika_player.volume_db = -6.0
	add_child(_pika_player)
	
	if _pika_player.stream == null:
		push_warning("Brainrot Edition: Failed to load notification sound: " + path)


func _play_pika() -> void:
	"""Play notification sound for new reminders."""
	if _pika_player != null and _pika_player.stream != null:
		_pika_player.play()


func _process(_delta: float) -> void:
	if not _initialized:
		return
	
	var now := Time.get_ticks_msec()
	if now < _next_poll:
		return
	_next_poll = now + POLL_INTERVAL_MS
	_inspect_current_phase()


func _inspect_current_phase() -> void:
	var main = get_tree().current_scene
	var state = main.get("current_state") if _has_property(main, "current_state") else null
	
	if _script_is(state, SHOP_SCRIPT):
		_handle_shop_phase(state)
	elif _script_is(state, BATTLE_SCRIPT):
		_handle_battle_phase(state)
	else:
		if _last_phase != "":
			_last_phase = ""
			_battle_logged = false
			if _advisor != null:
				_advisor.reset_suppression()
			if _reminder_label != null:
				_reminder_label.hide_all_reminders()
				_last_reminder_text = ""  # Reset sound trigger


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
		var rule_id: String = advice.get("rule_id", "")
		
		if not message.is_empty():
			# Format trainer-specific prefix based on rule_id
			var prefix := _get_trainer_prefix(rule_id)
			
			var full_message := ""
			if not prefix.is_empty():
				full_message = "*** BRAINROT %s | %s | %s" % [severity, prefix, message]
			else:
				full_message = "*** BRAINROT %s | %s" % [severity, message]
			
			_print_notice(full_message)
	
	# Update reminder panel with ALL active advice (no suppression for display)
	if _enable_trainer_reminders and _reminder_label != null:
		var reminders_to_show: Dictionary = {}
		
		for advice in all_active:
			var rule_id: String = advice.get("rule_id", "")
			var message: String = advice.get("message", "")
			
			# Include day reminders, shop target rules, and team composition rules
			if rule_id.contains("_day") or rule_id.ends_with("_targets") or rule_id == "blackbelt_beetbud" or rule_id == "beetdown_company":
				var simplified_message := _simplify_reminder_message(rule_id, message, advice)
				if not simplified_message.is_empty():
					reminders_to_show[rule_id] = simplified_message
		
		# Replace all reminders at once (single update, single render)
		_reminder_label.set_reminders(reminders_to_show)
		
		# Play notification sound if reminder text changed (new reminder appeared)
		if _reminder_label.visible:
			var current_text: String = _reminder_label.get_current_text()
			if not current_text.is_empty() and current_text != _last_reminder_text:
				_play_pika()
				_last_reminder_text = current_text
		else:
			_last_reminder_text = ""  # Reset when no reminders active
	
	# Diagnostic: Log Fighting type identifier once per shop entry
	if _debug_logging and not _diagnostic_logged:
		if context.trainer_id == "black_belt" or context.trainer_id == "blackbelt":
			for monster in context.team_monsters:
				if "fighting" in monster.types:
					_log_message("[DIAGNOSTIC] Fighting type detected in team slot %d: %s" % [monster.slot, monster.name_key])
					_diagnostic_logged = true
					break


func _get_trainer_prefix(rule_id: String) -> String:
	"""Get trainer display name from rule ID using prefix matching."""
	for key in TRAINER_PREFIXES:
		if rule_id.begins_with(key):
			return TRAINER_PREFIXES[key]
	return ""


func _simplify_reminder_message(rule_id: String, original_message: String, advice: Dictionary) -> String:
	"""Convert full reminder messages to compact single-line format."""
	
	# Check templates first (day reminders and team composition rules)
	if rule_id in REMINDER_TEMPLATES:
		return REMINDER_TEMPLATES[rule_id]
	
	# Shop target rules - extract unique monster names
	if rule_id.ends_with("_targets") or rule_id == "blackbelt_beetbud":
		var matched_slots: Array = advice.get("matched_slots", [])
		if matched_slots.is_empty():
			return ""
		
		var unique_names := _extract_unique_names(matched_slots)
		return "Reminders: " + ", ".join(unique_names) if not unique_names.is_empty() else ""
	
	# Default: use original message (shouldn't happen for displayed reminders)
	return original_message


func _extract_unique_names(matched_slots: Array) -> Array:
	"""Extract unique monster/item names from matched slot strings."""
	var unique_names: Array = []
	var seen_names := {}
	
	for slot_text in matched_slots:
		# slot_text format: "[0] Lamplet" or "[1] Basic Bait"
		var parts: PackedStringArray = str(slot_text).split("] ", false, 1)
		if parts.size() >= 2:
			var name: String = parts[1].strip_edges()
			if not seen_names.has(name):
				seen_names[name] = true
				unique_names.append(name)
	
	return unique_names


func _handle_shop_phase(state) -> void:
	var run = get_node_or_null("/root/RunManager")
	run = run.get("data") if run != null else null
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
		_diagnostic_logged = false  # Reset for new shop entry
		if _advisor != null:
			_advisor.reset_suppression()  # Reset for new shop visit
		_log_phase_entry("SHOP", run, manager)
		if _deep_inspection:
			_log_lines(_formatter.format_deep_inspect_shop(manager, run))
	elif _last_snapshot != null:
		# Compare snapshots and log changes
		var comparison = _changes_comparer.compare(_last_snapshot, current_snapshot)
		if comparison.has_changes():
			_log_lines(_formatter.format_snapshot_changes(comparison, run, manager, _debug_logging))
	
	# Reset suppression only on trainer identity changes (not gold/shop/freeze changes)
	if trainer_changed and _advisor != null:
		_advisor.reset_suppression()
	
	# Evaluate trainer advice (after logging, before updating snapshot)
	_evaluate_trainer_advice(current_snapshot)
	
	_last_phase = "shop"
	_last_snapshot = current_snapshot


func _handle_battle_phase(state) -> void:
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
		
		_battle_logged = true
	
	# Hide reminders during battle
	if _reminder_label != null:
		_reminder_label.hide_all_reminders()
	
	_last_phase = "battle"


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
	if obj == null or not is_instance_valid(obj):
		return false
	for prop in obj.get_property_list():
		if str(prop.name) == property:
			return true
	return false


func _script_is(obj, script_path: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var script: Script = obj.get_script()
	while script != null:
		if str(script.resource_path) == script_path:
			return true
		script = script.get_base_script()
	return false


func _log_message(message: String) -> void:
	if _log_path.is_empty():
		return
	
	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file == null:
		push_warning("Brainrot Edition: Cannot open log file: " + error_string(FileAccess.get_open_error()))
		return
	
	file.seek_end()
	file.store_line(message)
	file.close()


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
