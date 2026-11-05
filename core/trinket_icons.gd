extends RefCounted
## Trinket icon lookup backed by the game's GameDatabase.
##
## The game exposes trinket definitions through `GameDatabase.get_trinket_by_id(id)`,
## and each definition carries an `icon` Texture2D (the same source the game's own
## trinket bag and spectator view use). The database may not be ready when the mod
## initializes, so the lookup is resolved lazily on every call instead of cached.

const TrinketGains = preload("trinket_gains.gd")


## Icon for a trinket id, or null when the database or the definition is missing.
func icon(trinket_id: String) -> Texture2D:
	return TrinketGains.icon_for(trinket_id, _lookup)


func _lookup(id: String) -> Texture2D:
	var db = _game_database()
	if db == null or not db.has_method("get_trinket_by_id"):
		return null
	var definition = db.get_trinket_by_id(id)
	if definition == null:
		return null
	var icon = definition.get("icon") if "icon" in definition else null
	return icon if icon is Texture2D else null


static func _game_database():
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	var root: Window = (tree as SceneTree).root
	# Absolute get_node paths only resolve inside the active scene tree (a headless
	# --script run, e.g. the test suite, has a detached root).
	if root == null or not root.is_inside_tree():
		return null
	return root.get_node_or_null("/root/GameDatabase")
