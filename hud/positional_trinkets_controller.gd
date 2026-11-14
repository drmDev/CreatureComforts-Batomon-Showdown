extends RefCounted
## Feeds the positional trinket summary panel and its Clippy-style assistant.
##
## Reads the held trinket ids from the run, builds the summed positional
## summary, and hands it to the panel. The panel itself preserves the player's
## collapsed/expanded choice and drag position across shop visits. The assistant
## introduction is run-scoped, persisted across sessions, and only shown in the
## shop (this controller is only polled during the shop phase).

const NodeUtils = preload("../core/node_utils.gd")
const PositionalTrinkets = preload("../core/positional_trinkets.gd")
const ModConfig = preload("../core/mod_config.gd")
const RunData = preload("../core/run_data.gd")
const TrinketAssistant = preload("../core/trinket_assistant.gd")
const DevConfig = preload("../dev/dev_config.gd")

var _panel = null
var _context = null
var _assistant = null
var _seen_intro := false
var _run_id := ""
var _shown_this_run := false
var _rolled_this_run := false


func setup(panel, context, assistant = null) -> void:
	_panel = panel
	_context = context
	_assistant = assistant
	_seen_intro = TrinketAssistant.load_seen()
	if _assistant != null:
		_assistant.set_icon_pressed(_focus_summary)


## Refresh the panel from the player's held trinkets. Called on every shop poll;
## the panel ignores unchanged content.
func update(run) -> void:
	if _panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_POSITIONAL_TRINKETS):
		_panel.hide_panel()
		_hide_assistant()
		return

	var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	if held == null:
		held = []
	# The summary is a beta feature for late runs; keep it hidden until the
	# player holds enough trinkets for the positional breakdown to matter.
	if not PositionalTrinkets.meets_threshold(held):
		_panel.hide_panel()
		_hide_assistant()
		return

	_panel.show_summary(PositionalTrinkets.summarize(held))
	_update_assistant(run)


## A new run (or trainer) starts: collapse the summary and drop the assistant's
## visible introduction. The once-per-run flags stay intact until run_id changes
## in the next update, so a trainer swap inside one run cannot trigger a second
## introduction.
func on_trainer_changed() -> void:
	if _panel != null:
		_panel.reset_collapsed()
	if _assistant != null:
		_assistant.hide_bubble()


func on_feature_toggled(key: String, value: bool) -> void:
	if value:
		return
	if key == ModConfig.KEY_POSITIONAL_TRINKETS:
		if _panel != null:
			_panel.hide_panel()
		if _assistant != null:
			_assistant.hide_bubble()


func _hide_assistant() -> void:
	if _assistant != null:
		_assistant.hide_bubble()


## Decide whether the introduction should appear this run. The 25% roll is made
## once, the first time the threshold is reached in a run; a failed roll means no
## introduction for the rest of that run. The seen flag is written only on the
## guaranteed first introduction.
func _update_assistant(run) -> void:
	if _assistant == null:
		return

	if DevConfig.TRINKET_ASSISTANT_ALWAYS_SHOW:
		_assistant.show_bubble()
		return

	var run_id := RunData.identity(run)
	if run_id != _run_id:
		_run_id = run_id
		_shown_this_run = false
		_rolled_this_run = false

	if _shown_this_run or _rolled_this_run:
		return

	_rolled_this_run = true
	var roll := randf()
	if not TrinketAssistant.should_show(_seen_intro, _shown_this_run, true, roll):
		return

	_shown_this_run = true
	if not _seen_intro:
		_seen_intro = true
		TrinketAssistant.save_seen(true)
	_assistant.show_bubble()


func _focus_summary() -> void:
	if _panel == null:
		return
	_panel.visible = true
	_panel.set_minimized(false)
	_panel.queue_redraw()
