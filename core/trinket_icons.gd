extends RefCounted
## Trinket icon lookup backed by the game's GameDatabase.
##
## The game exposes trinket definitions through `GameDatabase.get_trinket_by_id(id)`,
## and each definition carries an `icon` Texture2D (the same source the game's own
## trinket bag and spectator view use). The database may not be ready when the mod
## initializes, so the lookup is resolved lazily on every call instead of cached.

const TrinketGains = preload("trinket_gains.gd")
const NodeUtils = preload("node_utils.gd")


## Icon for a trinket id, or null when the database or the definition is missing.
func icon(trinket_id: String) -> Texture2D:
	return TrinketGains.icon_for(trinket_id, _lookup)


func _lookup(id: String) -> Texture2D:
	var db = NodeUtils.get_autoload("GameDatabase")
	if db == null or not db.has_method("get_trinket_by_id"):
		return null
	var definition = db.get_trinket_by_id(id)
	if definition == null:
		return null
	var icon = definition.get("icon") if "icon" in definition else null
	return icon if icon is Texture2D else null
