extends Node
## Brainrot Edition - Phase 2.2: Monster Types and Shop Refresh Detection
## Inspects game state objects during Shop and Battle phases with configurable detail levels.

const VERSION := "0.2.2"
const OUTPUT_DIR := "user://np_brainrot"
const LOG_FILE := "inspect.log"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

# Stat names for readable output
const STAT_NAMES := {1: "Dmg", 2: "Heal", 3: "Shield", 4: "Burn", 5: "Poison", 6: "Shock", 7: "Multi"}

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
	_log_message("Initialized at %s" % _get_timestamp())
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


func _evaluate_trainer_notices(run, manager) -> void:
	"""Evaluate and emit trainer-specific notices."""
	if not _has_property(run, "trainer_id"):
		return
	
	var trainer_id: String = str(run.get("trainer_id"))
	
	if trainer_id == "scavenger":
		_check_scavenger_targets(manager)
	elif trainer_id == "black_belt" or trainer_id == "blackbelt":
		# Black Belt checks - identifiers to be verified
		_check_blackbelt_notices(run, manager)
	
	# Diagnostic: Log unknown trainer IDs once
	if trainer_id not in ["scavenger", "chemist", "black_belt", "blackbelt", "shopkeeper", ""]:
		if _debug_logging and not _diagnostic_logged:
			_log_message("[DIAGNOSTIC] Unknown trainer_id: %s" % trainer_id)
			_diagnostic_logged = true


func _check_blackbelt_notices(run, manager) -> void:
	"""Check Black Belt Beetbud and fighter warnings."""
	# Diagnostic mode: discover Beetbud and Fighter identifiers (once per shop entry)
	if _debug_logging and not _diagnostic_logged:
		# Check shop for Beetbud
		if _has_property(manager, "current_shop_items"):
			var items: Array = manager.current_shop_items
			for i in range(items.size()):
				var item = items[i]
				if item != null and item.has_method("get_gold_cost") and _has_property(item, "data"):
					var data = item.data
					if data != null and _has_property(data, "name_key"):
						var name_key: String = str(data.name_key)
						if "beet" in name_key.to_lower():
							_log_message("[DIAGNOSTIC] Beetbud candidate name_key: %s" % name_key)
		
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
								var type_name := _resolve_type_name(type_resource)
								if "fight" in type_name.to_lower():
									_log_message("[DIAGNOSTIC] Fighter candidate type: %s (resolved from %s)" % [type_name, _get_object_info(type_resource)])
		
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
			_deep_inspect_shop(state, manager, run)
	elif run_changed or shop_changed or team_changed or bench_changed:
		_log_shop_changes(run, manager, _last_run_state, _last_shop_state, _last_team_state, _last_bench_state)
	
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
			_deep_inspect_battle(state, player, opponent)
		
		_battle_logged = true
	
	_last_phase = "battle"


func _log_phase_entry(phase: String, run, manager = null) -> void:
	var timestamp := "[%s] " % _get_time_short() if _debug_logging else ""
	_log_message("\n%s%s PHASE" % [timestamp, phase])
	
	# Log trainer
	var trainer: Variant = run.get("trainer_id") if _has_property(run, "trainer_id") else "?"
	_log_message("  Trainer: %s" % trainer)
	
	# Log concise run state
	var day: Variant = run.get("current_round") if _has_property(run, "current_round") else "?"
	var wins: Variant = run.get("current_wins") if _has_property(run, "current_wins") else "?"
	var lives: Variant = run.get("lives") if _has_property(run, "lives") else "?"
	var gold: Variant = run.get("gold") if _has_property(run, "gold") else "?"
	var rank: Variant = run.get("shop_rank") if _has_property(run, "shop_rank") else "?"
	var battle_hp: Variant = run.get("player_hp") if _has_property(run, "player_hp") else "?"
	
	_log_message("  Day %s | Rank %s | Lives %s | Battle HP %s | Wins %s | Gold %s" % [day, rank, lives, battle_hp, wins, gold])
	
	# Log shop offers if in shop phase
	if phase == "SHOP" and manager != null:
		_log_message("")
		_log_shop_offers(manager, run, false)  # No context - already printed above
	
	# Log team and bench
	_log_team_compact(run)
	_log_bench_compact(run)


func _print_notice(message: String) -> void:
	"""Print notice to console and log file."""
	print(message)
	_log_message(message)


