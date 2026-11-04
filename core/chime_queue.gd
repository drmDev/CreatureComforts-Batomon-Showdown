extends RefCounted
## Queued reminder sounds, played once the shop overlay is visible.
##
## Extracted from mod_main.gd. Day reminders and trinket reminders share one
## queue so a single Notification Sounds toggle mutes both.

const UiSound = preload("ui_sound.gd")

var _pika = null
var _poke = null
var _pending_day: Dictionary = {}
var _pending_trinket := false


## `host` is the Node the AudioStreamPlayers are added to; `sounds_enabled` is
## the Notification Sounds gate passed to every UiSound.
func setup(host: Node, sounds_enabled: Callable) -> void:
	_pika = UiSound.new()
	_pika.setup(host, "pika.ogg", sounds_enabled)
	_poke = UiSound.new()
	_poke.setup(host, "poke_item_found.ogg", sounds_enabled)


func queue_day(rule_id: String) -> void:
	_pending_day[rule_id] = true


func queue_trinket() -> void:
	_pending_trinket = true


func clear() -> void:
	_pending_day.clear()
	_pending_trinket = false


func clear_day() -> void:
	_pending_day.clear()


func clear_trinket() -> void:
	_pending_trinket = false


func has_pending() -> bool:
	return not _pending_day.is_empty() or _pending_trinket


## Play queued sounds when the gate allows it. `gate` may be null (always allowed).
func try_play(gate) -> void:
	if not has_pending():
		return
	if gate != null and not gate.is_allowed():
		return
	if not _pending_day.is_empty():
		if _pika != null:
			_pika.play()
		_pending_day.clear()
	if _pending_trinket:
		if _poke != null:
			_poke.play()
		_pending_trinket = false
