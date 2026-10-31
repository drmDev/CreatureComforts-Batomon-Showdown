extends RefCounted
## Shared color palette for Creature Comforts HUD panels.
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
