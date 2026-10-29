extends Control
## ComfortPanel - shared foundation for Creature Comforts HUD panels.
##
## Provides the common dark-navy/gold palette, the Consolas-with-fallbacks font,
## shadowed text drawing, and viewport-resize plumbing used by the drawing panels
## (player HUD, shop income, trinket panel). Subclasses keep their own layout,
## styles, and drawing; this only removes the duplicated boilerplate.

# Shared palette (matches reminder_label / player_hud / shop_income_panel / trinket_panel)
const BG_COLOR := Color("#1a2332")       # Dark navy
const BORDER_COLOR := Color("#f39c12")   # Gold
const LABEL_COLOR := Color("#d4d8e0")    # Dimmer label text
const VALUE_COLOR := Color("#ecf0f1")    # Bright value text
const SHADOW_COLOR := Color("#2c3e50")   # Dark shadow

const FALLBACK_FONTS := [
	"res://assets/ui/fonts/NotoSansJP-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansKR-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansSC-ExtraBold.ttf",
]
const SYSTEM_FALLBACKS := ["Leelawadee UI", "Tahoma", "Segoe UI", "Noto Sans Thai", "Noto Sans", "Arial Unicode MS", "Droid Sans Fallback"]

var _text_font: Font


## Build the shared Consolas font with the game's font fallbacks.
func _build_panel_font() -> Font:
	var fallbacks: Array[Font] = []
	for font_path in FALLBACK_FONTS:
		if ResourceLoader.exists(font_path):
			var font_resource = load(font_path)
			if font_resource is Font:
				fallbacks.append(font_resource)
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(SYSTEM_FALLBACKS)
	fallbacks.append(system_font)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas"])
	font.fallbacks = fallbacks
	return font


## Load a mod-local PNG at runtime (loose mod assets are not imported by the game).
## The path is relative to the calling subclass script's directory.
func _load_texture(relative_path: String) -> Texture2D:
	var base_dir := str(get_script().resource_path).get_base_dir()
	var path := base_dir.path_join(relative_path)
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


## Connect the viewport resize signal once (safe to call from _ready).
func _connect_viewport_resize(handler: Callable) -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(handler):
		viewport.size_changed.connect(handler)


## Draw text with a light shadow for readability (shared panel look).
func _draw_text_shadow(pos: Vector2, text: String, color: Color, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_text_font, pos + Vector2(0.0, 1.0), text, align, width, font_size, SHADOW_COLOR)
	draw_string(_text_font, pos, text, align, width, font_size, color)


## Trim `text` with an ellipsis so it fits `max_w` at `font_size` (per character).
func _fit_text(font: Font, text: String, font_size: int, max_w: float) -> String:
	if max_w <= 0.0:
		return ""
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var dots := "..."
	var lo := 0
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var s := text.left(mid).strip_edges(false, true) + dots
		if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.left(lo).strip_edges(false, true) + dots if lo > 0 else dots
