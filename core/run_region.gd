extends RefCounted
## Resolves the region the player is currently running in (e.g. "Jinto", "Pantra").
##
## The game exposes no documented "current region" field, so this probes a list of
## plausible property names on RunManager, its `data` object, and a few state
## autoloads; any catalog id it finds is mapped through `sets_db` /
## `species_packs_db` to a display name. Region display names must line up with the
## watchlist's species `region` values (species.sets -> set name), which is why the
## same id -> name mapping is used.
##
## `detect()` returns `{ "region": String, "report": Array[String] }` so callers can
## log exactly what was inspected while troubleshooting.

## Property names that could carry the active region/set/pack, most likely first.
## `active_set_id` is the field RunManager.data actually exposes.
const CANDIDATE_KEYS := [
	"active_set_id",
	"region", "regions", "current_region", "region_id", "region_name",
	"set", "sets", "current_set", "active_set", "set_id", "home_set",
	"species_pack", "species_packs", "pack", "current_pack", "pack_id",
	"origin", "zone", "area", "map", "map_id",
]

## Autoload singletons that may own the run/region state.
const CANDIDATE_AUTOLOADS := [
	"RunManager", "GameState", "RunState", "GameManager", "ProgressManager", "SaveManager",
]

## Fields to read off an object found in one of the candidate properties.
const OBJECT_NAME_FIELDS := ["id", "name", "name_key"]

## Catalog collections (on GameDatabase) that map ids to display names.
const ALIAS_COLLECTIONS := ["sets_db", "species_packs_db"]


## Detects the current region. `has_property` is an optional
## `func(obj, name) -> bool`; when omitted, `name in obj` is used.
##
## Cost: one property read per candidate key on the first source that answers
## (`RunManager.data`, normally the very first), plus a small alias-map walk.
## `verbose` additionally dumps the run data's script variable names, which
## allocates a 100+ element array - only the diagnostic logger asks for that.
static func detect(has_property: Callable = Callable(), verbose := false) -> Dictionary:
	var report: Array = []
	var aliases := build_alias_map(null)
	for source in collect_sources():
		var obj = source.get("object")
		var label := str(source.get("label", "?"))
		if obj == null or not (obj is Object or obj is Dictionary):
			continue
		if verbose and obj is Object and not (obj is Node):
			# Property names of the run data object, so a field we did not guess
			# can still be identified from the log.
			report.append("%s: %s" % [label, describe_properties(obj)])
		var hit := _scan_object(obj, aliases, has_property, report, label)
		if not hit.is_empty():
			return {"region": hit, "report": report}
	return {"region": "", "report": report}


## Live candidate sources, in priority order: the run data first, then its owner.
static func collect_sources() -> Array:
	var out: Array = []
	var root = _get_root()
	if root == null:
		return out
	for node_name in CANDIDATE_AUTOLOADS:
		var node = root.get_node_or_null("/root/" + node_name)
		if node == null:
			continue
		if node_name == "RunManager" and "data" in node:
			var data = node.get("data")
			if data != null:
				out.append({"label": node_name + ".data", "object": data})
		out.append({"label": node_name, "object": node})
	return out


## Maps catalog ids (lowercased) to display names. Pass a Dictionary/object with a
## `sets_db` / `species_packs_db` field to override the GameDatabase lookup (tests).
static func build_alias_map(db = null) -> Dictionary:
	var aliases := {}
	if db == null:
		db = _get_database()
	if db == null:
		return aliases
	for collection in ALIAS_COLLECTIONS:
		for entry in _collection_entries(db, collection):
			var id := _string_field(entry, "id")
			var display := _string_field(entry, "name")
			if display.is_empty():
				display = _string_field(entry, "name_key")
			if id.is_empty() or display.is_empty():
				continue
			aliases[id.to_lower()] = display
	return aliases


## Normalizes a raw property value (String, Array, set/pack resource) to a region
## display name. Catalog ids are translated through `aliases`.
static func normalize_value(value, aliases: Dictionary) -> String:
	if value is String or value is StringName:
		return _match_name(str(value).strip_edges(), aliases)
	if value is Array:
		for item in value:
			var found := normalize_value(item, aliases)
			if not found.is_empty():
				return found
		return ""
	if value is Object and is_instance_valid(value):
		for field in OBJECT_NAME_FIELDS:
			if not (field in value):
				continue
			var found := normalize_value(value.get(field), aliases)
			if not found.is_empty():
				return found
	return ""


## Resolves a raw string to a region display name. Tries an exact catalog id
## (lowercased) first, then an exact display name, then a display name contained
## in the raw value, so ids such as "set_jinto"/"jinto" still resolve to "Jinto".
static func _match_name(text: String, aliases: Dictionary) -> String:
	if text.is_empty():
		return ""
	var mapped := str(aliases.get(text.to_lower(), ""))
	if not mapped.is_empty():
		return mapped
	var lower := text.to_lower()
	for display in aliases.values():
		var name := str(display)
		if not name.is_empty() and lower == name.to_lower():
			return name
	for display in aliases.values():
		var name := str(display)
		if not name.is_empty() and lower.contains(name.to_lower()):
			return name
	return text


static func describe_value(value) -> String:
	if value == null:
		return "null"
	if value is String or value is StringName:
		return "'%s'" % str(value)
	if value is Array:
		return "Array(%d)" % value.size()
	if value is Object and is_instance_valid(value):
		var script: Script = value.get_script()
		var script_path := str(script.resource_path) if script != null else "(no script)"
		return "<%s %s>" % [value.get_class(), script_path]
	return str(value)


## Script variable names of an object (or keys of a Dictionary), for discovery.
static func describe_properties(obj) -> String:
	var names: Array = []
	if obj is Dictionary:
		names = obj.keys()
	elif obj is Object and is_instance_valid(obj):
		for prop in obj.get_property_list():
			if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names.append(str(prop.get("name", "")))
	return "vars(%d): %s" % [names.size(), ", ".join(names)]


static func _scan_object(obj, aliases: Dictionary, has_property: Callable, report: Array, label: String) -> String:
	for key in CANDIDATE_KEYS:
		if not _has(obj, key, has_property):
			continue
		var value = obj.get(key)
		var normalized := normalize_value(value, aliases)
		report.append("%s.%s = %s -> %s" % [label, key, describe_value(value), normalized if not normalized.is_empty() else "(no match)"])
		if not normalized.is_empty():
			return normalized
	return ""


static func _has(obj, key: String, has_property: Callable) -> bool:
	if obj is Dictionary:
		return obj.has(key)
	if has_property.is_valid():
		return bool(has_property.call(obj, key))
	if obj is Object:
		return key in obj
	return false


static func _string_field(obj, field: String) -> String:
	if obj == null:
		return ""
	if obj is Dictionary:
		return str(obj.get(field, "")).strip_edges()
	if obj is Object and field in obj:
		return str(obj.get(field)).strip_edges()
	return ""


static func _collection_entries(db, collection: String) -> Array:
	var value = null
	if db is Dictionary:
		value = db.get(collection)
	elif db is Object and collection in db:
		value = db.get(collection)
	if value is Array:
		return value
	if value is Dictionary:
		return value.values()
	return []


static func _get_root():
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	var root: Window = (tree as SceneTree).root
	# Absolute get_node paths only resolve inside the active scene tree (a
	# headless --script run, e.g. the test suite, has a detached root).
	if root == null or not root.is_inside_tree():
		return null
	return root


static func _get_database():
	var root = _get_root()
	if root == null:
		return null
	return root.get_node_or_null("/root/GameDatabase")
