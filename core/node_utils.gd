extends RefCounted
## Scene-tree reflection helpers shared by the mod's modules.
##
## Extracted from mod_main.gd. These are static so they can be passed around as
## Callables (e.g. LogFormatter.new(NodeUtils.has_property)) without an instance.

## True when `obj` is a valid instance that exposes `property`.
## `in` is O(1) and avoids allocating the full property list on every call.
static func has_property(obj, property: String) -> bool:
	if not is_instance_valid(obj):
		return false
	return property in obj


## True when `obj`'s script (or any base script) is `script_path`.
static func script_is(obj, script_path: String) -> bool:
	if not is_instance_valid(obj):
		return false
	var script: Script = obj.get_script()
	while script != null:
		if str(script.resource_path) == script_path:
			return true
		script = script.get_base_script()
	return false


## The SceneTree root, or null outside an active scene tree (a headless
## --script run, e.g. the test suite, has a detached root).
static func get_root():
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	var root: Window = (tree as SceneTree).root
	if root == null or not root.is_inside_tree():
		return null
	return root


## An autoload node by name (e.g. "GameDatabase"), or null when unavailable.
static func get_autoload(autoload_name: String):
	var root = get_root()
	if root == null:
		return null
	return root.get_node_or_null("/root/" + autoload_name)


## `obj.get(property)` when present, else `fallback`. A present-but-null value is
## returned as null, matching a plain `get`.
static func get_or(obj, property: String, fallback = null):
	if not has_property(obj, property):
		return fallback
	return obj.get(property)


## `obj.get(property)` as an int, or `fallback` when absent or null.
static func int_or(obj, property: String, fallback: int) -> int:
	var value = get_or(obj, property, null)
	if value == null:
		return fallback
	return int(value)


## True when `obj` (an Object or Dictionary) exposes `field`.
static func has_field(obj, field: String) -> bool:
	if obj is Dictionary:
		return obj.has(field)
	return has_property(obj, field)


## `obj.get(field)` for an Object or Dictionary, or `fallback` when absent or
## invalid.
static func field_or(obj, field: String, fallback = null):
	if obj == null:
		return fallback
	if obj is Dictionary:
		return obj.get(field, fallback)
	if not is_instance_valid(obj):
		return fallback
	if not (field in obj):
		return fallback
	return obj.get(field)


## A trimmed String field of an Object or Dictionary, or "" when absent.
static func string_field(obj, field: String) -> String:
	var value = field_or(obj, field, null)
	if value == null:
		return ""
	return str(value).strip_edges()


## The game's current state object from the active scene, or null.
static func current_state(tree = null):
	if tree == null:
		var loop = Engine.get_main_loop()
		if not (loop is SceneTree):
			return null
		tree = loop
	if tree == null or tree.current_scene == null:
		return null
	return get_or(tree.current_scene, "current_state", null)


## Connect `handler` to the viewport's size_changed once, when a viewport exists.
static func connect_viewport_resize(node: Node, handler: Callable) -> void:
	if node == null or not node.is_inside_tree():
		return
	var viewport := node.get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(handler):
		viewport.size_changed.connect(handler)


## Disconnect `handler` from the viewport's size_changed, when connected.
static func disconnect_viewport_resize(node: Node, handler: Callable) -> void:
	if node == null or not node.is_inside_tree():
		return
	var viewport := node.get_viewport()
	if viewport != null and viewport.size_changed.is_connected(handler):
		viewport.size_changed.disconnect(handler)
