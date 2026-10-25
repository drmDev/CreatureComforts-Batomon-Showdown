extends Control
## ReminderPanel - Displays contextual trainer reminders during shop phase
## Supports multiple simultaneous reminders with automatic show/hide management.

const PANEL_PADDING := 8.0
const LINE_HEIGHT := 16.0
const FONT_SIZE := 10
const PANEL_WIDTH := 170.0  # Reduced by ~23% from 220
const PANEL_MARGIN_RIGHT := 15.0
const PANEL_MARGIN_BOTTOM := 80.0  # Space above LOCK/UNLOCK button

const BACKGROUND_COLOR := Color("#2c3e50")
const BORDER_COLOR := Color("#e74c3c")
const TEXT_COLOR := Color("#ecf0f1")

var _active_reminders: Dictionary = {}  # rule_id -> text
var _panel_style: StyleBox
var _text_font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style = _create_panel_style()
	_text_font = _create_font()
	visible = false


func _ready() -> void:
	# Position at top-right of viewport
	_update_position()


func show_reminder(rule_id: String, text: String) -> void:
	"""Display a reminder with the given ID and text."""
	_active_reminders[rule_id] = text
	_update_display()


func hide_reminder(rule_id: String) -> void:
	"""Hide a specific reminder by ID."""
	_active_reminders.erase(rule_id)
	_update_display()


func hide_inactive_reminders(active_rule_ids: Array) -> void:
	"""Hide all reminders except those in the active list."""
	var to_remove: Array = []
	for rule_id in _active_reminders.keys():
		if rule_id not in active_rule_ids:
			to_remove.append(rule_id)
	
	for rule_id in to_remove:
		_active_reminders.erase(rule_id)
	
	_update_display()


func hide_all_reminders() -> void:
	"""Hide all reminders and make panel invisible."""
	_active_reminders.clear()
	visible = false


func _update_display() -> void:
	"""Update panel visibility and size based on active reminders."""
	if _active_reminders.is_empty():
		visible = false
	else:
		visible = true
		# Calculate required height based on text wrapping
		var total_lines := 0
		for text in _active_reminders.values():
			var wrapped_lines := _count_wrapped_lines(text)
			total_lines += wrapped_lines
		
		size = Vector2(PANEL_WIDTH, PANEL_PADDING * 2 + LINE_HEIGHT * total_lines)
		_update_position()
		queue_redraw()


func _count_wrapped_lines(text: String) -> int:
	"""Count how many lines the text will take when wrapped."""
	var text_width := _text_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var available_width := PANEL_WIDTH - PANEL_PADDING * 2
	
	if text_width <= available_width:
		return 1
	
	# Estimate wrapped lines (rough calculation)
	return ceili(text_width / available_width)


func _update_position() -> void:
	"""Position panel at lower-right, above LOCK/UNLOCK button."""
	var viewport_size := get_viewport_rect().size
	var x_pos := viewport_size.x - PANEL_WIDTH - PANEL_MARGIN_RIGHT
	var y_pos := viewport_size.y - size.y - PANEL_MARGIN_BOTTOM
	position = Vector2(x_pos, y_pos)


func _draw() -> void:
	"""Draw panel background and reminder text."""
	if _active_reminders.is_empty():
		return
	
	# Draw panel background
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	
	# Draw reminder text with wrapping
	var y_offset := PANEL_PADDING
	for text in _active_reminders.values():
		var available_width := PANEL_WIDTH - PANEL_PADDING * 2
		var pos := Vector2(PANEL_PADDING, y_offset + LINE_HEIGHT - 3)
		
		# Draw multiline string with wrapping
		draw_multiline_string(_text_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, available_width, FONT_SIZE, -1, TEXT_COLOR)
		
		# Advance y_offset by the number of wrapped lines
		var wrapped_lines := _count_wrapped_lines(text)
		y_offset += LINE_HEIGHT * wrapped_lines


static func _create_panel_style() -> StyleBoxFlat:
	"""Create styled panel background."""
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(PANEL_PADDING)
	return style


static func _create_font() -> Font:
	"""Create system font with fallbacks for emoji support."""
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial", "sans-serif"])
	return font
