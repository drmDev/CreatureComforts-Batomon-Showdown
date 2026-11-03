extends RefCounted
## Debug-gated diagnostics dumps for Creature Comforts.
##
## Extracted from mod_main.gd. Writes the one-shot GameDatabase catalog overview,
## the per-shop structure dump, and the region report through core/mod_logger.gd.
## All output is gated by the logger's Debug Logging flag.

const NodeUtils = preload("node_utils.gd")
const RunRegion = preload("run_region.gd")
const ShopHighlight = preload("../hud/shop_highlight.gd")

var _logger = null
var _catalog_logged := false
var _region_logged := false


func _init(logger) -> void:
	_logger = logger


## Run the debug-gated dumps for a shop visit. The catalog overview is one-shot;
## the shop structure and region lines repeat per visit.
func on_shop_entered(state) -> void:
	if not _logger.debug_logging:
		return
	if not _catalog_logged:
		log_catalog()
	log_shop_structure(state)
	log_region()


func log_catalog() -> void:
	_catalog_logged = true
	_logger.log_message("GAMEDB DIAG | === begin ===")
	var db = _game_database()
	if db == null:
		_logger.log_message("GAMEDB DIAG | /root/GameDatabase not found")
	else:
		var db_script: Script = db.get_script()
		_logger.log_message("GAMEDB DIAG | node=%s class=%s script=%s" % [
			db.name, db.get_class(), str(db_script.resource_path) if db_script != null else "(none)"])
		for prop in db.get_property_list():
			if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_logger.log_message("GAMEDB DIAG | var %s: %s" % [
					str(prop.get("name", "")), type_string(int(prop.get("type", TYPE_NIL)))])
		var tokens := ["species", "monster", "batomon", "catalog", "icon", "portrait", "sprite", "item", "get_all", "all_"]
		var method_names: Array = []
		for method in db.get_method_list():
			var mname := str(method.get("name", ""))
			if mname.begins_with("_"):
				continue
			for token in tokens:
				if mname.to_lower().contains(token):
					method_names.append(mname)
					break
		_logger.log_message("GAMEDB DIAG | interesting methods (%d): %s" % [method_names.size(), ", ".join(method_names)])
		# Catalog shape for the watchlist filters.
		if "items_db" in db:
			var items = db.get("items_db")
			if items is Array:
				_logger.log_message("CATALOG DIAG | items_db size=%d" % items.size())
				if not items.is_empty() and items[0] != null:
					var item_vars: Array = []
					for prop in items[0].get_property_list():
						if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
							item_vars.append(str(prop.get("name", "")))
					_logger.log_message("CATALOG DIAG | first item vars: %s" % ", ".join(item_vars))
		if "items_by_pool" in db:
			var pools = db.get("items_by_pool")
			if pools is Dictionary:
				_logger.log_message("CATALOG DIAG | items_by_pool keys: %s" % ", ".join(pools.keys()))
		if db.has_method("get_all_species"):
			var species_list = db.get_all_species()
			if species_list is Array:
				if not species_list.is_empty() and species_list[0] != null:
					var species_vars: Array = []
					for prop in species_list[0].get_property_list():
						if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
							species_vars.append(str(prop.get("name", "")))
					_logger.log_message("CATALOG DIAG | first species vars: %s" % ", ".join(species_vars))
				var histogram := {}
				for s in species_list:
					if s == null:
						continue
					var tier := int(s.get("tier")) if "tier" in s else 0
					histogram[tier] = histogram.get(tier, 0) + 1
				_logger.log_message("CATALOG DIAG | species count=%d tier histogram=%s" % [species_list.size(), str(histogram)])
	_logger.log_message("GAMEDB DIAG | === end ===")


