extends Node
## Builds and owns the mod's CanvasLayers and panels.
##
## Extracted from mod_main.gd. Panels are created once at startup; feature
## toggles only change visibility, so no UI or signal subscriptions duplicate.

const NodeUtils = preload("../core/node_utils.gd")
const ModConfig = preload("../core/mod_config.gd")
const ShopHighlight = preload("shop_highlight.gd")
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

var reminder_layer: CanvasLayer = null
var player_hud_layer: CanvasLayer = null

var reminder_label = null
var shop_income_panel = null
var trinket_reminders_panel = null
var positional_trinkets_panel = null
var rank_odds_panel = null
var base_hp_panel = null
var watchlist_panel = null
var trinket_panel = null
var player_hud = null
var battle_elapsed_panel = null
var opponent_panel = null
var shop_highlight = null

var _logger = null
var _formatter = null
var _feature_enabled: Callable
var _sounds_enabled: Callable
var _rank_odds_popup_open := false
var _base_hp_popup_open := false


func setup(formatter, logger, feature_enabled: Callable, sounds_enabled: Callable) -> void:
	_formatter = formatter
	_logger = logger
	_feature_enabled = feature_enabled
	_sounds_enabled = sounds_enabled
	_build_reminder_layer()
	_build_shop_highlight()
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
	rank_odds_panel.log_line.connect(_logger.log_event)
	rank_odds_panel.popup_visibility_changed.connect(_on_rank_odds_popup_visibility_changed)
	reminder_layer.add_child(rank_odds_panel)

	# Base HP by day table, 25% across the viewport.
	base_hp_panel = BaseHpPanel.new()
	base_hp_panel.name = "BaseHpPanel"
	base_hp_panel.log_line.connect(_logger.log_event)
	base_hp_panel.popup_visibility_changed.connect(_on_base_hp_popup_visibility_changed)
	reminder_layer.add_child(base_hp_panel)

	# Watchlist button + popup; shop-gated with the rest of the reminder layer
	# and hidden entirely when the Shop Highlights setting is off.
	watchlist_panel = WatchlistPanel.new()
	watchlist_panel.name = "WatchlistPanel"
	watchlist_panel.setup(_formatter, _sounds_enabled)
	reminder_layer.add_child(watchlist_panel)


## Shop highlighting and the watchlist button share one setting: highlights are
## only useful with the watchlist, so disabling the feature hides both. The
## selection dictionary is shared by reference, so watchlist edits apply to the
## highlights on the next frame.
func _build_shop_highlight() -> void:
	shop_highlight = ShopHighlight.new()
	shop_highlight.name = "ShopHighlight"
	add_child(shop_highlight)
	shop_highlight.setup(watchlist_panel.selection)
	var enabled: bool = _feature_enabled.call(ModConfig.KEY_SHOP_HIGHLIGHTS)
	shop_highlight.set_enabled(enabled)
	watchlist_panel.visible = enabled


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


## Apply the shop overlay gate to the reminder layer. Returns true when the
## layer is visible (the caller may play queued chimes).
func apply_gate(allowed: bool) -> bool:
	if reminder_layer == null:
		return false
	reminder_layer.visible = allowed
	if not allowed:
		# The layer is hidden, so a still-open popup would reappear on the next
		# shop visit. Close every shop popup with the rest of the shop UI.
		if watchlist_panel != null:
			watchlist_panel.close_popup()
		if rank_odds_panel != null:
			rank_odds_panel.reset_for_shop()
		if base_hp_panel != null:
			base_hp_panel.reset_for_shop()
	return allowed


## Defensive fallback: hide shop-only panels whenever the shop is not current.
## The trinket gains panel is deliberately NOT hidden here: it lives on the gated reminder
## layer and its content must survive the results/event screens until the shop returns.
func hide_shop_panels() -> void:
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


## Close any open shop modal when the shop becomes interactive again.
func reset_shop_popups_for_shop() -> void:
	if rank_odds_panel != null:
		rank_odds_panel.reset_for_shop()
	if base_hp_panel != null:
		base_hp_panel.reset_for_shop()


func update_shop_income(income: int) -> void:
	if shop_income_panel == null:
		return
	if not _feature_enabled.call(ModConfig.KEY_SHOP_INCOME):
		shop_income_panel.hide_panel()
		return
	shop_income_panel.set_income(income)


func update_rank_odds(rank: int) -> void:
	if rank_odds_panel == null:
		return
	if not _feature_enabled.call(ModConfig.KEY_RANK_ODDS_PREVIEW):
		rank_odds_panel.hide_panel()
		return
	if _base_hp_popup_open:
		return
	rank_odds_panel.set_rank(rank)


func update_base_hp(day: int, total_hp: int) -> void:
	if base_hp_panel == null:
		return
	if not _feature_enabled.call(ModConfig.KEY_BASE_HP_CHART):
		base_hp_panel.hide_panel()
		return
	if _rank_odds_popup_open:
		return
	base_hp_panel.set_day(day, total_hp)


func update_player_hud(state, is_battle: bool) -> void:
	if player_hud == null:
		return
	if not _feature_enabled.call(ModConfig.KEY_BATTLE_STATUS_PANEL):
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
	if not _feature_enabled.call(ModConfig.KEY_BATTLE_STATUS_PANEL):
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
	if not _feature_enabled.call(ModConfig.KEY_BATTLE_STATUS_PANEL):
		opponent_panel.hide_panel()
		return
	opponent_panel.show_opponent(opp_name, mmr)


func hide_opponent_panel() -> void:
	if opponent_panel == null:
		return
	opponent_panel.hide_panel()


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
	if value:
		return
	if key == ModConfig.KEY_BATTLE_STATUS_PANEL:
		if player_hud != null:
			player_hud.visible = false
		if battle_elapsed_panel != null:
			battle_elapsed_panel.hide_panel()
		if opponent_panel != null:
			opponent_panel.hide_panel()
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
	for panel in [rank_odds_panel, base_hp_panel, watchlist_panel]:
		if panel != null and panel != modal:
			panel.visible = false


## Restore the shop button row after a modal closes or a setting changes.
## `watchlist_override` applies a live Shop Highlights value before the loader
## has persisted it; null reads the stored setting.
func _restore_shop_buttons(watchlist_override = null) -> void:
	if _rank_odds_popup_open or _base_hp_popup_open:
		return
	if rank_odds_panel != null:
		rank_odds_panel.visible = _feature_enabled.call(ModConfig.KEY_RANK_ODDS_PREVIEW)
	if base_hp_panel != null:
		base_hp_panel.visible = _feature_enabled.call(ModConfig.KEY_BASE_HP_CHART)
	if watchlist_panel == null:
		return
	if watchlist_override == null:
		watchlist_override = _feature_enabled.call(ModConfig.KEY_SHOP_HIGHLIGHTS)
	watchlist_panel.visible = bool(watchlist_override)


func _on_trinket_panel_layout_debug(message: String) -> void:
	if not _logger.debug_logging:
		return
	for line in message.split("\n"):
		_logger.log_message(line)
