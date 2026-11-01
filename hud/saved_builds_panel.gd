extends Control
## Saved Builds overlay for the watchlist popup.
##
## A separate modal layer (not a Batomon/Items tab) listing saved watchlist builds
## with an icon preview, tracked counts, and Load/Delete actions. Delete uses an
## inline two-step confirm so no extra modal or keyboard input is needed.
##
## The panel owns its own store copy: it reads it from the caller on open, writes
## deletions straight to disk, and never touches the active watchlist selection.

const Style = preload("../core/style.gd")
const SavedBuilds = preload("../core/saved_builds.gd")

signal load_requested(build: Dictionary)

const TITLE_FONT_SIZE := 12
const BODY_FONT_SIZE := 7
const ICON_SIZE := 12.0
const PANEL_BG := Color("#18232D")
const ROW_BG := Color("#1e2a36")

var _font: Font
var _lookup: Callable
var _play_click: Callable
var _store: Dictionary = SavedBuilds.empty_store()
var _panel: PanelContainer
var _rows_box: VBoxContainer
var _confirm_id := ""
var _open := false


func setup(font: Font, catalog_lookup: Callable, play_click: Callable = Callable()) -> void:
	_font = font
	_lookup = catalog_lookup
	_play_click = play_click
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()


func is_open() -> bool:
	return _open


## Show the overlay for a store snapshot. The confirm state is always reset so a
## half-armed Delete cannot survive a close/reopen.
func open_panel(store: Dictionary) -> void:
	_store = store
	_confirm_id = ""
	_open = true
	visible = true
	_rebuild_rows()


func close_panel() -> void:
	_open = false
	_confirm_id = ""
	visible = false


## Re-render after the watchlist saved a new build while this panel is open.
func refresh(store: Dictionary) -> void:
	_store = store
	if _open:
		_rebuild_rows()


## Match the watchlist popup's panel rect so the overlay reads as a sub-view of it.
func layout(rect: Rect2) -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = rect.size
	_panel.size = rect.size
	_panel.position = rect.position


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.set_corner_radius_all(3)
	panel_style.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Saved Builds"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(title, TITLE_FONT_SIZE)
	header.add_child(title)

	var close_x := CloseButton.new()
	close_x.on_press = close_panel
	close_x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(close_x)

	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.12)
	divider.custom_minimum_size.y = 1
	vbox.add_child(divider)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows_box)


func _rebuild_rows() -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	var builds := SavedBuilds.sorted_newest_first(_store)
	if builds.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved builds yet."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_font(empty_label, BODY_FONT_SIZE)
		_rows_box.add_child(empty_label)
		return
	for build in builds:
		_rows_box.add_child(_build_row(build))


func _build_row(build: Dictionary) -> Control:
	var row := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = ROW_BG
	row_style.set_corner_radius_all(2)
	row_style.set_content_margin_all(2)
	row.add_theme_stylebox_override("panel", row_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	row.add_child(vbox)

	var preview := SavedBuilds.preview_entries(build, _lookup)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	vbox.add_child(top)

	var name_label := Label.new()
	name_label.text = SavedBuilds.display_name(build)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_font(name_label, BODY_FONT_SIZE)
	top.add_child(name_label)

	var counts := Label.new()
	counts.text = "%d Batomon, %d items" % [int(preview["monster_count"]), int(preview["item_count"])]
	counts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	counts.add_theme_color_override("font_color", Style.LABEL_COLOR)
	_apply_font(counts, BODY_FONT_SIZE)
	top.add_child(counts)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.tooltip_text = "Replace your tracked Batomon and items with this build"
	load_button.focus_mode = Control.FOCUS_NONE
	load_button.custom_minimum_size = Vector2(0, 8)
	_apply_font(load_button, BODY_FONT_SIZE)
	_style_button(load_button)
	load_button.pressed.connect(_on_load_pressed.bind(build))
	top.add_child(load_button)

	var confirming := _confirm_id == str(build.get("id", ""))
	var delete_button := Button.new()
	delete_button.text = "Confirm?" if confirming else "Delete"
	delete_button.tooltip_text = "Delete this saved build" if not confirming else "Click again to delete this build"
	delete_button.focus_mode = Control.FOCUS_NONE
	delete_button.custom_minimum_size = Vector2(0, 8)
	_apply_font(delete_button, BODY_FONT_SIZE)
	_style_button(delete_button, Style.ACTION_BORDER if confirming else Color.TRANSPARENT)
	delete_button.pressed.connect(_on_delete_pressed.bind(build))
	top.add_child(delete_button)

	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 1)
	vbox.add_child(icon_row)
	for entry in preview["entries"]:
		var slot := _icon_slot(entry)
		if slot != null:
			icon_row.add_child(slot)
	var overflow := int(preview["overflow"])
	if overflow > 0:
		var more := Label.new()
		more.text = "+%d" % overflow
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.add_theme_color_override("font_color", Style.LABEL_COLOR)
		_apply_font(more, BODY_FONT_SIZE)
		icon_row.add_child(more)
	return row


