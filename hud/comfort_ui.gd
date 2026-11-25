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
const TrinketsPanel = preload("trinkets_panel.gd")
const ItemsUsedPanel = preload("items_used_panel.gd")
const GreenStoneTipsPopup = preload("green_stone_tips_popup.gd")
const RankOddsPanel = preload("rank_odds_panel.gd")
const BaseHpPanel = preload("base_hp_panel.gd")
const WatchlistPanel = preload("watchlist_panel.gd")
const PlayerHud = preload("player_hud.gd")
const BattleElapsedPanel = preload("battle_elapsed_panel.gd")
const OpponentPanel = preload("opponent_panel.gd")
const CombatStatsPanel = preload("combat_stats_panel.gd")
const ReplayButton = preload("replay_button.gd")
const ShopButtonBar = preload("../core/shop_button_bar.gd")
const BattleMonitor = preload("../core/battle_monitor.gd")
const HotkeyHint = preload("hotkey_hint.gd")

const BATTLE_SCRIPT := "res://game/states/battle_state.gd"
const BADGE_GAP := 4.0

var reminder_layer: CanvasLayer = null
var player_hud_layer: CanvasLayer = null

var reminder_label = null
## One unified Trinkets panel; its Alerts/Gained/Bonuses tabs are the content
## views the feature controllers update independently.
var trinkets_panel = null
## Standalone Items Used panel (daily + per-run item usage).
var items_used_panel = null
## Green Stone / Ratacomb strategy help, opened from the Items Used panel.
var green_stone_tips = null
var rank_odds_panel = null
var base_hp_panel = null
var watchlist_panel = null
var replay_button = null
var rank_odds_button = null
var watchlist_button = null
var base_hp_button = null
var player_hud = null
var battle_elapsed_panel = null
var opponent_panel = null
var combat_stats_panel = null
var shop_highlight = null
var sell_value_indicators = null
var purchase_reminder_hint = null

var _context = null
var _tree_watcher = null
var _is_replay_active: Callable
var _replay_available := false
var _replay_opponent_name := "?"
var _replay_opponent_mmr := "-"
var _replay_elapsed_shown := false
var _replay_player_hud_shown := false
var _replay_button_host_id := 0
var _rank_odds_button_host_id := 0
var _rank_odds_button_extra := 0.0
var _watchlist_button_host_id := 0
var _watchlist_button_shift := 0.0
var _base_hp_button_host_id := 0
var _base_hp_button_extra := 0.0

# Battle trainer badge tracking. The three battle readouts follow the game's
# trainer badges (bottom-left player, bottom-right enemy) each frame.
var _player_anchor: Control = null
var _enemy_anchor: Control = null
var _player_badge = null
var _enemy_badge = null
var _battle_state_id := 0
var _replay_battle_state = null

## Live settings changes: one handler per feature key (see on_feature_toggled).
var _toggles: Dictionary = {}


func _init() -> void:
	_toggles = {
		ModConfig.KEY_TRINKETS_PANEL: _on_trinkets_toggled,
		ModConfig.KEY_ITEM_USAGE_TRACKER: _on_items_used_toggled,
		ModConfig.KEY_SHOP_HIGHLIGHTS: _on_shop_highlights_toggled,
		ModConfig.KEY_SELL_VALUE_INDICATORS: _on_sell_value_toggled,
		ModConfig.KEY_BATTLE_STATUS_PANEL: _on_battle_status_toggled,
		ModConfig.KEY_COMBAT_STATS_PANEL: _on_combat_stats_toggled,
		ModConfig.KEY_RANK_ODDS_PREVIEW: _on_rank_odds_toggled,
		ModConfig.KEY_BASE_HP_CHART: _on_base_hp_toggled,
	}


