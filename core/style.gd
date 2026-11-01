extends RefCounted
## Shared color palette and small styling helpers for Creature Comforts HUD
## panels.
##
## Single source of truth for the colors used across the HUD so panels stay
## visually consistent and values are not duplicated.

# Panel palette
const BG_COLOR := Color("#1a2332")       # Dark navy panel background
const BORDER_COLOR := Color("#f39c12")   # Gold border / accent
const LABEL_COLOR := Color("#d4d8e0")    # Dimmer label text
const VALUE_COLOR := Color("#ecf0f1")    # Bright value text / glyphs
const SHADOW_COLOR := Color("#2c3e50")   # Text shadow
const HEADER_BG := Color("#2b3a52")      # Slightly lighter navy header bar
const DIM_COLOR := Color(0, 0, 0, 0.35)  # Modal backdrop
const HIGHLIGHT_COLOR := Color(0.95, 0.61, 0.07, 0.18)  # Current-row tint

# Rarity colors (match the shop rank-odds table)
const RARITY_COMMON := Color("#c8ccd4")
const RARITY_UNCOMMON := Color("#7ec850")
const RARITY_RARE := Color("#4a9ff5")
const RARITY_SUPER_RARE := Color("#b06ef0")
const RARITY_LEGENDARY := BORDER_COLOR
const RARITY_MYTHICAL := Color("#ff4fa3")

## Ordered rarity colors for the rank-odds table (Common..Legendary).
const RARITY_COLORS := [RARITY_COMMON, RARITY_UNCOMMON, RARITY_RARE, RARITY_SUPER_RARE, RARITY_LEGENDARY]

## Rarity colors keyed by display name (includes Mythical).
const RARITY_COLORS_BY_NAME := {
	"Common": RARITY_COMMON,
	"Uncommon": RARITY_UNCOMMON,
	"Rare": RARITY_RARE,
	"Super Rare": RARITY_SUPER_RARE,
	"Legendary": RARITY_LEGENDARY,
	"Mythical": RARITY_MYTHICAL,
}

# Type filter colors (watchlist), keyed by lowercased type name. Entries that
# reuse a rarity color are deliberate, to avoid duplicating hex values.
const TYPE_COLORS := {
	"bug": Color("#A4BC46"),       # yellow-green
	"curio": Color("#D9A5D9"),     # soft lavender-pink
	"dragon": RARITY_SUPER_RARE,   # light purple (reused)
	"electric": Color("#F1CF4B"),  # bright yellow
	"fighting": Color("#DF9680"),  # muted coral
	"fire": Color("#F28448"),      # warm orange
	"flying": Color("#A9D6E9"),    # pale sky blue
	"ghost": Color("#B59ADC"),     # lavender
	"grass": RARITY_UNCOMMON,      # leaf green (reused)
	"rock": Color("#C5AA87"),      # sandy beige
	"steel": Color("#ABC1CC"),     # cool gray-blue
	"toxic": Color("#CB91DC"),     # pink-purple
	"water": RARITY_RARE,          # light blue (reused)
}

# Action buttons (Snapshot Team) - muted red, so they read as actions rather than
# as filter toggles.
const ACTION_BG := Color("#87383B")
const ACTION_BG_HOVER := Color("#9A4044")
const ACTION_BORDER := Color("#CC6468")

# Save button (watchlist toolbar) - the same action treatment in muted green, so
# it reads as a sibling of Snapshot Team without competing with it.
const SAVE_BG := Color("#376B4B")
const SAVE_BG_HOVER := Color("#427B58")
const SAVE_BORDER := Color("#65A77A")
const SAVE_BG_DISABLED := Color("#2A4A38")


## Text colour for a type filter. Unknown types return TRANSPARENT so callers fall
## back to their neutral text colour.
static func type_color(type_name: String) -> Color:
	return TYPE_COLORS.get(type_name.to_lower(), Color.TRANSPARENT)


## Compact button styling for the small HUD scale: navy fill, gold 1px border,
## rounded corners. `color` overrides the text colour (filters pass their own).
static func compact_button(b: Button, color: Color = Color.TRANSPARENT) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_COLOR
	normal.border_color = BORDER_COLOR
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(1)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = BORDER_COLOR
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, normal)
	b.add_theme_stylebox_override("pressed", pressed)
	var text_color := color if color != Color.TRANSPARENT else VALUE_COLOR
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", BG_COLOR)
	b.add_theme_color_override("font_hover_pressed_color", BG_COLOR)
