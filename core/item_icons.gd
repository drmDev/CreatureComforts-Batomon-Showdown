extends RefCounted
## Item icon lookup backed by the game's GameDatabase.
##
## Mirrors trinket_icons.gd: the database may not be ready when the mod
## initializes, so the lookup is resolved lazily on every call instead of cached.
## Items are Resources in `GameDatabase.items_db` and carry an `icon`.

const NodeUtils = preload("node_utils.gd")


## Icon for an item id, or null when the database or the definition is missing.
func icon(item_id: String) -> Texture2D:
	var id := str(item_id)
	if id.is_empty():
		return null
	var db = NodeUtils.get_autoload("GameDatabase")
	if db == null or not ("items_db" in db):
		return null
	var items = db.get("items_db")
	if not (items is Array):
		return null
	for item in items:
		if item == null or not ("id" in item):
			continue
		if str(item.get("id")) != id:
			continue
		var texture = item.get("icon") if "icon" in item else null
		return texture if texture is Texture2D else null
	return null
