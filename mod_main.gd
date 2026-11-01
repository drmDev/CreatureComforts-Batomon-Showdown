extends Node
## Creature Comforts - QOL
const VERSION := "1.137"
const OUTPUT_DIR := "user://creature_comforts"
const LOG_FILE := "inspect.log"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

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
const TrinketGains = preload("core/trinket_gains.gd")
const RunRegion = preload("core/run_region.gd")
const RunData = preload("core/run_data.gd")
const ShopHighlight = preload("hud/shop_highlight.gd")
const DevConfig = preload("dev/dev_config.gd")
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

# Investigation diagnostics: catalog dump runs once, on the first shop entry
# with Debug Logging on (so it works if logging was toggled after startup).
var _catalog_diagnostics_logged := false
# The run-data variable dump is a session-once diagnostic; the short detected
# region line is repeated per shop visit.
var _region_diagnostics_logged := false

# Dev-only toggles (not user-facing settings). Startup defaults come from
# dev/dev_config.gd; flip them live with the key combos in _handle_dev_toggles().
var _debug_logging := DevConfig.DEBUG_LOGGING
var _deep_inspection := DevConfig.DEEP_INSPECTION
# Ctrl+Shift dev toggle keys
var _dev_toggle_debug_was_down := false
var _dev_toggle_inspect_was_down := false

var _log_path := ""
var _log_file: FileAccess = null  # Kept open for the session; avoids open/close per line
var _formatter = null

var _advisor = null
var _advice_context_builder = null

var _snapshot_builder = null
var _changes_comparer = null

var _reminder_label = null
var _reminder_layer: CanvasLayer = null
var _shop_overlay_gate = null
var _pika_player: AudioStreamPlayer = null
var _poke_item_player: AudioStreamPlayer = null

# Chime queue: rule_ids whose day reminder fired since the last play
var _pending_chime_rule_ids: Dictionary = {}
# Trinket-reminder sound queued until the overlay gate opens
var _pending_trinket_reminder_sound := false

var _trainer_display_names: Dictionary = {}

var _trinket_panel = null

var _shop_income_panel = null

var _trinket_reminders_panel = null
var _trinket_reminders_alerted := false
var _last_trinket_reminder_entries: Dictionary = {}  # name -> count, for change-only logging

var _rank_odds_panel = null
var _rank_odds_popup_open := false
var _watchlist_panel = null
var _shop_highlight = null
var _last_reminder_rule_ids: Dictionary = {}

# Trinket/passive gold_gain bonuses are added on top of the base schedule.
const BASE_INCOME := 35
const INCOME_PER_DAY := 5

# IDs follow the game's snake_case convention (e.g. "treasure_map").
const TRACKED_TRINKET_DESCRIPTIONS := {
	"mini_duplicator": "Next non-unique trinket gift: +1 copy",
	"mega_duplicator": "Next non-unique trinket gift: +2 copies",
	"treasure_map": "Next trinket gift: +1 rarity tier",
	"upgrade_disc": "Next monster purchase: +1 level",
	"greedy_gloves": "Next Trinket gift: take all choices",
}

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
	# Drop the loader subscription so a freed mod node is never called back.
	if _mod_config != null:
		_mod_config.teardown()
		_mod_config = null
	if _log_file != null:
		_log_file.close()
		_log_file = null


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	
	_formatter = LogFormatterScript.new(_has_property)
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
	# opened; _log_message already no-ops when _log_file is null.
	_initialized = true
	
	var dir_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_error("Creature Comforts: Failed to create directory %s: %s" % [dir_path, error_string(dir_result)])
		return
	
	_log_path = OUTPUT_DIR.path_join(LOG_FILE)
	var abs_log_path := ProjectSettings.globalize_path(_log_path)
	
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
	
	_log_message("=".repeat(80))
	_log_message("Creature Comforts %s " % VERSION)
	_log_message("Initialized at %s" % _formatter.get_timestamp())
	_log_message("Dev toggles: Debug Logging: %s | Deep Inspection: %s" % [_debug_logging, _deep_inspection])
	_log_message("Log file: %s" % abs_log_path)
	_log_message("=".repeat(80))
	
	if _debug_logging:
		# Catalog overview for troubleshooting; deferred so autoloads such as
		# GameDatabase exist.
		call_deferred("_log_catalog_diagnostics")
	
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


