extends RefCounted
## Clippy-inspired introduction for the Positional Trinkets Summary.
##
## Owns the independent pieces that are easy to reason about outside the UI:
## the exact introduction text, the once-per-run / 25% appearance decision,
## and the single-file persistence for whether the player has ever seen the
## introduction.
##
## The controller (hud/positional_trinkets_controller.gd) reads the seen flag
## once, rolls the 25% chance at most once per run when the threshold is first
## reached, and calls show_bubble() only when this module says the introduction
## should appear.

const INTRO_TEXT := "It looks like you're collecting a lot of trinkets. Would you like help making sense of them?"

## Chance the assistant appears on a subsequent qualifying run. The first ever
## qualifying run always shows, regardless of this value.
const CHANCE := 0.25

## The mod's own file for the seen flag, kept separate from Mod Volume so the
## assistant state never competes with the user-facing settings store.
const STORE_PATH := "user://creature_comforts/trinket_assistant.cfg"
const STORE_SECTION := "assistant"
const KEY_SEEN_INTRO := "seen_intro"


## True when the introduction should be shown for this query. The controller
## passes a roll value (normally randf()) so the decision stays deterministic
## and unit-testable.
static func should_show(seen_intro: bool, shown_this_run: bool, threshold_met: bool, roll: float) -> bool:
	if not threshold_met or shown_this_run:
		return false
	if not seen_intro:
		return true
	return roll < CHANCE


## Read the persisted "seen the introduction" flag. Missing or unreadable files
## return false, so the first qualifying run still guarantees the introduction.
static func load_seen(path: String = STORE_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	return bool(cfg.get_value(STORE_SECTION, KEY_SEEN_INTRO, false))


## Persist the "seen the introduction" flag. Failures only warn: the in-memory
## flag still prevents a duplicate introduction for the rest of the session.
static func save_seen(seen: bool, path: String = STORE_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(STORE_SECTION, KEY_SEEN_INTRO, seen)

	# Same directory pattern as the watchlist and saved-builds stores, so the
	# first save works even before the mod's user directory has been created.
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("Creature Comforts: cannot create trinket assistant directory %s: %s" % [abs_dir, error_string(dir_err)])
		return false

	var save_err := cfg.save(path)
	if save_err != OK:
		push_warning("Creature Comforts: cannot save trinket assistant state to %s: %s" % [path, error_string(save_err)])
		return false
	return true
