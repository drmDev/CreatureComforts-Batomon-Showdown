extends RefCounted
## Phase detection and dispatch: decides whether the current game state is the
## shop, a battle, or something else, and routes to the matching controller.
##
## Extracted from mod_main.gd. Owns the poll cadence and the last-phase marker.

const NodeUtils = preload("node_utils.gd")
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"
const POLL_INTERVAL_MS := 500

var _host: Node = null
var _context = null
var _ui = null
var _shop = null
var _battle = null

var _next_poll := 0
var _last_phase := ""


func setup(host: Node, context, ui, shop, battle) -> void:
	_host = host
	_context = context
	_ui = ui
	_shop = shop
	_battle = battle


## Poll the current phase at most once per POLL_INTERVAL_MS.
func poll() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_poll:
		return
	_next_poll = now + POLL_INTERVAL_MS
	_inspect_current_phase()


func _inspect_current_phase() -> void:
	var main = _host.get_tree().current_scene
	var state = main.get("current_state") if NodeUtils.has_property(main, "current_state") else null

	var is_battle := NodeUtils.script_is(state, BATTLE_SCRIPT)
	_ui.update_player_hud(state, is_battle)
	# Defensive fallback: the income and trinket-reminder panels are normally hidden by the
	# reminder layer's shop gate, but hide them directly whenever the shop is not the current phase.
	if not NodeUtils.script_is(state, SHOP_SCRIPT):
		_ui.hide_shop_panels()
	if not is_battle:
		_ui.hide_opponent_panel()
		# The elapsed readout belongs to the battle screen; drop it as soon as the
		# battle state is left (shop, event, or trinket select).
		_ui.hide_battle_elapsed()
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _last_phase == "battle":
			_battle.reset_completion()
		_battle.finalize_trinket_tracking()
		# Keep a rolling "last state outside battle" snapshot. The battle is simulated before the
		# first poll sees the battle state, so this is the only reliable pre-battle baseline.
		_battle.note_non_battle()

	if NodeUtils.script_is(state, SHOP_SCRIPT):
		var phase_changed := _last_phase != "shop"
		if _shop.handle(state, phase_changed):
			_last_phase = "shop"
	elif is_battle:
		var phase_changed := _last_phase != "battle"
		if _battle.handle(state, phase_changed):
			if phase_changed:
				_reset_transient_state(false, true, true)
			_last_phase = "battle"
	else:
		if _last_phase != "":
			_last_phase = ""
			_battle.reset_log_guard()
			_reset_transient_state(true, true, true)  # Drop stale chimes when leaving the shop


func _reset_transient_state(clear_suppression: bool, clear_reminders: bool, clear_chimes: bool) -> void:
	# The trinket gains panel is shop-gated and only cleared on a battle start or a
	# trainer/run change, so this per-phase reset leaves it alone.
	_shop.reset_transient(clear_suppression, clear_reminders)
	if clear_chimes:
		_context.chimes.clear()
