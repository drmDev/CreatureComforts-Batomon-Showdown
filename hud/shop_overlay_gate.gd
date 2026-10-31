extends Node
## Shop overlay gate: decides when the reminder overlay may be visible.
##
## Extracted from mod_main.gd. Owns the gate constants, timers, view-node cache,
## and the game's transition subscriptions. Emits visibility_changed() only when
## the gate state changes; mod_main applies the result to the reminder layer and
## plays queued chimes.
##
## Empty reason string = overlay allowed.

signal visibility_changed(allowed: bool, reason: String)

const SHOP_SCRIPT := "res://game/states/shop_state.gd"

# Overlay gate: hides reminders while the shop is not on screen or not interactive
const GATE_NOT_SHOP := "not in shop"
const GATE_SETTLING := "shop settling after transition"
const GATE_SEARCH := "opponent search (CancelButton visible)"
const GATE_BATTLE_STARTING := "battle starting (BattleButton hidden)"
const GATE_OVERLAY := "ui overlay open"
const GATE_PAUSED := "game paused"
const GATE_VIEW_NOT_READY := "shop view not ready"
const GATE_VIEW_HIDDEN := "shop view hidden"
const GATE_TRANSITION := "transition hold"
const SHOP_SETTLE_MS := 1200  # Overlay stays hidden this long after the shop state appears (transition fade-in)

# Candidate overlay node names checked as direct children of the shop view and the
# main scene. Missing names are harmless. The UI diagnostics log which candidates
# exist (and their paths) so the real Settings/Batopedia node names can be confirmed.
# Confirmed modal overlay nodes (the interaction-lock check is the primary gate;
# this list is a fallback for overlays that do not set the lock).
const OVERLAY_NODE_NAMES := ["DexUI", "SettingsMenu"]

# Injected helpers (same pattern as LogFormatterScript.new(_has_property)).
var _has_prop: Callable
var _is_script: Callable

var _overlay_gate_reason := ""
var _shop_since_ms := 0
var _gate_hold_until_ms := 0  # Transition signal hold: keep the overlay hidden until this tick
var _search_end_hold_until_ms := 0  # Brief hold after search ends, before the battle transition fires
var _view_member_cache: Dictionary = {}
var _transition_nodes: Dictionary = {}


func setup(has_prop: Callable, is_script: Callable) -> void:
	_has_prop = has_prop
	_is_script = is_script
	_setup_transition_listener()


func is_allowed() -> bool:
	return _overlay_gate_reason.is_empty()


func reset_for_shop() -> void:
	_view_member_cache.clear()


func update() -> void:
	var main = get_tree().current_scene if get_tree() != null else null
	var state = main.get("current_state") if main != null else null
	# The transition hold only needs to survive the shop→battle fade. Once the
	# phase actually leaves the shop, clear it so a later shop visit is unaffected.
	if not _is_script.call(state, SHOP_SCRIPT):
		_gate_hold_until_ms = 0

	var reason := _compute_overlay_gate_reason()
	# Opponent found: the search gate just closed and the battle transition is about
	# to fire. Keep the overlay closed briefly so the panel cannot flash in the gap.
	if reason.is_empty() and _overlay_gate_reason == GATE_SEARCH:
		_search_end_hold_until_ms = Time.get_ticks_msec() + 2000
	if reason.is_empty() and Time.get_ticks_msec() < _search_end_hold_until_ms:
		reason = GATE_TRANSITION
	if reason == _overlay_gate_reason:
		return

	_overlay_gate_reason = reason
	visibility_changed.emit(reason.is_empty(), reason)


func _compute_overlay_gate_reason() -> String:
	"""Empty string = overlay allowed. Cheap checks only (runs every frame)."""
	# A transition signal fired recently: keep the overlay closed until the state changes.
	if Time.get_ticks_msec() < _gate_hold_until_ms:
		return GATE_TRANSITION
	if get_tree().paused:
		return GATE_PAUSED

	var main = get_tree().current_scene
	if main == null:
		_shop_since_ms = 0
		return GATE_NOT_SHOP
	var state = main.get("current_state")
	if not _is_script.call(state, SHOP_SCRIPT):
		_shop_since_ms = 0
		return GATE_NOT_SHOP

	# The shop state exists before the transition has finished fading in; wait for it to settle
	var now := Time.get_ticks_msec()
	if _shop_since_ms == 0:
		_shop_since_ms = now
	if now - _shop_since_ms < SHOP_SETTLE_MS:
		return GATE_SETTLING

	var view = state.get("view") if _has_prop.call(state, "view") else null
	if view == null or not is_instance_valid(view) or not view is Node:
		return GATE_VIEW_NOT_READY
	if not view.is_node_ready():
		return GATE_VIEW_NOT_READY
	if view is CanvasItem and not view.is_visible_in_tree():
		return GATE_VIEW_HIDDEN

	# The shop's own transition animation (fade to black) is the authoritative
	# "shop is leaving" signal. It can outlast the signal-based hold.
	if _is_shop_transition_active(view):
		return GATE_TRANSITION

	# The shop's own interaction lock covers search, opponent-found, level-up
	# choices, Dex/Settings, and other modal states.
	if _has_prop.call(view, "_is_interaction_locked") and bool(view.get("_is_interaction_locked")):
		return GATE_OVERLAY + " (interaction locked)"

	# Modal overlays (Batopedia/Dex, Settings, pause) do not change current_state.
	var overlay := _find_visible_overlay(view, main)
	if not overlay.is_empty():
		return "%s (%s)" % [GATE_OVERLAY, overlay]

	# While searching for an opponent the shop's Cancel button replaces the Battle button.
	# Resolve via the view's properties first, then direct child, then a recursive search.
	var cancel = _get_view_member(view, ["cancel_button", "CancelButton"], "CancelButton")
	if cancel is CanvasItem and cancel.is_visible_in_tree():
		return GATE_SEARCH
	# After the search succeeds the shop stays up while the game transitions to battle
	var battle_button = _get_view_member(view, ["battle_button", "BattleButton"], "BattleButton")
	if battle_button is CanvasItem and not battle_button.is_visible_in_tree():
		return GATE_BATTLE_STARTING
	return ""


