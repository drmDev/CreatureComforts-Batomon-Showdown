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


func test_defaults_are_all_enabled() -> void:
	var config = ModConfig.new()
	for key in ModConfig.DEFAULTS.keys():
		assert_true(config.is_enabled(key), "default for %s" % key)


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
