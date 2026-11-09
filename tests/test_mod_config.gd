extends "test_runner.gd"
## Unit tests for core/mod_config.gd (centralized feature-toggle configuration).

const ModConfig = preload("../core/mod_config.gd")


## Minimal stand-in for the Mod Loader: exposes get_config() and the
## config_changed signal the real loader provides.
class FakeLoader:
	extends RefCounted
	signal config_changed(mod_id: String, key: String, value)

	var values: Dictionary = {}

	func get_config(mod_id: String, key: String, fallback = null):
		return values.get(key, fallback)

	func set_config(mod_id: String, key: String, value) -> int:
		values[key] = value
		config_changed.emit(mod_id, key, value)
		return OK


const DEFAULT_OFF_KEYS := [
	ModConfig.KEY_POSITIONAL_TRINKETS,
]


func test_defaults_are_enabled_except_beta_features() -> void:
	var config = ModConfig.new()
	for key in ModConfig.DEFAULTS.keys():
		if DEFAULT_OFF_KEYS.has(key):
			assert_false(config.is_enabled(key), "default for %s" % key)
		else:
			assert_true(config.is_enabled(key), "default for %s" % key)


func test_positional_trinkets_defaults_to_disabled() -> void:
	var config = ModConfig.new()
	assert_eq(ModConfig.KEY_POSITIONAL_TRINKETS, "positional_trinkets")
	assert_false(config.is_enabled(ModConfig.KEY_POSITIONAL_TRINKETS))


func test_auto_update_defaults_to_enabled() -> void:
	var config = ModConfig.new()
	assert_eq(ModConfig.KEY_AUTO_UPDATE, "auto_update")
	assert_true(config.is_enabled(ModConfig.KEY_AUTO_UPDATE))


func test_base_hp_chart_defaults_to_enabled() -> void:
	var config = ModConfig.new()
	assert_eq(ModConfig.KEY_BASE_HP_CHART, "base_hp_chart")
	assert_true(config.is_enabled(ModConfig.KEY_BASE_HP_CHART))


func test_shop_highlights_key_is_stable_and_defaults_to_enabled() -> void:
	# The key is unchanged so existing saved values keep working. It now gates
	# the watchlist button/popup and the shop highlights together.
	var config = ModConfig.new()
	assert_eq(ModConfig.KEY_SHOP_HIGHLIGHTS, "shop_highlights")
	assert_true(config.is_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS))


func test_shop_highlights_override_disables_watchlist_and_highlights() -> void:
	var loader = FakeLoader.new()
	loader.values[ModConfig.KEY_SHOP_HIGHLIGHTS] = false
	var config = ModConfig.new()
	config.setup(loader)
	assert_false(config.is_enabled(ModConfig.KEY_SHOP_HIGHLIGHTS))


func test_unknown_key_defaults_to_enabled() -> void:
	var config = ModConfig.new()
	assert_true(config.is_enabled("not_a_real_setting"))


func test_loader_override_disables_feature() -> void:
	var loader = FakeLoader.new()
	loader.values[ModConfig.KEY_SHOP_INCOME] = false
	var config = ModConfig.new()
	config.setup(loader)
	assert_false(config.is_enabled(ModConfig.KEY_SHOP_INCOME))
	assert_true(config.is_enabled(ModConfig.KEY_RANK_ODDS_PREVIEW))


func test_loader_non_bool_falls_back_to_default() -> void:
	var loader = FakeLoader.new()
	loader.values[ModConfig.KEY_SHOP_INCOME] = "nope"
	var config = ModConfig.new()
	config.setup(loader)
	assert_true(config.is_enabled(ModConfig.KEY_SHOP_INCOME))


func test_changed_signal_reemits_known_keys_only() -> void:
	var loader = FakeLoader.new()
	var config = ModConfig.new()
	config.setup(loader)
	var received: Array = []
	config.changed.connect(func(key, value): received.append([key, value]))
	loader.config_changed.emit(ModConfig.MOD_ID, ModConfig.KEY_SHOP_INCOME, false)
	loader.config_changed.emit("other_mod", ModConfig.KEY_SHOP_INCOME, false)
	loader.config_changed.emit(ModConfig.MOD_ID, "unknown_key", false)
	assert_eq(received.size(), 1)
	assert_eq(received[0][0], ModConfig.KEY_SHOP_INCOME)
	assert_eq(received[0][1], false)


func test_setup_is_idempotent() -> void:
	var loader = FakeLoader.new()
	var config = ModConfig.new()
	config.setup(loader)
	config.setup(loader)
	var received: Array = []
	config.changed.connect(func(key, _value): received.append(key))
	loader.config_changed.emit(ModConfig.MOD_ID, ModConfig.KEY_SHOP_INCOME, false)
	assert_eq(received.size(), 1, "no duplicate subscriptions")


const TEST_STORE := "user://creature_comforts_test/settings.cfg"


func _remove_test_store() -> void:
	if FileAccess.file_exists(TEST_STORE):
		DirAccess.remove_absolute(TEST_STORE)


