extends Node
## Shared slot-badge lifecycle for the mod's My Team indicators.
##
## Walks the shop's `monster_team_ui.team_slots` and `bench_slots` arrays and
## attaches one badge per slot. Badges are reused across polls and pruned when
## their slot is freed. Subclasses supply the badge script, group name, and
## feature gate. The shop controller calls update_team() on each poll and
## hide_all() when the phase leaves or the gate closes.

const NodeUtils = preload("../core/node_utils.gd")

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
	_enabled = _initial_enabled(context)


## Feature toggle. Disabling hides every badge immediately; enabling lets the
## next poll re-show them without duplicates.
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		hide_all()
	if is_inside_tree():
		get_tree().call_group(_badge_group(), "set_enabled", on)


## Hide every badge without detaching them (phase leave, gate close, or the
## feature no longer applying).
func hide_all() -> void:
	_phase_visible = false
	_set_phase_visible(false)


## Attach badges to the current shop view's My Team grid. `active` false hides
## every badge. Safe to call on every 500 ms shop poll: badges are reused.
func update_team(view, active := true) -> void:
	if not _enabled:
		return
	if not active:
		hide_all()
		return
	_prune()
	var team_ui = _team_ui(view)
	if team_ui == null:
		_log_missing(view)
		return
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
	var script = _badge_script()
	if script == null:
		return
	var badge = script.new()
	badge.slot = slot
	if slot is Container:
		# A Container would lay the badge out as a row child; host it on the
		# shop view and follow the slot's global rect instead.
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
	get_tree().call_group(_badge_group(), "set_phase_visible", on)


## One Debug Logging line when the team UI cannot be found while active, so a
## game update is diagnosable from the session log.
func _log_missing(view) -> void:
	if _missing_logged or _logger == null or not _logger.debug_logging:
		return
	_missing_logged = true
	var reason := "view not ready"
	if view != null and is_instance_valid(view) and view is Node:
		var view_script: Script = view.get_script()
		reason = "no team UI on %s (%s)" % [view.name, view.get_class()]
		if view_script != null:
			reason += " script=%s" % view_script.resource_path
	_logger.log_message("%s | indicators inactive: %s" % [_diag_prefix(), reason])


## Badges hosted on the shop view are not children of the mod, so free them when
## the controller leaves the tree.
func _exit_tree() -> void:
	for id in _attached.keys():
		var badge = _attached[id]
		if badge != null and is_instance_valid(badge):
			badge.free()
	_attached.clear()


# --- Subclass hooks ---------------------------------------------------------

func _badge_script():
	return null


func _badge_group() -> String:
	return ""


func _initial_enabled(_context) -> bool:
	return true


func _diag_prefix() -> String:
	return "BADGE DIAG"
