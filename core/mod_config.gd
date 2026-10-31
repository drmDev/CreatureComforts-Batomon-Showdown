extends RefCounted
## Centralized user-facing feature toggles for Creature Comforts.
##
## Configuration lives here: setting keys, defaults, persistence lookups, and
## change notifications. Feature logic (mod_main.gd) and presentation (hud/)
## never read the Mod Loader directly; they ask this module.
##
## Values are persisted by the community Mod Loader in user://mod_settings.cfg
## (declared in mod.json). When the loader is absent (standalone run) the
## defaults below are used, so every feature stays enabled.

const MOD_ID := "creature_comforts"

const KEY_DAY_REMINDERS := "day_reminders"
const KEY_TRINKET_REMINDERS := "trinket_reminders"
const KEY_NOTIFICATION_SOUNDS := "notification_sounds"
const KEY_BATTLE_STATUS_PANEL := "battle_status_panel"
const KEY_TRINKETS_GAINED_PANEL := "trinkets_gained_panel"
const KEY_SHOP_INCOME := "shop_income"
const KEY_RANK_ODDS_PREVIEW := "rank_odds_preview"

## All features default to enabled to preserve existing behavior.
const DEFAULTS := {
	KEY_DAY_REMINDERS: true,
	KEY_TRINKET_REMINDERS: true,
	KEY_NOTIFICATION_SOUNDS: true,
	KEY_BATTLE_STATUS_PANEL: true,
	KEY_TRINKETS_GAINED_PANEL: true,
	KEY_SHOP_INCOME: true,
	KEY_RANK_ODDS_PREVIEW: true,
}

## Emitted when a known setting changes. Only our own keys are re-emitted.
signal changed(key: String, value: bool)

var _loader = null


## Bind to the Mod Loader (may be null when running standalone). Subscribes to
## config_changed exactly once, so repeated setup calls cannot duplicate signals.
func setup(loader) -> void:
	_loader = loader
	if _loader == null:
		return
	if not _loader.has_signal("config_changed"):
		return
	if not _loader.config_changed.is_connected(_on_loader_config_changed):
		_loader.config_changed.connect(_on_loader_config_changed)


## True when the feature is enabled. Unknown keys fall back to enabled.
func is_enabled(key: String) -> bool:
	if not DEFAULTS.has(key):
		return true
	if _loader != null and _loader.has_method("get_config"):
		var value = _loader.get_config(MOD_ID, key, DEFAULTS[key])
		if value is bool:
			return value
	return DEFAULTS[key]


func _on_loader_config_changed(mod_id: String, key: String, value) -> void:
	if mod_id != MOD_ID:
		return
	if not DEFAULTS.has(key):
		return
	if not (value is bool):
		return
	changed.emit(key, value)
