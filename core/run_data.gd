extends RefCounted
## Shared accessor for the active run data (RunManager.data).
##
## Both mod_main.gd and hud/watchlist_panel.gd need the same lookup; keeping it
## here avoids two copies drifting apart.

const NodeUtils = preload("node_utils.gd")


static func get_run_data():
	var run_manager = NodeUtils.get_autoload("RunManager")
	if run_manager == null or not ("data" in run_manager):
		return null
	return run_manager.get("data")


## Stable identity for the active run: the game's run_id when present, else the
## object instance id. Used to detect a new run (which must clear run-scoped UI).
static func identity(run) -> String:
	if run == null:
		return ""
	if NodeUtils.has_property(run, "run_id"):
		var id := str(run.get("run_id"))
		if not id.is_empty():
			return id
	if run is Object:
		return str(run.get_instance_id())
	return ""