func setup(context, tree_watcher = null, is_replay_active: Callable = Callable()) -> void:
	_context = context
	_tree_watcher = tree_watcher
	_is_replay_active = is_replay_active
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

	# Unified Trinkets panel (Alerts / Gained / Bonuses), left-aligned ~10% down the
	# screen and shop-gated. Added after the label so it draws on top while visible.
	# It lives on this gated layer so battle gains are held back through the
	# results/event screens and revealed once the shop is interactive again.
	trinkets_panel = TrinketsPanel.new()
	trinkets_panel.name = "TrinketsPanel"
	trinkets_panel.setup(_context.config)
	trinkets_panel.set_enabled(_context.feature_enabled(ModConfig.KEY_TRINKETS_PANEL))
	reminder_layer.add_child(trinkets_panel)

	# Standalone Items Used panel, positioned below the Trinkets panel. The shop
	# controller pushes its content on every poll.
	items_used_panel = ItemsUsedPanel.new()
	items_used_panel.name = "ItemsUsedPanel"
	items_used_panel.setup(_context.config, _context.item_icons)
	reminder_layer.add_child(items_used_panel)

	rank_odds_panel = RankOddsPanel.new()
	rank_odds_panel.name = "RankOddsPanel"
	rank_odds_panel.log_line.connect(_on_panel_log_line)
	rank_odds_panel.popup_visibility_changed.connect(_on_shop_modal_visibility_changed.bind(rank_odds_panel))
	reminder_layer.add_child(rank_odds_panel)

	# Base HP by day table, 25% across the viewport.
	base_hp_panel = BaseHpPanel.new()
	base_hp_panel.name = "BaseHpPanel"
	base_hp_panel.log_line.connect(_on_panel_log_line)
	base_hp_panel.popup_visibility_changed.connect(_on_shop_modal_visibility_changed.bind(base_hp_panel))
	reminder_layer.add_child(base_hp_panel)

	# Watchlist button + popup; shop-gated with the rest of the reminder layer
	# and hidden entirely when the Shop Highlights setting is off.
	watchlist_panel = WatchlistPanel.new()
	watchlist_panel.name = "WatchlistPanel"
	watchlist_panel.setup(_context.formatter, _context.sounds_enabled, _context.mod_volume)
	reminder_layer.add_child(watchlist_panel)

	# Shop monster purchase reminder tooltip (hover over a shop monster card).
	purchase_reminder_hint = HotkeyHint.new()
	purchase_reminder_hint.name = "PurchaseReminderHint"
	reminder_layer.add_child(purchase_reminder_hint)

	# Green Stone tips modal. Added last so its dim backdrop covers the rest of
	# the reminder layer; it must be a sibling of the Items Used panel because
	# that panel clips its children.
	green_stone_tips = GreenStoneTipsPopup.new()
	green_stone_tips.name = "GreenStoneTipsPopup"
	reminder_layer.add_child(green_stone_tips)
	items_used_panel.set_tips_popup(green_stone_tips)

	# Replay Last Battle is created on demand and attached to the game's shop
	# HudButtons bar (see attach_to_shop_view) so the game owns its layout and
	# visibility. The controller owns the read-only battle overlay; this button
	# only asks for it.


## Shop highlighting and the watchlist button share one setting: highlights are
## only useful with the watchlist, so disabling the feature hides both. The
## selection dictionary is shared by reference, so watchlist edits apply to the
## highlights on the next frame.
func _build_shop_highlight() -> void:
	shop_highlight = ShopHighlight.new()
	shop_highlight.name = "ShopHighlight"
	add_child(shop_highlight)
	shop_highlight.setup(watchlist_panel.selection, _tree_watcher)
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

	# Player-side anchor: a plain Control (not a container) placed at the top
	# centre of the game's PlayerTrainerBadge. The HUD and elapsed panels are its
	# children and are positioned above that point each frame, so they follow the
	# badge's slide-in/out tween. A container would re-layout its children.
	_player_anchor = Control.new()
	_player_anchor.name = "CreatureComforts_PlayerAnchor"
	_player_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_hud_layer.add_child(_player_anchor)

	player_hud = PlayerHud.new()
	player_hud.name = "PlayerHud"
	_player_anchor.add_child(player_hud)

	# Post-battle simulation time. Lives on the battle HUD layer (not the shop-gated
	# reminder layer) so it can appear during the battle results screen.
	battle_elapsed_panel = BattleElapsedPanel.new()
	battle_elapsed_panel.name = "BattleElapsedPanel"
	_player_anchor.add_child(battle_elapsed_panel)

	# Enemy-side anchor: placed at the top-right of the game's EnemyTrainerBadge.
	_enemy_anchor = Control.new()
	_enemy_anchor.name = "CreatureComforts_EnemyAnchor"
	_enemy_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_hud_layer.add_child(_enemy_anchor)

	# Bottom-right opponent name + MMR readout, battle-only and on the same layer.
	opponent_panel = OpponentPanel.new()
	opponent_panel.name = "OpponentPanel"
	_enemy_anchor.add_child(opponent_panel)

	# Post-battle combat statistics (merged from BatoStats++). Lives on the battle
	# HUD layer so it can appear on the results screen; the battle coordinator
	# shows it when a battle finishes and hides it while a replay runs.
	combat_stats_panel = CombatStatsPanel.new()
	combat_stats_panel.name = "CombatStatsPanel"
	player_hud_layer.add_child(combat_stats_panel)


