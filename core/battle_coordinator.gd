extends RefCounted
## Battle-phase orchestration: trinket gain tracking, completion detection,
## result logging, and the opponent card.
##
## Extracted from mod_main.gd. Owns the battle-scoped trackers and the
## once-per-battle log guard. mod_main decides when the battle phase is current
## and passes the phase-change flag in.

const NodeUtils = preload("node_utils.gd")
const RunData = preload("run_data.gd")
const BattleMonitor = preload("battle_monitor.gd")
const OpponentInfo = preload("opponent_info.gd")
const BattleCompletionReporter = preload("battle_completion_reporter.gd")
const BattleTrinketTracker = preload("battle_trinket_tracker.gd")
const TrinketGainPresenter = preload("../hud/trinket_gain_presenter.gd")

var _context = null
var _ui = null

var _battle_trinkets = null
var _trinket_gains = null
var _battle_completion = null
var _battle_logged := false

var _captured_opponent = null
var _captured_at := 0
var _opponent_battle_id := 0
var _opponent_info: Dictionary = {}


func setup(context, ui) -> void:
	_context = context
	_ui = ui

	_battle_trinkets = BattleTrinketTracker.new()
	_battle_completion = BattleCompletionReporter.new()
	_trinket_gains = TrinketGainPresenter.new()
	_trinket_gains.setup(_ui.trinket_panel, _context)


## Capture the opponent RunData from the game's battle transition signal.
func on_transition(target: String, data) -> void:
	if target != "battle":
		return
	if not (data is Dictionary):
		return
	var opp = data.get("opponent_data")
	if opp != null and is_instance_valid(opp):
		_captured_opponent = opp
		_captured_at = Time.get_ticks_msec()


## Keep a rolling "last state outside battle" snapshot for the pre-battle baseline.
func note_non_battle() -> void:
	_battle_trinkets.note_non_battle(RunData.get_run_data())


## Reset the once-per-battle completion guard when leaving the battle phase.
func reset_completion() -> void:
	_battle_completion.reset()


## Reset the once-per-battle log guard (new shop visit or non-battle phase).
func reset_log_guard() -> void:
	_battle_logged = false


## Hide the trinket gains panel (Trinkets Gained Panel setting turned off).
func hide_trinket_gains() -> void:
	_trinket_gains.hide()


## A new run started: drop any tracked battle and clear the gains panel so the
## previous run's trinkets never appear in the new run.
func on_run_changed() -> void:
	_battle_trinkets.reset()
	_trinket_gains.hide()


## Handle one battle poll. Returns true when the battle phase was processed (so
## the caller can record the phase); false when the replay data is not ready.
func handle(state, phase_changed: bool) -> bool:
	# On battle entry, clear the previous battle's elapsed readout before checking
	# completion, so a battle that is already over still shows its own time.
	if phase_changed:
		_ui.hide_battle_elapsed()

	# A replay restarts the simulation inside the same battle state. Hide the
	# previous readout while the replay runs; _check_battle_completion shows it
	# again when the replay finishes.
	if not BattleMonitor.is_over(state):
		_ui.hide_battle_elapsed()

	# The opponent card follows the exact same visibility as the lives/wins/day HUD.
	var is_active: bool = state.get("is_battle_active") if NodeUtils.has_property(state, "is_battle_active") else false

	# Battle completion detection (win/loss/draw) - independent of replay logging
	_check_battle_completion(state)
	_update_opponent_panel(state, is_active)

	var player = state.get("_replay_p1_data") if NodeUtils.has_property(state, "_replay_p1_data") else null
	var opponent = state.get("_replay_p2_data") if NodeUtils.has_property(state, "_replay_p2_data") else null

	if player == null or opponent == null:
		return false

	# Only log once per battle when battle is actually active (is_active is above)
	if not _battle_logged and is_active:
		_log_phase_entry(player)

		if _context.logger.deep_inspection:
			_context.logger.log_lines(_context.formatter.format_deep_inspect_battle(state, player, opponent))
			_context.logger.log_lines(_context.formatter.format_battle_trinket_state(RunData.get_run_data()))

		# Battle-scoped trinket baseline (prefers the last snapshot taken OUTSIDE battle).
		# Any gains still on the panel are from the previous battle, so clear them now.
		_battle_trinkets.start(RunData.get_run_data())
		_trinket_gains.on_battle_started()

		_battle_logged = true

	# Freeze the battle-end snapshot the FIRST time battle_over is observed. The game pre-computes
	# the following event's rewards during the results screen, applying them to run.trinket_ids
	# before the event UI appears; continuing to refresh the end snapshot would leak those future
	# event trinkets into the battle diff. The panel itself is displayed later, when the battle
	# state ends (see finalize_trinket_tracking).
	_battle_trinkets.poll(state, RunData.get_run_data())

	return true


## Stop battle trinket tracking. Called when leaving the battle state and on trainer/run changes.
## Gains are always logged once. This runs on EVERY non-battle poll, so an empty result (no
## battle was being tracked) must not hide a panel still waiting to be seen in the shop.
## The panel itself is shop-gated: it appears once the player is back in the shop and stays
## until collapsed or the next battle starts.
func finalize_trinket_tracking(show_panel := true) -> void:
	var gains: Dictionary = _battle_trinkets.finalize(RunData.get_run_data(), _context.logger, _context.formatter, show_panel)
	_trinket_gains.apply_finalized(gains, show_panel)


func _update_opponent_panel(state, is_active: bool) -> void:
	var p2 = state.get("_replay_p2_data") if NodeUtils.has_property(state, "_replay_p2_data") else null
	if p2 == null:
		_ui.hide_opponent_panel()
		return
	var battle_id: int = state.get_instance_id()
	if battle_id != _opponent_battle_id or _opponent_info.is_empty():
		_opponent_battle_id = battle_id
		_opponent_info = OpponentInfo.info(p2, _captured_opponent, _captured_at)
	# Keep the card up through the results screen, matching the elapsed readout;
	# both are hidden when the battle state is left (PhaseRouter).
	if is_active or BattleMonitor.is_over(state):
		_ui.show_opponent(str(_opponent_info.get("name", "?")), str(_opponent_info.get("mmr", "-")))
	else:
		_ui.hide_opponent_panel()


func _check_battle_completion(state) -> void:
	if not _battle_completion.check(state):
		return
	var sim = state.get("simulation") if NodeUtils.has_property(state, "simulation") else null
	var battle_data = sim.get("data") if sim != null and NodeUtils.has_property(sim, "data") else null
	# Log the result once per battle; a replay only refreshes the elapsed readout.
	if _battle_completion.is_first_completion():
		_log_battle_result(battle_data)
	_ui.show_battle_elapsed(BattleMonitor.format_seconds(BattleMonitor.time_elapsed(battle_data)))
	# The elapsed readout sits over the lives/wins/day HUD; show only one of them.
	_ui.hide_player_hud()


func _log_battle_result(battle_data) -> void:
	var info := BattleMonitor.classify(battle_data)
	if info["hp"] == null:
		if str(info["detail"]).is_empty():
			_context.logger.log_event("BATTLE COMPLETE | %s" % info["result"])
		else:
			_context.logger.log_event("BATTLE COMPLETE | %s | %s" % [info["result"], info["detail"]])
		return
	_context.logger.log_event("BATTLE COMPLETE | %s | HP %d" % [info["result"], info["hp"]])


func _log_phase_entry(run) -> void:
	_context.logger.log_event(_context.formatter.format_phase_entry("BATTLE", run))
	if _context.logger.deep_inspection:
		_context.logger.log_lines(_context.formatter.format_phase_snapshot("BATTLE", run))
