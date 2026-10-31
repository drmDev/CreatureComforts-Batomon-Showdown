## Dev-only toggles for Creature Comforts.
##
## These are NOT user-facing settings and are intentionally absent from mod.json.
## They are read once at startup as the initial `_debug_logging` / `_deep_inspection`
## values, then can be flipped live in-game with the key combos defined below.
##
## Edit the defaults here and restart the game to change startup behavior.

extends RefCounted

const DEBUG_LOGGING := false

## Discover and log additional properties of game objects (types, keywords, abilities).
## Off by default: deep inspection uses reflection (get_property_list) and is expensive.
## Toggle on at runtime with Ctrl+Shift+I only when you need it.
const DEEP_INSPECTION := false

const TOGGLE_DEBUG_KEY := Key.KEY_D
const TOGGLE_INSPECT_KEY := Key.KEY_I