func _log_shop_offers(manager, run, include_context: bool = true) -> void:
	"""Log current shop offers with prices."""
	if not _has_property(manager, "current_shop_items"):
		return
	
	var items: Array = manager.current_shop_items
	
	if include_context:
		var gold: Variant = run.get("gold") if _has_property(run, "gold") else "?"
		var day: Variant = run.get("current_round") if _has_property(run, "current_round") else "?"
		_log_message("  Day %s | Gold %s" % [day, gold])
	
	_log_message("\n  SHOP:")
	
	for i in range(items.size()):
		var item = items[i]
		if item == null:
			_log_message("    [%d] Empty" % i)
		elif item.has_method("get_gold_cost") and _has_property(item, "data"):
			# Creature
			var name := _format_monster_name(item)
			var level := ""
			if _has_property(item, "level"):
				level = " Lv%s" % item.level
			var price := ""
			if item.has_method("get_gold_cost"):
				price = " | %sg" % item.get_gold_cost()
			_log_message("    [%d] %s%s%s" % [i, name, level, price])
		elif _has_property(item, "id"):
			# Item
			var item_name := str(item.id)
			var price := ""
			if _has_property(item, "cost"):
				price = " | %sg" % item.cost
			_log_message("    [%d] %s (Item)%s" % [i, item_name, price])
		else:
			_log_message("    [%d] Unknown" % i)


func _log_shop_changes(run, manager, old_run: Dictionary, old_shop: Dictionary, old_team: Dictionary, old_bench: Dictionary) -> void:
	var changes := []
	var timestamp := "[%s] " % _get_time_short() if _debug_logging else ""
	
	# Detect run state changes
	var run_changes := _detect_run_changes(run, old_run)
	if not run_changes.is_empty():
		changes.append_array(run_changes)
	
	# Detect shop changes
	var shop_changes := _detect_shop_changes(manager, old_shop)
	if not shop_changes.is_empty():
		changes.append_array(shop_changes)
	
	# Detect team changes
	var team_changes := _detect_team_changes(run, old_team)
	if not team_changes.is_empty():
		changes.append_array(team_changes)
	
	# Detect bench changes
	var bench_changes := _detect_bench_changes(run, old_bench)
	if not bench_changes.is_empty():
		changes.append_array(bench_changes)
	
	if changes.is_empty():
		return
	
	# Determine event type
	var event_type := _infer_event_type(run_changes, shop_changes, team_changes, bench_changes)
	
	_log_message("\n%s%s" % [timestamp, event_type])
	for change in changes:
		_log_message("  %s" % change)
	
	# If shop changed, log current offers
	if not shop_changes.is_empty():
		_log_message("")
		_log_shop_offers(manager, run, true)  # Include context for updates


func _detect_run_changes(run, old_state: Dictionary) -> Array:
	var changes := []
	
	var props := ["current_round", "shop_rank", "lives", "player_hp", "gold", "current_wins"]
	var labels := {"current_round": "Day", "shop_rank": "Rank", "lives": "Lives", 
		"player_hp": "HP", "gold": "Gold", "current_wins": "Wins"}
	
	for prop in props:
		if not _has_property(run, prop):
			continue
		var new_val = run.get(prop)
		var old_val = old_state.get(prop, null)
		if old_val != null and new_val != old_val:
			changes.append("%s: %s -> %s" % [labels.get(prop, prop), old_val, new_val])
	
	return changes