## Follow the game's trainer badges every frame so the battle readouts stay
## glued to the trainers during their slide-in/out tweens. The panels remain on
## this mod's CanvasLayer (not children of the badge), so a PanelContainer cannot
## re-layout them; this tracker mirrors the badge's global rect instead.
func _process(_delta: float) -> void:
	if player_hud_layer == null or not player_hud_layer.visible:
		return
	_track_battle_badges()


func _track_battle_badges() -> void:
	var state = _current_battle_state()
	if state == null:
		_clear_battle_badges()
		return
	var state_id = state.get_instance_id()
	if state_id != _battle_state_id:
		_battle_state_id = state_id
		_player_badge = state.get_node_or_null("BattleView/CanvasLayer/PlayerTrainerBadge")
		_enemy_badge = state.get_node_or_null("BattleView/CanvasLayer/EnemyTrainerBadge")
		if _replay_active_now():
			_show_replay_opponent()
	_position_player_anchor()
	_position_enemy_anchor()
	if _replay_active_now():
		_check_replay_completion(state)


func _current_battle_state():
	var state = _current_scene_battle_state()
	if state != null:
		return state
	# The replay battle is not the current scene state, so it is only worth
	# searching for while a replay is actually running.
	if not _replay_active_now():
		return null
	if _replay_battle_state != null and is_instance_valid(_replay_battle_state):
		return _replay_battle_state
	_replay_battle_state = _find_replay_battle_state()
	return _replay_battle_state


func _current_scene_battle_state():
	var state = NodeUtils.current_state(get_tree())
	if state == null or not NodeUtils.script_is(state, BATTLE_SCRIPT):
		return null
	return state


## The mod's replay overlay instantiates a battle scene named
## "CreatureComfortsReplayBattle" (see hud/battle_replay_controller.gd). It is not
## the current scene state, so the phase router does not drive it; the tracker
## finds it here so the battle readouts can follow its trainer badges.
func _find_replay_battle_state():
	var tree := get_tree()
	if tree == null:
		return null
	var root = tree.root
	if root == null:
		return null
	return root.find_child("CreatureComfortsReplayBattle", true, false)


func _clear_battle_badges() -> void:
	_battle_state_id = 0
	_player_badge = null
	_enemy_badge = null
	_replay_battle_state = null
	if _player_anchor != null:
		_player_anchor.visible = false
	if _enemy_anchor != null:
		_enemy_anchor.visible = false


func _position_player_anchor() -> void:
	if _player_anchor == null:
		return
	var badge = _player_badge
	if badge == null or not is_instance_valid(badge):
		_player_anchor.visible = false
		return
	_player_anchor.visible = true
	var rect = _badge_rest_rect(badge)
	var ref := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	_player_anchor.position = ref
	if player_hud != null:
		player_hud.position = Vector2(-player_hud.size.x * 0.5, -player_hud.size.y - BADGE_GAP)
	if battle_elapsed_panel != null:
		battle_elapsed_panel.position = Vector2(-battle_elapsed_panel.size.x * 0.5, -battle_elapsed_panel.size.y - BADGE_GAP)


