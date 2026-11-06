extends RefCounted
## Resolves the region the player is currently running in (e.g. "Jinto", "Pantra").
##
## `RunManager.data.active_set_id` holds the region as a set id (e.g. "oshima"),
## which `sets_db` maps to a display name. The watchlist labels species with the
## same set display names, so both sides agree on the string.
##
## `detect()` returns `{ "region": String, "report": Array[String] }`; the report
## exists so the diagnostic logger can show what was read.

const NodeUtils = preload("node_utils.gd")

## Fields that may carry the active set/region, most likely first.
const CANDIDATE_KEYS := ["active_set_id", "region", "current_region", "set_id", "current_set", "active_set"]

## GameDatabase collection that describes a region, keyed by id.
const REGION_COLLECTIONS := ["sets_db"]


## Detects the current region.
##
## Cost: a few property existence checks on the run data (the confirmed source,
## normally answered on the first read), then one small id -> name walk over
## `sets_db`. `verbose` also dumps the run data's script variable names for
## troubleshooting; that allocates a 100+ element array, so only the diagnostic
## logger asks for it.
static func detect(verbose := false) -> Dictionary:
	var report: Array = []
	var regions := build_region_map()
	var run_manager = NodeUtils.get_autoload("RunManager")
	var run_data = null
	if run_manager != null and "data" in run_manager:
		run_data = run_manager.get("data")
	# Run data is the confirmed source; the manager node is a fallback.
	var sources := [
		{"label": "RunManager.data", "object": run_data},
		{"label": "RunManager", "object": run_manager},
	]
	for source in sources:
		var obj = source["object"]
		if obj == null:
			continue
		if verbose and obj is Object and not (obj is Node):
			report.append("%s: %s" % [source["label"], describe_properties(obj)])
		var hit := _scan_object(obj, regions, report, source["label"])
		if not hit.is_empty():
			return {"region": hit, "report": report}
	return {"region": "", "report": report}


## Region id -> display name (e.g. "oshima" -> "Jinto"), lowercased keys. Shared
## with the watchlist, which labels each species with its set's display name.
static func build_region_map(db = null) -> Dictionary:
	if db == null:
		db = NodeUtils.get_autoload("GameDatabase")
	var regions := {}
	for collection in REGION_COLLECTIONS:
		for entry in _collection_entries(db, collection):
			var id := _string_field(entry, "id")
			var display := _string_field(entry, "name")
			if display.is_empty():
				display = _string_field(entry, "name_key")
			if id.is_empty() or display.is_empty():
				continue
			regions[id.to_lower()] = display
	return regions


## Species id -> region display names. The game's own dex membership
## (`get_dex_species_for_set`) is authoritative: it includes species that belong
## to a set but are not in any shop pack (e.g. Onsetra in Jinto) and excludes
## foreign/event-only entries. Keys are lowercased so callers can look up by
## species.id or name_key.
##
## When the game has no dex helper, this returns an empty map and the watchlist
## falls back to `species.sets` (hud/watchlist_panel.gd `_extract_regions`).
static func build_species_region_map(db = null) -> Dictionary:
	if db == null:
		db = NodeUtils.get_autoload("GameDatabase")
	var out := {}
	if not (db is Object and is_instance_valid(db) and db.has_method("get_dex_species_for_set")):
		return out
	var regions := build_region_map(db)
	for set_id in _set_ids(db, regions):
		var region := str(regions.get(set_id.to_lower(), ""))
		if region.is_empty():
			continue
		var dex = db.call("get_dex_species_for_set", set_id)
		if not (dex is Array):
			continue
		for entry in dex:
			_add_species_region(out, _species_id(entry), region)
	return out


## Set ids to ask the game's dex helper about. Prefer the raw ids from sets_db
## (the helper expects the original casing); fall back to the region map keys.
static func _set_ids(db, regions: Dictionary) -> Array:
	var ids: Array = []
	for set_entry in _collection_entries(db, "sets_db"):
		var set_id := _string_field(set_entry, "id")
		if not set_id.is_empty() and not ids.has(set_id):
			ids.append(set_id)
	if ids.is_empty():
		ids = regions.keys()
	return ids


## Species id from a dex entry: a plain id string, a dictionary, or a species
## object exposing `id` (preferred) or `name_key`.
static func _species_id(entry) -> String:
	if entry is String or entry is StringName:
		return str(entry).strip_edges().to_lower()
	for field in ["id", "name_key"]:
		var value := _string_field(entry, field).to_lower()
		if not value.is_empty():
			return value
	return ""


static func _add_species_region(out: Dictionary, species_id: String, region: String) -> void:
	if species_id.is_empty() or region.is_empty():
		return
	var list: Array = out.get(species_id, [])
	if not list.has(region):
		list.append(region)
	out[species_id] = list


## Normalizes a raw property value (a String or an Array of ids) to a region name.
static func normalize_value(value, aliases: Dictionary) -> String:
	if value is String or value is StringName:
		return _match_name(str(value).strip_edges(), aliases)
	if value is Array:
		for item in value:
			var found := normalize_value(item, aliases)
			if not found.is_empty():
				return found
	return ""


## Resolves a raw string to a display name: exact set id, then exact display name,
## then a display name contained in the value ("jinto_base" -> "Jinto"). Unmapped
## values pass through unchanged.
static func _match_name(text: String, aliases: Dictionary) -> String:
	if text.is_empty():
		return ""
	var lower := text.to_lower()
	var mapped := str(aliases.get(lower, ""))
	if not mapped.is_empty():
		return mapped
	var partial := ""
	for display in aliases.values():
		var name := str(display)
		if name.is_empty():
			continue
		if lower == name.to_lower():
			return name
		if partial.is_empty() and lower.contains(name.to_lower()):
			partial = name
	return partial if not partial.is_empty() else text


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


static func _scan_object(obj, aliases: Dictionary, report: Array, label: String) -> String:
	for key in CANDIDATE_KEYS:
		if not _has(obj, key):
			continue
		var value = obj.get(key)
		var normalized := normalize_value(value, aliases)
		report.append("%s.%s = %s -> %s" % [
			label, key, describe_value(value),
			normalized if not normalized.is_empty() else "(no match)"])
		if not normalized.is_empty():
			return normalized
	return ""


static func _has(obj, key: String) -> bool:
	if obj is Dictionary:
		return obj.has(key)
	return obj is Object and key in obj


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


