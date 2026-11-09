extends "test_runner.gd"
## Unit tests for the shared sound player (core/ui_sound.gd).
##
## The test runner executes before the scene tree is live, so these tests avoid
## playback and check the setup/guard logic instead.

const UiSound = preload("../core/ui_sound.gd")


func test_play_on_detached_host_creates_no_player() -> void:
	var host := Node.new()
	var sound = UiSound.new()
	sound.setup(host, "click.ogg")
	sound.play()
	assert_eq(host.get_child_count(), 0)
	host.free()


## Regression: two sounds on one host used to share a single player, so the
## second one silently played the first one's stream.
func test_two_instances_use_distinct_player_names() -> void:
	var host := Node.new()
	var click = UiSound.new()
	click.setup(host, "click.ogg")
	var save = UiSound.new()
	save.setup(host, "save.ogg")
	assert_ne(click._player_name, save._player_name)
	host.free()


func test_enabled_gate_is_consulted() -> void:
	var host := Node.new()
	var called := [false]
	var sound = UiSound.new()
	sound.setup(host, "click.ogg", func():
		called[0] = true
		return false)
	sound.play()
	assert_true(called[0])
	assert_eq(host.get_child_count(), 0)
	host.free()


## 100% keeps the mod's historic -6 dB level, 50% halves it by ~6 dB, and 0%
## maps to the finite silent floor instead of linear_to_db(0)'s -inf.
func test_volume_db_curve() -> void:
	assert_true(absf(UiSound.volume_db_for(100.0) - UiSound.VOLUME_DB) < 0.001, "100% is the ceiling")
	var half := UiSound.volume_db_for(50.0)
	assert_true(absf(half - (UiSound.VOLUME_DB - 6.0206)) < 0.01, "50% is ~6 dB down")
	assert_true(UiSound.volume_db_for(0.0) <= -79.0, "0% is silent")
	assert_true(UiSound.volume_db_for(0.0) == UiSound.SILENT_DB)
	assert_true(UiSound.volume_db_for(250.0) == UiSound.VOLUME_DB, "clamped above 100")
	assert_true(UiSound.volume_db_for(-10.0) == UiSound.SILENT_DB, "clamped below 0")


## A provider is stored as-is; volume is only read when a sound actually plays.
func test_volume_provider_is_stored() -> void:
	var host := Node.new()
	var sound = UiSound.new()
	sound.setup(host, "click.ogg", Callable(), func(): return 40)
	assert_true(sound._volume.is_valid())
	sound.play()
	assert_eq(host.get_child_count(), 0, "detached host still creates no player")
	host.free()