func _detect_shop_changes(manager, old_state: Dictionary) -> Array:
	var changes := []
	
	if _has_property(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		var new_fingerprint: Array = _create_shop_fingerprint(items)
		var old_fingerprint: Array = old_state.get("fingerprint", [])
		
		# Compare fingerprints - check through larger array
		var max_size := max(new_fingerprint.size(), old_fingerprint.size())
		for i in range(max_size):
			var new_slot: Dictionary = new_fingerprint[i] if i < new_fingerprint.size() else {}
			var old_slot: Dictionary = old_fingerprint[i] if i < old_fingerprint.size() else {}
			
			# Compare slot data
			if new_slot != old_slot:
				var old_name := _format_slot_name(old_slot)
				var new_name := _format_slot_name(new_slot)
				if old_name != new_name:
					changes.append("Slot %d: %s -> %s" % [i, old_name, new_name])
	
	if _has_property(manager, "is_shop_frozen"):
		var new_frozen: bool = manager.is_shop_frozen
		var old_frozen: bool = old_state.get("frozen", false)
		if new_frozen != old_frozen:
			changes.append("Shop %s" % ("Locked" if new_frozen else "Unlocked"))
	
	return changes


func _format_slot_name(slot: Dictionary) -> String:
	"""Format a shop slot fingerprint into a readable name."""
	if slot.is_empty() or slot.get("type") == "empty":
		return "Empty"
	
	var slot_type: String = slot.get("type", "unknown")
	if slot_type == "creature":
		var name: String = str(slot.get("id", "Unknown")).capitalize()
		if slot.has("level"):
			name += " Lv%s" % slot.get("level")
		if slot.get("shiny", false):
			name += " Shiny"
		return name
	elif slot_type == "item":
		return "%s (Item)" % str(slot.get("id", "Unknown"))
	
	return "Unknown"


func _detect_team_changes(run, old_state: Dictionary) -> Array:
	var changes := []
	
	if not _has_property(run, "team"):
		return changes
	
	var team: Array = run.team
	var old_monsters: Array = old_state.get("monsters", [])
	
	# Team is stored bottom-right to top-left, reverse for visual order
	# Check through larger array to detect additions/removals
	var max_size := max(team.size(), old_monsters.size())
	for i in range(max_size):
		var visual_slot := team.size() - 1 - i if i < team.size() else old_monsters.size() - 1 - i
		var new_id = team[i].get_instance_id() if i < team.size() and team[i] != null else 0
		var old_id = old_monsters[i] if i < old_monsters.size() else 0
		
		if new_id != old_id:
			var old_name := _get_monster_name(old_monsters[i]) if i < old_monsters.size() and old_monsters[i] != 0 else "Empty"
			var new_name := _get_monster_name(team[i]) if i < team.size() and team[i] != null else "Empty"
			if old_name != new_name:
				changes.append("Team[%d]: %s -> %s" % [visual_slot, old_name, new_name])
	
	return changes


func _detect_bench_changes(run, old_state: Dictionary) -> Array:
	var changes := []
	
	if not _has_property(run, "bench"):
		return changes
	
	var bench: Array = run.bench
	var old_monsters: Array = old_state.get("monsters", [])
	
	# Bench is also stored bottom-right to top-left
	# Check through larger array to detect additions/removals
	var max_size := max(bench.size(), old_monsters.size())
	for i in range(max_size):
		var visual_slot := bench.size() - 1 - i if i < bench.size() else old_monsters.size() - 1 - i
		var new_id = bench[i].get_instance_id() if i < bench.size() and bench[i] != null else 0
		var old_id = old_monsters[i] if i < old_monsters.size() else 0
		
		if new_id != old_id:
			var old_name := _get_monster_name(old_monsters[i]) if i < old_monsters.size() and old_monsters[i] != 0 else "Empty"
			var new_name := _get_monster_name(bench[i]) if i < bench.size() and bench[i] != null else "Empty"
			if old_name != new_name:
				changes.append("Bench[%d]: %s -> %s" % [visual_slot, old_name, new_name])
	
	return changes


func _infer_event_type(run_changes: Array, shop_changes: Array, team_changes: Array, bench_changes: Array) -> String:
	# Don't try to be too clever - just describe what changed
	var parts := []
	
	if not run_changes.is_empty():
		# Check for specific run changes
		var has_day_change := false
		var has_gold_change := false
		for change in run_changes:
			if "Day:" in change:
				has_day_change = true
			if "Gold:" in change:
				has_gold_change = true
		
		if has_day_change:
			parts.append("DAY CHANGED")
		elif has_gold_change and shop_changes.is_empty():
			# Gold changed but shop didn't - might be sell or other action
			pass
	
	if not shop_changes.is_empty():
		# Check if all slots changed (likely reroll) or specific slots
		var slot_changes := 0
		for change in shop_changes:
			if "Slot" in change:
				slot_changes += 1
		
		if slot_changes >= 4:
			parts.append("SHOP REROLL")
		elif slot_changes > 0:
			parts.append("SHOP CHANGED")
		else:
			parts.append("SHOP CHANGED")
	
	if not team_changes.is_empty():
		parts.append("TEAM CHANGED")
	
	if not bench_changes.is_empty():
		parts.append("BENCH CHANGED")
	
	return " + ".join(parts) if not parts.is_empty() else "STATE CHANGED"


func _get_shop_item_name(item_id) -> String:
	# item_id is either an instance ID (int) or an object
	if item_id is int:
		# This is from old state, we can't retrieve the object
		return "Item"
	
	var item = item_id
	if item == null:
		return "Empty"
	
	# Check if it's a creature
	if item.has_method("get_gold_cost") and _has_property(item, "data"):
		var data = item.data
		if data != null and _has_property(data, "name_key"):
			return str(data.name_key)
	
	# Check if it's an item
	if _has_property(item, "id"):
		return str(item.id)
	
	return "Unknown"


func _get_monster_name(monster_id) -> String:
	# monster_id is either an instance ID (int) or an object
	if monster_id is int:
		return "Monster"
	
	var monster = monster_id
	if monster == null:
		return "Empty"
	
	if _has_property(monster, "data"):
		var data = monster.data
		if data != null and _has_property(data, "name_key"):
			var name := str(data.name_key)
			if _has_property(monster, "level"):
				name += " Lv%s" % monster.level
			return name
	
	return "Unknown"


func _log_team_compact(run) -> void:
	if not _has_property(run, "team"):
		return
	
	var team: Array = run.team
	_log_message("\n  TEAM:")
	
	# Reverse order for visual display (game stores bottom-right to top-left)
	for i in range(team.size()):
		var visual_slot := team.size() - 1 - i
		var monster = team[i]
		if monster != null:
			_log_message("    [%d] %s" % [visual_slot, _format_monster_compact(monster)])
		else:
			_log_message("    [%d] Empty" % visual_slot)


func _log_bench_compact(run) -> void:
	if not _has_property(run, "bench"):
		return
	
	var bench: Array = run.bench
	_log_message("\n  BENCH:")
	
	# Reverse order for visual display
	for i in range(bench.size()):
		var visual_slot := bench.size() - 1 - i
		var monster = bench[i]
		if monster != null:
			_log_message("    [%d] %s" % [visual_slot, _format_monster_compact(monster)])
		else:
			_log_message("    [%d] Empty" % visual_slot)


func _format_monster_compact(monster) -> String:
	var parts := []
	
	# Get name and level
	var name := _format_monster_name(monster)
	if _has_property(monster, "level"):
		name += " Lv%s" % monster.level
	if _has_property(monster, "is_shiny") and monster.is_shiny:
		name += " Shiny"
	parts.append(name)
	
	# Get types (always show, not just in deep inspection)
	if _has_property(monster, "data"):
		var data = monster.data
		if data != null and _has_property(data, "types"):
			var types = data.types
			if types is Array and types.size() > 0:
				var type_names := []
				for type_resource in types:
					type_names.append(_resolve_type_name(type_resource))
				parts.append("| %s" % "/".join(type_names))
	
	# Get stats
	if monster.has_method("get_stat"):
		var stats := []
		for stat_id in [1, 2, 3, 4, 5, 6, 7]:
			var value = monster.get_stat(stat_id)
			if value != 0 and (stat_id != 7 or value > 1):
				stats.append("%s %s" % [STAT_NAMES.get(stat_id, str(stat_id)), value])
		if not stats.is_empty():
			parts.append("| %s" % " ".join(stats))
	
	return " ".join(parts) if not parts.is_empty() else "Unknown"


func _deep_inspect_shop(state, manager, run) -> void:
	_log_message("\n--- DEEP INSPECTION: SHOP ---")
	
	# Inspect shop items in detail
	if _has_property(manager, "current_shop_items"):
		var items: Array = manager.current_shop_items
		_log_message("\nShop Items:")
		for i in range(items.size()):
			var item = items[i]
			if item != null:
				_log_message("  [%d] %s" % [i, _inspect_shop_item_deep(item)])


func _inspect_shop_item_deep(item) -> String:
	var lines := []
	
	# Check if it's a creature
	if item.has_method("get_gold_cost") and _has_property(item, "data"):
		var data = item.data
		if data != null:
			lines.append("Creature: %s" % _get_object_info(data))
			
			# Inspect species data
			var props := ["name_key", "tier", "cost", "types", "added_keywords", "ability_script"]
			for prop in props:
				if _has_property(data, prop):
					var value = data.get(prop)
					if value is Array:
						lines.append("  %s: %s" % [prop, _format_array_contents(value)])
					elif value is Script or (value is Object and value.has_method("get_class")):
						lines.append("  %s: %s" % [prop, _get_object_info(value)])
					else:
						lines.append("  %s: %s" % [prop, str(value)])
	
	return "\n    ".join(lines) if not lines.is_empty() else "Unknown item"


func _deep_inspect_battle(state, player, opponent) -> void:
	_log_message("\n--- DEEP INSPECTION: BATTLE ---")
	_log_message("Player: %s" % _get_object_info(player))
	_log_message("Opponent: %s" % _get_object_info(opponent))
	
	if _has_property(state, "is_battle_active"):
		_log_message("Battle Active: %s" % state.is_battle_active)


func _format_array_contents(arr: Array) -> String:
	if arr.is_empty():
		return "[]"
	
	var items := []
	for item in arr:
		if item is String or item is int or item is float or item is bool:
			items.append(str(item))
		elif item is Object:
			items.append(_get_object_info(item))
		else:
			items.append(typeof(item))
	
	return "[%s]" % ", ".join(items)


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
		state["fingerprint"] = _create_shop_fingerprint(items)
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

func _resolve_type_name(type_resource) -> String:
	"""Resolve a monster type Resource into a readable name."""
	if type_resource == null or not is_instance_valid(type_resource):
		return "Unknown"
	
	# Try to find a name or id property
	if _has_property(type_resource, "id"):
		return str(type_resource.id).capitalize()
	if _has_property(type_resource, "name"):
		return str(type_resource.name).capitalize()
	if _has_property(type_resource, "type_name"):
		return str(type_resource.type_name).capitalize()
	
	# Fallback: extract from resource path
	# res://game/monsters/type_data/fire.tres -> Fire
	if type_resource.has_method("get_path"):
		var path: String = type_resource.get_path()
		if path.contains("/type_data/"):
			var filename := path.get_file().get_basename()
			return filename.capitalize()
	
	# Last resort: use resource_path
	var script: Script = type_resource.get_script()
	if script != null:
		var path := str(type_resource.resource_path)
		if path.contains("/type_data/"):
			var filename := path.get_file().get_basename()
			return filename.capitalize()
	
	return "Unknown"


func _format_monster_name(monster) -> String:
	"""Format a readable monster name from name_key."""
	if not _has_property(monster, "data"):
		return "Unknown"
	
	var data = monster.data
	if data == null or not _has_property(data, "name_key"):
		return "Unknown"
	
	var name_key: String = str(data.name_key)
	
	# Try TranslationServer if available
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(name_key)
		if translated != name_key:
			return translated
	
	# Fallback: capitalize the name_key
	# "lamplet" -> "Lamplet"
	# "monster.name.lamplet" -> "Lamplet"
	if "." in name_key:
		name_key = name_key.split(".")[-1]
	
	return name_key.capitalize()


func _create_shop_fingerprint(items: Array) -> Array:
	"""Create a deterministic fingerprint of shop offers."""
	var fingerprint := []
	
	for i in range(items.size()):
		var item = items[i]
		var slot_data := {"slot": i}
		
		if item == null:
			slot_data["type"] = "empty"
		elif item.has_method("get_gold_cost") and _has_property(item, "data"):
			# Creature
			slot_data["type"] = "creature"
			if _has_property(item, "data") and item.data != null:
				if _has_property(item.data, "id"):
					slot_data["id"] = str(item.data.id)
			if _has_property(item, "level"):
				slot_data["level"] = item.level
			if _has_property(item, "is_shiny"):
				slot_data["shiny"] = item.is_shiny
		elif _has_property(item, "id"):
			# Item
			slot_data["type"] = "item"
			slot_data["id"] = str(item.id)
		else:
			slot_data["type"] = "unknown"
		
		fingerprint.append(slot_data)
	
	return fingerprint


func _get_object_info(obj) -> String:
	if obj == null:
		return "null"
	if not is_instance_valid(obj):
		return "invalid"
	
	var obj_class: String = obj.get_class()
	var script: Script = obj.get_script()
	if script != null:
		return "%s @ %s" % [obj_class, str(script.resource_path)]
	return obj_class


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


func _get_timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]


func _get_time_short() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]


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