func test_mod_volume_defaults_to_full() -> void:
	var config = ModConfig.new()
	assert_eq(ModConfig.KEY_MOD_VOLUME, "mod_volume")
	assert_eq(config.mod_volume(), ModConfig.DEFAULT_MOD_VOLUME)
	assert_eq(ModConfig.DEFAULT_MOD_VOLUME, 100)


## The loader would draw a declared setting as a left/right stepper, so Mod
## Volume must stay out of the loader-facing toggle table (and mod.json).
func test_mod_volume_is_not_a_feature_toggle() -> void:
	assert_false(ModConfig.DEFAULTS.has(ModConfig.KEY_MOD_VOLUME))
	assert_true(ModConfig.NUMERIC_DEFAULTS.has(ModConfig.KEY_MOD_VOLUME))
	var config = ModConfig.new()
	assert_true(config.is_enabled(ModConfig.KEY_MOD_VOLUME))


func test_mod_volume_is_not_declared_in_mod_json() -> void:
	var path: String = str(get_script().resource_path).get_base_dir().path_join("../mod.json")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(manifest is Dictionary, "mod.json readable at %s" % path)
	if not (manifest is Dictionary):
		return
	var keys: Array = []
	for setting in manifest.get("settings", []):
		keys.append(str(setting.get("key", "")))
	assert_false(keys.has(ModConfig.KEY_MOD_VOLUME), "mod_volume must not be declared")
	# The loader appends custom rows after every declared setting, so the
	# Notification Sounds toggle must be last for the slider to sit under it.
	assert_eq(keys.back(), ModConfig.KEY_NOTIFICATION_SOUNDS, "notification_sounds is the last setting")


func test_set_number_clamps_emits_and_dedupes() -> void:
	var config = ModConfig.new()
	var received: Array = []
	config.changed.connect(func(key, value): received.append([key, value]))
	config.set_number(ModConfig.KEY_MOD_VOLUME, 40)
	assert_eq(config.mod_volume(), 40)
	assert_eq(received, [[ModConfig.KEY_MOD_VOLUME, 40]])
	config.set_number(ModConfig.KEY_MOD_VOLUME, 40)
	assert_eq(received.size(), 1, "same value is a no-op")
	config.set_number(ModConfig.KEY_MOD_VOLUME, 500)
	assert_eq(config.mod_volume(), ModConfig.MOD_VOLUME_MAX, "clamped to max")
	config.set_number(ModConfig.KEY_MOD_VOLUME, -20)
	assert_eq(config.mod_volume(), ModConfig.MOD_VOLUME_MIN, "clamped to min")
	assert_eq(received.size(), 3)


func test_set_number_ignores_unknown_key() -> void:
	var config = ModConfig.new()
	var received: Array = []
	config.changed.connect(func(key, value): received.append([key, value]))
	config.set_number("unknown_key", 50)
	assert_eq(config.get_number("unknown_key"), 0)
	assert_empty(received)


func test_loader_numeric_changes_are_ignored() -> void:
	# Numbers belong to the mod's own store; a stray loader signal for the key
	# must not change or announce anything.
	var loader = FakeLoader.new()
	var config = ModConfig.new()
	config.setup(loader)
	var received: Array = []
	config.changed.connect(func(key, value): received.append([key, value]))
	loader.config_changed.emit(ModConfig.MOD_ID, ModConfig.KEY_MOD_VOLUME, 35)
	assert_empty(received)
	assert_eq(config.mod_volume(), ModConfig.DEFAULT_MOD_VOLUME)


func test_store_round_trip() -> void:
	_remove_test_store()
	var writer = ModConfig.new()
	writer.use_store(TEST_STORE)
	writer.set_number(ModConfig.KEY_MOD_VOLUME, 65)
	assert_true(FileAccess.file_exists(TEST_STORE), "store written")
	var reader = ModConfig.new()
	reader.use_store(TEST_STORE)
	assert_eq(reader.mod_volume(), 65, "value survives a restart")
	_remove_test_store()


func test_store_values_are_clamped_and_bad_types_ignored() -> void:
	_remove_test_store()
	DirAccess.make_dir_recursive_absolute(TEST_STORE.get_base_dir())
	var file := ConfigFile.new()
	file.set_value(ModConfig.STORE_SECTION, ModConfig.KEY_MOD_VOLUME, 900)
	file.save(TEST_STORE)
	var config = ModConfig.new()
	config.use_store(TEST_STORE)
	assert_eq(config.mod_volume(), ModConfig.MOD_VOLUME_MAX, "stored value clamped")
	file.set_value(ModConfig.STORE_SECTION, ModConfig.KEY_MOD_VOLUME, "loud")
	file.save(TEST_STORE)
	config.use_store(TEST_STORE)
	assert_eq(config.mod_volume(), ModConfig.DEFAULT_MOD_VOLUME, "bad type falls back")
	_remove_test_store()


func test_missing_store_uses_default() -> void:
	_remove_test_store()
	var config = ModConfig.new()
	config.use_store(TEST_STORE)
	assert_eq(config.mod_volume(), ModConfig.DEFAULT_MOD_VOLUME)
	config.use_store("")
	assert_eq(config.mod_volume(), ModConfig.DEFAULT_MOD_VOLUME)
