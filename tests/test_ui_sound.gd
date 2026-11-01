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
