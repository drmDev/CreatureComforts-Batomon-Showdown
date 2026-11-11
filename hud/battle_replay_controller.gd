extends Node
## Read-only battle replay overlay for the shop's Replay Last Battle button.
##
## The game's own Replay button lives inside the battle state and disappears
## when the player returns to the shop. This controller rebuilds the same visual
## replay from the captured TEMPLATE copies on a top CanvasLayer. It never calls
## the battle state's enter() path, so no rewards, lives, wins, gold, or saves
## are touched.
##
## The battle state is a game script, so this controller uses reflection only
## (load/set/get/call/has_method). That keeps the mod's standalone parse check
## green while still reusing the game's own replay visuals.

const NodeUtils = preload("../core/node_utils.gd")
const Style = preload("../core/style.gd")
const BattleBackground = preload("../core/battle_background.gd")

const BATTLE_SCENE := "res://game/states/battle_state.tscn"
const SHOP_SCRIPT := "res://game/states/shop_state.gd"

## Canvas layer plan (CanvasLayer.layer is limited to -128..128). The battle
## scene keeps its own internal layer order (background < units < HUD < end
## screen); every layer it owns is shifted up by BATTLE_BASE_LAYER so the whole
## stack sits above the black backdrop and the shop, never under it.
const BACKDROP_LAYER := 40
const BATTLE_BASE_LAYER := 60
## Battle-scene canvas layers below this value get shifted. Layers already at or
## above it are left alone (they are above the backdrop anyway).
const SHIFT_BELOW_LAYER := 50
const CLOSE_LAYER := 128
const LAYER_SCAN_INTERVAL := 5
const END_SCREEN_DELAY := 0.3
const SIM_WAIT_FRAMES := 60
## The battle scene can stop or replace the shop music as it closes (sometimes a
## few frames later), so the saved audio state is re-applied a few times.
const AUDIO_RESTORE_DELAYS := [0.1, 0.5, 1.2]
const MUSIC_MIN_SECONDS := 15.0
const SFX_PLAYER_PREFIX := "CreatureComfortsSound_"
const CLOSE_WIDTH := 96.0
const CLOSE_HEIGHT := 28.0
const CLOSE_MARGIN := 12.0
const CLOSE_TOP_RATIO := 0.10
const CLOSE_FONT_SIZE := 14

signal finished

var _context = null
var _active := false
var _payload: Dictionary = {}
var _state = null
var _layer: CanvasLayer = null
var _backdrop_layer: CanvasLayer = null
var _ui_layer: CanvasLayer = null
var _close_button = null
var _camera_before = null
var _canvas_before := Transform2D.IDENTITY
var _shop_view = null
var _shop_view_visible := true
var _mouse_mode_before := Input.MOUSE_MODE_VISIBLE
var _audio_snapshot: Array = []
var _bus_snapshot: Array = []
var _audio_token := 0
var _audio_fallbacks: Array = []
var _layer_scan_frames := 0


func setup(context) -> void:
	_context = context


func is_active() -> bool:
	return _active


## Start a replay from a payload produced by core/battle_replay_store.gd.
## Returns false when a replay is already running or the payload is incomplete.
func start(payload: Dictionary) -> bool:
	if _active:
		return false
	if payload.is_empty() or payload.get("p1") == null or payload.get("p2") == null:
		return false
	_active = true
	_payload = payload
	_begin()
	return true


func _begin() -> void:
	_snapshot_audio()
	_save_camera()
	_mouse_mode_before = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hide_shop_view()
	_build_layer()

	var scene = load(BATTLE_SCENE)
	if scene == null:
		_log("battle scene not found")
		_teardown()
		return
	_state = scene.instantiate()
	if _state == null:
		_log("battle scene instantiate failed")
		_teardown()
		return
	_state.name = "CreatureComfortsReplayBattle"
	_state.set("_replay_p1_data", _payload.get("p1"))
	_state.set("_replay_p2_data", _payload.get("p2"))
	_layer.add_child(_state)
	# The mod node runs with PROCESS_MODE_ALWAYS so its HUD works while paused.
	# The battle scene must still obey the game's pause, so opt it back in.
	_state.process_mode = Node.PROCESS_MODE_PAUSABLE
	_offset_battle_layers()

	await get_tree().process_frame
	if not _active or _state == null:
		return
	if not _state.has_method("_start_visual_battle"):
		_log("battle state has no _start_visual_battle")
		_teardown()
		return

	await _start_visual_replay()
	if not _active or _state == null:
		return
	_mount_background()
	_offset_battle_layers()
	_log("started")


