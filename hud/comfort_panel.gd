extends Control

const Style = preload("../core/style.gd")
const PanelIcons = preload("panel_icons.gd")

# Shared palette (single source: core/style.gd)
const BG_COLOR := Style.BG_COLOR
const BORDER_COLOR := Style.BORDER_COLOR
const LABEL_COLOR := Style.LABEL_COLOR
const VALUE_COLOR := Style.VALUE_COLOR
const SHADOW_COLOR := Style.SHADOW_COLOR

const FALLBACK_FONTS := [
	"res://assets/ui/fonts/NotoSansJP-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansKR-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansSC-ExtraBold.ttf",
]
const SYSTEM_FALLBACKS := ["Leelawadee UI", "Tahoma", "Segoe UI", "Noto Sans Thai", "Noto Sans", "Arial Unicode MS", "Droid Sans Fallback"]

var _text_font: Font


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


## Shared HUD box: navy fill, gold 1px border, rounded corners. Used by the
## rank-odds button, the income widget and the watchlist button so small
## clickable HUD elements look identical.
func _build_hud_box(radius := 3, border_width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BG_COLOR
	box.border_color = BORDER_COLOR
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box


## Draw a texture inside `rect` at its natural aspect ratio (contain), centred.
## Keeps a wide icon from being stretched into a square button.
func _draw_texture_fit(tex: Texture2D, rect: Rect2) -> void:
	PanelIcons.draw_fit(self, tex, rect)


## Load a mod-local PNG at runtime (loose mod assets are not imported by the game).
## The path is relative to the calling subclass script's directory.
func _load_texture(relative_path: String) -> Texture2D:
	var base_dir := str(get_script().resource_path).get_base_dir()
	var path := base_dir.path_join(relative_path)
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


## Load one of the shared panel icons (minimize, maximize, close) from
## assets/icons/. The path resolves from the calling script's directory.
func _load_icon(file_name: String) -> Texture2D:
	return PanelIcons.load_icon(str(get_script().resource_path), file_name)


## Vertical mirror of a texture, used to point an icon the other way without
## shipping a second asset (e.g. the sort arrow, the Second Chance heart).
func _flip_texture_vertically(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	img.flip_y()
	return ImageTexture.create_from_image(img)


func _connect_viewport_resize(handler: Callable) -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(handler):
		viewport.size_changed.connect(handler)


## Tooltips are drawn with the TooltipLabel theme type, which per-control theme
## overrides cannot reach, and the game's default size is far too large at this
## HUD scale. Half of the inherited size stays readable without covering the
## panel. Assigned to the panel so every tooltip in its subtree picks it up.
func _apply_tooltip_theme() -> void:
	theme = Style.tooltip_theme(_text_font, get_theme_font_size("font_size", "TooltipLabel"))


func _draw_text_shadow(pos: Vector2, text: String, color: Color, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_text_font, pos + Vector2(0.0, 1.0), text, align, width, font_size, SHADOW_COLOR)
	draw_string(_text_font, pos, text, align, width, font_size, color)


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
