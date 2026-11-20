extends RefCounted
## Shows a hover reminder on shop monster cards for next-purchase trinkets.
##
## Reads the held trinket ids, builds the reminder lines, and drives a shared
## HotkeyHint from the shop cards' own monster_hovered/monster_unhovered signals.
## power_band is dropped once the first purchase of the day has happened.

const NodeUtils = preload("../core/node_utils.gd")
const PurchaseReminders = preload("../core/purchase_reminders.gd")
const ModConfig = preload("../core/mod_config.gd")

var _context = null
var _hint = null
var _bought_today := false
var _last_round := -1
var _current_text := ""
var _attached_view_id := 0


func setup(context, hint) -> void:
	_context = context
	_hint = hint
	_connect_signal_bus()


func _connect_signal_bus() -> void:
	var bus = NodeUtils.get_autoload("SignalBus")
	if bus != null and bus.has_signal("monster_bought"):
		if not bus.monster_bought.is_connected(_on_monster_bought):
			bus.monster_bought.connect(_on_monster_bought)


func _on_monster_bought(_monster) -> void:
	_bought_today = true


func update(run, view) -> void:
	if _hint == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_PURCHASE_REMINDERS):
		_current_text = ""
		_hint.hide_hint()
		return

	var round := int(run.get("current_round")) if NodeUtils.has_property(run, "current_round") else -1
	if round != _last_round:
		_last_round = round
		_bought_today = false

	var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	if held == null:
		held = []
	var lines: Array = PurchaseReminders.build_lines(held, _bought_today)
	_current_text = "\n".join(lines)
	if _current_text.is_empty():
		_hint.hide_hint()
		return
	_attach(view)


func _attach(view) -> void:
	if view == null or not is_instance_valid(view):
		return
	var view_id: int = view.get_instance_id()
	if _attached_view_id == view_id:
		return
	_attached_view_id = view_id
	var slots = view.get("shop_slots") if NodeUtils.has_property(view, "shop_slots") else []
	if slots == null:
		return
	for slot in slots:
		if slot == null or not is_instance_valid(slot):
			continue
		if not slot.has_signal("monster_hovered"):
			continue
		slot.monster_hovered.connect(_on_card_hovered.bind(slot))
		slot.monster_unhovered.connect(_on_card_unhovered)


func _on_card_hovered(_zone, _index, _monster, card) -> void:
	if _hint != null and not _current_text.is_empty():
		_hint.show_for(card, _current_text)


func _on_card_unhovered() -> void:
	if _hint != null:
		_hint.hide_hint()


func on_feature_toggled(key: String, value: bool) -> void:
	if value:
		return
	if key == ModConfig.KEY_PURCHASE_REMINDERS:
		_current_text = ""
		if _hint != null:
			_hint.hide_hint()
