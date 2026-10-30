extends "collapsible_panel.gd"
## TrinketRemindersPanel - Compact shop-phase reminder for unused one-shot trinkets.
##
## Collapsed it is a small left-aligned tab ~10% down the screen showing the gem icon followed
## by "(N)", where N is the total number of relevant trinkets held. Clicking the tab (or its
## +/- button) expands a content-fitted panel (capped at 320 px); each trinket shows its name +
## quantity on the first line and its wrapped description underneath. The expanded/collapsed
## choice persists while reminders remain, and resets to collapsed when the list reaches zero or
## on a new run. The whole tab disappears when no relevant trinkets are held. When a new alerting
## trinket appears (first show, or after the list was cleared), the caller plays the notification
## sound; the panel stays collapsed until the player expands it.
##
## Collapsible header mechanics live in collapsible_panel.gd. This subclass supplies the
## left-aligned, 10%-down anchoring, the gem + "(N)" title, the wrapped rows, and the tab width.

const CONTENT_PADDING := 6.0
const NAME_LINE_H := 14.0     # First line: name + quantity
const DESC_LINE_H := 13.0     # Second line: short description
const ROW_GAP := 5.0
const NAME_FONT_SIZE := 8
const DESC_FONT_SIZE := 7
const MAX_EXPANDED_WIDTH := 320.0  # Cap for very long descriptions; the panel fits the content
const TAB_EXTRA_WIDTH := 30.0  # Button + header insets for the collapsed tab
const GEM_SIZE := 10.0
const GEM_GAP := 2.0
const DEBUG_SETTLE_SEC := 0.2  # Wait past the reveal tween before logging the settled layout

# Left-aligned with hud/reminder_label.gd but slightly lower
const LEFT_MARGIN := 55.0
const TOP_OFFSET_RATIO := 0.125
const FALLBACK_TOP_OFFSET := 100.0

## Emitted with a one-shot layout snapshot for Debug Logging (mod_main filters on _debug_logging).
signal layout_debug(message: String)

var _total_count := 0  # Sum of entry counts, shown in the tab title
var _gem_texture: Texture2D = null


func _ready() -> void:
	# Left-aligned with the reminder label, ~10% down so both can be visible at once.
	var viewport := get_viewport()
	var top_offset := FALLBACK_TOP_OFFSET
	if viewport != null:
		top_offset = viewport.get_visible_rect().size.y * TOP_OFFSET_RATIO
	position = Vector2(LEFT_MARGIN, top_offset)
	minimized = true
	reveal = 0.0
	_gem_texture = _load_texture("../assets/icons/gem.png")


## Height of the panel when fully expanded (name line + wrapped description lines per entry).
func full_height() -> float:
	if _entries.is_empty():
		return HEAD_H + CONTENT_PADDING * 2.0
	var row_w := _content_width() - CONTENT_PADDING * 2.0 - 2.0
	var total := HEAD_H + CONTENT_PADDING * 2.0
	for entry in _entries:
		total += NAME_LINE_H + DESC_LINE_H * _desc_line_count(entry, row_w) + ROW_GAP
	return total


## Collapsed tab title (between the left edge and the +/- button).
func header_text() -> String:
	return "(%d)" % _total_count


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
	_log_layout_after_settle("show")


## Hide the panel immediately, keeping the collapsed state for the next appearance.
func hide_panel() -> void:
	# Already hidden with no rows: nothing to do (called every poll outside the shop).
	if not visible and _entries.is_empty():
		return
	if _tween != null:
		_tween.kill()
		_tween = null
	_entries.clear()
	_total_count = 0
	_content_key = ""
	visible = false
	queue_redraw()
	_emit_layout_debug("hide")


## Hide and reset to the collapsed default (zero reminders or new run).
func reset_collapsed() -> void:
	# Already hidden and collapsed with no rows: nothing to do (called every poll at zero).
	if not visible and minimized and _entries.is_empty():
		return
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
	_emit_layout_debug("reset")


## Reset the collapsed state to the collapsed default (new run).
func reset_for_run() -> void:
	reset_collapsed()


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
	# Width animates between the small tab and the content-fitted width; height between
	# header-only and the wrapped rows.
	var w := lerpf(_tab_width(), _content_width(), reveal)
	size = Vector2(w, lerpf(HEAD_H + 1.0, full_height(), reveal))


