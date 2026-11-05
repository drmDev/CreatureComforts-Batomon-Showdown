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
