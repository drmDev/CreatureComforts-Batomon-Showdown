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
## the loader. Mod Volume is the one numeric setting: the loader can only draw a
## declared setting as a left/right stepper, so it is deliberately NOT declared
## in mod.json. mod_main draws it as a slider and this module persists it in the
## mod's own file (STORE_PATH).

const FileStore = preload("file_store.gd")

const MOD_ID := "creature_comforts"
## The mod's own store for Mod Volume and the selected Trinkets tab; missing
## keys fall back to DEFAULT_MOD_VOLUME / DEFAULT_TRINKETS_TAB.
const STORE_PATH := "user://creature_comforts/settings.cfg"
const STORE_SECTION := "settings"

const KEY_DAY_REMINDERS := "day_reminders"
## One setting for the unified Trinkets panel (Alerts, Gained and Bonuses tabs).
## The three feature panels are always wired; this only shows or hides the
## shared panel, so no per-tab visibility setting exists.
const KEY_TRINKETS_PANEL := "trinkets_panel"
const KEY_NOTIFICATION_SOUNDS := "notification_sounds"
## Volume of every reminder/UI sound this mod plays, 0-100. 100 is the level the
## mod has always used (-6 dB), so existing users hear no change until they move
## the slider. Drawn as a slider under Notification Sounds, never as a stepper.
const KEY_MOD_VOLUME := "mod_volume"
const MOD_VOLUME_MIN := 0
const MOD_VOLUME_MAX := 100
const DEFAULT_MOD_VOLUME := 100
const KEY_BATTLE_STATUS_PANEL := "battle_status_panel"
## Gold sell-value badges on the fielded and bench slots of the shop's My Team
## grid. Shop-phase only; the shop controller drives the attach/hide lifecycle.
const KEY_SELL_VALUE_INDICATORS := "sell_value_indicators"
const KEY_RANK_ODDS_PREVIEW := "rank_odds_preview"
const KEY_BASE_HP_CHART := "base_hp_chart"
## Gates the watchlist button/popup and the matching-card shop highlights
## together: highlighting is only useful with the watchlist, so one setting
## controls both. The key keeps its original name so saved values carry over.
const KEY_SHOP_HIGHLIGHTS := "shop_highlights"
## Post-battle combat statistics panel (merged from BatoStats++). It is the only
## control for that panel: the team headings and summed comparison are part of it.
const KEY_COMBAT_STATS_PANEL := "combat_stats_panel"
## Backtick fast-forward and Tab trinket bag hotkeys.
const KEY_HOTKEYS := "hotkeys"
## Shop monster purchase hover reminders (next-purchase trinkets).
const KEY_PURCHASE_REMINDERS := "purchase_reminders"

## Every feature toggle defaults to enabled. The unified Trinkets panel replaced
## the old per-panel settings and defaults to on for everyone.
const DEFAULTS := {
	KEY_DAY_REMINDERS: true,
	KEY_TRINKETS_PANEL: true,
	KEY_NOTIFICATION_SOUNDS: true,
	KEY_BATTLE_STATUS_PANEL: true,
	KEY_SELL_VALUE_INDICATORS: true,
	KEY_RANK_ODDS_PREVIEW: true,
	KEY_BASE_HP_CHART: true,
	KEY_SHOP_HIGHLIGHTS: true,
	KEY_COMBAT_STATS_PANEL: true,
	KEY_HOTKEYS: true,
	KEY_PURCHASE_REMINDERS: true,
}

## Last selected tab of the unified Trinkets panel. Stored in the mod's own file
## (STORE_PATH) next to Mod Volume; Alerts is the default.
const STORE_KEY_TRINKETS_TAB := "trinkets_tab"
const DEFAULT_TRINKETS_TAB := "alerts"

## Emitted when a feature toggle changes (loader-driven). Mod Volume is read on
## demand by the sound players, so it is not announced here.
signal changed(key: String, value: bool)

var _loader = null
var _store_path := ""
var _mod_volume := DEFAULT_MOD_VOLUME
var _trinkets_tab := DEFAULT_TRINKETS_TAB


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


## Bind the mod's own file for Mod Volume and the Trinkets tab, and read both.
## Without this call (tests, standalone) they live in memory only and nothing
## touches the disk. A missing, unreadable, or malformed file leaves the
## defaults in place.
func use_store(path: String) -> void:
	_store_path = path
	_mod_volume = DEFAULT_MOD_VOLUME
	_trinkets_tab = DEFAULT_TRINKETS_TAB
	if path.is_empty():
		return
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	var value = file.get_value(STORE_SECTION, KEY_MOD_VOLUME, null)
	if value is int or value is float:
		_mod_volume = _clamp_volume(int(value))
	var tab = file.get_value(STORE_SECTION, STORE_KEY_TRINKETS_TAB, DEFAULT_TRINKETS_TAB)
	if tab is String and not str(tab).is_empty():
		_trinkets_tab = str(tab)


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


## Volume for every reminder/UI sound this mod plays, 0-100.
func mod_volume() -> int:
	return _mod_volume


## Store a new Mod Volume (clamped to 0-100). Setting the current value is a
## no-op, so the slider's release/focus-out/exit commits write the file once.
func set_mod_volume(value: int) -> void:
	var clamped := _clamp_volume(value)
	if clamped == _mod_volume:
		return
	_mod_volume = clamped
	_save_store()


## Last selected tab of the unified Trinkets panel (Alerts when never set).
func trinkets_tab() -> String:
	return _trinkets_tab


## Persist the selected Trinkets tab. Setting the current value is a no-op.
func set_trinkets_tab(tab: String) -> void:
	if tab.is_empty() or tab == _trinkets_tab:
		return
	_trinkets_tab = tab
	_save_store()


func _clamp_volume(value: int) -> int:
	return clampi(value, MOD_VOLUME_MIN, MOD_VOLUME_MAX)


## Write Mod Volume to the store, keeping any unrelated keys already in the file.
## Failures only warn: the in-memory value still applies this session.
func _save_store() -> void:
	if _store_path.is_empty():
		return
	var file := ConfigFile.new()
	file.load(_store_path)
	file.set_value(STORE_SECTION, KEY_MOD_VOLUME, _mod_volume)
	file.set_value(STORE_SECTION, STORE_KEY_TRINKETS_TAB, _trinkets_tab)
	var error := FileStore.save_config(_store_path, file)
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
