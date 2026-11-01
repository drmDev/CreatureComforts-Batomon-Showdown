extends RefCounted
## Saved Watchlist builds: pure data helpers plus single-file JSON persistence.
##
## A "store" is `{ "next_number": int, "builds": Array }`. Each build is
## `{ "id": String, "number": int, "created": String (ISO timestamp),
##    "monsters": Array[String], "items": Array[String] }`.
##
## Build numbers are monotonic: `next_number` only ever grows, so a deleted
## build's number is never handed out again. Parsing repairs a missing or stale
## `next_number` from the highest stored build number, which also covers a
## hand-edited or partially written file.
##
## Everything here is static and side-effect free apart from `load_store` /
## `save_store`, so the ordering and naming rules are unit-testable.

const PATH := "user://creature_comforts/saved_builds.json"
const PREVIEW_LIMIT := 10
## Unresolved catalog ids sort after every real Batomon (tiers are 1..6).
const UNRESOLVED_TIER := 999


static func empty_store() -> Dictionary:
	return {"next_number": 1, "builds": []}


## Parse a store from JSON text. Missing, corrupt, or wrongly typed data yields an
## empty store; individual malformed build entries are dropped rather than
## discarding the whole file.
static func parse(text: String) -> Dictionary:
	var store := empty_store()
	if text.strip_edges().is_empty():
		return store
	# JSON.new().parse() reports the error through its return value instead of
	# printing an engine error, so a damaged file stays quiet in the log.
	var json := JSON.new()
	if json.parse(text) != OK:
		return store
	var parsed = json.data
	if not (parsed is Dictionary):
		return store
	var raw_builds = parsed.get("builds", [])
	if not (raw_builds is Array):
		return store
	var builds: Array = []
	var highest := 0
	for raw in raw_builds:
		var build := _normalize_build(raw)
		if build.is_empty():
			continue
		builds.append(build)
		highest = maxi(highest, int(build["number"]))
	store["builds"] = builds
	var stored_next := 1
	var raw_next = parsed.get("next_number")
	if raw_next is int or raw_next is float:
		stored_next = int(raw_next)
	# Never hand out a number that is already in use, even if the file's
	# next_number was lost or rolled back.
	store["next_number"] = maxi(maxi(stored_next, highest + 1), 1)
	return store


static func serialize(store: Dictionary) -> String:
	return JSON.stringify(store, "\t")


## Append a new build capturing every tracked id. Returns the created build.
## `unix_time` is passed in so tests stay deterministic.
static func create_build(store: Dictionary, monsters: Array, items: Array, unix_time: int) -> Dictionary:
	var number := int(store.get("next_number", 1))
	if number < 1:
		number = 1
	var build := {
		"id": "build-%d-%d" % [number, unix_time],
		"number": number,
		"created": Time.get_datetime_string_from_unix_time(unix_time, true),
		"monsters": _sorted_unique(monsters),
		"items": _sorted_unique(items),
	}
	store["next_number"] = number + 1
	var builds = store.get("builds", [])
	if not (builds is Array):
		builds = []
	store["builds"] = builds
	builds.append(build)
	return build


## Remove one build by id. `next_number` is deliberately untouched, so the
## deleted number is never reused and the remaining builds keep their numbers.
static func delete_build(store: Dictionary, id: String) -> bool:
	var builds = store.get("builds", [])
	if not (builds is Array):
		return false
	for i in range(builds.size()):
		if str(builds[i].get("id", "")) == id:
			builds.remove_at(i)
			return true
	return false


## "Build 3 (2026-11-01)" - the stored timestamp keeps the time of day, but only
## the creation date is shown.
static func display_name(build: Dictionary) -> String:
	return "Build %d (%s)" % [int(build.get("number", 0)), creation_date(build)]


static func creation_date(build: Dictionary) -> String:
	var created := str(build.get("created", ""))
	if created.length() >= 10:
		return created.substr(0, 10)
	return created


## Newest first. Build numbers are monotonic, so they are the primary key; the
## timestamp only breaks ties (e.g. a hand-edited file).
static func sorted_newest_first(store: Dictionary) -> Array:
	var builds: Array = []
	var raw = store.get("builds", [])
	if raw is Array:
		builds = raw.duplicate()
	builds.sort_custom(func(a, b):
		var an := int(a.get("number", 0))
		var bn := int(b.get("number", 0))
		if an != bn:
			return an > bn
		return str(a.get("created", "")) > str(b.get("created", "")))
	return builds


