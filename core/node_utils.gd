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
