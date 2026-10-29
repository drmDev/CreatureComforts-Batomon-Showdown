extends "comfort_panel.gd"
## TrinketRemindersPanel - Compact shop-phase reminder for unused one-shot trinkets.
##
## Collapsed it is a small top-left tab reading "Trinkets (N)", where N is the total number of
## relevant trinkets held. Clicking the tab (or its +/- button) expands a fixed-width (~320 px)
## panel; each trinket shows its name + quantity on the first line and its short description
## underneath. The expanded/collapsed choice persists across show/hide cycles and only resets
## to collapsed on a new run. The whole tab disappears when no relevant trinkets are held.
##
## Behaviour adapted from hud/trinket_panel.gd:
##   * Clicking the header (without dragging) toggles; clicking the +/- button toggles too.
##   * Dragging the header moves the tab/panel.
##   * The control clips to its animated rect and animates height/width ignoring Engine.time_scale.

const CONTENT_PADDING := 6.0
const NAME_LINE_H := 14.0     # First line: name + quantity
const DESC_LINE_H := 13.0     # Second line: short description
const ROW_GAP := 5.0
const NAME_FONT_SIZE := 10
const DESC_FONT_SIZE := 9
const TITLE_FONT_SIZE := 11
const EXPANDED_WIDTH := 320.0
const TAB_EXTRA_WIDTH := 42.0  # Title width + button + header insets for the collapsed tab

# Collapsible panel geometry (mirrors trinket_panel.gd)
const HEAD_H := 16.0
const BTN := 12.0
const ANIM_SEC := 0.14
const DRAG_THRESHOLD := 3.0

# Same top-left spot as hud/reminder_label.gd (LEFT_MARGIN, TOP_BAR_Y)
const LEFT_MARGIN := 55.0
const TOP_BAR_Y := 2.0

const HEADER_BG := Color("#2b3a52")      # Slightly lighter navy for the header bar
const INK_COLOR := Color("#ecf0f1")      # "-" / "+" glyph colour


var _entries: Array = []  # Array of Dictionary {"name": String, "count": int, "desc": String}
var _total_count := 0     # Sum of entry counts, shown in the tab title
var _content_key := ""    # Cheap change detection so repeated updates don't re-size needlessly
var _panel_style: StyleBoxFlat
var _header_style: StyleBoxFlat
var _button_style: StyleBoxFlat

# Collapsible state (persisted across show/hide; reset only per run)
var minimized := true
var reveal := 0.0  # 1 = expanded, 0 = collapsed (animated)

var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	position = Vector2(LEFT_MARGIN, TOP_BAR_Y)
	_setup_styles()
	_text_font = _build_panel_font()


func _setup_styles() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(3)
	_panel_style.set_content_margin_all(3)

	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = HEADER_BG
	_header_style.border_color = BORDER_COLOR
	_header_style.set_border_width_all(1)
	_header_style.set_corner_radius_all(3)
	_header_style.set_content_margin_all(3)

	_button_style = StyleBoxFlat.new()
	_button_style.bg_color = BORDER_COLOR
	_button_style.set_corner_radius_all(2)
	_button_style.set_content_margin_all(2)


## Height of the panel when fully expanded (two lines per entry).
func full_height() -> float:
	var rows := float(_entries.size())
	if rows <= 0.0:
		return HEAD_H + CONTENT_PADDING * 2.0
	return HEAD_H + CONTENT_PADDING + rows * (NAME_LINE_H + DESC_LINE_H + ROW_GAP) + CONTENT_PADDING


## Collapsed tab title (between the left edge and the +/- button).
func header_text() -> String:
	return "Trinkets (%d)" % _total_count


## Show the panel with the given entries.
## entries: Array of Dictionary {"name": String, "count": int, "desc": String}
##
## Does NOT reset the collapsed state: a player who collapses the panel keeps it collapsed
## across shop visits. Only the first show anchors/sizes it from the current state.
func show_reminders(entries: Array) -> void:
	var key := _make_content_key(entries)
	# Repeated polls with unchanged content (already visible) do nothing.
	if visible and key == _content_key:
		return
	_entries = entries
	_total_count = 0
	for entry in entries:
		_total_count += int(entry.get("count", 1))
	_content_key = key
	_apply_size()
	visible = true
	queue_redraw()


## Hide the panel immediately, keeping the collapsed state for the next appearance.
func hide_panel() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_entries.clear()
	_total_count = 0
	_content_key = ""
	visible = false
	queue_redraw()


