extends RefCounted
## Feeds the positional trinket summary panel.
##
## Reads the held trinket ids from the run, builds the summed positional
## summary, and hands it to the panel. The panel itself preserves the player's
## collapsed/expanded choice and drag position across shop visits.

const NodeUtils = preload("../core/node_utils.gd")
const PositionalTrinkets = preload("../core/positional_trinkets.gd")
const ModConfig = preload("../core/mod_config.gd")

var _panel = null
var _feature_enabled: Callable


func setup(panel, feature_enabled: Callable) -> void:
	_panel = panel
	_feature_enabled = feature_enabled


## Refresh the panel from the player's held trinkets. Called on every shop poll;
## the panel ignores unchanged content.
func update(run) -> void:
	if _panel == null:
		return
	if not _feature_enabled.call(ModConfig.KEY_POSITIONAL_TRINKETS):
		_panel.hide_panel()
		return

	var held = run.get("trinket_ids") if NodeUtils.has_property(run, "trinket_ids") else []
	if held == null:
		held = []
	_panel.show_summary(PositionalTrinkets.summarize(held))


func on_trainer_changed() -> void:
	if _panel != null:
		_panel.reset_collapsed()


func on_feature_toggled(key: String, value: bool) -> void:
	if value:
		return
	if key == ModConfig.KEY_POSITIONAL_TRINKETS:
		if _panel != null:
			_panel.hide_panel()
