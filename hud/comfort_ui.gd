extends Node
## Builds and owns the mod's CanvasLayers and panels.
##
## Extracted from mod_main.gd. Panels are created once at startup; feature
## toggles only change visibility, so no UI or signal subscriptions duplicate.

## Emitted when the shop's Replay Last Battle button is pressed.
signal replay_requested

const NodeUtils = preload("../core/node_utils.gd")
const ModConfig = preload("../core/mod_config.gd")
const ShopHighlight = preload("shop_highlight.gd")
const SellValueIndicators = preload("sell_value_indicators.gd")
const ReminderLabel = preload("reminder_label.gd")
const ShopIncomePanel = preload("shop_income_panel.gd")
const TrinketRemindersPanel = preload("trinket_reminders_panel.gd")
const PositionalTrinketsPanel = preload("positional_trinkets_panel.gd")
const RankOddsPanel = preload("rank_odds_panel.gd")
const BaseHpPanel = preload("base_hp_panel.gd")
const WatchlistPanel = preload("watchlist_panel.gd")
const PlayerHud = preload("player_hud.gd")
const TrinketPanel = preload("trinket_panel.gd")
const BattleElapsedPanel = preload("battle_elapsed_panel.gd")
const OpponentPanel = preload("opponent_panel.gd")
const CombatStatsPanel = preload("combat_stats_panel.gd")
const ReplayButton = preload("replay_button.gd")

var reminder_layer: CanvasLayer = null
var player_hud_layer: CanvasLayer = null

var reminder_label = null
var shop_income_panel = null
var trinket_reminders_panel = null
var positional_trinkets_panel = null
var rank_odds_panel = null
var base_hp_panel = null
var watchlist_panel = null
var replay_button = null
var trinket_panel = null
var player_hud = null
var battle_elapsed_panel = null
var opponent_panel = null
var combat_stats_panel = null
var shop_highlight = null
var sell_value_indicators = null

var _context = null
var _rank_odds_popup_open := false
var _base_hp_popup_open := false
var _replay_available := false
var _replay_active := false


func setup(context) -> void:
	_context = context
	_build_reminder_layer()
	_build_shop_highlight()
	_build_sell_value_indicators()
	_build_player_hud()


func _build_reminder_layer() -> void:
	reminder_layer = CanvasLayer.new()
	reminder_layer.layer = 100  # Above game UI but below debug overlays
	reminder_layer.name = "CreatureComforts_Reminders"
	add_child(reminder_layer)

	reminder_label = ReminderLabel.new()
	reminder_label.name = "ReminderLabel"
	reminder_layer.add_child(reminder_label)

	# Bottom-center income readout; the reminder layer's shop gate controls visibility.
	shop_income_panel = ShopIncomePanel.new()
	shop_income_panel.name = "ShopIncomePanel"
	reminder_layer.add_child(shop_income_panel)

	# Left-aligned trinket reminders ~10% down the screen; shop-gated. Added after the label
	# so it draws on top while visible.
	trinket_reminders_panel = TrinketRemindersPanel.new()
	trinket_reminders_panel.name = "TrinketRemindersPanel"
	trinket_reminders_panel.layout_debug.connect(_on_trinket_panel_layout_debug)
	reminder_layer.add_child(trinket_reminders_panel)

	# Movable positional trinket summary. Starts collapsed at 25% of the viewport
	# and is refreshed by the controller on every shop poll.
	positional_trinkets_panel = PositionalTrinketsPanel.new()
	positional_trinkets_panel.name = "PositionalTrinketsPanel"
	reminder_layer.add_child(positional_trinkets_panel)

	# Battle trinket gains. Lives here (not on a separate layer) so the shop overlay gate
	# holds it back through the results/event/gift screens and reveals it once the shop is
	# interactive again. The presenter keeps its content across that wait.
	trinket_panel = TrinketPanel.new()
	trinket_panel.name = "TrinketPanel"
	reminder_layer.add_child(trinket_panel)

	rank_odds_panel = RankOddsPanel.new()
	rank_odds_panel.name = "RankOddsPanel"
	rank_odds_panel.log_line.connect(_context.logger.log_event)
	rank_odds_panel.popup_visibility_changed.connect(_on_rank_odds_popup_visibility_changed)
	reminder_layer.add_child(rank_odds_panel)

	# Base HP by day table, 25% across the viewport.
	base_hp_panel = BaseHpPanel.new()
	base_hp_panel.name = "BaseHpPanel"
	base_hp_panel.log_line.connect(_context.logger.log_event)
	base_hp_panel.popup_visibility_changed.connect(_on_base_hp_popup_visibility_changed)
	reminder_layer.add_child(base_hp_panel)

	# Watchlist button + popup; shop-gated with the rest of the reminder layer
	# and hidden entirely when the Shop Highlights setting is off.
	watchlist_panel = WatchlistPanel.new()
	watchlist_panel.name = "WatchlistPanel"
	watchlist_panel.setup(_context.formatter, _context.sounds_enabled, _context.mod_volume)
	reminder_layer.add_child(watchlist_panel)

	# Replay Last Battle: shop-gated like the other HUD buttons. The controller
	# owns the read-only battle overlay; this button only asks for it.
	replay_button = ReplayButton.new()
	replay_button.name = "ReplayButton"
	replay_button.setup_sound(_context.sounds_enabled, _context.mod_volume)
	replay_button.log_line.connect(_context.logger.log_event)
	replay_button.pressed.connect(func(): replay_requested.emit())
	reminder_layer.add_child(replay_button)