## Reset the collapsed state to the collapsed default (new run).
func reset_for_run() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	minimized = true
	reveal = 0.0
	_entries.clear()
	_total_count = 0
	_content_key = ""
	visible = false
	_apply_size()
	queue_redraw()


## First line: "<name>[ xN]".
func _name_line(entry: Dictionary) -> String:
	var label := str(entry.get("name", ""))
	var count := int(entry.get("count", 1))
	if count > 1:
		label += " x%d" % count
	return label


## Stable, ordered text key used to detect whether the displayed rows changed.
func _make_content_key(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%dx %s | %s" % [int(entry.get("count", 1)), str(entry.get("name", "")), str(entry.get("desc", ""))])
	return "|".join(parts)


func _apply_size() -> void:
	# Width animates between the small tab and the fixed expanded width; height between
	# header-only and the two-line rows.
	var w := lerpf(_tab_width(), EXPANDED_WIDTH, reveal)
	size = Vector2(w, lerpf(HEAD_H + 1.0, full_height(), reveal))


## Collapsed tab width: fits the title plus the +/- button.
func _tab_width() -> float:
	if _text_font == null:
		return EXPANDED_WIDTH
	var title_w := _text_font.get_string_size(header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	return title_w + BTN + TAB_EXTRA_WIDTH


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
		# The game slows / stops Engine.time_scale (KO slow motion, pause), so animate
		# in real time like the reference implementation.
		# Position is intentionally NOT re-anchored: the top-left stays fixed and the panel
		# expands down/right.
		_tween = create_tween().set_ignore_time_scale(true)
		_tween.tween_method(func(v: float):
			reveal = v
			_apply_size()
			queue_redraw(), reveal, target, ANIM_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func toggle() -> void:
	set_minimized(not minimized)


func button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 8 - BTN - 3, 2.0), Vector2(BTN, BTN))


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	if _entries.is_empty() and reveal <= 0.01:
		return

	var ci := get_canvas_item()
	var w := size.x

	# Body + two-line rows (drawn only when expanded)
	if reveal > 0.01:
		_panel_style.draw(ci, Rect2(Vector2(0, 4), Vector2(w, maxf(size.y - 4, 8))))
		var cursor_y := HEAD_H + CONTENT_PADDING
		var row_w := w - CONTENT_PADDING * 2.0 - 2.0
		for entry in _entries:
			var name_baseline := cursor_y + NAME_LINE_H - 3.0
			var name_line := _fit_text(_text_font, _name_line(entry), NAME_FONT_SIZE, row_w)
			_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, name_baseline), name_line, VALUE_COLOR, NAME_FONT_SIZE)
			var desc_baseline := name_baseline + DESC_LINE_H
			var desc_line := _fit_text(_text_font, str(entry.get("desc", "")), DESC_FONT_SIZE, row_w)
			_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, desc_baseline), desc_line, LABEL_COLOR, DESC_FONT_SIZE)
			cursor_y += NAME_LINE_H + DESC_LINE_H + ROW_GAP

	# Header bar
	_header_style.draw(ci, Rect2(Vector2(7, 0), Vector2(w - 14, HEAD_H)))
	_draw_title(Rect2(Vector2(12, 0), Vector2(button_rect().position.x - 16, HEAD_H)))

	# -/+ button
	var b := button_rect()
	_button_style.draw(ci, b)
	var c := b.get_center().floor()
	draw_rect(Rect2(c.x - 3, c.y, 6, 1), INK_COLOR)
	if minimized:
		draw_rect(Rect2(c.x, c.y - 3, 1, 7), INK_COLOR)


## Header title, trimmed so it never runs under the button, centred vertically.
func _draw_title(r: Rect2) -> void:
	var t := _fit_text(_text_font, header_text(), TITLE_FONT_SIZE, r.size.x)
	var baseline := r.position.y + HEAD_H * 0.5 + 3.0
	_draw_text_shadow(Vector2(r.position.x, baseline), t, VALUE_COLOR, TITLE_FONT_SIZE)


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEAD_H + 1:
				return  # body: not ours to handle
			_pressing = true
			_dragged = false
			_press_pos = event.position
		elif _pressing:
			_pressing = false
			if not _dragged:
				toggle()
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		if not _dragged and event.position.distance_to(_press_pos) >= DRAG_THRESHOLD:
			_dragged = true
		if _dragged:
			# event.relative is the mouse delta in screen space; using it avoids the feedback
			# loop that made the panel jump/snap back as it moved under the cursor.
			position += event.relative
		accept_event()
