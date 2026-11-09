extends RefCounted
## Opponent name and MMR helpers for the battle HUD.
##
## `_replay_p2_data` carries the opponent's display name and trainer id. MMR is
## only on the RunData the game passes to `transition_requested`, so mod_main
## captures that and hands it here. Everything works with plain dictionaries or
## game objects, which keeps these helpers unit-testable.

const NodeUtils = preload("node_utils.gd")

const MMR_UNKNOWN := "-"
const MMR_MATCH_WINDOW_MS := 600000


## Build the two facts the panel needs.
static func info(p2, captured, captured_at: int) -> Dictionary:
	var trainer := trainer_name(p2)
	var name := display_name(p2, trainer, _hide_usernames(), _user_logged_in())
	var mmr := mmr_value(captured if same_opponent(captured, p2, captured_at) else null)
	return {"name": name, "mmr": mmr}


## The name the game itself shows in the battle intro (respects "hide usernames").
static func display_name(p2, trainer: String, hide_usernames: bool, user_logged_in: bool) -> String:
	if hide_usernames or not user_logged_in:
		return trainer
	var n := _text(p2, "display_name")
	return n if n != "" else trainer


## The trainer id (e.g. "chef") of a run object or dictionary, or "".
static func trainer_id(run) -> String:
	return _text(run, "trainer_id")


## The opponent's trainer class from GameDatabase, or an empty string.
static func trainer_name(p2) -> String:
	var db = NodeUtils.get_autoload("GameDatabase")
	if db == null or not db.has_method("get_trainer_by_id"):
		return ""
	var trainer = db.get_trainer_by_id(_text(p2, "trainer_id"))
	return _text(trainer, "name")


## Numeric MMR text for the second line: "123", "123 (casual)", "Bot", or "-".
static func mmr_value(opp) -> String:
	if opp == null:
		return MMR_UNKNOWN
	var uid := _text(opp, "_matched_user_id")
	if uid.begins_with("bot_"):
		return "Bot"
	var raw = _field(opp, "_matched_opponent_mmr")
	if raw == null:
		return MMR_UNKNOWN
	var mmr := int(raw)
	if _field(opp, "_matched_mmr_is_ranked") == false:
		return "%d (casual)" % mmr
	return str(mmr)


## True when the captured transition RunData still belongs to this battle's opponent.
static func same_opponent(captured, p2, captured_at: int) -> bool:
	if captured == null or p2 == null:
		return false
	if captured is Object and not is_instance_valid(captured):
		return false
	if _text(captured, "display_name") != _text(p2, "display_name"):
		return false
	if _text(captured, "trainer_id") != _text(p2, "trainer_id"):
		return false
	return Time.get_ticks_msec() - captured_at < MMR_MATCH_WINDOW_MS


static func _hide_usernames() -> bool:
	var settings = NodeUtils.get_autoload("SettingsManager")
	if settings != null and settings.has_method("is_hide_usernames_enabled"):
		return bool(settings.is_hide_usernames_enabled())
	return false


static func _user_logged_in() -> bool:
	var user = NodeUtils.get_autoload("UserManager")
	if user == null or not NodeUtils.has_property(user, "data"):
		return false
	var data = user.get("data")
	return data != null and _text(data, "display_name") != ""


static func _text(obj, key: String) -> String:
	var value = _field(obj, key)
	return str(value) if value != null else ""


static func _field(obj, key: String):
	if obj == null:
		return null
	if obj is Dictionary:
		return obj.get(key)
	if obj is Object and is_instance_valid(obj) and key in obj:
		return obj.get(key)
	return null