func _position_enemy_anchor() -> void:
	if _enemy_anchor == null:
		return
	var badge = _enemy_badge
	if badge == null or not is_instance_valid(badge):
		_enemy_anchor.visible = false
		return
	_enemy_anchor.visible = true
	var rect = _badge_rest_rect(badge)
	var ref := Vector2(rect.position.x + rect.size.x, rect.position.y)
	_enemy_anchor.position = ref
	if opponent_panel != null:
		opponent_panel.position = Vector2(-opponent_panel.size.x, -opponent_panel.size.y - BADGE_GAP)


## The badge's rest rect (before the end-screen inset). The game tweens the
## badge inward to make room for the Hide/Confirm buttons at the end of a battle;
## the mod panels stay at the rest position instead of following that inward
## shift. `rest_left()` returns the badge's captured rest x offset.
func _badge_rest_rect(badge):
	var rect = badge.get_global_rect()
	if badge.has_method("rest_left"):
		var rest_x = badge.rest_left()
		var shifted = rect.position
		shifted.x += rest_x - badge.position.x
		rect.position = shifted
	return rect


## During the mod's replay overlay the phase router is paused (mod_main skips
## its poll), so the battle readouts are not driven by the normal controllers.
## The opponent card is static for the whole replay, so it is shown once when the
## replay battle state is first seen.
func _show_replay_opponent() -> void:
	show_opponent(_replay_opponent_name, _replay_opponent_mmr)


## Per-frame replay completion check. The player HUD is refreshed only until it
## becomes visible (the battle's is_battle_active flips on a few frames after the
## state is first seen), and the elapsed readout is shown once when the battle
## ends. After that this is a cheap battle_over lookup.
func _check_replay_completion(state) -> void:
	if _replay_elapsed_shown:
		return
	if BattleMonitor.is_over(state):
		_replay_elapsed_shown = true
		show_battle_elapsed_and_hide_hud(BattleMonitor.format_seconds(BattleMonitor.time_elapsed(BattleMonitor.battle_data(state))))
		return
	if not _replay_player_hud_shown:
		update_player_hud(state, true)
		if player_hud != null and player_hud.visible:
			_replay_player_hud_shown = true


## Apply the shop overlay gate to the reminder layer. Returns true when the
## layer is visible (the caller may play queued chimes).
func apply_gate(allowed: bool) -> bool:
	# The replay overlay owns the screen; the gate must not re-show the mod's
	# shop HUD over it.
	if _replay_active_now():
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
	watchlist_panel.close_popup()
	green_stone_tips.hide_panel()
	rank_odds_panel.reset_for_shop()
	base_hp_panel.reset_for_shop()
	sell_value_indicators.hide_all()


## Enter or leave the shop replay overlay. The replay's p2 template lacks the
## MMR fields, so the captured opponent values are passed in on entry.
func set_replay_active(active: bool, opponent_name := "", opponent_mmr := "") -> void:
	if active:
		_replay_opponent_name = opponent_name
		_replay_opponent_mmr = opponent_mmr
	_replay_elapsed_shown = false
	_replay_player_hud_shown = false
	reminder_layer.visible = not active
	# The battle HUD layer stays visible during the mod's replay so the three
	# battle readouts can follow the replay battle's trainer badges. The tracker
	# syncs them from the replay battle state while a replay is active.
	if active:
		_close_shop_popups()
		shop_highlight.set_enabled(false)
	else:
		# Leaving the replay overlay: hide the battle readouts until the next
		# phase poll re-shows them for a real battle.
		hide_player_hud()
		hide_battle_elapsed()
		hide_opponent_panel()
		shop_highlight.set_enabled(_context.feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS))


## True while the replay overlay is running (queried from the replay controller).
func _replay_active_now() -> bool:
	return _is_replay_active.is_valid() and bool(_is_replay_active.call())


## Defensive fallback: hide shop-only panels whenever the shop is not current.
## The trinket gains panel is deliberately NOT hidden here: it lives on the gated reminder
## layer and its content must survive the results/event screens until the shop returns.
func hide_shop_panels() -> void:
	sell_value_indicators.hide_all()
	# Hide only; content is kept so battle gains survive the phase change and the
	# next shop poll re-shows the panels.
	trinkets_panel.hide_panel()
	items_used_panel.hide_panel()
	green_stone_tips.hide_panel()
	rank_odds_panel.hide_panel()
	base_hp_panel.hide_panel()
	watchlist_panel.close_popup()
	_detach_rank_odds_button()
	_detach_watchlist_button()
	_detach_base_hp_button()


