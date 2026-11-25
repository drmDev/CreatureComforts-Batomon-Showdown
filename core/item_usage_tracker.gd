extends RefCounted
## Per-run item usage history.
##
## Pure state plus JSON persistence: no UI and no game access. The caller records
## one use per successful shop item purchase, keyed by the item's stable internal
## id. Counts are scoped to the game's run_id, so a new run always starts empty.

const FileStore = preload("file_store.gd")

const STORE_DIR := "user://creature_comforts/items_used"

var _store_dir := STORE_DIR
var _run_id := ""
var _counts: Dictionary = {}  # item id -> use count


## Tests use an isolated directory instead of the real user:// store.
func use_store_dir(path: String) -> void:
	if not path.is_empty():
		_store_dir = path


## Bind to a run and load its saved history. A different run id replaces the
## counts; a missing file, unreadable text, or malformed JSON starts empty.
func load_run(run_id: String) -> void:
	var id := _sanitize(run_id)
	if id == _run_id:
		return
	_run_id = id
	_counts = {}
	if id.is_empty():
		return
	var data = _read_json(store_path(id))
	if data is Dictionary and str(data.get("run_id", "")) == id:
		_counts = _clean_counts(data.get("counts", {}))


## Record one successful use of `item_id`. Returns true when the count changed.
func record_use(item_id: String) -> bool:
	var id := str(item_id).strip_edges()
	if id.is_empty():
		return false
	_counts[id] = int(_counts.get(id, 0)) + 1
	save()
	return true


func has_any() -> bool:
	return not _counts.is_empty()


func total_used() -> int:
	var total := 0
	for value in _counts.values():
		total += int(value)
	return total


func count_for(item_id: String) -> int:
	return int(_counts.get(str(item_id), 0))


## Display rows sorted by quantity descending, then name ascending. `formatter`
## supplies item display names (LogFormatter.format_item_name).
func entries(formatter) -> Array:
	var rows: Array = []
	for item_id in _counts.keys():
		var count := int(_counts[item_id])
		if count <= 0:
			continue
		rows.append({
			"id": str(item_id),
			"name": str(formatter.format_item_name(str(item_id))),
			"count": count,
		})
	rows.sort_custom(_compare_entries)
	return rows


static func _compare_entries(a: Dictionary, b: Dictionary) -> bool:
	if int(a["count"]) != int(b["count"]):
		return int(a["count"]) > int(b["count"])
	return str(a["name"]).to_lower() < str(b["name"]).to_lower()


func save() -> void:
	if _run_id.is_empty():
		return
	var path := store_path(_run_id)
	var payload := {"run_id": _run_id, "counts": _counts}
	var error := FileStore.write_text(path, JSON.stringify(payload, "\t"))
	if error != OK:
		push_warning("Creature Comforts: cannot save item usage (%s): %s" % [path, error_string(error)])


func store_path(run_id: String) -> String:
	return _store_dir.path_join("%s.json" % _sanitize(run_id))


## Run ids are generated as "run_<digits>_<unix>"; other characters are replaced
## so an unexpected id can never escape the store directory.
static func _sanitize(run_id: String) -> String:
	var out := ""
	for ch in str(run_id):
		var code := ch.unicode_at(0)
		var safe := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122) or ch == "_" or ch == "-"
		out += ch if safe else "_"
	return out


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	# JSON.parse_string logs an engine error on invalid input; a JSON instance
	# reports the same failure quietly, and a corrupt save is an expected case.
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _clean_counts(raw) -> Dictionary:
	var counts := {}
	if not (raw is Dictionary):
		return counts
	for key in raw.keys():
		var id := str(key).strip_edges()
		var value = raw[key]
		var count := int(value) if (value is int or value is float) else 0
		if not id.is_empty() and count > 0:
			counts[id] = count
	return counts