## Mount the game's map scene behind the replay units. The view's own map
## arrays are preferred; the known map scenes are the fallback.
func _mount_background() -> void:
	if _state == null:
		return
	var view = _state.get("view")
	if view == null:
		return
	var scene = BattleBackground.scene_for(view)
	if scene == null:
		_log("background scene not found")
		return
	var map = scene.instantiate()
	if map == null:
		return
	map.name = "CreatureComfortsReplayMap"
	view.add_child(map)
	view.move_child(map, 0)
	_log("background mounted: %s" % str(scene.resource_path))


## Start (or restart) the game's visual replay from the injected templates. The
## simulation stays paused until the battle-ended signal is intercepted.
func _start_visual_replay() -> void:
	if _state == null:
		return
	if NodeUtils.has_property(_state, "_is_simulation_paused"):
		_state.set("_is_simulation_paused", true)
	var old_sim = _state.get("simulation")
	var old_id := 0
	if old_sim != null:
		old_id = old_sim.get_instance_id()
	_state.call("_start_visual_battle", true)
	await _wait_for_simulation(old_id)
	if not _active or _state == null:
		return
	await _settle_and_intercept()
	if not _active or _state == null:
		return
	if NodeUtils.has_property(_state, "_is_simulation_paused"):
		_state.set("_is_simulation_paused", false)
	_refresh_trinket_bags()


## Wait until the battle state has a simulation. `old_id` is the previous
## simulation's instance id when restarting a replay; -1 means any simulation.
func _wait_for_simulation(old_id := -1) -> void:
	var frames := 0
	while _state != null and frames < SIM_WAIT_FRAMES:
		var sim = _state.get("simulation")
		if sim != null and (old_id < 0 or sim.get_instance_id() != old_id):
			return
		await get_tree().process_frame
		frames += 1


## The simulation stays paused while the view finishes wiring its signals. A
## few frames of interception cover a late _on_battle_ended connection without
## letting the replay end before we own the signal.
func _settle_and_intercept() -> void:
	for i in range(3):
		_intercept_battle_end()
		await get_tree().process_frame
		if not _active or _state == null:
			return


## The battle state connects its own _on_battle_ended to the simulation. Replace
## that connection with ours so the replay never transitions the real game.
func _intercept_battle_end() -> void:
	if _state == null:
		return
	var sim = _state.get("simulation")
	if sim == null:
		return
	var data = sim.get("data")
	if data == null:
		return
	var sig = data.get("battle_ended")
	if not (sig is Signal):
		return
	for conn in sig.get_connections():
		var cb = conn.get("callable")
		if cb is Callable and str(cb.get_method()) == "_on_battle_ended":
			sig.disconnect(cb)
	if not sig.is_connected(_on_replay_battle_ended):
		sig.connect(_on_replay_battle_ended)


func _on_replay_battle_ended(winner_id: int, _a = null, _b = null, _c = null) -> void:
	if not _active or _state == null:
		return
	if NodeUtils.has_property(_state, "is_battle_active"):
		_state.set("is_battle_active", false)
	var effects = get_node_or_null("/root/EffectsManager")
	if effects != null and effects.has_method("cancel_pending_trinket_grants"):
		effects.call("cancel_pending_trinket_grants")

	await get_tree().create_timer(END_SCREEN_DELAY).timeout
	if not _active or _state == null:
		return
	var view = _state.get("view")
	if view == null or not view.has_method("play_battle_end_sequence"):
		_teardown()
		return

	var context := _build_end_context(winner_id)
	_log("battle ended (winner %d); showing the end screen" % winner_id)
	_offset_battle_layers()
	var wants_replay = await view.call("play_battle_end_sequence", context)
	if not _active or _state == null:
		return
	_log("end screen returned (replay again: %s)" % str(wants_replay))
	if bool(wants_replay):
		_log("replay again")
		await _start_visual_replay()
	else:
		_log("confirmed")
		_teardown()


## The end screen only needs the result context. The captured result is used
## when available; otherwise the replay's own winner id is the fallback.
func _build_end_context(winner_id: int) -> Dictionary:
	var context: Dictionary = _payload.get("context", {})
	if str(_payload.get("result", "")).is_empty():
		context = context.duplicate()
		context["is_victory"] = winner_id == 0
		context["lives_to_lose"] = int(_payload.get("loss_cost", 1)) if winner_id == 1 else 0
	return context


## The vanilla view fills the player's trinket bag from the live RunManager.
## Replace both bags with the captured battle's trinkets so the replay matches
## what was actually fought.
func _refresh_trinket_bags() -> void:
	if _state == null:
		return
	var view = _state.get("view")
	if view == null:
		return
	_refresh_bag(view, "player_trinket_bag_ui", _payload.get("p1"))
	_refresh_bag(view, "enemy_trinket_bag_ui", _payload.get("p2"))


