extends Node
## Creature Comforts - QOL
const VERSION := "3.313"

const LogFormatterScript = preload("core/log_formatter.gd")
const ShopOverlayGate = preload("hud/shop_overlay_gate.gd")
const ChimeQueue = preload("core/chime_queue.gd")
const TrinketIcons = preload("core/trinket_icons.gd")
const ComfortUi = preload("hud/comfort_ui.gd")
const NodeUtils = preload("core/node_utils.gd")
const ModLogger = preload("core/mod_logger.gd")
const ModConfig = preload("core/mod_config.gd")
const AutoUpdater = preload("core/auto_updater.gd")
const RuntimeContext = preload("core/runtime_context.gd")
const DevTools = preload("core/dev_tools.gd")
const ShopController = preload("core/shop_controller.gd")
const BattleCoordinator = preload("core/battle_coordinator.gd")
const PhaseRouter = preload("core/phase_router.gd")

var _initialization_started := false
var _initialized := false

# Shared collaborators: formatter, logger, config, chimes, trinket icons.
var _context = null

# Debug-gated hotkeys and diagnostics dumps (core/dev_tools.gd).
var _dev_tools = null

# Shop-phase orchestration (core/shop_controller.gd).
var _shop = null

# Battle-phase orchestration (core/battle_coordinator.gd).
var _battle = null

# Phase detection and dispatch (core/phase_router.gd).
var _router = null

# Owns the CanvasLayers and panels (hud/comfort_ui.gd).
var _ui = null
var _shop_overlay_gate = null

# Self-updater: checks the GitHub release manifest and swaps files (core/auto_updater.gd).
var _updater = null


func mod_ready() -> void:
	_initialize_mod()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_loaded_by_mod_loader():
		_initialize_mod()


func _exit_tree() -> void:
	# Drop the loader subscription so a freed mod node is never called back.
	if _context != null and _context.config != null:
		_context.config.teardown()
	if _context != null and _context.logger != null:
		_context.logger.close()


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true

	var formatter = LogFormatterScript.new(NodeUtils.has_property)
	var logger = ModLogger.new(formatter)
	_dev_tools = DevTools.new(logger)

	var config = ModConfig.new()
	config.setup(get_node_or_null("/root/ModLoader"))

	var chimes = ChimeQueue.new()
	var trinket_icons = TrinketIcons.new()
	_context = RuntimeContext.new(formatter, logger, config, chimes, trinket_icons)
	chimes.setup(self, _context.sounds_enabled)

	_ui = ComfortUi.new()
	_ui.name = "ComfortUi"
	add_child(_ui)
	_ui.setup(_context)

	_setup_shop_overlay_gate()

	_battle = BattleCoordinator.new()
	_battle.setup(_context, _ui)

	_shop = ShopController.new()
	_shop.setup(_context, _ui, _shop_overlay_gate, _dev_tools, _on_shop_entered, _on_shop_run_changed)

	_router = PhaseRouter.new()
	_router.setup(self, _context, _ui, _shop, _battle)

	_setup_auto_updater()
	_setup_transition_capture()

	# The UI is live and the overlay gate must run even if the log file cannot be
	# opened; the logger no-ops when its file handle is null.
	_initialized = true
	# Connect only after every subsystem exists, so an early config change
	# cannot dereference a null panel.
	_context.config.changed.connect(_on_feature_toggled)

	var abs_log_path: String = _context.logger.open(VERSION)
	if abs_log_path.is_empty():
		return

	if _context.logger.debug_logging:
		# Catalog overview for troubleshooting; deferred so autoloads such as
		# GameDatabase exist.
		_dev_tools.log_catalog_deferred()

	print("Creature Comforts %s loaded - logging to %s" % [VERSION, abs_log_path])


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
		_context.feature_enabled(ModConfig.KEY_AUTO_UPDATE))
	_updater.start()


func _on_shop_visibility_changed(allowed: bool, _reason: String) -> void:
	if _ui.apply_gate(allowed):
		_context.chimes.try_play(_shop_overlay_gate)


## The battle transition signal carries the opponent RunData (MMR / bot flags).
## The shop overlay gate owns the game subscription and forwards it here, so
## there is only one transition listener in the mod.
func _setup_transition_capture() -> void:
	if _shop_overlay_gate != null:
		_shop_overlay_gate.transition_requested.connect(_battle.on_transition)


## A new shop visit begins: reset the once-per-battle log guard.
func _on_shop_entered() -> void:
	_battle.reset_log_guard()


## A new run (or trainer) starts: drop any battle trinket gains from the previous run.
func _on_shop_run_changed() -> void:
	_battle.on_run_changed()


## Apply a live settings change. Disabling a feature hides its UI immediately and
## drops any queued sound; enabling lets the next poll re-show it. Panels are
## created once at startup, so toggling never duplicates UI or subscriptions.
func _on_feature_toggled(key: String, value: bool) -> void:
	_ui.on_feature_toggled(key, value)
	_shop.on_feature_toggled(key, value)
	if key == ModConfig.KEY_NOTIFICATION_SOUNDS:
		_context.chimes.clear()
	elif key == ModConfig.KEY_TRINKETS_GAINED_PANEL:
		_battle.hide_trinket_gains()
	elif key == ModConfig.KEY_AUTO_UPDATE:
		_updater.set_auto(value)


func _process(_delta: float) -> void:
	if not _initialized:
		return
	if _shop_overlay_gate != null:
		_shop_overlay_gate.update()

	_dev_tools.poll(_context.logger)
	_router.poll()


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