func log_shop_structure(state) -> void:
	_logger.log_message("SHOP DIAG | === begin ===")
	var view = state.get("view") if NodeUtils.has_property(state, "view") else null
	if view == null or not is_instance_valid(view):
		_logger.log_message("SHOP DIAG | state.view not found")
		_logger.log_message("SHOP DIAG | === end ===")
		return
	var view_script: Script = view.get_script()
	_logger.log_message("SHOP DIAG | view=%s class=%s script=%s path=%s" % [
		view.name, view.get_class(), str(view_script.resource_path) if view_script != null else "(none)", view.get_path()])
	if NodeUtils.has_property(view, "shop_slots"):
		var slots = view.get("shop_slots")
		_logger.log_message("SHOP DIAG | view.shop_slots type=%s size=%s" % [
			type_string(typeof(slots)), str(slots.size() if slots is Array else "n/a")])
	else:
		_logger.log_message("SHOP DIAG | view.shop_slots NOT found")
	_logger.log_message("SHOP DIAG | view direct children:")
	for child in view.get_children():
		_logger.log_message("SHOP DIAG |   %s" % _describe_node(child))
	var cards: Array = []
	_collect_shop_cards(view, cards)
	_logger.log_message("SHOP DIAG | shop_slot_ui cards found: %d" % cards.size())
	for card in cards:
		_logger.log_message("SHOP DIAG |   card %s" % _describe_shop_card(card))
	_logger.log_message("SHOP DIAG | === end ===")


## Reports what core/run_region.gd found (and everything it inspected) so an
## unexpected watchlist Region default can be traced to the field the game
## actually stores the active region/set in.
func log_region() -> void:
	# verbose (run-data variable dump) is a session-once diagnostic: it allocates
	# the 100+ name list, so it is not repeated on every shop visit.
	var verbose := not _region_logged
	var result = RunRegion.detect(verbose)
	var detected := str(result.get("region", ""))
	_logger.log_message("REGION DIAG | === begin ===")
	_logger.log_message("REGION DIAG | detected region: %s" % (detected if not detected.is_empty() else "(none)"))
	for line in result.get("report", []):
		_logger.log_message("REGION DIAG | %s" % str(line))
	_logger.log_message("REGION DIAG | === end ===")
	_region_logged = true


func _collect_shop_cards(node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		var script: Script = node.get_script()
		if script != null and str(script.resource_path.get_file().get_basename()) == ShopHighlight.CARD_SCRIPT:
			out.append(node)
	for child in node.get_children():
		_collect_shop_cards(child, out)


func _describe_node(node) -> String:
	if node == null or not is_instance_valid(node):
		return "(invalid)"
	var script: Script = node.get_script()
	var script_name := str(script.resource_path.get_file().get_basename()) if script != null else ""
	var visible := ""
	if node is CanvasItem:
		visible = " visible=%s" % node.is_visible_in_tree()
	return "%s (%s) script=%s%s" % [node.name, node.get_class(), script_name, visible]


func _describe_shop_card(card) -> String:
	var content = card.get("current_content") if NodeUtils.has_property(card, "current_content") else null
	var content_desc := "none"
	if content != null and is_instance_valid(content):
		var kind := "other"
		var key := ""
		# Raw shop entries expose get_gold_cost()+data (monster) or id (item),
		# matching ShopSnapshot.is_monster_offer()/classify_shop_entry().
		if content.has_method("get_gold_cost") and NodeUtils.has_property(content, "data"):
			kind = "monster"
			var data = content.get("data")
			if data != null and NodeUtils.has_property(data, "name_key"):
				key = str(data.get("name_key"))
		elif NodeUtils.has_property(content, "id"):
			kind = "item"
			key = str(content.get("id"))
		var content_script: Script = content.get_script() if content is Object else null
		content_desc = "%s id=%s key=%s script=%s" % [
			kind, str(content.get_instance_id()), key,
			str(content_script.resource_path) if content_script != null else "(none)"]
	var rect := ""
	if card is Control:
		rect = " rect=%s" % card.get_global_rect()
	return "%s (%s)%s content=[%s]" % [card.name, card.get_class(), rect, content_desc]


func _game_database():
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	var root: Window = (tree as SceneTree).root
	if root == null or not root.is_inside_tree():
		return null
	return root.get_node_or_null("/root/GameDatabase")
