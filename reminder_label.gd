extends Label
## ReminderLabel - Compact single-line reminder display for top bar
## Positioned between Backpack icon and Heart/lives indicator.

const FONT_SIZE := 10
const TEXT_COLOR := Color("#ecf0f1")
const SHADOW_COLOR := Color("#2c3e50")
const SHADOW_OFFSET := Vector2(1, 1)
const MAX_WIDTH := 300.0
const TOP_BAR_Y := 8.0
const LEFT_MARGIN := 80.0  # Space after backpack icon

var _active_reminders: Dictionary = {}  # rule_id -> simplified text


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	
	# Configure label appearance
	add_theme_color_override("font_color", TEXT_COLOR)
	add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	add_theme_constant_override("shadow_offset_x", int(SHADOW_OFFSET.x))
	add_theme_constant_override("shadow_offset_y", int(SHADOW_OFFSET.y))
	add_theme_font_size_override("font_size", FONT_SIZE)
	
	# Single line, no wrapping
	autowrap_mode = TextServer.AUTOWRAP_OFF
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	# Position in top-left area
	position = Vector2(LEFT_MARGIN, TOP_BAR_Y)
	custom_minimum_size = Vector2(MAX_WIDTH, 20)


func show_reminder(rule_id: String, simplified_text: String) -> void:
	"""Display a reminder with simplified text."""
	_active_reminders[rule_id] = simplified_text
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
	"""Hide all reminders and make label invisible."""
	_active_reminders.clear()
	visible = false
	text = ""


func _update_display() -> void:
	"""Update label visibility and text based on active reminders."""
	if _active_reminders.is_empty():
		visible = false
		text = ""
	else:
		# Combine all active reminders into single line
		var reminder_texts: Array = []
		for reminder_text in _active_reminders.values():
			if not reminder_text.is_empty():
				reminder_texts.append(reminder_text)
		
		if reminder_texts.is_empty():
			visible = false
			text = ""
		else:
			text = " | ".join(reminder_texts)
			visible = true
