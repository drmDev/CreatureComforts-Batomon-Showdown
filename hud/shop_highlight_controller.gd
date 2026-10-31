extends RefCounted
## NOT WIRED UP IN v1. Shop-card highlighting is deferred to a v2 release; this
## controller keeps the integration logic (target building + live rect resolution)
## out of mod_main so it can be re-enabled without re-tangling the main loop.

const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const TrainerRules = preload("../advice/trainer_rules.gd")
const ShopHighlightScript = preload("shop_highlight.gd")

var _overlay = null
var _tree: SceneTree = null


func setup(parent: Node, tree: SceneTree) -> void:
	_tree = tree
	_overlay = ShopHighlightScript.new()
	_overlay.name = "ShopHighlight"
	_overlay.setup(_resolve_rects)
	parent.add_child(_overlay)


func update(all_active: Array) -> void:
	if _overlay == null:
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
	_overlay.set_targets(targets)


func clear() -> void:
	if _overlay != null:
		_overlay.clear_targets()


func _resolve_rects(targets: Array) -> Array:
	var rects: Array = []
	if targets.is_empty() or _tree == null:
		return rects

	var main = _tree.current_scene
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


func _script_is(obj, script_path: String) -> bool:
	if not is_instance_valid(obj):
		return false
	var script: Script = obj.get_script()
	while script != null:
		if str(script.resource_path) == script_path:
			return true
		script = script.get_base_script()
	return false
