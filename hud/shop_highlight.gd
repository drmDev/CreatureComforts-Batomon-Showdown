extends Node
## Node-attached shop highlighting driven by the watchlist selection.
##
## Detects shop_slot_ui cards as they appear (including rerolls and purchases)
## and attaches a full-rect overlay child to each. The overlay reads the card's
## live current_content every frame, so highlights follow rerolls and never use
## stale coordinates. Non-blocking (mouse_filter IGNORE) and deduplicated by
## node name, so repeated detection cannot stack overlays.

const CARD_SCRIPT := "shop_slot_ui"
const OVERLAY_NAME := "CreatureComfortsHighlight"
const BORDER_COLOR := Color(1.0, 0.85, 0.2, 0.95)
const FILL_COLOR := Color(1.0, 0.85, 0.2, 0.10)
const BORDER_WIDTH := 2.0

var _watchlist = null
var _enabled := true
var _overlays: Array = []  # weakrefs to attached overlays


## `watchlist` is the panel's selection dictionary, shared by reference so
## selection changes apply on the next frame without extra wiring.
func setup(watchlist) -> void:
	_watchlist = watchlist
	if get_tree() != null and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	_scan.call_deferred(get_tree().root)


## Enable/disable highlighting. Existing overlays clear immediately when off.
func set_enabled(on: bool) -> void:
	_enabled = on
	var live: Array = []
	for ref in _overlays:
		var overlay = ref.get_ref()
		if overlay != null:
			overlay.enabled = on
			live.append(ref)
	_overlays = live


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node) -> void:
	if not node is Control:
		return
	var script = node.get_script()
	if script == null:
		return
	if str(script.resource_path.get_file().get_basename()) != CARD_SCRIPT:
		return
	_attach.call_deferred(weakref(node))


func _scan(node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_scan(child)


func _attach(reference) -> void:
	var card = reference.get_ref()
	if card == null or not card.is_inside_tree() or card.is_queued_for_deletion():
		return
	if card.has_node(OVERLAY_NAME):
		return
	var overlay = HighlightOverlay.new()
	overlay.name = OVERLAY_NAME
	overlay.watchlist = _watchlist
	overlay.enabled = _enabled
	card.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlays.append(weakref(overlay))


class HighlightOverlay extends Control:
	var watchlist = null
	var enabled := true
	var _active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		z_index = 2

	func _process(_delta: float) -> void:
		if not is_visible_in_tree():
			return
		var next := enabled and _matches()
		if next != _active:
			_active = next
			queue_redraw()

	func _matches() -> bool:
		if watchlist == null:
			return false
		var card = get_parent()
		if card == null or not ("current_content" in card):
			return false
		var content = card.get("current_content")
		if content == null or not is_instance_valid(content):
			return false
		# MonsterInstance exposes data.name_key; ItemData exposes id.
		if content.has_method("get_gold_cost") and ("data" in content):
			var data = content.get("data")
			if data != null and ("name_key" in data):
				return watchlist.get("monster", {}).has(str(data.get("name_key")))
		elif "id" in content:
			return watchlist.get("item", {}).has(str(content.get("id")))
		return false

	func _draw() -> void:
		if not _active:
			return
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, FILL_COLOR, true)
		draw_rect(r, BORDER_COLOR, false, BORDER_WIDTH)