func _refresh_bag(view, property: String, run) -> void:
	if run == null:
		return
	var bag = view.get(property)
	if bag == null or not bag.has_method("refresh"):
		return
	var ids = run.get("trinket_ids")
	var used = run.get("used_trinket_ids")
	var masks = run.get("mask_trainer_choices")
	if ids == null:
		ids = []
	if used == null:
		used = []
	if masks == null:
		masks = []
	bag.call("refresh", ids, used, masks)


func _build_layer() -> void:
	# The battle view frames its field with a Camera2D, so its layer must follow
	# the viewport. The backdrop and close button stay screen-aligned.
	_backdrop_layer = CanvasLayer.new()
	_backdrop_layer.name = "CreatureComforts_ReplayBackdrop"
	_backdrop_layer.layer = BACKDROP_LAYER
	add_child(_backdrop_layer)

	var backdrop := ColorRect.new()
	backdrop.name = "ReplayBackdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_layer.add_child(backdrop)

	var blocker := Control.new()
	blocker.name = "ReplayInputBlocker"
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_layer.add_child(blocker)

	# The battle's own world (units, and any background it draws) lives at the
	# base layer, exactly where the root canvas sat in the real battle.
	_layer = CanvasLayer.new()
	_layer.name = "CreatureComforts_Replay"
	_layer.layer = BATTLE_BASE_LAYER
	_layer.follow_viewport_enabled = true
	add_child(_layer)

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "CreatureComforts_ReplayUi"
	_ui_layer.layer = CLOSE_LAYER
	add_child(_ui_layer)

	# A labelled button: the bare X icon was not clear enough as the way out when
	# the game's own end-screen buttons are not showing.
	var close := Button.new()
	close.name = "ReplayCloseButton"
	close.text = "CLOSE"
	close.tooltip_text = "Close the replay and return to the shop (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(CLOSE_WIDTH, CLOSE_HEIGHT)
	close.add_theme_font_size_override("font_size", CLOSE_FONT_SIZE)
	Style.compact_button(close)
	close.pressed.connect(_teardown)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -CLOSE_WIDTH - CLOSE_MARGIN
	close.offset_right = -CLOSE_MARGIN
	_ui_layer.add_child(close)
	_close_button = close
	_position_close_button()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_position_close_button):
		viewport.size_changed.connect(_position_close_button)


## Keep the close button 10% of the viewport height down from the top, plus the
## usual 12 px margin, and re-apply it when the window is resized.
func _position_close_button() -> void:
	if _close_button == null or not is_instance_valid(_close_button):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var top := roundf(viewport.get_visible_rect().size.y * CLOSE_TOP_RATIO) + CLOSE_MARGIN
	_close_button.offset_top = top
	_close_button.offset_bottom = top + CLOSE_HEIGHT


func _save_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	_camera_before = viewport.get_camera_2d()
	_canvas_before = viewport.canvas_transform


func _restore_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if _camera_before != null and is_instance_valid(_camera_before) and _camera_before.is_inside_tree():
		_camera_before.make_current()
	else:
		viewport.canvas_transform = _canvas_before
	_camera_before = null


## Hide the shop view while the replay is up. The shop overlay gate already
## treats a hidden view as "not interactive", so the mod's shop HUD and
## reminders stay out of the replay.
func _hide_shop_view() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var main = tree.current_scene
	if main == null:
		return
	var state = main.get("current_state")
	if not NodeUtils.script_is(state, SHOP_SCRIPT):
		return
	var view = state.get("view") if NodeUtils.has_property(state, "view") else null
	if view is CanvasItem:
		_shop_view = view
		_shop_view_visible = view.visible
		view.visible = false


func _restore_shop_view() -> void:
	if _shop_view != null and is_instance_valid(_shop_view) and _shop_view is CanvasItem:
		_shop_view.visible = _shop_view_visible
	_shop_view = null


## Remember what the game was playing before the replay starts: every music-like
## AudioStreamPlayer that is playing, plus each bus's volume and mute state.
func _snapshot_audio() -> void:
	_audio_token += 1
	_audio_snapshot.clear()
	_bus_snapshot.clear()
	for fallback in _audio_fallbacks:
		if fallback != null and is_instance_valid(fallback):
			fallback.queue_free()
	_audio_fallbacks.clear()

	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for node in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		var player := node as AudioStreamPlayer
		if player == null or not player.playing:
			continue
		if str(player.name).begins_with(SFX_PLAYER_PREFIX):
			continue
		_audio_snapshot.append({
			"node": player,
			"position": player.get_playback_position(),
			"stream": player.stream,
			"volume_db": player.volume_db,
			"paused": player.stream_paused,
			"bus": player.bus,
		})
	for i in range(AudioServer.bus_count):
		_bus_snapshot.append({
			"volume_db": AudioServer.get_bus_volume_db(i),
			"mute": AudioServer.is_bus_mute(i),
		})


