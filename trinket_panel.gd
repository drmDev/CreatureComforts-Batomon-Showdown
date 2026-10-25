extends PanelContainer
## TrinketPanel - Collapsible panel displaying owned trinkets in shop
## Positioned below ReminderLabel, shows trinket counts sorted by quantity

signal minimized_changed(minimized: bool)

const HEADER_HEIGHT := 15.0
const BUTTON_SIZE := 11.0
const LINE_HEIGHT := 10.0
const FONT_SIZE := 9
const ANIM_SEC := 0.14
const DRAG_THRESHOLD := 3.0

const BG_COLOR := Color("#1a2332")  # Dark navy
const HEADER_COLOR := Color("#2c3e50")  # Darker blue-grey
const BORDER_COLOR := Color("#3498db")  # Blue
const TEXT_COLOR := Color("#ecf0f1")  # Light grey
const SHADOW_COLOR := Color("#2c3e50")
const INK_COLOR := Color("#ecf0f1")

const TOP_MARGIN := 18.0  # Below reminder label
const LEFT_MARGIN := 55.0  # Aligned with reminder label
const PANEL_WIDTH := 150.0
const MAX_VISIBLE_LINES := 10  # Maximum trinkets to show before scrolling

var minimized := false
var reveal := 1.0  # 1 = expanded, 0 = minimized (animated)
var _trinket_entries: Array = []  # Array of {name: String, count: int}
var _panel_style: StyleBoxFlat
var _header_style: StyleBoxFlat

var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _drag_off := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	
	# Create panel background style
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(2)
	_panel_style.set_content_margin_all(2)
	add_theme_stylebox_override("panel", _panel_style)
	
	# Create header style
	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = HEADER_COLOR
	_header_style.set_corner_radius_all(2)
	
	# Position below reminder label
	position = Vector2(LEFT_MARGIN, TOP_MARGIN)
	custom_minimum_size = Vector2(PANEL_WIDTH, HEADER_HEIGHT + 1)
	
	_apply_size()


func set_trinkets(trinket_ids: Array) -> void:
	"""Update trinket display from array of trinket ID strings."""
	# Count occurrences of each trinket
	var trinket_counts: Dictionary = {}
	for trinket_id in trinket_ids:
		var id_str := str(trinket_id)
		if trinket_counts.has(id_str):
			trinket_counts[id_str] += 1
		else:
			trinket_counts[id_str] = 1
	
	# Convert to array of entries with translated names
	_trinket_entries.clear()
	for trinket_id in trinket_counts.keys():
		var display_name := _translate_trinket_name(trinket_id)
		_trinket_entries.append({
			"name": display_name,
			"count": trinket_counts[trinket_id]
		})
	
	# Sort by count (descending), then alphabetically
	_trinket_entries.sort_custom(func(a, b):
		if a.count != b.count:
			return a.count > b.count
		return a.name < b.name
	)
	
	# Show/hide panel based on trinket count
	if _trinket_entries.is_empty():
		visible = false
	else:
		visible = true
		_apply_size()
		queue_redraw()


func _translate_trinket_name(trinket_id: String) -> String:
	"""Translate trinket ID to display name, fallback to ID if translation unavailable."""
	# Try translation key pattern: "item.name.{trinket_id}"
	var translation_key := "item.name.%s" % trinket_id
	
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(translation_key)
		if translated != translation_key:
			return translated
	
	# Fallback: capitalize the ID
	return trinket_id.capitalize()


func full_height() -> float:
	"""Calculate full expanded height based on trinket count."""
	if _trinket_entries.is_empty():
		return HEADER_HEIGHT + 1
	
	var line_count := mini(_trinket_entries.size(), MAX_VISIBLE_LINES)
	return HEADER_HEIGHT + 4 + (line_count * LINE_HEIGHT) + 4


func _apply_size() -> void:
	var target_height := lerpf(HEADER_HEIGHT + 1, full_height(), reveal)
	custom_minimum_size = Vector2(PANEL_WIDTH, target_height)
	size = Vector2(PANEL_WIDTH, target_height)