## Ordered preview for one build: Batomon first by rarity tier (Common..Mythical)
## then name, items after them by name only. At most `limit` entries are returned;
## `overflow` is how many tracked entries did not fit.
##
## `catalog_lookup` is `Callable(kind, key) -> Dictionary` (or null) supplying
## `name`, `tier` and `icon`. Unresolved ids still count toward the totals and the
## overflow, they just have no icon to draw.
static func preview_entries(build: Dictionary, catalog_lookup: Callable, limit: int = PREVIEW_LIMIT) -> Dictionary:
	var monsters: Array = []
	for key in build.get("monsters", []):
		monsters.append(_preview_entry("monster", str(key), catalog_lookup))
	monsters.sort_custom(_compare_monsters)
	var items: Array = []
	for key in build.get("items", []):
		items.append(_preview_entry("item", str(key), catalog_lookup))
	items.sort_custom(_compare_items)
	var ordered: Array = monsters + items
	var shown: Array = ordered.slice(0, maxi(limit, 0))
	return {
		"entries": shown,
		"overflow": maxi(ordered.size() - shown.size(), 0),
		"monster_count": monsters.size(),
		"item_count": items.size(),
	}


static func total_tracked(build: Dictionary) -> int:
	return build.get("monsters", []).size() + build.get("items", []).size()


static func load_store() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return empty_store()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Creature Comforts: cannot read saved builds at %s: %s" % [PATH, error_string(FileAccess.get_open_error())])
		return empty_store()
	var text := file.get_as_text()
	file.close()
	return parse(text)


static func save_store(store: Dictionary) -> bool:
	# The mod's user directory is created later in mod_main, so make sure it
	# exists before the first save (same pattern as the watchlist config).
	var abs_dir := ProjectSettings.globalize_path(PATH.get_base_dir())
	var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("Creature Comforts: cannot create saved-builds directory %s: %s" % [abs_dir, error_string(dir_err)])
		return false
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Creature Comforts: cannot write saved builds to %s: %s" % [PATH, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(serialize(store))
	file.close()
	return true


static func _normalize_build(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var number := int(raw.get("number", 0))
	if number < 1:
		return {}
	var id := str(raw.get("id", "")).strip_edges()
	if id.is_empty():
		id = "build-%d" % number
	return {
		"id": id,
		"number": number,
		"created": str(raw.get("created", "")),
		"monsters": _string_list(raw.get("monsters", [])),
		"items": _string_list(raw.get("items", [])),
	}


static func _string_list(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for value in raw:
		if value is String or value is StringName:
			var key := str(value).strip_edges()
			if not key.is_empty() and not out.has(key):
				out.append(key)
	return out


static func _sorted_unique(ids: Array) -> Array:
	var out: Array = []
	for value in ids:
		var key := str(value).strip_edges()
		if not key.is_empty() and not out.has(key):
			out.append(key)
	out.sort()
	return out


static func _preview_entry(kind: String, key: String, catalog_lookup: Callable) -> Dictionary:
	var entry = null
	if catalog_lookup.is_valid():
		entry = catalog_lookup.call(kind, key)
	if entry is Dictionary:
		return {
			"kind": kind,
			"key": key,
			"name": str(entry.get("name", key)),
			"tier": int(entry.get("tier", 0)),
			"icon": entry.get("icon"),
			"resolved": true,
		}
	return {
		"kind": kind,
		"key": key,
		"name": key,
		"tier": UNRESOLVED_TIER,
		"icon": null,
		"resolved": false,
	}


static func _compare_monsters(a: Dictionary, b: Dictionary) -> bool:
	var at := int(a.get("tier", UNRESOLVED_TIER))
	var bt := int(b.get("tier", UNRESOLVED_TIER))
	if at != bt:
		return at < bt
	var by_name := str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", "")))
	if by_name != 0:
		return by_name < 0
	return str(a.get("key", "")) < str(b.get("key", ""))


static func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	var by_name := str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", "")))
	if by_name != 0:
		return by_name < 0
	return str(a.get("key", "")) < str(b.get("key", ""))