## Fixed-size icon holder. A plain Control keeps the 12x12 rect exact; the
## TextureRect is anchored inside it so the sprite cannot resize the row.
func _icon_slot(entry: Dictionary) -> Control:
	var icon_tex = entry.get("icon")
	if not (icon_tex is Texture2D):
		return null
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.tooltip_text = str(entry.get("name", ""))
	var icon := TextureRect.new()
	icon.texture = icon_tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return slot


func _on_load_pressed(build: Dictionary) -> void:
	_confirm_id = ""
	load_requested.emit(build)


func _on_delete_pressed(build: Dictionary) -> void:
	if _play_click.is_valid():
		_play_click.call()
	var id := str(build.get("id", ""))
	if _confirm_id != id:
		# First click arms the row; the second one deletes it.
		_confirm_id = id
		_rebuild_rows()
		return
	_confirm_id = ""
	if SavedBuilds.delete_build(_store, id):
		SavedBuilds.save_store(_store)
	_rebuild_rows()


func _apply_font(control: Control, size: int) -> void:
	if _font != null:
		control.add_theme_font_override("font", _font)
	control.add_theme_font_size_override("font_size", size)


## Compact button styling matching the watchlist popup controls.
func _style_button(b: Button, color: Color = Color.TRANSPARENT) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Style.BG_COLOR
	normal.border_color = Style.BORDER_COLOR
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(1)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Style.BORDER_COLOR
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, normal)
	b.add_theme_stylebox_override("pressed", pressed)
	var text_color := color if color != Color.TRANSPARENT else Style.VALUE_COLOR
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", Style.BG_COLOR)
	b.add_theme_color_override("font_hover_pressed_color", Style.BG_COLOR)


## Close (X) button mirroring the watchlist popup: a gold rounded box with dark
## arms drawn straight onto the canvas.
class CloseButton extends Control:
	const Style = preload("../core/style.gd")
	const SIZE := 14.0
	const ARM := 3.0
	const ARM_WIDTH := 1.5

	var on_press: Callable
	var _box: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "Close"
		custom_minimum_size = Vector2(SIZE, SIZE)
		_box = StyleBoxFlat.new()
		_box.bg_color = Style.BORDER_COLOR
		_box.set_corner_radius_all(2)

	func _draw() -> void:
		_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		var c := size * 0.5
		draw_line(c + Vector2(-ARM, -ARM), c + Vector2(ARM, ARM), Style.BG_COLOR, ARM_WIDTH)
		draw_line(c + Vector2(-ARM, ARM), c + Vector2(ARM, -ARM), Style.BG_COLOR, ARM_WIDTH)

	func _gui_input(event) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if on_press.is_valid():
				on_press.call()
			accept_event()