## Shop highlighting and the watchlist button share one setting: highlights are
## only useful with the watchlist, so disabling the feature hides both. The
## selection dictionary is shared by reference, so watchlist edits apply to the
## highlights on the next frame.
func _build_shop_highlight() -> void:
	shop_highlight = ShopHighlight.new()
	shop_highlight.name = "ShopHighlight"
	add_child(shop_highlight)
	shop_highlight.setup(watchlist_panel.selection)
	var enabled: bool = _context.feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS)
	shop_highlight.set_enabled(enabled)
	watchlist_panel.visible = enabled


## Sell-value badges on the fielded and bench slots. The controller attaches to
## the game's My Team grid on each shop poll; this node only owns its lifecycle
## and the feature toggle.
func _build_sell_value_indicators() -> void:
	sell_value_indicators = SellValueIndicators.new()
	sell_value_indicators.name = "SellValueIndicators"
	add_child(sell_value_indicators)
	sell_value_indicators.setup(_context)


func _build_player_hud() -> void:
	player_hud_layer = CanvasLayer.new()
	player_hud_layer.layer = 110  # Above game UI, matching NP_QoL's HUD layer
	player_hud_layer.name = "CreatureComforts_PlayerHud"
	add_child(player_hud_layer)

	player_hud = PlayerHud.new()
	player_hud.name = "PlayerHud"
	player_hud_layer.add_child(player_hud)

	# Post-battle simulation time. Lives on the battle HUD layer (not the shop-gated
	# reminder layer) so it can appear during the battle results screen.
	battle_elapsed_panel = BattleElapsedPanel.new()
	battle_elapsed_panel.name = "BattleElapsedPanel"
	player_hud_layer.add_child(battle_elapsed_panel)

	# Bottom-right opponent name + MMR readout, battle-only and on the same layer.
	opponent_panel = OpponentPanel.new()
	opponent_panel.name = "OpponentPanel"
	player_hud_layer.add_child(opponent_panel)

	# Post-battle combat statistics (merged from BatoStats++). Lives on the battle
	# HUD layer so it can appear on the results screen; the battle coordinator
	# shows it when a battle finishes and hides it while a replay runs.
	combat_stats_panel = CombatStatsPanel.new()
	combat_stats_panel.name = "CombatStatsPanel"
	player_hud_layer.add_child(combat_stats_panel)


## Apply the shop overlay gate to the reminder layer. Returns true when the
## layer is visible (the caller may play queued chimes).
func apply_gate(allowed: bool) -> bool:
	if reminder_layer == null:
		return false
	# The replay overlay owns the screen; the gate must not re-show the mod's
	# shop HUD over it.
	if _replay_active:
		reminder_layer.visible = false
		return false
	reminder_layer.visible = allowed
	if not allowed:
		# The layer is hidden, so a still-open popup would reappear on the next
		# shop visit. Close every shop popup with the rest of the shop UI.
		_close_shop_popups()
	return allowed


## Close the shop's modals and hide the sell-value badges. Used when the shop
## HUD is hidden, either by the overlay gate or by the replay overlay.
func _close_shop_popups() -> void:
	if watchlist_panel != null:
		watchlist_panel.close_popup()
	if rank_odds_panel != null:
		rank_odds_panel.reset_for_shop()
	if base_hp_panel != null:
		base_hp_panel.reset_for_shop()
	if sell_value_indicators != null:
		sell_value_indicators.hide_all()


## Hide every mod-owned shop panel while the replay overlay is up. The game's
## own battle UI is part of the replay; the mod's HUD would otherwise float
## over it.
func set_replay_active(active: bool) -> void:
	_replay_active = active
	if reminder_layer != null:
		reminder_layer.visible = not active
	if player_hud_layer != null:
		player_hud_layer.visible = not active
	if active:
		_close_shop_popups()
		if shop_highlight != null:
			shop_highlight.set_enabled(false)
	elif shop_highlight != null:
		shop_highlight.set_enabled(_context.feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS))


