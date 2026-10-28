extends PanelContainer
## ReminderLabel - Compact single-line reminder display for top bar
## Positioned between Backpack icon and Heart/lives indicator.

const FONT_SIZE := 9
const TEXT_COLOR := Color("#ecf0f1")
const SHADOW_COLOR := Color("#2c3e50")
const SHADOW_OFFSET := Vector2(1, 1)
const MAX_WIDTH := 130.0
const TOP_BAR_Y := 2.0 
const LEFT_MARGIN := 55.0  # Just right of backpack icon

const BG_COLOR := Color("#1a2332")  # Dark navy
const BORDER_COLOR := Color("#f39c12")  # Gold/yellow
const BORDER_WIDTH := 1
const PADDING := 3

var _active_reminders: Dictionary = {}  # rule_id -> simplified text
var _label: Label
var _panel_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	
	# Create styled panel background
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(BORDER_WIDTH)
	_panel_style.set_corner_radius_all(2)
	_panel_style.set_content_margin_all(PADDING)
	add_theme_stylebox_override("panel", _panel_style)
	
	# Create label for text with multi-line support
	_label = Label.new()
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	_label.add_theme_constant_override("shadow_offset_x", int(SHADOW_OFFSET.x))
	_label.add_theme_constant_override("shadow_offset_y", int(SHADOW_OFFSET.y))
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.clip_text = false
	_label.custom_minimum_size = Vector2(MAX_WIDTH, 12)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_label)
	
	# Position in top-left area
	position = Vector2(LEFT_MARGIN, TOP_BAR_Y)


func set_reminders(reminders: Dictionary) -> void:
	"""Replace all reminders with the provided dictionary. Single update, single render."""
	_active_reminders = reminders.duplicate()
	_update_display()


func hide_all_reminders() -> void:
	"""Hide all reminders and make label invisible."""
	_active_reminders.clear()
	_update_display()


func _update_display() -> void:
	"""Update label visibility and text based on active reminders."""
	# Combine all active reminders into a single line.
	var reminder_texts: Array = []
	for reminder_text in _active_reminders.values():
		if not reminder_text.is_empty():
			reminder_texts.append(reminder_text)
	
	if reminder_texts.is_empty():
		visible = false
		_label.text = ""
	else:
		_label.text = " | ".join(reminder_texts)
		visible = true