## Close any open shop modal when the shop becomes interactive again.
func reset_shop_popups_for_shop() -> void:
	rank_odds_panel.reset_for_shop()
	base_hp_panel.reset_for_shop()


## Free a hosted button, restoring the host's layout through `restore` when the
## host is still the one the button was attached to.
func _free_hosted(button, host, host_id: int, restore: Callable) -> void:
	if not is_instance_valid(button):
		return
	if is_instance_valid(host) and host.get_instance_id() == host_id and restore.is_valid():
		restore.call(host)
	button.free()


## Attach the replay button to the game's shop HudButtons bar. The bar is a
## fresh node on every shop entry, so its instance id is tracked and the button
## is rebuilt whenever the bar changes. Mirrors Brain Rot's shop button attach
## (name-sorted insertion and idempotent bar widening) so the two mods coexist.
func attach_to_shop_view(view) -> void:
	var hud_buttons = _get_shop_hud_buttons(view)
	if hud_buttons == null:
		if is_instance_valid(replay_button):
			_detach_replay_button()
			_panel_log("REPLAY", "detached (no HudButtons)")
		return
	var host_id: int = hud_buttons.get_instance_id()
	if is_instance_valid(replay_button) and _replay_button_host_id == host_id:
		return
	_detach_replay_button()
	replay_button = _make_replay_button()
	if replay_button == null:
		return
	hud_buttons.add_child(replay_button)
	_insert_replay_button(hud_buttons)
	_replay_button_host_id = host_id
	_widen_hud_buttons(hud_buttons)
	replay_button.set_available(_replay_available)
	_panel_log("REPLAY", "attached")


func _get_shop_hud_buttons(view):
	if not is_instance_valid(view):
		return null
	return view.get_node_or_null("HudButtons")


func _make_replay_button():
	var button = ReplayButton.new()
	button.setup_sound(_context.sounds_enabled, _context.mod_volume)
	button.log_line.connect(_on_panel_log_line)
	button.replay_pressed.connect(func(): replay_requested.emit())
	return button


func _detach_replay_button() -> void:
	_free_hosted(replay_button, null, 0, Callable())
	replay_button = null
	_replay_button_host_id = 0


func _insert_replay_button(hud_buttons) -> void:
	var names: Array = []
	for i in range(hud_buttons.get_child_count()):
		var child = hud_buttons.get_child(i)
		if child == replay_button:
			continue
		names.append(str(child.name))
	var index: int = ShopButtonBar.sorted_insert_index(names, str(replay_button.name))
	hud_buttons.move_child(replay_button, index)


func _widen_hud_buttons(hud_buttons) -> void:
	var widths: Array = []
	for i in range(hud_buttons.get_child_count()):
		var child = hud_buttons.get_child(i)
		widths.append(child.get_combined_minimum_size().x if child is Control else 0.0)
	var separation := float(hud_buttons.get_theme_constant("separation"))
	hud_buttons.offset_left = ShopButtonBar.widened_left_offset(widths, separation, hud_buttons.offset_right)


func _panel_log(label: String, detail: String) -> void:
	_on_panel_log_line("%s | %s" % [label, detail])


## Update the Replay Last Battle button. The shop controller calls this on every
## shop poll with the current view. The button's visibility is owned by the
## game's HudButtons bar; the mod only sets its availability (dimming).
func update_replay_button(view, available: bool) -> void:
	_replay_available = available
	attach_to_shop_view(view)
	if not is_instance_valid(replay_button):
		return
	replay_button.set_available(available)


## Attach/refresh the sell-value badges for the current shop view. Called on
## every shop poll; the controller reuses existing badges. `allowed` mirrors the
## shop overlay gate so badges stay hidden through the shop fade-in and modals.
func update_sell_values(view, allowed: bool = true) -> void:
	if not allowed:
		sell_value_indicators.hide_all()
		return
	sell_value_indicators.update_team(view)