## `transition_anim` is the view's AnimationPlayer; the `Transition` node is the
## visual overlay fallback.
func _is_shop_transition_active(view) -> bool:
	if view == null or not is_instance_valid(view) or not view is Node:
		return false
	var anim = view.get("transition_anim") if _has_prop.call(view, "transition_anim") else null
	if anim is AnimationPlayer:
		return anim.is_playing()
	var trans = view.get_node_or_null("Transition")
	if trans is CanvasItem and trans.is_visible_in_tree() and trans.modulate.a > 0.01:
		return true
	return false


## Direct-child overlay probe. Cheap enough to run every frame.
func _find_visible_overlay(view, main) -> String:
	for name in OVERLAY_NODE_NAMES:
		var node = _get_direct_child(view, name)
		if node == null:
			node = _get_direct_child(main, name)
		if _node_is_visible(node):
			return name
	# Fallback for unknown overlay names: only consider CanvasLayer/Window roots,
	# so ordinary Controls (e.g. a "SettingsButton") cannot false-positive.
	for root in [view, main]:
		if root == null or not is_instance_valid(root) or not root is Node:
			continue
		for child in root.get_children():
			if not (child is CanvasLayer or child is Window):
				continue
			if not _node_is_visible(child):
				continue
			# Ignore empty persistent layers; only a layer with visible content counts.
			if child is CanvasLayer:
				var has_visible_child := false
				for grandchild in child.get_children():
					if grandchild is CanvasItem and grandchild.is_visible_in_tree():
						has_visible_child = true
						break
				if not has_visible_child:
					continue
			var lower := str(child.name).to_lower()
			if lower.begins_with("dex") or lower.contains("batopedia") or lower.contains("settings") or lower.contains("pause") or lower.contains("stats"):
				return str(child.name)
	return ""


func _get_direct_child(root, name: String):
	if root == null or not is_instance_valid(root) or not root is Node:
		return null
	return root.get_node_or_null(name)


func _node_is_visible(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is CanvasLayer:
		return node.visible
	if node is Window:
		return node.visible
	if node is CanvasItem:
		return node.is_visible_in_tree()
	return false


## Results (including misses) are cached per view instance and cleared on shop entry.
func _get_view_member(view, property_names: Array, node_name: String):
	if view == null or not is_instance_valid(view) or not view is Node:
		return null
	var cache_key := "%d:%s" % [view.get_instance_id(), node_name]
	if _view_member_cache.has(cache_key):
		var cached = _view_member_cache[cache_key]
		if cached != null and is_instance_valid(cached):
			return cached
		if cached == null and not view.is_node_ready():
			return null
		_view_member_cache.erase(cache_key)

	for prop in property_names:
		if _has_prop.call(view, prop):
			var value = view.get(prop)
			if value != null and is_instance_valid(value):
				_view_member_cache[cache_key] = value
				return value

	var direct = view.get_node_or_null(node_name)
	if direct != null:
		_view_member_cache[cache_key] = direct
		return direct

	var found = view.find_child(node_name, true, false)
	if found != null or view.is_node_ready():
		_view_member_cache[cache_key] = found
	return found


## Connect to the game's transition signal (verified in examples/MyBattleStats) so
## battle start hides the overlay immediately, independent of button visibility.
func _setup_transition_listener() -> void:
	if get_tree() == null:
		return
	if not get_tree().node_added.is_connected(_on_node_added_transition):
		get_tree().node_added.connect(_on_node_added_transition)
	_scan_transition_nodes(get_tree().root)


func _scan_transition_nodes(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_on_node_added_transition(node)
	for child in node.get_children():
		_scan_transition_nodes(child)


func _on_node_added_transition(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.has_signal("transition_requested"):
		return
	if not node.has_method("request_transition"):
		return
	var id := node.get_instance_id()
	if _transition_nodes.has(id):
		return
	_transition_nodes[id] = true
	node.transition_requested.connect(_on_transition_requested)


func _on_transition_requested(target: String, data) -> void:
	if target != "battle":
		return
	# The shop state can remain current for the whole fade-to-black; hold the
	# overlay closed long enough to cover the transition, then let the phase
	# change clear it (see update()).
	_gate_hold_until_ms = Time.get_ticks_msec() + 5000
	# Preserve the immediate hide: if the overlay was open, close it now rather
	# than waiting for the next update() tick.
	if _overlay_gate_reason.is_empty():
		_overlay_gate_reason = GATE_TRANSITION
		visibility_changed.emit(false, GATE_TRANSITION)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added_transition):
		get_tree().node_added.disconnect(_on_node_added_transition)
