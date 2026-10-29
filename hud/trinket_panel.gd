extends "comfort_panel.gd"
## TrinketPanel - Collapsible panel showing non-junk trinkets earned during a battle.
##
## Behaviour adapted from examples/MyBattleStats/disabled_collapsible_panel.gd:
##   * A header bar carries the title and a "-" / "+" button in its right corner.
##   * Clicking the header (without dragging) toggles minimized; clicking the button toggles too.
##   * Dragging the header moves the panel.
##   * Minimized = only the header bar; the control clips to its animated rect.
##   * Smooth height animation that ignores Engine.time_scale so it stays smooth during KO slow motion.
##
## Unlike the MyBattleStats panel (which needs its shared skin object), this panel draws with its
## own StyleBoxFlat + font (same NP_QoL drawing pattern as before), so it has no external skin
## dependency. It also keeps the earlier right/bottom auto-hide behaviour.
##
## Appears bottom-right when the battle state ends and the panel is shown, and auto-hides
## after a few seconds. It only shows when at least one non-junk trinket was earned; that
## filtering is done by mod_main before calling show_gains().

const PANEL_WIDTH := 185.0
const CONTENT_PADDING := 6.0
const ROW_HEIGHT := 16.0
const ROW_GAP := 2.0
const FONT_SIZE := 10
const TITLE_FONT_SIZE := 11

# Collapsible panel geometry (mirrors disabled_collapsible_panel.gd)
const HEAD_H := 16.0
const BTN := 12.0
const ANIM_SEC := 0.14
const DRAG_THRESHOLD := 3.0

# Display
const DISPLAY_DURATION_MS := 8000  # Auto-hide after 8 seconds on the results screen
const MARGIN_RIGHT := 10.0
const MARGIN_BOTTOM := 130.0       # Leaves room for a bottom-right toast from a companion mod

const HEADER_BG := Color("#2b3a52")      # Slightly lighter navy for the header bar
const INK_COLOR := Color("#ecf0f1")      # "-" / "+" glyph colour


var _entries: Array = []  # Array of Dictionary {"name": String, "count": int}
var _content_key := ""    # Cheap change detection so repeated show_gains() calls don't re-anchor
var _panel_style: StyleBoxFlat
var _header_style: StyleBoxFlat
var _button_style: StyleBoxFlat
var _hide_at_ms := 0

# Collapsible state
var minimized := false
var reveal := 1.0  # 1 = expanded, 0 = minimized (animated)

var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
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


## Height of the panel when fully expanded (depends on the number of entries).
func full_height() -> float:
	return HEAD_H + CONTENT_PADDING + ROW_HEIGHT * float(_entries.size()) \
		+ ROW_GAP * float(_entries.size()) + CONTENT_PADDING


## Header title (between the left edge and the -/+ button).
func header_text() -> String:
	return "Trinkets Gained"


## Show the panel with the given (already non-junk filtered) entries.
## entries: Array of Dictionary {"name": String, "count": int}
##
## Idempotent: only the FIRST call (hidden -> visible) anchors the panel. Later calls with the
## same content do nothing, which preserves any drag position and the minimize animation.
func show_gains(entries: Array) -> void:
	var key := _make_content_key(entries)
	var first_show := not visible
	_entries = entries
	if first_show:
		# Start each battle expanded and positioned above the bottom-right toast area.
		reveal = 1.0
		minimized = false
		_content_key = key
		_apply_size()
		_anchor_bottom_right()
	elif key != _content_key:
		_content_key = key
		_apply_size()
	_hide_at_ms = Time.get_ticks_msec() + DISPLAY_DURATION_MS
	visible = true
	queue_redraw()


## Hide the panel immediately.
func hide_panel() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_entries.clear()
	_content_key = ""
	reveal = 1.0
	minimized = false
	_hide_at_ms = 0
	visible = false
	queue_redraw()


## Stable, ordered text key used to detect whether the displayed rows changed.
func _make_content_key(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%dx %s" % [int(entry.get("count", 0)), str(entry.get("name", ""))])
	return "|".join(parts)


func _apply_size() -> void:
	# Keep the width we were set to (or a default) and animate height between header-only and full.
	var w := size.x
	if w <= 0.0:
		w = PANEL_WIDTH
	size = Vector2(w, lerpf(HEAD_H + 1.0, full_height(), reveal))


func _anchor_bottom_right() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	position = Vector2(viewport_size.x - size.x - MARGIN_RIGHT, viewport_size.y - size.y - MARGIN_BOTTOM)


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
		# NOTE: position is intentionally NOT re-anchored here. Keeping the top fixed makes the
		# panel expand downwards (the reference re-anchored the bottom, which expanded upwards).
		_tween = create_tween().set_ignore_time_scale(true)
		_tween.tween_method(func(v: float):
			reveal = v
			_apply_size()
			queue_redraw(), reveal, target, ANIM_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func toggle() -> void:
	set_minimized(not minimized)


func button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 8 - BTN - 3, 2.0), Vector2(BTN, BTN))


func _process(_delta: float) -> void:
	if visible and _hide_at_ms > 0 and Time.get_ticks_msec() >= _hide_at_ms:
		hide_panel()


func _draw() -> void:
	if _panel_style == null or _text_font == null:
		return
	if _entries.is_empty() and reveal <= 0.01:
		return

	var ci := get_canvas_item()
	var w := size.x

	# Body + rows (drawn only when expanded)
	if reveal > 0.01:
		_panel_style.draw(ci, Rect2(Vector2(0, 4), Vector2(w, maxf(size.y - 4, 8))))
		var cursor_y := HEAD_H + CONTENT_PADDING
		for entry in _entries:
			var baseline := cursor_y + ROW_HEIGHT - 2.0
			var line := "%dx %s" % [entry.count, entry.name]
			_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, baseline), line, LABEL_COLOR, FONT_SIZE)
			cursor_y += ROW_HEIGHT + ROW_GAP

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


## Trim `text` with an ellipsis so it fits `max_w` at `font_size` (Overrun-style, per character).
func _fit_text(font: Font, text: String, font_size: int, max_w: float) -> String:
	if max_w <= 0.0:
		return ""
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var dots := "..."
	var lo := 0
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var s := text.left(mid).strip_edges(false, true) + dots
		if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.left(lo).strip_edges(false, true) + dots if lo > 0 else dots


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
			# event.relative is the mouse delta in screen space; using it (instead of comparing
			# local event.position against a fixed press point) avoids the feedback loop that made
			# the panel jump/snap back as it moved under the cursor.
			position += event.relative
		accept_event()
