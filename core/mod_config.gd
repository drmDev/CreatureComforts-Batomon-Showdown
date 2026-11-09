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
##
## Feature toggles are booleans (DEFAULTS) declared in mod.json and persisted by
## the loader. Sliders such as Mod Volume are integers (NUMERIC_DEFAULTS): the
## loader can only draw a declared setting as a left/right stepper, so these are
## deliberately NOT declared in mod.json. They are drawn by mod_main's custom
## settings row and persisted here, in the mod's own file (STORE_PATH).

const MOD_ID := "creature_comforts"
## The mod's own store for numeric settings; absent keys use NUMERIC_DEFAULTS.
const STORE_PATH := "user://creature_comforts/settings.cfg"
const STORE_SECTION := "settings"

const KEY_DAY_REMINDERS := "day_reminders"
const KEY_TRINKET_REMINDERS := "trinket_reminders"
const KEY_POSITIONAL_TRINKETS := "positional_trinkets"
const KEY_NOTIFICATION_SOUNDS := "notification_sounds"
## Volume of every reminder/UI sound this mod plays, 0-100. 100 is the level the
## mod has always used (-6 dB), so existing users hear no change until they move
## the slider. Drawn as a slider under Notification Sounds, never as a stepper.
const KEY_MOD_VOLUME := "mod_volume"
const MOD_VOLUME_MIN := 0
const MOD_VOLUME_MAX := 100
const DEFAULT_MOD_VOLUME := 100
const KEY_BATTLE_STATUS_PANEL := "battle_status_panel"
const KEY_TRINKETS_GAINED_PANEL := "trinkets_gained_panel"
const KEY_SHOP_INCOME := "shop_income"
const KEY_RANK_ODDS_PREVIEW := "rank_odds_preview"
const KEY_BASE_HP_CHART := "base_hp_chart"
## Gates the watchlist button/popup and the matching-card shop highlights
## together: highlighting is only useful with the watchlist, so one setting
## controls both. The key keeps its original name so saved values carry over.
const KEY_SHOP_HIGHLIGHTS := "shop_highlights"
## Post-battle combat statistics panel (merged from BatoStats++). It is the only
## control for that panel: the team headings and summed comparison are part of it.
const KEY_COMBAT_STATS_PANEL := "combat_stats_panel"
const KEY_AUTO_UPDATE := "auto_update"

## Most features default to enabled to preserve existing behavior. The beta
## positional trinket summary defaults to disabled.
const DEFAULTS := {
	KEY_DAY_REMINDERS: true,
	KEY_TRINKET_REMINDERS: true,
	KEY_POSITIONAL_TRINKETS: false,
	KEY_NOTIFICATION_SOUNDS: true,
	KEY_BATTLE_STATUS_PANEL: true,
	KEY_TRINKETS_GAINED_PANEL: true,
	KEY_SHOP_INCOME: true,
	KEY_RANK_ODDS_PREVIEW: true,
	KEY_BASE_HP_CHART: true,
	KEY_SHOP_HIGHLIGHTS: true,
	KEY_COMBAT_STATS_PANEL: true,
	KEY_AUTO_UPDATE: true,
}

## Numeric settings (rendered as sliders). Kept apart from DEFAULTS so
## is_enabled() only ever sees boolean toggles.
const NUMERIC_DEFAULTS := {
	KEY_MOD_VOLUME: DEFAULT_MOD_VOLUME,
}

## Inclusive (min, max) for each numeric setting.
const NUMERIC_RANGES := {
	KEY_MOD_VOLUME: Vector2i(MOD_VOLUME_MIN, MOD_VOLUME_MAX),
}

## Emitted when a known setting changes. Only our own keys are re-emitted; the
## value is a bool for toggles (from the loader) and an int for sliders (from
## set_number()).
signal changed(key: String, value)

var _loader = null
var _store_path := ""
var _numbers: Dictionary = {}


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


## Bind the mod's own file for numeric settings and read it. Without this call
## (tests, standalone) numbers live in memory only and nothing touches the disk.
## A missing, unreadable, or malformed file leaves the defaults in place.
func use_store(path: String) -> void:
	_store_path = path
	_numbers.clear()
	if path.is_empty():
		return
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for key in NUMERIC_DEFAULTS.keys():
		var value = file.get_value(STORE_SECTION, key, null)
		if value is int or value is float:
			_numbers[key] = _clamp_number(key, int(value))


## Disconnect from the Mod Loader. Called when the mod node leaves the tree so a
## freed mod is never called back through the loader's config_changed signal.
func teardown() -> void:
	if _loader != null and _loader.has_signal("config_changed"):
		if _loader.config_changed.is_connected(_on_loader_config_changed):
			_loader.config_changed.disconnect(_on_loader_config_changed)
	_loader = null


## True when the feature is enabled. Unknown keys fall back to enabled.
func is_enabled(key: String) -> bool:
	if not DEFAULTS.has(key):
		return true
	if _loader != null and _loader.has_method("get_config"):
		var value = _loader.get_config(MOD_ID, key, DEFAULTS[key])
		if value is bool:
			return value
	return DEFAULTS[key]


## The current value of a numeric setting, always inside its range. Unknown keys
## return 0; a key never set returns its default.
func get_number(key: String) -> int:
	if not NUMERIC_DEFAULTS.has(key):
		return 0
	return int(_numbers.get(key, _clamp_number(key, int(NUMERIC_DEFAULTS[key]))))


## Set a numeric setting: clamp it, remember it, write the store file (when one
## is bound), and emit changed(key, value). Setting the current value again is a
## no-op, so release/focus-out/exit commits never rewrite the file.
func set_number(key: String, value: int) -> void:
	if not NUMERIC_DEFAULTS.has(key):
		return
	var clamped := _clamp_number(key, value)
	if clamped == get_number(key):
		return
	_numbers[key] = clamped
	_save_store()
	changed.emit(key, clamped)


## Volume for every reminder/UI sound this mod plays, 0-100.
func mod_volume() -> int:
	return get_number(KEY_MOD_VOLUME)


func _clamp_number(key: String, value: int) -> int:
	var range: Vector2i = NUMERIC_RANGES.get(key, Vector2i(0, 100))
	return clampi(value, range.x, range.y)


## Write every numeric setting to the store, keeping any other keys already in
## the file. Failures only warn: the in-memory value still applies this session.
func _save_store() -> void:
	if _store_path.is_empty():
		return
	var file := ConfigFile.new()
	file.load(_store_path)
	for key in _numbers.keys():
		file.set_value(STORE_SECTION, key, _numbers[key])
	DirAccess.make_dir_recursive_absolute(_store_path.get_base_dir())
	var error := file.save(_store_path)
	if error != OK:
		push_warning("Creature Comforts: cannot save settings (%s): %s" % [_store_path, error_string(error)])


func _on_loader_config_changed(mod_id: String, key: String, value) -> void:
	if mod_id != MOD_ID:
		return
	if not DEFAULTS.has(key):
		return
	if not (value is bool):
		return
	changed.emit(key, value)
