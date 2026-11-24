extends Node
## User-facing hotkeys: backtick toggles fast-forward, Tab toggles the trinket bag.
##
## Fast-forward is available during battle and replay; the trinket bag is
## available during shop and battle. The mod's replay overlay instantiates its
## own battle state, so the active battle view is resolved through the replay
## controller when that overlay is running.

const NodeUtils = preload("node_utils.gd")
const ModConfig = preload("mod_config.gd")
const HotkeyHint = preload("../hud/hotkey_hint.gd")

const BATTLE_SCRIPT := "res://game/states/battle_state.gd"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"

const FAST_FORWARD_KEY := Key.KEY_QUOTELEFT
const BACKPACK_KEY := Key.KEY_TAB

const ACTION_FAST_FORWARD := "fast_forward"
const ACTION_BACKPACK := "backpack"

const HINT_FAST_FORWARD := "Press ` to toggle"
const HINT_BACKPACK := "Press Tab to toggle"

var _context = null
var _replay = null

var _hint_layer: CanvasLayer = null
var _ff_hint = null
var _bag_hint = null
var _ff_target_id := 0
var _bag_target_id := 0


func setup(context, replay) -> void:
	_context = context
	_replay = replay
	_build_hint()


## Pure key matching: returns the action name for a key event, or "".
static func action_for_event(event: InputEvent) -> String:
	if not (event is InputEventKey):
		return ""
	if not event.pressed or event.echo:
		return ""
	if event.ctrl_pressed or event.shift_pressed or event.alt_pressed or event.meta_pressed:
		return ""
	if event.keycode == FAST_FORWARD_KEY or event.physical_keycode == FAST_FORWARD_KEY:
		return ACTION_FAST_FORWARD
	if event.keycode == BACKPACK_KEY or event.physical_keycode == BACKPACK_KEY:
		return ACTION_BACKPACK
	return ""


func _input(event: InputEvent) -> void:
	if not _hotkeys_enabled():
		return
	var action := action_for_event(event)
	if action.is_empty():
		return
	if _text_input_focused():
		return
	var handled := false
	if action == ACTION_FAST_FORWARD:
		handled = _toggle_fast_forward()
	elif action == ACTION_BACKPACK:
		handled = _toggle_backpack()
	if handled:
		get_viewport().set_input_as_handled()


func _toggle_fast_forward() -> bool:
	var view = _active_battle_view()
	if view == null or not is_instance_valid(view):
		return false
	if _battle_modal_open(view):
		return false
	var button = view.get("fast_forward_button")
	if button == null or not is_instance_valid(button):
		return false
	if not button.visible:
		return false
	button.button_pressed = not button.button_pressed
	_log("HOTKEY fast-forward -> %s" % button.button_pressed)
	return true


func _toggle_backpack() -> bool:
	var battle_view = _active_battle_view()
	if battle_view != null and is_instance_valid(battle_view):
		return _toggle_battle_bag(battle_view)
	var shop_view = _active_shop_view()
	if shop_view != null and is_instance_valid(shop_view):
		return _toggle_shop_bag(shop_view)
	return false


func _toggle_battle_bag(view) -> bool:
	if _battle_modal_open(view):
		return false
	var bag = view.get("player_trinket_bag_ui")
	if bag == null or not is_instance_valid(bag):
		return false
	if view.has_method("_toggle_bag"):
		view.call("_toggle_bag", bag)
	else:
		bag.toggle()
	_log("HOTKEY backpack (battle)")
	return true


func _toggle_shop_bag(view) -> bool:
	if _shop_modal_open(view):
		return false
	var bag = view.get("trinket_bag_ui")
	if bag == null or not is_instance_valid(bag):
		return false
	if bag.is_open():
		if view.has_method("_close_trinket_bag"):
			view.call("_close_trinket_bag")
		else:
			bag.close()
	else:
		bag.toggle()
	_log("HOTKEY backpack (shop)")
	return true


