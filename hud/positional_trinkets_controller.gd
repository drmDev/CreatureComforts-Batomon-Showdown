extends RefCounted
## Feeds the trinket summary panel.
##
## Reads the held trinket ids from the run, builds the summed positional and
## economical summaries, and hands both to the panel. The panel itself preserves
## the player's collapsed/expanded choice and drag position across shop visits.

const NodeUtils = preload("../core/node_utils.gd")
const PositionalTrinkets = preload("../core/positional_trinkets.gd")
const EconomicalTrinkets = preload("../core/economical_trinkets.gd")
const ModConfig = preload("../core/mod_config.gd")

var _panel = null
var _context = null


func setup(panel, context) -> void:
	_panel = panel
	_context = context


## Refresh the panel from the player's held trinkets. Called on every shop poll;
## the panel ignores unchanged content.
func update(run) -> void:
	if _panel == null:
		return
	if not _context.feature_enabled(ModConfig.KEY_POSITIONAL_TRINKETS):
		_panel.hide_panel()
		return

	var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	if held == null:
		held = []
	var gold := int(run.get("gold")) if NodeUtils.has_property(run, "gold") else 0

	var positional := PositionalTrinkets.summarize(held)
	var economical := EconomicalTrinkets.summarize(held, gold)
	# Show the panel as soon as the player holds a trinket from either category.
	if not bool(positional.get("has_any", false)) and not bool(economical.get("has_any", false)):
		_panel.hide_panel()
		return
	_panel.show_summary({"positional": positional, "economical": economical})


func on_trainer_changed() -> void:
	if _panel != null:
		_panel.reset_collapsed()


func on_feature_toggled(key: String, value: bool) -> void:
	if value:
		return
	if key == ModConfig.KEY_POSITIONAL_TRINKETS:
		if _panel != null:
			_panel.hide_panel()