## Defensive fallback: hide shop-only panels whenever the shop is not current.
## The trinket gains panel is deliberately NOT hidden here: it lives on the gated reminder
## layer and its content must survive the results/event screens until the shop returns.
func hide_shop_panels() -> void:
	if sell_value_indicators != null:
		sell_value_indicators.hide_all()
	if shop_income_panel != null:
		shop_income_panel.hide_panel()
	if trinket_reminders_panel != null:
		trinket_reminders_panel.hide_panel()
	if positional_trinkets_panel != null:
		positional_trinkets_panel.hide_panel()
	if rank_odds_panel != null:
		rank_odds_panel.hide_panel()
	if base_hp_panel != null:
		base_hp_panel.hide_panel()
	if watchlist_panel != null:
		watchlist_panel.close_popup()
	if replay_button != null:
		replay_button.hide_panel()


## Close any open shop modal when the shop becomes interactive again.
func reset_shop_popups_for_shop() -> void:
	if rank_odds_panel != null:
		rank_odds_panel.reset_for_shop()
	if base_hp_panel != null:
		base_hp_panel.reset_for_shop()


## Update the Replay Last Battle button. The shop controller calls this on every
## shop poll. The button is always shown in the shop while the feature is on
## (dimmed until a battle has been captured), and is hidden by the shop overlay
## gate and by an open modal.
func update_replay_button(available: bool) -> void:
	_replay_available = available
	if replay_button == null:
		return
	if _rank_odds_popup_open or _base_hp_popup_open:
		replay_button.hide_panel()
		return
	replay_button.set_available(available)
	replay_button.show_button()


func update_shop_income(income: int) -> void:
	if shop_income_panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_SHOP_INCOME):
		shop_income_panel.hide_panel()
		return
	shop_income_panel.set_income(income)


## Attach/refresh the sell-value badges for the current shop view. Called on
## every shop poll; the controller reuses existing badges. `allowed` mirrors the
## shop overlay gate so badges stay hidden through the shop fade-in and modals.
func update_sell_values(view, allowed: bool = true) -> void:
	if sell_value_indicators == null:
		return
	if not allowed:
		sell_value_indicators.hide_all()
		return
	sell_value_indicators.update_team(view)


func update_rank_odds(rank: int) -> void:
	if rank_odds_panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_RANK_ODDS_PREVIEW):
		rank_odds_panel.hide_panel()
		return
	if _base_hp_popup_open:
		return
	rank_odds_panel.set_rank(rank)


func update_base_hp(day: int, total_hp: int) -> void:
	if base_hp_panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_BASE_HP_CHART):
		base_hp_panel.hide_panel()
		return
	if _rank_odds_popup_open:
		return
	base_hp_panel.set_day(day, total_hp)


func update_player_hud(state, is_battle: bool) -> void:
	if player_hud == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_BATTLE_STATUS_PANEL):
		player_hud.visible = false
		return
	if not is_battle:
		player_hud.visible = false
		return
	# The elapsed readout occupies the same spot; never show both.
	if battle_elapsed_panel != null and battle_elapsed_panel.visible:
		player_hud.visible = false
		return

	var player_run = state.get("_replay_p1_data") if NodeUtils.has_property(state, "_replay_p1_data") else null
	if player_run == null:
		player_hud.visible = false
		return

	player_hud.update_stats(_build_player_stats(player_run))
	var is_active: bool = state.get("is_battle_active") if NodeUtils.has_property(state, "is_battle_active") else false
	player_hud.visible = is_active


## Hide the lives/wins/day HUD without changing its stored stats. Used when the
## elapsed readout takes over the same screen space.
func hide_player_hud() -> void:
	if player_hud != null:
		player_hud.visible = false


## Show the simulated battle duration once the battle is over. Shares the Battle
## Status Panel toggle with the lives/wins/day HUD, so one setting controls every
## battle readout.
func show_battle_elapsed(seconds_text: String) -> void:
	if battle_elapsed_panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_BATTLE_STATUS_PANEL):
		battle_elapsed_panel.hide_panel()
		return
	battle_elapsed_panel.show_elapsed(seconds_text)


func hide_battle_elapsed() -> void:
	if battle_elapsed_panel == null:
		return
	battle_elapsed_panel.hide_panel()


## Show the opponent name and MMR during battle. Shares the Battle Status Panel
## toggle with the rest of the battle readouts.
func show_opponent(opp_name: String, mmr: String) -> void:
	if opponent_panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_BATTLE_STATUS_PANEL):
		opponent_panel.hide_panel()
		return
	opponent_panel.show_opponent(opp_name, mmr)


func hide_opponent_panel() -> void:
	if opponent_panel == null:
		return
	opponent_panel.hide_panel()


