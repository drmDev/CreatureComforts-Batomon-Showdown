extends "test_runner.gd"
## Unit tests for the user-facing hotkey matcher (core/hotkeys.gd).

const Hotkeys = preload("../core/hotkeys.gd")


func _key(keycode: int, pressed = true, echo = false, ctrl = false, shift = false, alt = false, meta = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.echo = echo
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	event.meta_pressed = meta
	return event


func test_backtick_maps_to_fast_forward() -> void:
	assert_eq(Hotkeys.action_for_event(_key(Key.KEY_QUOTELEFT)), "fast_forward")


func test_tab_maps_to_backpack() -> void:
	assert_eq(Hotkeys.action_for_event(_key(Key.KEY_TAB)), "backpack")


func test_release_is_ignored() -> void:
	assert_eq(Hotkeys.action_for_event(_key(Key.KEY_QUOTELEFT, false)), "")


func test_echo_is_ignored() -> void:
	assert_eq(Hotkeys.action_for_event(_key(Key.KEY_TAB, true, true)), "")


func test_modifiers_are_ignored() -> void:
	assert_eq(Hotkeys.action_for_event(_key(Key.KEY_QUOTELEFT, true, false, true)), "")
	assert_eq(Hotkeys.action_for_event(_key(Key.KEY_TAB, true, false, false, true)), "")


func test_unrelated_key_is_ignored() -> void:
	assert_eq(Hotkeys.action_for_event(_key(Key.KEY_A)), "")


func test_non_key_event_is_ignored() -> void:
	assert_eq(Hotkeys.action_for_event(InputEventMouseButton.new()), "")
