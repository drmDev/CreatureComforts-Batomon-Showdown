extends PanelContainer
## TrinketPanel - Collapsible scrollable panel displaying owned trinkets with summaries
## Positioned below ReminderLabel, shows trinket counts alphabetically with descriptions

signal minimized_changed(minimized: bool)

const HEADER_HEIGHT := 15.0
const BUTTON_SIZE := 11.0
const LINE_HEIGHT := 10.0
const FONT_SIZE := 9
const SUMMARY_FONT_SIZE := 8
const ANIM_SEC := 0.14
const DRAG_THRESHOLD := 3.0

const BG_COLOR := Color("#1a2332")  # Dark navy
const HEADER_COLOR := Color("#2c3e50")  # Darker blue-grey
const BORDER_COLOR := Color("#3498db")  # Blue
const TEXT_COLOR := Color("#ecf0f1")  # Light grey
const SUMMARY_COLOR := Color("#95a5a6")  # Dimmer grey for summaries
const SHADOW_COLOR := Color("#2c3e50")
const INK_COLOR := Color("#ecf0f1")

const GAP_BELOW_REMINDER := 4.0  # Small gap below reminder panel
const LEFT_MARGIN := 55.0  # Aligned with reminder label
const PANEL_WIDTH := 280.0
const MAX_BODY_HEIGHT := 200.0  # Maximum height for scrollable body

var minimized := false
var reveal := 1.0  # 1 = expanded, 0 = minimized (animated)
var _trinket_entries: Array = []  # Array of {id: String, name: String, count: int, summary: String}
var _panel_style: StyleBoxFlat
var _header_style: StyleBoxFlat
var _scroll_container: ScrollContainer
var _vbox_container: VBoxContainer
var _descriptions_catalog = null
var _last_scroll_position := 0.0

var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _drag_off := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	
	# Load trinket descriptions catalog
	var TrinketDescriptions = load("res://mods/NP_Brainrot/trinket_descriptions.gd")
	_descriptions_catalog = TrinketDescriptions.new()
	
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
	
	# Create scroll container for body content
	_scroll_container = ScrollContainer.new()
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll_container.position = Vector2(2, HEADER_HEIGHT + 3)
	_scroll_container.custom_minimum_size = Vector2(PANEL_WIDTH - 4, 0)
	add_child(_scroll_container)
	
	# Create VBoxContainer inside scroll container
	_vbox_container = VBoxContainer.new()
	_vbox_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox_container.add_theme_constant_override("separation", 2)
	_scroll_container.add_child(_vbox_container)
	
	# Position below reminder label with gap
	_update_position()
	custom_minimum_size = Vector2(PANEL_WIDTH, HEADER_HEIGHT + 1)
	
	_apply_size()


func _update_position() -> void:
	"""Calculate position below reminder label."""
	# Get reminder label to calculate its bottom edge
	var reminder_label = get_parent().get_node_or_null("ReminderLabel")
	if reminder_label != null and reminder_label.visible:
		var reminder_bottom: float = reminder_label.position.y + reminder_label.size.y
		position = Vector2(LEFT_MARGIN, reminder_bottom + GAP_BELOW_REMINDER)
	else:
		# Fallback: use reminder label's default top position + estimated height
		position = Vector2(LEFT_MARGIN, 2.0 + 18.0 + GAP_BELOW_REMINDER)