func set_minimized(on: bool, animate := true) -> void:
	if on == minimized and (_tween == null or not _tween.is_running()):
		return
	minimized = on
	if _tween != null:
		_tween.kill()
	var target := 0.0 if on else 1.0
	if not animate or not is_inside_tree():
		reveal = target
		_apply_size()
		queue_redraw()
	else:
		_tween = create_tween().set_ignore_time_scale(true)
		_tween.tween_method(func(v: float):
			reveal = v
			_apply_size()
			queue_redraw(), reveal, target, ANIM_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	minimized_changed.emit(on)


func toggle() -> void:
	set_minimized(not minimized)


func _button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 8 - BUTTON_SIZE - 2, 2), Vector2(BUTTON_SIZE, BUTTON_SIZE))


func _draw() -> void:
	var ci := get_canvas_item()
	var w := size.x
	
	# Draw header background
	_header_style.draw(ci, Rect2(Vector2(2, 2), Vector2(w - 4, HEADER_HEIGHT)))
	
	# Draw header text
	var total_count := 0
	for entry in _trinket_entries:
		total_count += entry.count
	
	var header_text := "Trinkets (%d)" % total_count
	var font := get_theme_default_font()
	var font_size := FONT_SIZE
	
	# Draw header text with shadow
	var text_pos := Vector2(10, 11)
	draw_string(font, text_pos + Vector2(1, 1), header_text, HORIZONTAL_ALIGNMENT_LEFT, w - 30, font_size, SHADOW_COLOR)
	draw_string(font, text_pos, header_text, HORIZONTAL_ALIGNMENT_LEFT, w - 30, font_size, TEXT_COLOR)
	
	# Draw toggle button
	var btn := _button_rect()
	draw_rect(btn, HEADER_COLOR)
	draw_rect(Rect2(btn.position, Vector2(btn.size.x, 1)), BORDER_COLOR)
	draw_rect(Rect2(btn.position, Vector2(1, btn.size.y)), BORDER_COLOR)
	draw_rect(Rect2(btn.position + Vector2(btn.size.x - 1, 0), Vector2(1, btn.size.y)), BORDER_COLOR)
	draw_rect(Rect2(btn.position + Vector2(0, btn.size.y - 1), Vector2(btn.size.x, 1)), BORDER_COLOR)
	
	# Draw +/- symbol
	var c := btn.get_center().floor()
	draw_rect(Rect2(c.x - 3, c.y, 6, 1), INK_COLOR)
	if minimized:
		draw_rect(Rect2(c.x, c.y - 3, 1, 7), INK_COLOR)
	
	# Draw body content if expanded
	if reveal > 0.01 and not _trinket_entries.is_empty():
		var y_offset := HEADER_HEIGHT + 6
		var visible_count := mini(_trinket_entries.size(), MAX_VISIBLE_LINES)
		
		for i in range(visible_count):
			var entry = _trinket_entries[i]
			var line_text := "[%d] %s" % [entry.count, entry.name]
			var line_pos := Vector2(6, y_offset + (i * LINE_HEIGHT))
			
			# Draw with shadow
			draw_string(font, line_pos + Vector2(1, 1), line_text, HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, SHADOW_COLOR)
			draw_string(font, line_pos, line_text, HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, TEXT_COLOR)
		
		# Draw "..." if more trinkets exist
		if _trinket_entries.size() > MAX_VISIBLE_LINES:
			var more_pos := Vector2(6, y_offset + (visible_count * LINE_HEIGHT))
			draw_string(font, more_pos + Vector2(1, 1), "...", HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, SHADOW_COLOR)
			draw_string(font, more_pos, "...", HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, TEXT_COLOR)


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEADER_HEIGHT + 1:
				return  # Body click, ignore
			_pressing = true
			_dragged = false
			_press_pos = event.position
			_drag_off = event.position
		elif _pressing:
			_pressing = false
			if _dragged:
				# Dragging complete, don't toggle
				pass
			else:
				toggle()
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		if not _dragged and event.position.distance_to(_press_pos) >= DRAG_THRESHOLD:
			_dragged = true
		if _dragged:
			position += event.position - _drag_off
		accept_event()
