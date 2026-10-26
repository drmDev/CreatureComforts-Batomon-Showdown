extends Control
## ShopHighlight - click-through overlay that outlines shop cards.
## Holds only plain values (slot index + offer instance id) and a resolver Callable.
## Every frame it asks the resolver for the current rectangles of cards whose live content
## still matches the recorded offer, so a stale highlight is never drawn on the wrong card.

const OUTLINE_COLOR := Color(1.0, 0.85, 0.2, 0.95)
const FILL_COLOR := Color(1.0, 0.85, 0.2, 0.12)
const OUTLINE_WIDTH := 2.0
const GROW_PX := 2.0

var _targets: Array = []  # Dictionaries {"slot": int, "id": int}
var _resolver: Callable = Callable()
var _rects: Array[Rect2] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## resolver(targets: Array) -> Array of Rect2 for targets whose live card still matches
func setup(resolver: Callable) -> void:
	_resolver = resolver


func set_targets(targets: Array) -> void:
	_targets = targets


func clear_targets() -> void:
	_targets = []
	if not _rects.is_empty():
		_rects.clear()
		queue_redraw()


func _process(_delta: float) -> void:
	if _targets.is_empty():
		if not _rects.is_empty():
			_rects.clear()
			queue_redraw()
		return
	if not _resolver.is_valid():
		return
	
	var resolved = _resolver.call(_targets)
	var next: Array[Rect2] = []
	if resolved is Array:
		for entry in resolved:
			if entry is Rect2:
				next.append(entry)
	
	if next != _rects:
		_rects = next
		queue_redraw()


func _draw() -> void:
	for rect in _rects:
		var outer: Rect2 = rect.grow(GROW_PX)
		draw_rect(outer, FILL_COLOR, true)
		draw_rect(outer, OUTLINE_COLOR, false, OUTLINE_WIDTH)