func set_trinkets(trinket_ids: Array) -> void:
	"""Update trinket display from array of trinket ID strings."""
	# Preserve scroll position before rebuild
	if _scroll_container != null:
		var vscroll := _scroll_container.get_v_scroll_bar()
		if vscroll != null:
			_last_scroll_position = vscroll.value
	
	# Count occurrences of each trinket
	var trinket_counts: Dictionary = {}
	for trinket_id in trinket_ids:
		var id_str := str(trinket_id)
		if trinket_counts.has(id_str):
			trinket_counts[id_str] += 1
		else:
			trinket_counts[id_str] = 1
	
	# Convert to array of entries with translated names and summaries
	_trinket_entries.clear()
	for trinket_id in trinket_counts.keys():
		var display_name := _translate_trinket_name(trinket_id)
		var summary := _get_trinket_summary(trinket_id)
		_trinket_entries.append({
			"id": trinket_id,
			"name": display_name,
			"count": trinket_counts[trinket_id],
			"summary": summary
		})
	
	# Sort alphabetically by name
	_trinket_entries.sort_custom(func(a, b):
		return a.name < b.name
	)
	
	# Rebuild UI
	_rebuild_trinket_list()
	
	# Show/hide panel based on trinket count
	if _trinket_entries.is_empty():
		visible = false
	else:
		_update_position()  # Recalculate position
		visible = true
		_apply_size()
		
		# Restore scroll position after rebuild
		if _scroll_container != null:
			await get_tree().process_frame  # Wait for layout
			var vscroll := _scroll_container.get_v_scroll_bar()
			if vscroll != null:
				vscroll.value = _last_scroll_position


func _rebuild_trinket_list() -> void:
	"""Rebuild the VBoxContainer with current trinket entries."""
	# Clear existing children
	for child in _vbox_container.get_children():
		child.queue_free()
	
	# Add entry for each trinket
	for entry in _trinket_entries:
		var entry_container := VBoxContainer.new()
		entry_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_container.add_theme_constant_override("separation", 1)
		
		# Name and count label
		var name_label := Label.new()
		name_label.text = "%s ×%d" % [entry.name, entry.count]
		name_label.add_theme_font_size_override("font_size", FONT_SIZE)
		name_label.add_theme_color_override("font_color", TEXT_COLOR)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = false
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_container.add_child(name_label)
		
		# Summary label (dimmer, wrapped)
		if not entry.summary.is_empty():
			var summary_label := Label.new()
			summary_label.text = entry.summary
			summary_label.add_theme_font_size_override("font_size", SUMMARY_FONT_SIZE)
			summary_label.add_theme_color_override("font_color", SUMMARY_COLOR)
			summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			summary_label.clip_text = false
			summary_label.custom_minimum_size = Vector2(PANEL_WIDTH - 16, 0)
			summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entry_container.add_child(summary_label)
		else:
			# Unknown trinket - show placeholder
			var unknown_label := Label.new()
			unknown_label.text = "Summary unavailable."
			unknown_label.add_theme_font_size_override("font_size", SUMMARY_FONT_SIZE)
			unknown_label.add_theme_color_override("font_color", SUMMARY_COLOR)
			unknown_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			unknown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entry_container.add_child(unknown_label)
		
		_vbox_container.add_child(entry_container)


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


func _get_trinket_summary(trinket_id: String) -> String:
	"""Get the summary description for a trinket ID."""
	if _descriptions_catalog != null:
		return _descriptions_catalog.get_description(trinket_id)
	return ""


func full_height() -> float:
	"""Calculate full expanded height based on content."""
	if _trinket_entries.is_empty():
		return HEADER_HEIGHT + 1
	
	# Calculate body height (capped at MAX_BODY_HEIGHT for scrolling)
	var content_height := _vbox_container.size.y if _vbox_container != null else 0.0
	var body_height := minf(content_height + 8, MAX_BODY_HEIGHT)
	
	return HEADER_HEIGHT + 4 + body_height


func _apply_size() -> void:
	var target_height := lerpf(HEADER_HEIGHT + 1, full_height(), reveal)
	custom_minimum_size = Vector2(PANEL_WIDTH, target_height)
	size = Vector2(PANEL_WIDTH, target_height)
	
	# Update scroll container size
	if _scroll_container != null:
		var body_height := target_height - HEADER_HEIGHT - 4
		_scroll_container.custom_minimum_size = Vector2(PANEL_WIDTH - 4, maxf(0, body_height))
		_scroll_container.size = Vector2(PANEL_WIDTH - 4, maxf(0, body_height))


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
	else:
		_tween = create_tween().set_ignore_time_scale(true)
		_tween.tween_method(func(v: float):
			reveal = v
			_apply_size(), reveal, target, ANIM_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEADER_HEIGHT + 1:
				return  # Body click, ignore (allow scrolling)
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
