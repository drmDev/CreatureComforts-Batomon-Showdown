extends "shop_modal_panel.gd"
## Shop button that replays the last battle in a read-only overlay.
##
## Reuses the shared HUD box, icon loader, and viewport anchoring from
## shop_modal_panel.gd, but overrides the press hook so it acts instead of
## opening a modal.

signal pressed

const UiSound = preload("../core/ui_sound.gd")

const RIGHT_RATIO := 0.80
const TOP_RATIO := 0.05

const TOOLTIP_READY := "Replay last battle"
const TOOLTIP_EMPTY := "Replay last battle (fight a battle first)"
const DIMMED_ALPHA := 0.4

var _click = null
var _available := false


func _init() -> void:
	super()
	tooltip_text = TOOLTIP_EMPTY
	modulate = Color(1.0, 1.0, 1.0, DIMMED_ALPHA)


func _ready() -> void:
	super()
	_apply_tooltip_theme()


## Tooltips are drawn with the TooltipLabel theme type, which per-control theme
## overrides cannot reach, and the game's default size is far too large at this
## HUD scale. Half of the inherited size matches the watchlist panel's tooltips.
func _apply_tooltip_theme() -> void:
	var inherited := get_theme_font_size("font_size", "TooltipLabel")
	if inherited <= 0:
		inherited = ThemeDB.fallback_font_size
	var tooltip_theme := Theme.new()
	tooltip_theme.set_font_size("font_size", "TooltipLabel", maxi(6, roundi(inherited * 0.5)))
	if _text_font != null:
		tooltip_theme.set_font("font", "TooltipLabel", _text_font)
	theme = tooltip_theme


## The button is always shown in the shop so it can be found; it is dimmed and
## inert until a previous battle has been captured.
func set_available(available: bool) -> void:
	if _available == available:
		return
	_available = available
	tooltip_text = TOOLTIP_READY if available else TOOLTIP_EMPTY
	modulate = Color(1.0, 1.0, 1.0, 1.0 if available else DIMMED_ALPHA)
	queue_redraw()


## Wire the optional click sound. The callables are the same gates the rest of
## the mod's UI sounds use (Notification Sounds and Mod Volume).
func setup_sound(enabled: Callable, volume: Callable) -> void:
	_click = UiSound.new()
	_click.setup(self, "click.ogg", enabled, volume)


func show_button() -> void:
	_ensure_visible()


func _button_texture_path() -> String:
	return "../assets/icons/replay.png"


func _button_position(viewport_size: Vector2) -> Vector2:
	var half := _button_size() * 0.5
	return Vector2(
		roundf(viewport_size.x * RIGHT_RATIO - half),
		roundf(viewport_size.y * TOP_RATIO - half))


func _log_label() -> String:
	return "REPLAY"


func _on_button_pressed() -> void:
	if not _available:
		return
	if _click != null:
		_click.play()
	_emit_log("button pressed")
	pressed.emit()
