extends Node
## Attaches sell-value badges to the fielded and bench slots of the shop's
## My Team grid.
##
## The game's shop view exposes `monster_team_ui.team_slots` (6) and
## `bench_slots` (4); each slot carries `current_monster`. Badges are attached
## once per slot and read the live monster themselves, so team edits, level-ups,
## and shiny swaps update without a snapshot. Shop-phase only: the shop
## controller calls update_team() on every poll and hide_all() when the phase
## leaves or the shop gate closes.

const NodeUtils = preload("../core/node_utils.gd")
const ModConfig = preload("../core/mod_config.gd")
const SellValueBadge = preload("sell_value_badge.gd")

const TEAM_UI_PROPERTY := "monster_team_ui"
const SLOT_ARRAYS := ["team_slots", "bench_slots"]

var _enabled := true
var _phase_visible := false
var _missing_logged := false
var _logger = null
## Slot instance id -> badge. Kept so a rebuilt slot is re-attached and a freed
## slot's badge is pruned instead of leaking.
var _attached := {}


func setup(context) -> void:
	_logger = context.logger if context != null else null
	_enabled = context.feature_enabled(ModConfig.KEY_SELL_VALUE_INDICATORS) if context != null else true


## Feature toggle. Disabling hides every badge immediately; enabling lets the
## next shop poll re-show them without creating duplicates.
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		hide_all()
	if is_inside_tree():
		get_tree().call_group(SellValueBadge.BADGE_GROUP, "set_enabled", on)


## Hide every badge without disabling the feature. Used when the shop gate
## closes or the phase leaves the shop.
func hide_all() -> void:
	_phase_visible = false
	_set_phase_visible(false)


## Attach badges to every slot of the current shop view's My Team grid. Safe to
## call on every 500 ms shop poll: existing badges are reused.
func update_team(view) -> void:
	if not _enabled:
		return
	var team_ui = _team_ui(view)
	if team_ui == null:
		_log_missing(view)
		return
	_prune()
	for key in SLOT_ARRAYS:
		if not NodeUtils.has_property(team_ui, key):
			continue
		var slots = team_ui.get(key)
		if not (slots is Array):
			continue
		for slot in slots:
			_attach(slot, view)
	if not _phase_visible:
		_phase_visible = true
		_set_phase_visible(true)


func _team_ui(view):
	if view == null or not is_instance_valid(view) or not (view is Node):
		return null
	if not NodeUtils.has_property(view, TEAM_UI_PROPERTY):
		return null
	var team_ui = view.get(TEAM_UI_PROPERTY)
	if team_ui == null or not is_instance_valid(team_ui) or not (team_ui is Node):
		return null
	return team_ui


func _attach(slot, view) -> void:
	if slot == null or not is_instance_valid(slot) or not (slot is Control):
		return
	var id: int = slot.get_instance_id()
	var existing = _attached.get(id)
	if existing != null and is_instance_valid(existing) and existing.slot == slot:
		return
	_attached.erase(id)

	var badge = SellValueBadge.new()
	badge.slot = slot
	if slot is Container:
		# A Container would lay the badge out as a row child. Host it on the
		# shop view instead (ShopUI is a CanvasLayer, not a Control) and follow
		# the slot's global rect.
		if view == null or not is_instance_valid(view) or not (view is Node):
			badge.free()
			return
		badge.follow_slot = true
		badge.top_level = true
		view.add_child(badge)
	else:
		slot.add_child(badge)
	_attached[id] = badge


func _prune() -> void:
	for id in _attached.keys():
		var badge = _attached[id]
		if badge == null or not is_instance_valid(badge):
			_attached.erase(id)
			continue
		var source = badge.slot
		if source == null or not is_instance_valid(source):
			badge.free()
			_attached.erase(id)


func _set_phase_visible(on: bool) -> void:
	if not is_inside_tree():
		return
	get_tree().call_group(SellValueBadge.BADGE_GROUP, "set_phase_visible", on)


## One Debug Logging line when the live build does not expose the expected
## team UI, so a game update is diagnosable from the session log.
func _log_missing(view) -> void:
	if _missing_logged or _logger == null or not _logger.debug_logging:
		return
	_missing_logged = true
	var reason := "view not ready"
	if view != null and is_instance_valid(view) and view is Node:
		var view_script: Script = view.get_script()
		reason = "no team UI under view=%s (%s) script=%s path=%s" % [
			view.name, view.get_class(),
			str(view_script.resource_path) if view_script != null else "(none)",
			view.get_path()]
	_logger.log_message("SELL DIAG | indicators inactive: %s" % reason)


## Badges hosted on the shop view are not children of the mod, so free them
## explicitly when the controller leaves the tree.
func _exit_tree() -> void:
	for id in _attached.keys():
		var badge = _attached[id]
		if badge != null and is_instance_valid(badge):
			badge.free()
	_attached.clear()