func _active_battle_view():
	if _replay != null and _replay.is_active():
		return _replay.active_battle_view()
	var state = _current_state()
	if NodeUtils.script_is(state, BATTLE_SCRIPT):
		return state.get("view") if NodeUtils.has_property(state, "view") else null
	return null


func _active_shop_view():
	var state = _current_state()
	if NodeUtils.script_is(state, SHOP_SCRIPT):
		return state.get("view") if NodeUtils.has_property(state, "view") else null
	return null


func _current_state():
	return NodeUtils.current_state(get_tree())


func _battle_modal_open(view) -> bool:
	if _get_bool(view, "_tutorial_active"):
		return true
	if view.has_method("_stats_panel_up") and view.call("_stats_panel_up"):
		return true
	if view.has_method("_endscreen_panel_up") and view.call("_endscreen_panel_up"):
		return true
	var inspect = view.get("inspect_popup")
	if inspect != null and is_instance_valid(inspect) and inspect.has_method("is_open") and inspect.is_open():
		return true
	return false


func _shop_modal_open(view) -> bool:
	if _get_bool(view, "_is_interaction_locked"):
		return true
	if _get_bool(view, "_holding"):
		return true
	if _get_bool(view, "_state_modal_active"):
		return true
	if view.has_method("_is_overlay_open") and view.call("_is_overlay_open"):
		return true
	return false


func _get_bool(obj, property: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	if not NodeUtils.has_property(obj, property):
		return false
	return bool(obj.get(property))


func _text_input_focused() -> bool:
	var focus = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _hotkeys_enabled() -> bool:
	if _context == null:
		return true
	return _context.feature_enabled(ModConfig.KEY_HOTKEYS)


func _build_hint() -> void:
	_hint_layer = CanvasLayer.new()
	_hint_layer.name = "CreatureComforts_HotkeyHints"
	_hint_layer.layer = 100
	add_child(_hint_layer)
	_ff_hint = HotkeyHint.new()
	_ff_hint.name = "FastForwardHint"
	_hint_layer.add_child(_ff_hint)
	_bag_hint = HotkeyHint.new()
	_bag_hint.name = "BackpackHint"
	_hint_layer.add_child(_bag_hint)


func _process(_delta: float) -> void:
	if not _hotkeys_enabled():
		_ff_hint.unwatch()
		_bag_hint.unwatch()
		_ff_target_id = 0
		_bag_target_id = 0
		return
	_ff_target_id = _sync_hint(_ff_hint, _fast_forward_target(), HINT_FAST_FORWARD, _ff_target_id)
	_bag_target_id = _sync_hint(_bag_hint, _backpack_target(), HINT_BACKPACK, _bag_target_id)


func _sync_hint(hint, target, text: String, current_id: int) -> int:
	if target == null or not is_instance_valid(target):
		hint.unwatch()
		return 0
	if current_id != target.get_instance_id():
		hint.watch(target, text)
		return target.get_instance_id()
	return current_id


func _fast_forward_target():
	var view = _active_battle_view()
	if view == null or not is_instance_valid(view):
		return null
	var button = view.get("fast_forward_button")
	if button == null or not is_instance_valid(button):
		return null
	return button


func _backpack_target():
	var battle_view = _active_battle_view()
	if battle_view != null and is_instance_valid(battle_view):
		var button = _bag_open_button(battle_view.get("player_trinket_bag_ui"))
		if button != null:
			return button
	var shop_view = _active_shop_view()
	if shop_view != null and is_instance_valid(shop_view):
		return _bag_open_button(shop_view.get("trinket_bag_ui"))
	return null


func _bag_open_button(bag):
	if bag == null or not is_instance_valid(bag):
		return null
	var open_button = bag.get("open_button")
	if open_button == null or not is_instance_valid(open_button):
		return null
	return open_button


func _log(message: String) -> void:
	if _context == null or _context.logger == null:
		return
	if not _context.logger.debug_logging:
		return
	_context.logger.log_event(message)