## Attach the rank odds icon to the game's RankUI panel. The icon becomes the
## first child of the panel's HBoxContainer and the panel extends leftward by
## the icon width plus separation, so the game's odds text stays in place.
func _attach_rank_odds_button(view) -> void:
	var rank_ui = _get_shop_rank_ui(view)
	var hbox = _get_rank_ui_hbox(rank_ui)
	if hbox == null:
		if is_instance_valid(rank_odds_button):
			_detach_rank_odds_button()
			_panel_log("RANK ODDS", "detached (no RankUI)")
		return
	var host_id: int = rank_ui.get_instance_id()
	if is_instance_valid(rank_odds_button) and _rank_odds_button_host_id == host_id:
		return
	_detach_rank_odds_button()
	rank_odds_button = rank_odds_panel.make_external_button()
	if rank_odds_button == null:
		return
	rank_odds_button.name = "CreatureComfortsRankOddsButton"
	rank_odds_button.tooltip_text = "Preview shop rank odds"
	hbox.add_child(rank_odds_button)
	hbox.move_child(rank_odds_button, 0)
	_rank_odds_button_host_id = host_id
	var separation := float(hbox.get_theme_constant("separation"))
	var added_width: float = rank_odds_button.get_combined_minimum_size().x
	_rank_odds_button_extra = added_width + separation
	rank_ui.offset_left = ShopButtonBar.insert_on_left(rank_ui.offset_left, added_width, separation)
	_panel_log("RANK ODDS", "attached")


func _get_shop_rank_ui(view):
	if not is_instance_valid(view):
		return null
	return view.get_node_or_null("RankUI")


func _get_rank_ui_hbox(rank_ui):
	if not is_instance_valid(rank_ui):
		return null
	return rank_ui.get_node_or_null("HBoxContainer")


func _detach_rank_odds_button() -> void:
	var host = null
	if is_instance_valid(rank_odds_button):
		var parent = rank_odds_button.get_parent()
		if is_instance_valid(parent):
			host = parent.get_parent()
	_free_hosted(rank_odds_button, host, _rank_odds_button_host_id, func(h): h.offset_left += _rank_odds_button_extra)
	rank_odds_button = null
	_rank_odds_button_host_id = 0
	_rank_odds_button_extra = 0.0




func update_rank_odds(view, rank: int, held_trinket_ids = []) -> void:
	if not _context.feature_enabled(ModConfig.KEY_RANK_ODDS_PREVIEW):
		rank_odds_panel.hide_panel()
		_detach_rank_odds_button()
		return
	_attach_rank_odds_button(view)
	rank_odds_panel.set_rank(rank, held_trinket_ids)


## Attach the watchlist button to the game's active-team HBox (the row holding
## the Team panel), inserting it left of the team and shifting the centred HBox
## left by half the added width so the team stays put.
func update_watchlist_button(view) -> void:
	if not _context.feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS):
		_detach_watchlist_button()
		return
	_attach_watchlist_button(view)


func _attach_watchlist_button(view) -> void:
	var hbox = _get_team_hbox(view)
	if hbox == null:
		if is_instance_valid(watchlist_button):
			_detach_watchlist_button()
			_panel_log("WATCHLIST", "detached (no team HBox)")
		return
	var host_id: int = hbox.get_instance_id()
	if is_instance_valid(watchlist_button) and _watchlist_button_host_id == host_id:
		return
	_detach_watchlist_button()
	watchlist_button = watchlist_panel.make_button()
	if watchlist_button == null:
		return
	watchlist_button.name = "CreatureComfortsWatchlistButton"
	hbox.add_child(watchlist_button)
	hbox.move_child(watchlist_button, 0)
	_watchlist_button_host_id = host_id
	var separation := float(hbox.get_theme_constant("separation"))
	var added: float = watchlist_button.get_combined_minimum_size().x + separation
	_watchlist_button_shift = added * 0.5
	hbox.offset_left -= _watchlist_button_shift
	hbox.offset_right -= _watchlist_button_shift
	_panel_log("WATCHLIST", "attached")


