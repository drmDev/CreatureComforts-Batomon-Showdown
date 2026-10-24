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
var _next_poll := 0
var _last_phase := ""
var _last_run_state := {}
var _last_shop_state := {}
var _last_team_state := {}
var _last_bench_state := {}
var _battle_logged := false
var _initialization_started := false
var _initialized := false

# Settings (defaults match mod.json)
var _debug_logging := true
var _deep_inspection := true
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
	
	if mod_loader.has_method("get_setting"):
		_debug_logging = mod_loader.get_setting("np_brainrot", "debug_logging", true)
		_deep_inspection = mod_loader.get_setting("np_brainrot", "deep_inspection", true)
	elif not _settings_warning_shown:
		# Fallback if ModLoader doesn't support settings - keep defaults
		_settings_warning_shown = true
		push_warning("Brainrot Edition: ModLoader.get_setting() not available, using defaults")


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	
	# Load settings if not already loaded
	_load_settings()
	
	# Create formatter
	var LogFormatter = load("res://mods/NP_Brainrot/log_formatter.gd")
	_formatter = LogFormatter.new(_has_property)
	
	# Create advisor and register rules
	_setup_advisor()
	
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
	_log_message("Debug Logging: %s | Deep Inspection: %s" % [_debug_logging, _deep_inspection])
	_log_message("Log file: %s" % abs_log_path)
	_log_message("=".repeat(80))
	
	print("Brainrot Edition %s loaded - logging to %s" % [VERSION, abs_log_path])


func _setup_advisor() -> void:
	"""Initialize advisor and register all rules."""
	var TrainerAdvisor = load("res://mods/NP_Brainrot/trainer_advisor.gd")
	var TrainerRules = load("res://mods/NP_Brainrot/trainer_rules.gd")
	
	_advisor = TrainerAdvisor.new()
	
	# Cache AdviceContext script and builder
	_advice_context_script = load("res://mods/NP_Brainrot/advice_context.gd")
	_advice_context_builder = _advice_context_script.new()
	
	# Scavenger shop targets rule
	var scavenger_rule = TrainerRules.ShopTargetsRule.new(
		"scavenger_targets",
		"scavenger",
		["monster.name.lamplet", "monster.name.swoonet"],
		["basic_bait"],
		"NOTICE",
		"Shop targets: %s | Level-up/trinket opportunities"
	)
	_advisor.register_rule(scavenger_rule)
	
	# Black Belt Beetbud shop rule
	var blackbelt_beetbud_rule = TrainerRules.ShopTargetsRule.new(
		"blackbelt_beetbud",
		"black_belt",
		["monster.name.beetbud"],
		[],
		"NOTICE",
		"Beetbud available: shop %s"
	)
	_advisor.register_rule(blackbelt_beetbud_rule)
	
	# Black Belt Beetdown company rule
	var beetdown_company_rule = TrainerRules.BeetdownCompanyRule.new(
		"beetdown_company",
		"black_belt",
		"WARNING"
	)
	_advisor.register_rule(beetdown_company_rule)
	
	# *** TEMPORARY TEST: Day 6 reminder (no trainer filter) ***
	var day6_test_rule = TrainerRules.DayReminderRule.new(
		"day6_test",
		"",  # No trainer filter - matches any trainer
		6,
		"NOTICE",
		"*** BRAINROT TEST | DayReminderRule matched Day 6"
	)
	_advisor.register_rule(day6_test_rule)


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


func _evaluate_trainer_advice(run, manager) -> void:
	"""Evaluate trainer advice using the advisor system."""
	if _advisor == null or _advice_context_builder == null:
		return
	
	# Create context from game state using cached builder
	var context = _advice_context_builder.from_game_state(run, manager, _has_property, _formatter)
	
	# Evaluate all rules
	var result: Dictionary = _advisor.evaluate(context)
	var new_or_changed: Array = result.get("new_or_changed", [])
	
	# Emit new or changed advice
	for advice in new_or_changed:
		var severity: String = advice.get("severity", "NOTICE")
		var message: String = advice.get("message", "")
		var rule_id: String = advice.get("rule_id", "")
		
		if not message.is_empty():
			# Format trainer-specific prefix based on rule_id
			var prefix := ""
			if rule_id.begins_with("scavenger"):
				prefix = "Scavenger"
			elif rule_id.begins_with("blackbelt") or rule_id.begins_with("beetdown"):
				prefix = "Black Belt"
			
			var full_message := ""
			if not prefix.is_empty():
				full_message = "*** BRAINROT %s | %s | %s" % [severity, prefix, message]
			else:
				full_message = "*** BRAINROT %s | %s" % [severity, message]
			
			_print_notice(full_message)
	
	# Diagnostic: Log Fighting type identifier once per shop entry
	if _debug_logging and not _diagnostic_logged:
		if context.trainer_id == "black_belt" or context.trainer_id == "blackbelt":
			for monster in context.team_monsters:
				if "fighting" in monster.types:
					_log_message("[DIAGNOSTIC] Fighting type detected in team slot %d: %s" % [monster.slot, monster.name_key])
					_diagnostic_logged = true
					break


