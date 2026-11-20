extends Button
## Shop button that replays the last battle in a read-only overlay.
##
## Attached to the game's shop HudButtons bar (see comfort_ui.gd) instead of
## being drawn at a viewport fraction, so the game keeps owning layout,
## visibility, and input. The button is dimmed until a battle has been captured.

signal log_line(message: String)
## Emitted only when the button is available and actually pressed. The native
## Button.pressed signal fires on every click, so this custom signal gates the
## replay request behind the availability state.
signal replay_pressed

const Style = preload("../core/style.gd")
const PanelIcons = preload("panel_icons.gd")
const UiSound = preload("../core/ui_sound.gd")

const ICON_FILE := "replay.png"

const TOOLTIP_READY := "Replay last battle"
const TOOLTIP_EMPTY := "Replay last battle (fight a battle first)"
const DIMMED_ALPHA := 0.4

var _click = null
var _available := false


func _init() -> void:
	name = "CreatureComfortsReplayButton"
	tooltip_text = TOOLTIP_EMPTY
	modulate = Color(1.0, 1.0, 1.0, DIMMED_ALPHA)
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(24, 24)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	expand_icon = true
	# The replay glyph is a tight 46x51 crop of a 60x60 canvas. Pad it (see
	# _load_icon) so expand_icon keeps it centred with breathing room inside the
	# 24x24 button.
	icon = _load_icon()
	Style.compact_button(self)
	pressed.connect(_on_pressed)


## The button is always shown in the shop so it can be found; it is dimmed and
## inert until a previous battle has been captured.
func set_available(available: bool) -> void:
	if _available == available:
		return
	_available = available
	tooltip_text = TOOLTIP_READY if available else TOOLTIP_EMPTY
	modulate = Color(1.0, 1.0, 1.0, 1.0 if available else DIMMED_ALPHA)


## Wire the optional click sound. The callables are the same gates the rest of
## the mod's UI sounds use (Notification Sounds and Mod Volume).
func setup_sound(enabled: Callable, volume: Callable) -> void:
	_click = UiSound.new()
	_click.setup(self, "click.ogg", enabled, volume)


func _on_pressed() -> void:
	if not _available:
		return
	if _click != null:
		_click.play()
	log_line.emit("REPLAY | button pressed")
	replay_pressed.emit()


func _load_icon() -> Texture2D:
	return PanelIcons.padded_icon(str(get_script().resource_path), ICON_FILE, 6)