func _get_team_hbox(view):
	if not is_instance_valid(view):
		return null
	var team_ui = view.get_node_or_null("MonsterTeamUI")
	if not is_instance_valid(team_ui):
		return null
	return team_ui.get_node_or_null("HBoxContainer")


func _detach_watchlist_button() -> void:
	var host = watchlist_button.get_parent() if is_instance_valid(watchlist_button) else null
	_free_hosted(watchlist_button, host, _watchlist_button_host_id, func(h):
		h.offset_left += _watchlist_button_shift
		h.offset_right += _watchlist_button_shift)
	watchlist_button = null
	_watchlist_button_host_id = 0
	_watchlist_button_shift = 0.0




## Attach the base HP heart icon to the game's trainer HP bar, extending the bar
## rightward so the icon sits just past its right edge without moving the bar.
func _attach_base_hp_button(view) -> void:
	var hp_ui = _get_shop_hp_ui(view)
	if hp_ui == null:
		if is_instance_valid(base_hp_button):
			_detach_base_hp_button()
			_panel_log("BASE HP", "detached (no HpUI)")
		return
	var host_id: int = hp_ui.get_instance_id()
	if is_instance_valid(base_hp_button) and _base_hp_button_host_id == host_id:
		return
	_detach_base_hp_button()
	base_hp_button = base_hp_panel.make_external_button()
	if base_hp_button == null:
		return
	base_hp_button.name = "CreatureComfortsBaseHpButton"
	base_hp_button.tooltip_text = "Base HP by day"
	hp_ui.add_child(base_hp_button)
	_base_hp_button_host_id = host_id
	var button_size: Vector2 = base_hp_button.get_combined_minimum_size()
	base_hp_button.size = button_size
	var width: float = hp_ui.offset_right - hp_ui.offset_left
	var height: float = hp_ui.offset_bottom - hp_ui.offset_top
	var gap := 4.0
	_base_hp_button_extra = button_size.x + gap
	hp_ui.offset_right += _base_hp_button_extra
	base_hp_button.position = Vector2(width + gap, roundf((height - button_size.y) * 0.5))
	_panel_log("BASE HP", "attached")


func _get_shop_hp_ui(view):
	if not is_instance_valid(view):
		return null
	return view.get_node_or_null("HpUI")


func _detach_base_hp_button() -> void:
	var host = base_hp_button.get_parent() if is_instance_valid(base_hp_button) else null
	_free_hosted(base_hp_button, host, _base_hp_button_host_id, func(h): h.offset_right -= _base_hp_button_extra)
	base_hp_button = null
	_base_hp_button_host_id = 0
	_base_hp_button_extra = 0.0




func update_base_hp(view, day: int, total_hp: int) -> void:
	if not _context.feature_enabled(ModConfig.KEY_BASE_HP_CHART):
		base_hp_panel.hide_panel()
		_detach_base_hp_button()
		return
	_attach_base_hp_button(view)
	base_hp_panel.set_day(day, total_hp)


func update_player_hud(state, is_battle: bool) -> void:
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

	var player_run = NodeUtils.get_or(state, "_replay_p1_data", null)
	if player_run == null:
		player_hud.visible = false
		return

	player_hud.update_stats(_build_player_stats(player_run))
	var is_active: bool = bool(NodeUtils.get_or(state, "is_battle_active", false))
	player_hud.visible = is_active


## Hide the lives/wins/day HUD without changing its stored stats. Used when the
## elapsed readout takes over the same screen space.
func hide_player_hud() -> void:
	player_hud.visible = false


## Show the simulated battle duration once the battle is over. Shares the Battle
## Status Panel toggle with the lives/wins/day HUD, so one setting controls every
## battle readout.
func show_battle_elapsed(seconds_text: String) -> void:
	if not _context.feature_enabled(ModConfig.KEY_BATTLE_STATUS_PANEL):
		battle_elapsed_panel.hide_panel()
		return
	battle_elapsed_panel.show_elapsed(seconds_text)


## Show the elapsed readout and hide the lives/wins/day HUD, which share a spot.
func show_battle_elapsed_and_hide_hud(seconds_text: String) -> void:
	show_battle_elapsed(seconds_text)
	hide_player_hud()


func hide_battle_elapsed() -> void:
	battle_elapsed_panel.hide_panel()


