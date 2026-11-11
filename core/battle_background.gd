extends RefCounted
## Resolves the game's battle map/background scene for the replay overlay.
##
## The battle view keeps its map scenes in early_map_scenes, mid_map_scenes and
## champ_map_scenes. The game's map scenes live under res://game/maps. This
## helper collects every available scene from the view and the known map
## scenes, then picks one at random. It returns a PackedScene or null; the
## caller instantiates it.

const NodeUtils = preload("node_utils.gd")

const MAP_SCENE_PROPS := ["early_map_scenes", "mid_map_scenes", "champ_map_scenes"]
const FALLBACK_MAP_SCENES := [
	"res://game/maps/meadow/meadow_map.tscn",
	"res://game/maps/caves/cave_map.tscn",
	"res://game/maps/snow_field/snow_field_map.tscn",
]


## A random available map scene, or null when none can be resolved.
static func scene_for(view) -> PackedScene:
	var candidates := _collect_candidates(view)
	if candidates.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## Every distinct scene the view exposes plus the known map scenes. The view's
## arrays are the game's own source; the fallback paths cover a view that has
## not populated them yet.
static func _collect_candidates(view) -> Array:
	var out: Array = []
	var seen := {}
	if view != null and is_instance_valid(view):
		for prop in MAP_SCENE_PROPS:
			if NodeUtils.has_property(view, prop):
				_append_scenes(out, seen, view.get(prop))
	for path in FALLBACK_MAP_SCENES:
		if not ResourceLoader.exists(path):
			continue
		var scene = load(path)
		if scene is PackedScene:
			_append_scene(out, seen, scene)
	return out


static func _append_scenes(out: Array, seen: Dictionary, value) -> void:
	if value is PackedScene:
		_append_scene(out, seen, value)
		return
	if value is Array:
		for item in value:
			if item is PackedScene:
				_append_scene(out, seen, item)
			elif item is String and ResourceLoader.exists(item):
				var scene = load(item)
				if scene is PackedScene:
					_append_scene(out, seen, scene)


static func _append_scene(out: Array, seen: Dictionary, scene: PackedScene) -> void:
	var key := str(scene.resource_path)
	if key.is_empty():
		key = str(scene.get_instance_id())
	if seen.has(key):
		return
	seen[key] = true
	out.append(scene)
