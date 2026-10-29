extends "collapsible_panel.gd"
## TrinketRemindersPanel - Compact shop-phase reminder for unused one-shot trinkets.
##
## Collapsed it is a small top-left tab showing the gem icon followed by "(N)", where N is the
## total number of relevant trinkets held. Clicking the tab (or its +/- button) expands a
## fixed-width (~320 px) panel; each trinket shows its name + quantity on the first line and
## its short description underneath. The expanded/collapsed choice persists across show/hide
## cycles and only resets to collapsed on a new run. The whole tab disappears when no relevant
## trinkets are held. When a new alerting trinket appears (first show, or after the list was
## cleared), the caller expands the panel via expand() and plays the notification sound.
##
## Collapsible header mechanics live in collapsible_panel.gd. This subclass supplies the
## top-left anchoring, the gem + "(N)" title, the two-line rows, and the tab width.

const CONTENT_PADDING := 6.0
const NAME_LINE_H := 14.0     # First line: name + quantity
const DESC_LINE_H := 13.0     # Second line: short description
const ROW_GAP := 5.0
const NAME_FONT_SIZE := 8
const DESC_FONT_SIZE := 7
const EXPANDED_WIDTH := 320.0
const TAB_EXTRA_WIDTH := 30.0  # Button + header insets for the collapsed tab
const GEM_SIZE := 10.0
const GEM_GAP := 2.0

# Same top-left spot as hud/reminder_label.gd (LEFT_MARGIN, TOP_BAR_Y)
const LEFT_MARGIN := 55.0
const TOP_BAR_Y := 2.0

var _total_count := 0  # Sum of entry counts, shown in the tab title
var _gem_texture: Texture2D = null


func _ready() -> void:
	# Fixed top-left anchor; starts collapsed (the player's choice is remembered afterwards).
	position = Vector2(LEFT_MARGIN, TOP_BAR_Y)
	minimized = true
	reveal = 0.0
	_gem_texture = _load_texture("../assets/icons/gem.png")


## Height of the panel when fully expanded (two lines per entry).
func full_height() -> float:
	var rows := float(_entries.size())
	if rows <= 0.0:
		return HEAD_H + CONTENT_PADDING * 2.0
	return HEAD_H + CONTENT_PADDING + rows * (NAME_LINE_H + DESC_LINE_H + ROW_GAP) + CONTENT_PADDING


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


## Expand the panel (used when a new alerting trinket appears). Animates like a manual toggle.
func expand() -> void:
	set_minimized(false)


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


## Collapsed tab width: fits the gem icon + "(N)" plus the +/- button.
func _tab_width() -> float:
	if _text_font == null:
		return EXPANDED_WIDTH
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


## Two-line rows: "Name [xN]" then the short description.
func _draw_body(width: float) -> void:
	var cursor_y := HEAD_H + CONTENT_PADDING
	var row_w := width - CONTENT_PADDING * 2.0 - 2.0
	for entry in _entries:
		var name_baseline := cursor_y + NAME_LINE_H - 3.0
		var name_line := _fit_text(_text_font, _name_line(entry), NAME_FONT_SIZE, row_w)
		_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, name_baseline), name_line, VALUE_COLOR, NAME_FONT_SIZE)
		var desc_baseline := name_baseline + DESC_LINE_H
		var desc_line := _fit_text(_text_font, str(entry.get("desc", "")), DESC_FONT_SIZE, row_w)
		_draw_text_shadow(Vector2(CONTENT_PADDING + 1.0, desc_baseline), desc_line, LABEL_COLOR, DESC_FONT_SIZE)
		cursor_y += NAME_LINE_H + DESC_LINE_H + ROW_GAP
