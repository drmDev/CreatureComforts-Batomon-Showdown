extends RefCounted
## Reusable one-shot UI sound player.
##
## A single AudioStreamPlayer is attached to the host node and reused, so rapid
## clicks restart the same stream instead of allocating a player per press. The
## stream is loaded lazily on the first play, which keeps setup cheap and lets
## the host exist before it is added to the tree.
##
## Usage:
##   var click := UiSound.new()
##   click.setup(self, "/abs/path/to/click.ogg")
##   click.play()

const PLAYER_NAME := "CreatureComfortsUiSound"
const VOLUME_DB := -6.0

var _host: Node
var _path := ""
var _stream: AudioStream
var _player: AudioStreamPlayer
var _load_attempted := false


func setup(host: Node, path: String) -> void:
	_host = host
	_path = path


func play() -> void:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_player = _host.get_node_or_null(PLAYER_NAME)
		if not (_player is AudioStreamPlayer):
			_player = AudioStreamPlayer.new()
			_player.name = PLAYER_NAME
			_player.volume_db = VOLUME_DB
			_host.add_child(_player)
	if _player.stream == null:
		_player.stream = _load_stream()
	if _player.stream == null:
		return
	_player.play()


func _load_stream() -> AudioStream:
	if _load_attempted:
		return _stream
	_load_attempted = true
	if _path.is_empty() or not FileAccess.file_exists(_path):
		push_warning("Creature Comforts: UI sound not found: %s" % _path)
		return null
	_stream = AudioStreamOggVorbis.load_from_file(_path)
	if _stream == null:
		push_warning("Creature Comforts: cannot load UI sound: %s" % _path)
	return _stream