## --- Diagnostics -----------------------------------------------------------
## Gated by Debug Logging. One-shot catalog overview plus the region dump (the
## latter lives in core/run_region.gd).

func _log_catalog_diagnostics() -> void:
	_catalog_diagnostics_logged = true
	_log_message("GAMEDB DIAG | === begin ===")
	var db = get_node_or_null("/root/GameDatabase")
	if db == null:
		_log_message("GAMEDB DIAG | /root/GameDatabase not found")
	else:
		var db_script: Script = db.get_script()
		_log_message("GAMEDB DIAG | node=%s class=%s script=%s" % [
			db.name, db.get_class(), str(db_script.resource_path) if db_script != null else "(none)"])
		for prop in db.get_property_list():
			if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_log_message("GAMEDB DIAG | var %s: %s" % [
					str(prop.get("name", "")), type_string(int(prop.get("type", TYPE_NIL)))])
		var tokens := ["species", "monster", "batomon", "catalog", "icon", "portrait", "sprite", "item", "get_all", "all_"]
		var method_names: Array = []
		for method in db.get_method_list():
			var mname := str(method.get("name", ""))
			if mname.begins_with("_"):
				continue
			for token in tokens:
				if mname.to_lower().contains(token):
					method_names.append(mname)
					break
		_log_message("GAMEDB DIAG | interesting methods (%d): %s" % [method_names.size(), ", ".join(method_names)])
		# Catalog shape for the watchlist filters.
		if "items_db" in db:
			var items = db.get("items_db")
			if items is Array:
				_log_message("CATALOG DIAG | items_db size=%d" % items.size())
				if not items.is_empty() and items[0] != null:
					var item_vars: Array = []
					for prop in items[0].get_property_list():
						if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
							item_vars.append(str(prop.get("name", "")))
					_log_message("CATALOG DIAG | first item vars: %s" % ", ".join(item_vars))
		if "items_by_pool" in db:
			var pools = db.get("items_by_pool")
			if pools is Dictionary:
				_log_message("CATALOG DIAG | items_by_pool keys: %s" % ", ".join(pools.keys()))
		if db.has_method("get_all_species"):
			var species_list = db.get_all_species()
			if species_list is Array:
				if not species_list.is_empty() and species_list[0] != null:
					var species_vars: Array = []
					for prop in species_list[0].get_property_list():
						if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
							species_vars.append(str(prop.get("name", "")))
					_log_message("CATALOG DIAG | first species vars: %s" % ", ".join(species_vars))
				var histogram := {}
				for s in species_list:
					if s == null:
						continue
					var tier := int(s.get("tier")) if "tier" in s else 0
					histogram[tier] = histogram.get(tier, 0) + 1
				_log_message("CATALOG DIAG | species count=%d tier histogram=%s" % [species_list.size(), str(histogram)])
	_log_message("GAMEDB DIAG | === end ===")


func _log_shop_structure_diagnostic(state) -> void:
	_log_message("SHOP DIAG | === begin ===")
	var view = state.get("view") if _has_property(state, "view") else null
	if view == null or not is_instance_valid(view):
		_log_message("SHOP DIAG | state.view not found")
		_log_message("SHOP DIAG | === end ===")
		return
	var view_script: Script = view.get_script()
	_log_message("SHOP DIAG | view=%s class=%s script=%s path=%s" % [
		view.name, view.get_class(), str(view_script.resource_path) if view_script != null else "(none)", view.get_path()])
	if _has_property(view, "shop_slots"):
		var slots = view.get("shop_slots")
		_log_message("SHOP DIAG | view.shop_slots type=%s size=%s" % [
			type_string(typeof(slots)), str(slots.size() if slots is Array else "n/a")])
	else:
		_log_message("SHOP DIAG | view.shop_slots NOT found")
	_log_message("SHOP DIAG | view direct children:")
	for child in view.get_children():
		_log_message("SHOP DIAG |   %s" % _describe_node(child))
	var cards: Array = []
	_collect_shop_cards(view, cards)
	_log_message("SHOP DIAG | shop_slot_ui cards found: %d" % cards.size())
	for card in cards:
		_log_message("SHOP DIAG |   card %s" % _describe_shop_card(card))
	_log_message("SHOP DIAG | === end ===")