## Show the post-battle combat statistics panel. An empty snapshot (the capture
## failed) hides it instead of showing an empty panel.
func show_combat_stats(snapshot: Dictionary) -> void:
	if combat_stats_panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_COMBAT_STATS_PANEL):
		combat_stats_panel.hide_panel()
		return
	combat_stats_panel.show_snapshot(snapshot)


func hide_combat_stats() -> void:
	if combat_stats_panel != null:
		combat_stats_panel.hide_panel()


func _build_player_stats(player_run) -> Dictionary:
	var stats := {
		"hp": "?",
		"wins": "?",
		"day": "?",
	}

	for pair in [
		["hp", "lives"],
		["wins", "current_wins"],
		["day", "current_round"],
	]:
		var value = player_run.get(pair[1])
		if value != null:
			stats[pair[0]] = str(value)

	# The game sets this once the first 0-lives revive has happened, so the HUD
	# can show the run is on its last life (upside-down heart).
	var used_second_chance = player_run.get("has_used_second_chance")
	if used_second_chance != null:
		stats["second_chance"] = bool(used_second_chance)

	return stats


## Apply a live settings change to the panels this UI owns.
func on_feature_toggled(key: String, value: bool) -> void:
	# Shop highlighting has no poll-driven re-show, so handle both states here.
	# The same setting shows/hides the watchlist button and popup.
	if key == ModConfig.KEY_SHOP_HIGHLIGHTS:
		if shop_highlight != null:
			shop_highlight.set_enabled(value)
		if not value and watchlist_panel != null:
			watchlist_panel.close_popup()
		# Restore the button row, which also respects an open Base HP popup.
		_restore_shop_buttons(value)
		return
	# Sell-value badges are re-shown by the next shop poll when enabled.
	if key == ModConfig.KEY_SELL_VALUE_INDICATORS:
		if sell_value_indicators != null:
			sell_value_indicators.set_enabled(value)
		return
	if value:
		return
	if key == ModConfig.KEY_BATTLE_STATUS_PANEL:
		if player_hud != null:
			player_hud.visible = false
		if battle_elapsed_panel != null:
			battle_elapsed_panel.hide_panel()
		if opponent_panel != null:
			opponent_panel.hide_panel()
	elif key == ModConfig.KEY_COMBAT_STATS_PANEL:
		hide_combat_stats()
	elif key == ModConfig.KEY_SHOP_INCOME:
		if shop_income_panel != null:
			shop_income_panel.hide_panel()
	elif key == ModConfig.KEY_POSITIONAL_TRINKETS:
		if positional_trinkets_panel != null:
			positional_trinkets_panel.hide_panel()
	elif key == ModConfig.KEY_RANK_ODDS_PREVIEW:
		if rank_odds_panel != null:
			rank_odds_panel.hide_panel()
	elif key == ModConfig.KEY_BASE_HP_CHART:
		if base_hp_panel != null:
			base_hp_panel.hide_panel()


## The shop popups are full-screen modals drawn by sibling panels. Hide the other
## buttons while one is open so they do not float above its dim backdrop.
func _on_rank_odds_popup_visibility_changed(open: bool) -> void:
	_rank_odds_popup_open = open
	_on_shop_modal_visibility_changed(open, rank_odds_panel)


func _on_base_hp_popup_visibility_changed(open: bool) -> void:
	_base_hp_popup_open = open
	_on_shop_modal_visibility_changed(open, base_hp_panel)


func _on_shop_modal_visibility_changed(open: bool, modal) -> void:
	if not open:
		_restore_shop_buttons()
		return
	for panel in [rank_odds_panel, base_hp_panel, watchlist_panel, replay_button]:
		if panel != null and panel != modal:
			panel.visible = false


## Restore the shop button row after a modal closes or a setting changes.
## `watchlist_override` applies a live Shop Highlights value before the loader
## has persisted it; null reads the stored setting.
func _restore_shop_buttons(watchlist_override = null) -> void:
	if _rank_odds_popup_open or _base_hp_popup_open:
		return
	if rank_odds_panel != null:
		rank_odds_panel.visible = _context.feature_enabled(ModConfig.KEY_RANK_ODDS_PREVIEW)
	if base_hp_panel != null:
		base_hp_panel.visible = _context.feature_enabled(ModConfig.KEY_BASE_HP_CHART)
	if watchlist_panel != null:
		if watchlist_override == null:
			watchlist_override = _context.feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS)
		watchlist_panel.visible = bool(watchlist_override)
	if replay_button != null:
		replay_button.set_available(_replay_available)
		replay_button.show_button()


func _on_trinket_panel_layout_debug(message: String) -> void:
	if not _context.logger.debug_logging:
		return
	for line in message.split("\n"):
		_context.logger.log_message(line)