## Re-apply the saved audio state now and again shortly after, in case the
## battle scene's own shutdown stops or replaces the music a few frames later.
func _restore_audio_over_time() -> void:
	_audio_token += 1
	var token := _audio_token
	_restore_audio()
	if not is_inside_tree():
		return
	for delay in AUDIO_RESTORE_DELAYS:
		await get_tree().create_timer(float(delay), true, false, true).timeout
		if token != _audio_token:
			return
		_restore_audio()


func _restore_audio() -> void:
	for i in range(mini(_bus_snapshot.size(), AudioServer.bus_count)):
		var bus: Dictionary = _bus_snapshot[i]
		AudioServer.set_bus_volume_db(i, float(bus["volume_db"]))
		AudioServer.set_bus_mute(i, bool(bus["mute"]))

	var restored: Array = []
	for entry in _audio_snapshot:
		var stream: AudioStream = entry["stream"]
		if stream == null:
			continue
		var player = entry["node"]
		if player == null or not is_instance_valid(player):
			# The battle scene freed the player that held the shop music.
			player = _make_fallback_player(entry)
			entry["node"] = player
			if player == null:
				continue
		if player.stream != stream:
			player.stream = stream
		player.volume_db = float(entry["volume_db"])
		player.stream_paused = bool(entry["paused"])
		if not player.playing:
			player.play(float(entry["position"]))
		restored.append(player)

	# Music the replay started on another player (the battle track) must not keep
	# playing on top of the restored shop music.
	if _audio_snapshot.is_empty():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for node in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		var other := node as AudioStreamPlayer
		if other == null or not other.playing or restored.has(other):
			continue
		if str(other.name).begins_with(SFX_PLAYER_PREFIX):
			continue
		var other_stream: AudioStream = other.stream
		if other_stream != null and other_stream.get_length() > MUSIC_MIN_SECONDS:
			other.stop()


func _make_fallback_player(entry: Dictionary):
	var stream: AudioStream = entry["stream"]
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.name = "CreatureComfortsMusicRestore"
	player.bus = str(entry["bus"])
	add_child(player)
	_audio_fallbacks.append(player)
	return player


func _teardown() -> void:
	if not _active and _state == null and _layer == null:
		return
	_active = false
	if _state != null and is_instance_valid(_state):
		if _state.get_parent() != null:
			_state.get_parent().remove_child(_state)
		_state.queue_free()
	_state = null
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	if _backdrop_layer != null and is_instance_valid(_backdrop_layer):
		_backdrop_layer.queue_free()
	_backdrop_layer = null
	if _ui_layer != null and is_instance_valid(_ui_layer):
		_ui_layer.queue_free()
	_ui_layer = null
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_position_close_button):
		viewport.size_changed.disconnect(_position_close_button)
	_close_button = null
	Input.set_mouse_mode(_mouse_mode_before)
	Engine.time_scale = 1.0
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	_restore_camera()
	_restore_shop_view()
	_restore_audio_over_time()
	_payload = {}
	_log("stopped")
	finished.emit()


func _log(message: String) -> void:
	if _context != null and _context.logger != null:
		_context.logger.log_event("REPLAY | " + message)


## Shift every canvas layer the battle scene owns above the backdrop while
## keeping their order relative to each other. The scene keeps its HUD and end
## screen on small layers of its own, so without this they sit under the black
## backdrop and its input blocker: invisible and unclickable.
func _offset_battle_layers() -> void:
	if _state == null or not is_instance_valid(_state):
		return
	for node in _state.find_children("*", "CanvasLayer", true, false):
		var battle_layer := node as CanvasLayer
		if battle_layer != null and battle_layer.layer < SHIFT_BELOW_LAYER:
			battle_layer.layer += BATTLE_BASE_LAYER


## The battle view can hide the OS cursor. Keep it visible so the close button
## and the end screen stay usable. Deferred so it runs after the battle view's
## own _process. The battle scene's layers are also re-checked every few frames,
## because the view may create or re-number canvas layers while it runs.
func _process(_delta: float) -> void:
	if not _active:
		return
	call_deferred("_ensure_cursor_visible")
	_layer_scan_frames += 1
	if _layer_scan_frames >= LAYER_SCAN_INTERVAL:
		_layer_scan_frames = 0
		_offset_battle_layers()


func _ensure_cursor_visible() -> void:
	if _active and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unhandled_input(event) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_teardown()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _active:
		_teardown()
