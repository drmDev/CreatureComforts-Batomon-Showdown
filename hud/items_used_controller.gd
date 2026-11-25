extends RefCounted
## Feeds the Items Used panel and records item uses for the current run.
##
## A use is one shop item purchase: ShopManager increments
## blackboard.items_bought_this_round and emits item_bought(index) BEFORE the
## slot is refilled, so reading current_shop_items[index] there yields the item
## id exactly once. The same signal also fires for monster purchases, so those
## are filtered out. Daily figures come straight from the game state.
##
## Tracking is independent of the panel: uses are still recorded while the panel
## is collapsed, hidden, or disabled by its setting.

const NodeUtils = preload("../core/node_utils.gd")
const RunData = preload("../core/run_data.gd")
const ShopSnapshot = preload("../core/shop_snapshot.gd")
const ItemUsageTracker = preload("../core/item_usage_tracker.gd")
const ModConfig = preload("../core/mod_config.gd")

var _panel = null
var _context = null
var _tracker = null
var _manager = null
var _run_id := ""
var _icon_cache := {}  # item id -> Texture2D (or null), avoids per-poll DB scans


func setup(panel, context) -> void:
	_panel = panel
	_context = context
	_tracker = ItemUsageTracker.new()


## Refresh the panel from the current run and bind the shop's use signal.
func update(run, manager) -> void:
	_sync_run(run)
	_bind_manager(manager)
	if _panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_ITEM_USAGE_TRACKER):
		_panel.hide_panel()
		return
	_panel.show_usage(_snapshot(run))


## Daily used and allowance straight from the game state.
## `items_bought_this_round` counts items bought (and applied) in the shop; the
## allowance includes Membership Card and similar trinket bonuses.
static func daily_counts(run) -> Dictionary:
	var used := 0
	var allowance := 1
	var blackboard = NodeUtils.get_or(run, "blackboard", null)
	if blackboard is Dictionary:
		used = int(blackboard.get("items_bought_this_round", 0))
		allowance = int(blackboard.get("max_items_per_round", 1))
	if run is Object and is_instance_valid(run) and run.has_method("get_shop_item_budget"):
		allowance = int(run.get_shop_item_budget())
	return {"used": used, "allowance": allowance}


func _sync_run(run) -> void:
	var id := RunData.identity(run)
	if id == _run_id:
		return
	_run_id = id
	_tracker.load_run(id)


func _bind_manager(manager) -> void:
	if manager == _manager and is_instance_valid(_manager):
		return
	_unbind_manager()
	_manager = manager
	if _manager != null and is_instance_valid(_manager) \
			and _manager.has_signal("item_bought") \
			and not _manager.item_bought.is_connected(_on_item_bought):
		_manager.item_bought.connect(_on_item_bought)


func _unbind_manager() -> void:
	if _manager != null and is_instance_valid(_manager) \
			and _manager.has_signal("item_bought") \
			and _manager.item_bought.is_connected(_on_item_bought):
		_manager.item_bought.disconnect(_on_item_bought)
	_manager = null


## A shop purchase completed. The signal fires for monsters too; only item slots
## (still holding their ItemData at emit time) are recorded.
func _on_item_bought(index: int) -> void:
	var item = _item_at(index)
	if item == null:
		return
	var item_id := str(item.get("id"))
	if item_id.is_empty() or not _tracker.record_use(item_id):
		return
	_context.logger.log_event("ITEM USED | %s" % item_id)
	if _panel != null and _context.feature_enabled(ModConfig.KEY_ITEM_USAGE_TRACKER):
		_panel.show_usage(_snapshot(RunData.get_run_data()))


func _item_at(index: int):
	if _manager == null or not is_instance_valid(_manager):
		return null
	var items = NodeUtils.get_or(_manager, "current_shop_items", null)
	if not (items is Array) or index < 0 or index >= items.size():
		return null
	var item = items[index]
	if item == null or not NodeUtils.has_property(item, "id"):
		return null
	if ShopSnapshot.is_monster_offer(item, NodeUtils.has_property):
		return null
	return item


func _snapshot(run) -> Dictionary:
	var daily := daily_counts(run)
	var entries = _tracker.entries(_context.formatter)
	for entry in entries:
		entry["icon"] = _icon_for(str(entry.get("id", "")))
	return {
		"day_used": int(daily["used"]),
		"day_allowance": int(daily["allowance"]),
		"entries": entries,
	}


func _icon_for(item_id: String) -> Texture2D:
	if _context == null or _context.item_icons == null:
		return null
	# Cache hits only: a null means the database was not ready yet, so retry.
	var cached = _icon_cache.get(item_id)
	if cached != null:
		return cached
	var texture: Texture2D = _context.item_icons.icon(item_id)
	if texture != null:
		_icon_cache[item_id] = texture
	return texture