func _handle_shop_phase(state) -> void:
	var run = get_node_or_null("/root/RunManager")
	run = run.get("data") if run != null else null
	var manager = state.get("manager") if _has_property(state, "manager") else null
	
	if run == null or manager == null:
		return
	
	# Build current state snapshots
	var run_state := _capture_run_state(run)
	var shop_state := _capture_shop_state(manager)
	var team_state := _capture_team_state(run)
	var bench_state := _capture_bench_state(run)
	
	# Detect changes
	var phase_changed := _last_phase != "shop"
	var run_changed := not _states_equal(run_state, _last_run_state)
	var shop_changed := not _states_equal(shop_state, _last_shop_state)
	var team_changed := not _states_equal(team_state, _last_team_state)
	var bench_changed := not _states_equal(bench_state, _last_bench_state)
	
	# Check for trainer/run identity changes (not just gold/shop offers)
	var trainer_changed := false
	if run_changed and _last_run_state.has("trainer_id") and run_state.has("trainer_id"):
		trainer_changed = _last_run_state.get("trainer_id") != run_state.get("trainer_id")
	
	if phase_changed:
		_battle_logged = false
		_diagnostic_logged = false  # Reset for new shop entry
		if _advisor != null:
			_advisor.reset_suppression()  # Reset for new shop visit
		_log_phase_entry("SHOP", run, manager)
		if _deep_inspection:
			_log_lines(_formatter.format_deep_inspect_shop(manager, run))
	elif run_changed or shop_changed or team_changed or bench_changed:
		_log_lines(_formatter.format_shop_changes(run, manager, _last_run_state, _last_shop_state, _last_team_state, _last_bench_state, _debug_logging))
	
	# Reset suppression only on trainer identity changes (not gold/shop/freeze changes)
	if trainer_changed and _advisor != null:
		_advisor.reset_suppression()
	
	# Evaluate trainer advice (after logging, before updating snapshots)
	_evaluate_trainer_advice(run, manager)
	
	_last_phase = "shop"
	_last_run_state = run_state
	_last_shop_state = shop_state
	_last_team_state = team_state
	_last_bench_state = bench_state


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


# State capture functions

func _capture_run_state(run) -> Dictionary:
	var state := {}
	var props := ["trainer_id", "current_round", "current_wins", "lives", "gold", "shop_rank", "player_hp"]
	for prop in props:
		if _has_property(run, prop):
			state[prop] = run.get(prop)
	return state


func _capture_shop_state(manager) -> Dictionary:
	var state := {}
	if _has_property(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		state["fingerprint"] = _formatter.create_shop_fingerprint(items)
	if _has_property(manager, "is_shop_frozen"):
		state["frozen"] = manager.is_shop_frozen
	return state


func _capture_team_state(run) -> Dictionary:
	var state := {}
	if _has_property(run, "team"):
		var team: Array = run.team
		var team_fingerprint := []
		for monster in team:
			if monster != null:
				var fp := {
					"id": monster.get_instance_id(),
					"level": monster.get("level") if _has_property(monster, "level") else 1
				}
				# Include species for detecting evolutions
				if _has_property(monster, "data"):
					var data = monster.data
					if data != null and _has_property(data, "name_key"):
						fp["species"] = str(data.name_key)
				team_fingerprint.append(fp)
			else:
				team_fingerprint.append(0)
		state["monsters"] = team_fingerprint
	return state


func _capture_bench_state(run) -> Dictionary:
	var state := {}
	if _has_property(run, "bench"):
		var bench: Array = run.bench
		var bench_ids := []
		for monster in bench:
			if monster != null:
				bench_ids.append(monster.get_instance_id())
			else:
				bench_ids.append(0)
		state["monsters"] = bench_ids
	return state


func _states_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
		if a[key] != b[key]:
			return false
	return true


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
