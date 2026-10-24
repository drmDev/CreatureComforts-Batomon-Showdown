extends Node
## Brainrot Edition - Phase 2.2: Monster Types and Shop Refresh Detection
## Inspects game state objects during Shop and Battle phases with configurable detail levels.

const VERSION := "0.2.2"
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

# Notice tracking for duplicate suppression
var _last_scavenger_notice := ""
var _last_blackbelt_shop_notice := ""
var _last_blackbelt_team_warning := ""

# Settings (defaults match mod.json)
var _debug_logging := true
var _deep_inspection := true
var _settings_load_attempted := false
var _settings_warning_shown := false
var _diagnostic_logged := false

# Logging
var _log_path := ""
var _formatter = null


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
	_log_message("Brainrot Edition %s - Configurable Diagnostic Logger" % VERSION)
	_log_message("Initialized at %s" % _formatter.get_timestamp())
	_log_message("Debug Logging: %s | Deep Inspection: %s" % [_debug_logging, _deep_inspection])
	_log_message("Log file: %s" % abs_log_path)
	_log_message("=".repeat(80))
	
	print("Brainrot Edition %s loaded - logging to %s" % [VERSION, abs_log_path])


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
			_reset_trainer_notice_signatures()


func _reset_trainer_notice_signatures() -> void:
	"""Reset all trainer notice signatures for a new shop visit."""
	_last_scavenger_notice = ""
	_last_blackbelt_shop_notice = ""
	_last_blackbelt_team_warning = ""


func _check_scavenger_targets(manager) -> void:
	"""Check for Scavenger target items in shop."""
	if not _has_property(manager, "current_shop_items"):
		return
	
	var matches := []
	var items: Array = manager.current_shop_items
	
	for i in range(items.size()):
		var item = items[i]
		if item == null:
			continue
		
		# Check for Lamplet/Swoonet creatures
		if item.has_method("get_gold_cost") and _has_property(item, "data"):
			var data = item.data
			if data != null and _has_property(data, "name_key"):
				var name_key: String = str(data.name_key)
				if name_key == "monster.name.lamplet":
					matches.append("[%d] Lamplet" % i)
				elif name_key == "monster.name.swoonet":
					matches.append("[%d] Swoonet" % i)
		
		# Check for Basic Bait item
		if _has_property(item, "id") and str(item.id) == "basic_bait":
			matches.append("[%d] Basic Bait" % i)
	
	if not matches.is_empty():
		var notice := "*** BRAINROT NOTICE | Scavenger | Shop targets: %s | Level-up/trinket opportunities" % ", ".join(matches)
		if notice != _last_scavenger_notice:
			_print_notice(notice)
			_last_scavenger_notice = notice
	else:
		_last_scavenger_notice = ""


func _check_blackbelt_beetbud(manager) -> void:
	"""Check for Beetbud creatures in shop for Black Belt trainer."""
	if not _has_property(manager, "current_shop_items"):
		return
	
	var matches := []
	var items: Array = manager.current_shop_items
	
	for i in range(items.size()):
		var item = items[i]
		if item == null:
			continue
		
		# Check for Beetbud creatures
		if item.has_method("get_gold_cost") and _has_property(item, "data"):
			var data = item.data
			if data != null and _has_property(data, "name_key"):
				var name_key: String = str(data.name_key)
				if name_key == "monster.name.beetbud":
					matches.append("[%d]" % i)
	
	if not matches.is_empty():
		var notice := "*** BRAINROT NOTICE | Black Belt | Beetbud available: shop %s" % ", ".join(matches)
		if notice != _last_blackbelt_shop_notice:
			_print_notice(notice)
			_last_blackbelt_shop_notice = notice
	else:
		_last_blackbelt_shop_notice = ""


func _evaluate_trainer_notices(run, manager) -> void:
	"""Evaluate and emit trainer-specific notices."""
	if not _has_property(run, "trainer_id"):
		return
	
	var trainer_id: String = str(run.get("trainer_id"))
	
	if trainer_id == "scavenger":
		_check_scavenger_targets(manager)
	elif trainer_id == "black_belt" or trainer_id == "blackbelt":
		_check_blackbelt_beetbud(manager)
		_check_blackbelt_fighter_warning(run)
	
	# Diagnostic: Log unknown trainer IDs once
	if trainer_id not in ["scavenger", "chemist", "black_belt", "blackbelt", "shopkeeper", ""]:
		if _debug_logging and not _diagnostic_logged:
			_log_message("[DIAGNOSTIC] Unknown trainer_id: %s" % trainer_id)
			_diagnostic_logged = true


func _check_blackbelt_fighter_warning(run) -> void:
	"""Check Black Belt team for multiple Fighter types (diagnostic mode)."""
	# Diagnostic mode: discover Fighter identifiers (once per shop entry)
	if _debug_logging and not _diagnostic_logged:
		# Check team for Fighter types
		if _has_property(run, "team"):
			var team: Array = run.team
			for i in range(team.size()):
				var monster = team[i]
				if monster != null and _has_property(monster, "data"):
					var data = monster.data
					if data != null and _has_property(data, "types"):
						var types = data.types
						if types is Array:
							for type_resource in types:
								var type_name: String = _formatter.resolve_type_name(type_resource)
								if "fight" in type_name.to_lower():
									_log_message("[DIAGNOSTIC] Fighter candidate type: %s (resolved from %s)" % [type_name, _formatter.get_object_info(type_resource)])
		
		_diagnostic_logged = true


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
	
	if phase_changed:
		_battle_logged = false
		_diagnostic_logged = false  # Reset for new shop entry
		_reset_trainer_notice_signatures()  # Reset for new shop visit
		_log_phase_entry("SHOP", run, manager)
		if _deep_inspection:
			_log_lines(_formatter.format_deep_inspect_shop(manager, run))
	elif run_changed or shop_changed or team_changed or bench_changed:
		_log_lines(_formatter.format_shop_changes(run, manager, _last_run_state, _last_shop_state, _last_team_state, _last_bench_state, _debug_logging))
	
	# Evaluate trainer notices (after logging, before updating snapshots)
	_evaluate_trainer_notices(run, manager)
	
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
		var team_ids := []
		for monster in team:
			if monster != null:
				team_ids.append(monster.get_instance_id())
			else:
				team_ids.append(0)
		state["monsters"] = team_ids
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