func _collect_shop_cards(node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		var script: Script = node.get_script()
		if script != null and str(script.resource_path.get_file().get_basename()) == ShopHighlight.CARD_SCRIPT:
			out.append(node)
	for child in node.get_children():
		_collect_shop_cards(child, out)


func _describe_node(node) -> String:
	if node == null or not is_instance_valid(node):
		return "(invalid)"
	var script: Script = node.get_script()
	var script_name := str(script.resource_path.get_file().get_basename()) if script != null else ""
	var visible := ""
	if node is CanvasItem:
		visible = " visible=%s" % node.is_visible_in_tree()
	return "%s (%s) script=%s%s" % [node.name, node.get_class(), script_name, visible]


func _describe_shop_card(card) -> String:
	var content = card.get("current_content") if _has_property(card, "current_content") else null
	var content_desc := "none"
	if content != null and is_instance_valid(content):
		var kind := "other"
		var key := ""
		# Raw shop entries expose get_gold_cost()+data (monster) or id (item),
		# matching ShopSnapshot.is_monster_offer()/classify_shop_entry().
		if content.has_method("get_gold_cost") and _has_property(content, "data"):
			kind = "monster"
			var data = content.get("data")
			if data != null and _has_property(data, "name_key"):
				key = str(data.get("name_key"))
		elif _has_property(content, "id"):
			kind = "item"
			key = str(content.get("id"))
		var content_script: Script = content.get_script() if content is Object else null
		content_desc = "%s id=%s key=%s script=%s" % [
			kind, str(content.get_instance_id()), key,
			str(content_script.resource_path) if content_script != null else "(none)"]
	var rect := ""
	if card is Control:
		rect = " rect=%s" % card.get_global_rect()
	return "%s (%s)%s content=[%s]" % [card.name, card.get_class(), rect, content_desc]


## Reports what core/run_region.gd found (and everything it inspected) so an
## unexpected watchlist Region default can be traced to the field the game
## actually stores the active region/set in.
func _log_region_diagnostic() -> void:
	# verbose (run-data variable dump) is a session-once diagnostic: it allocates
	# the 100+ name list, so it is not repeated on every shop visit.
	var verbose := not _region_diagnostics_logged
	var result = RunRegion.detect(verbose)
	var detected := str(result.get("region", ""))
	_log_message("REGION DIAG | === begin ===")
	_log_message("REGION DIAG | detected region: %s" % (detected if not detected.is_empty() else "(none)"))
	for line in result.get("report", []):
		_log_message("REGION DIAG | %s" % str(line))
	_log_message("REGION DIAG | === end ===")
	_region_diagnostics_logged = true


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
	_rank_odds_panel.log_line.connect(_log_event)
	_rank_odds_panel.popup_visibility_changed.connect(_on_rank_odds_popup_visibility_changed)
	_reminder_layer.add_child(_rank_odds_panel)

	# Watchlist button + popup; shop-gated with the rest of the reminder layer.
	var WatchlistPanel = load(_base_dir().path_join("hud/watchlist_panel.gd"))
	_watchlist_panel = WatchlistPanel.new()
	_watchlist_panel.name = "WatchlistPanel"
	_watchlist_panel.setup(_formatter)
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
	_shop_overlay_gate.setup(_has_property, _script_is)


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
	if not _debug_logging:
		return
	for line in message.split("\n"):
		_log_message(line)


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
	if not _feature_enabled(ModConfig.KEY_NOTIFICATION_SOUNDS):
		return
	if _pika_player != null and _pika_player.stream != null:
		_pika_player.play()


func _play_poke_item() -> void:
	"""Play notification sound for new trinket reminders."""
	if not _feature_enabled(ModConfig.KEY_NOTIFICATION_SOUNDS):
		return
	if _poke_item_player != null and _poke_item_player.stream != null:
		_poke_item_player.play()


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
		if _watchlist_panel != null:
			_watchlist_panel.close_popup()
	if not is_battle:
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _last_phase == "battle":
			_reset_battle_completion()
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
	if _player_hud == null:
		return
	if not _feature_enabled(ModConfig.KEY_BATTLE_STATUS_PANEL):
		_player_hud.visible = false
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
			
			var full_message := ""
			if not prefix.is_empty():
				full_message = "*** COMFORTS %s | %s | %s" % [severity, prefix, message]
			else:
				full_message = "*** COMFORTS %s | %s" % [severity, message]
			
			_print_notice(full_message)
		
		# Queue the chime for chime-flagged rules (day reminders); played once the overlay is showing
		if advice.get("chime", false) and _feature_enabled(ModConfig.KEY_DAY_REMINDERS):
			_pending_chime_rule_ids[advice.get("rule_id", "")] = true
			_log_event("DAY REMINDER | %s | %s" % [advice.get("rule_id", ""), message])
	
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
	if _pending_chime_rule_ids.is_empty() and not _pending_trinket_reminder_sound:
		return
	if _shop_overlay_gate == null or _shop_overlay_gate.is_allowed():
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
	
	var current_snapshot = _snapshot_builder.capture(run, manager, _has_property, _formatter.resolve_type_name)
	
	var phase_changed := _last_phase != "shop"
	
	var trainer_changed := false
	if _last_snapshot != null:
		trainer_changed = _last_snapshot.trainer_id != current_snapshot.trainer_id
	
	if phase_changed:
		_battle_logged = false
		if _shop_overlay_gate != null:
			_shop_overlay_gate.reset_for_shop()
		_log_phase_entry("SHOP", run, manager)
		if _debug_logging:
			if not _catalog_diagnostics_logged:
				_log_catalog_diagnostics()
			_log_shop_structure_diagnostic(state)
			_log_region_diagnostic()
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
	
	_evaluate_trainer_advice(current_snapshot)
	
	_update_shop_income(run)
	_update_trinket_reminders(run)
	_update_rank_odds(run)

	# (overlay visibility is handled every frame by the shop overlay gate)
	
	_last_phase = "shop"
	_last_snapshot = current_snapshot


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
	var rank := int(run.get("shop_rank")) if _has_property(run, "shop_rank") else 1
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


func _reset_battle_completion() -> void:
	_battle_completion_state_id = 0
	_battle_completion_reported = false


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


func _capture_trinket_state(run) -> Dictionary:
	var snapshot := {}
	var ids = run.get("trinket_ids") if _has_property(run, "trinket_ids") else []
	# Copy the lists so the battle_over snapshot stays frozen if the game mutates the live data.
	snapshot["trinket_ids"] = ids.duplicate() if ids != null else []
	snapshot["trinkets_gained_total"] = int(run.get("trinkets_gained_total")) if _has_property(run, "trinkets_gained_total") else 0
	var used = run.get("used_trinket_ids") if _has_property(run, "used_trinket_ids") else []
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
			var gains := TrinketGains.diff_states(_battle_trinket_start, _battle_trinket_end)
			if not _battle_gains_logged and (not gains["ids"].is_empty() or int(gains["counter"]) != 0):
				_battle_gains_logged = true
				for tid in gains["ids"]:
					_log_event("TRINKET ACQUIRED | %s" % str(tid))
				if _deep_inspection:
					_log_lines(_formatter.format_battle_trinket_gains(gains))
			if _deep_inspection:
				# Diagnostic: changes applied after the freeze (e.g. event rewards) are excluded.
				var live := _capture_trinket_state(run)
				var post := TrinketGains.diff_states(_battle_trinket_end, live)
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
	_log_event(_formatter.format_phase_entry(phase, run))
	if _deep_inspection:
		_log_lines(_formatter.format_phase_snapshot(phase, run, manager))


func _log_event(message: String) -> void:
	_log_message("[%s] %s" % [_formatter.get_time_short(), message])


func _print_notice(message: String) -> void:
	print(message)
	_log_message(message)


func _log_lines(lines: Array) -> void:
	for line in lines:
		_log_message(line)


func _has_property(obj, property: String) -> bool:
	if not is_instance_valid(obj):
		return false
	# `in` is O(1) and avoids allocating the full property list on every call.
	# This runs several times per frame from the shop overlay gate.
	return property in obj


func _script_is(obj, script_path: String) -> bool:
	if not is_instance_valid(obj):
		return false
	var script: Script = obj.get_script()
	while script != null:
		if str(script.resource_path) == script_path:
			return true
		script = script.get_base_script()
	return false


func _base_dir() -> String:
	return str(get_script().resource_path).get_base_dir()


func _get_run_data():
	return RunData.get_run_data()


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
