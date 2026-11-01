extends RefCounted
## Shared accessor for the active run data (RunManager.data).
##
## Both mod_main.gd and hud/watchlist_panel.gd need the same lookup; keeping it
## here avoids two copies drifting apart.

static func get_run_data():
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	var root: Window = (tree as SceneTree).root
	# Absolute get_node paths only resolve inside the active scene tree (a headless
	# --script run, e.g. the test suite, has a detached root).
	if root == null or not root.is_inside_tree():
		return null
	var run_manager := root.get_node_or_null("/root/RunManager")
	if run_manager == null or not ("data" in run_manager):
		return null
	return run_manager.get("data")