## Expanded width fitted to the widest name/description, capped for very long text.
func _content_width() -> float:
	if _text_font == null:
		return MAX_EXPANDED_WIDTH
	var inner := 0.0
	for entry in _entries:
		inner = maxf(inner, _text_font.get_string_size(_name_line(entry), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x)
		inner = maxf(inner, _text_font.get_string_size(str(entry.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, DESC_FONT_SIZE).x)
	return clampf(inner + CONTENT_PADDING * 2.0 + 2.0, _tab_width(), MAX_EXPANDED_WIDTH)


## Keep the header bar only as wide as the collapsed tab (gem + "(N)" + button).
func header_width() -> float:
	return _tab_width()


## Number of wrapped description lines for an entry at the given row width.
func _desc_line_count(entry: Dictionary, row_w: float) -> int:
	return maxi(1, _wrap_text(_text_font, str(entry.get("desc", "")), DESC_FONT_SIZE, row_w).size())


## Word-wrap `text` to `max_w` at `font_size`; long words are broken by character.
func _wrap_text(font: Font, text: String, font_size: int, max_w: float) -> Array[String]:
	var lines: Array[String] = []
	if font == null or text.is_empty() or max_w <= 0.0:
		return lines
	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			current = candidate
			continue
		if not current.is_empty():
			lines.append(current)
		if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			current = word
			continue
		# Break a single word that is wider than the row.
		var chunk := ""
		for ch in word:
			var next := chunk + ch
			if not chunk.is_empty() and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
				lines.append(chunk)
				chunk = ch
			else:
				chunk = next
		current = chunk
	if not current.is_empty():
		lines.append(current)
	return lines


## Emit a one-shot layout snapshot for Debug Logging (mod_main filters on _debug_logging).
func _emit_layout_debug(reason: String) -> void:
	var parent := get_parent()
	var parent_desc := "none"
	if parent != null:
		parent_desc = "%s (%s)" % [parent.name, parent.get_class()]
	var viewport_size := Vector2.ZERO
	if get_viewport() != null:
		viewport_size = get_viewport().get_visible_rect().size
	var lines: Array[String] = []
	lines.append("TRINKET PANEL | %s | expanded=%s | reminders=%d" % [reason, str(not minimized), _entries.size()])
	lines.append("  Panel: size=%s min=%s custom_min=%s" % [str(size), str(get_combined_minimum_size()), str(custom_minimum_size)])
	lines.append("  Flags: h=%d v=%d anchors=(%.2f,%.2f,%.2f,%.2f)" % [size_flags_horizontal, size_flags_vertical, anchor_left, anchor_top, anchor_right, anchor_bottom])
	lines.append("  Intended: tab_width=%.1f content_width=%.1f reveal=%.3f minimized=%s" % [_tab_width(), _content_width(), reveal, str(minimized)])
	lines.append("  Parent: %s | canvas_scale=%s | viewport=%s" % [parent_desc, str(get_global_transform_with_canvas().get_scale()), str(viewport_size)])
	for entry in _entries:
		lines.append("  Entry \"%s\": desc_len=%d" % [str(entry.get("name", "")), str(entry.get("desc", "")).length()])
	layout_debug.emit("\n".join(lines))


## Log the settled layout after the reveal tween has had time to finish.
func _log_layout_after_settle(reason: String) -> void:
	await get_tree().create_timer(DEBUG_SETTLE_SEC).timeout
	if is_inside_tree():
		_emit_layout_debug(reason)


## Collapsed tab width: fits the gem icon + "(N)" plus the +/- button.
func _tab_width() -> float:
	if _text_font == null:
		return MAX_EXPANDED_WIDTH
	var title_w := _text_font.get_string_size(header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	var icon_w := GEM_SIZE + GEM_GAP if _gem_texture != null else 0.0
	return icon_w + title_w + BTN + TAB_EXTRA_WIDTH


## Header title: gem icon followed by "(N)" (replaces the base text-only title).
func _draw_title(r: Rect2) -> void:
	var text := header_text()
	var icon_w := GEM_SIZE if _gem_texture != null else 0.0
	var gap := GEM_GAP if _gem_texture != null else 0.0
	var start_x := r.position.x
	if _gem_texture != null:
		var icon_y := r.position.y + (HEAD_H - GEM_SIZE) * 0.5
		draw_texture_rect(_gem_texture, Rect2(Vector2(start_x, icon_y), Vector2(GEM_SIZE, GEM_SIZE)), false)
	var baseline := r.position.y + HEAD_H * 0.5 + 3.0
	_draw_text_shadow(Vector2(start_x + icon_w + gap, baseline), text, VALUE_COLOR, TITLE_FONT_SIZE)


## Rows: "Name [xN]" then the wrapped description lines.
func _draw_body(width: float) -> void:
	var cursor_y := HEAD_H + CONTENT_PADDING
	var row_w := width - CONTENT_PADDING * 2.0 - 2.0
	for entry in _entries:
		var name_baseline := cursor_y + NAME_LINE_H - 3.0
		var name_line := _fit_text(_text_font, _name_line(entry), NAME_FONT_SIZE, row_w)
		_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, name_baseline), name_line, VALUE_COLOR, NAME_FONT_SIZE)
		cursor_y += NAME_LINE_H
		for desc_line in _wrap_text(_text_font, str(entry.get("desc", "")), DESC_FONT_SIZE, row_w):
			var desc_baseline := cursor_y + DESC_LINE_H - 3.0
			_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, desc_baseline), desc_line, LABEL_COLOR, DESC_FONT_SIZE)
			cursor_y += DESC_LINE_H
		cursor_y += ROW_GAP