## Show the opponent name and MMR during battle. Shares the Battle Status Panel
## toggle with the rest of the battle readouts.
func show_opponent(opp_name: String, mmr: String) -> void:
	if not _context.feature_enabled(ModConfig.KEY_BATTLE_STATUS_PANEL):
		opponent_panel.hide_panel()
		return
	opponent_panel.show_opponent(opp_name, mmr)


func hide_opponent_panel() -> void:
	opponent_panel.hide_panel()


## Show the post-battle combat statistics panel. An empty snapshot (the capture
## failed) hides it instead of showing an empty panel.
func show_combat_stats(snapshot: Dictionary) -> void:
	if not _context.feature_enabled(ModConfig.KEY_COMBAT_STATS_PANEL):
		combat_stats_panel.hide_panel()
		return
	combat_stats_panel.show_snapshot(snapshot)


func hide_combat_stats() -> void:
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
	if _toggles.has(key):
		_toggles[key].call(value)


## The single Trinkets Panel setting shows/hides the whole unified panel.
func _on_trinkets_toggled(value: bool) -> void:
	trinkets_panel.set_enabled(value)
	if not value:
		_context.chimes.clear_trinket()


## The Items Used panel hides while disabled; tracking keeps running and the
## next shop poll re-shows the panel once the setting is back on.
func _on_items_used_toggled(value: bool) -> void:
	if not value:
		items_used_panel.hide_panel()


## Shop highlighting has no poll-driven re-show, so handle both states here.
## The same setting shows/hides the watchlist button and popup.
func _on_shop_highlights_toggled(value: bool) -> void:
	shop_highlight.set_enabled(value)
	if not value:
		watchlist_panel.close_popup()
		_detach_watchlist_button()
	# Restore the button row, which also respects an open Base HP popup.
	_restore_shop_buttons(value)


## Sell-value badges are re-shown by the next shop poll when enabled.
func _on_sell_value_toggled(value: bool) -> void:
	sell_value_indicators.set_enabled(value)


func _on_battle_status_toggled(value: bool) -> void:
	if not value:
		player_hud.visible = false
		battle_elapsed_panel.hide_panel()
		opponent_panel.hide_panel()


func _on_combat_stats_toggled(value: bool) -> void:
	if not value:
		hide_combat_stats()


func _on_rank_odds_toggled(value: bool) -> void:
	if not value:
		rank_odds_panel.hide_panel()
		_detach_rank_odds_button()


func _on_base_hp_toggled(value: bool) -> void:
	if not value:
		base_hp_panel.hide_panel()
		_detach_base_hp_button()


## Panel lifecycle lines are debug detail, not events: drop them unless Debug
## Logging is on. The panels emit unconditionally, so the live toggle applies.
func _on_panel_log_line(message: String) -> void:
	if _context != null and _context.logger != null and _context.logger.debug_logging:
		_context.logger.log_event(message)


## The shop popups are full-screen modals drawn by sibling panels. Hide the other
## buttons while one is open so they do not float above its dim backdrop. Both
## popup signals bind their panel, so one handler serves every modal.
func _on_shop_modal_visibility_changed(open: bool, modal) -> void:
	if not open:
		_restore_shop_buttons()
		return
	for panel in [rank_odds_panel, base_hp_panel, watchlist_panel]:
		if panel != modal:
			panel.visible = false


## Restore the shop button row after a modal closes or a setting changes.
## `watchlist_override` applies a live Shop Highlights value before the loader
## has persisted it; null reads the stored setting.
func _restore_shop_buttons(watchlist_override = null) -> void:
	if rank_odds_panel.is_popup_open() or base_hp_panel.is_popup_open():
		return
	rank_odds_panel.visible = _context.feature_enabled(ModConfig.KEY_RANK_ODDS_PREVIEW)
	base_hp_panel.visible = _context.feature_enabled(ModConfig.KEY_BASE_HP_CHART)
	if watchlist_override == null:
		watchlist_override = _context.feature_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS)
	watchlist_panel.visible = bool(watchlist_override)
	if is_instance_valid(replay_button):
		replay_button.set_available(_replay_available)
