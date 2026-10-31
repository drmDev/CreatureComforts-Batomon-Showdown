extends "comfort_panel.gd"
## Watchlist panel: tabbed Batomon/Items catalog with mouse-driven Rarity and
## Type filters, selection, and persistence.
##
## No text inputs: the game handles hotkeys globally (R = reroll), so a focused
## text field would let typed letters trigger shop actions. All filtering is
## clickable. Filters only affect what is displayed; saved selections are never
## changed by filtering.

const CFG_PATH := "user://creature_comforts/watchlist.cfg"
const BTN_SIZE := 14
const LEFT_RATIO := 0.25
const BOTTOM_OFFSET_RATIO := 0.35

const POPUP_WIDTH := 352.0
const POPUP_HEIGHT := 300.0

const TITLE_FONT_SIZE := 12
const BODY_FONT_SIZE := 7
const ROW_HEIGHT := 10.0
const LIST_COLUMNS := 3

const TAB_MONSTER := "monster"
const TAB_ITEM := "item"

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Super Rare", "Legendary", "Mythical"]
const RARITY_BY_TIER := {1: "Common", 2: "Uncommon", 3: "Rare", 4: "Super Rare", 5: "Legendary", 6: "Mythical"}
const RARITY_COLORS := Style.RARITY_COLORS_BY_NAME

# Placeholder/non-Batomon entries that should not appear in the watchlist.
const EXCLUDED_NAME_PARTS := ["mysterious", "null", "egg", "missing"]
const EXCLUDED_TYPES := ["all", "null"]

# Region filter options and the species fields that may carry the region.
const REGION_NAMES := ["Jinto", "Pantra"]

## { "monster": { name_key: true }, "item": { id: true } }
var selection := {"monster": {}, "item": {}}

var _formatter = null
var _catalog: Array = []  # {kind, key, name, tier, types}
var _available_types: Array = []
var _catalog_loaded := false

var _button: WatchlistButton
var _popup: Control
var _panel: PanelContainer
var _filters_box: VBoxContainer
var _type_flow: HFlowContainer
var _tab := TAB_MONSTER
var _tab_buttons: Array = []
var _rarity_filter := ""
var _type_filter := ""
var _rarity_buttons: Array = []
var _type_buttons: Array = []
var _region_filter := ""
var _region_option: OptionButton
var _rows_box: GridContainer
var _popup_open := false


func _init() -> void:
	_text_font = _build_panel_font()


func setup(formatter) -> void:
	_formatter = formatter
	_load_selection()
	_build_ui()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_button()
	_position_panel()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_anchor_button()
	_position_panel()


func _anchor_button() -> void:
	if _button == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	_button.position = Vector2(
		roundf(vs.x * LEFT_RATIO),
		roundf(vs.y * (1.0 - BOTTOM_OFFSET_RATIO) - BTN_SIZE))


func _position_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	_panel.size = Vector2(POPUP_WIDTH, POPUP_HEIGHT)
	_panel.position = Vector2(
		roundf((vs.x - POPUP_WIDTH) * 0.5),
		roundf((vs.y - POPUP_HEIGHT) * 0.5))


func _apply_font(control: Control, size: int) -> void:
	if _text_font != null:
		control.add_theme_font_override("font", _text_font)
	control.add_theme_font_size_override("font_size", size)


func _build_ui() -> void:
	# Custom-drawn control (not a Button) so BTN_SIZE fully controls the size;
	# a Button clamps to its text + theme padding minimum.
	_button = WatchlistButton.new()
	_button.font = _text_font
	_button.font_size = BODY_FONT_SIZE
	_button.on_press = _toggle_popup
	_button.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_button.size = Vector2(BTN_SIZE, BTN_SIZE)
	add_child(_button)

	_popup = Control.new()
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.visible = false
	add_child(_popup)

	var dim := ColorRect.new()
	dim.color = Style.DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(dim)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(POPUP_WIDTH, POPUP_HEIGHT)
	_popup.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_panel.add_child(vbox)

	# Header: centered title + top-right close (X).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Watchlist"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(title, TITLE_FONT_SIZE)
	header.add_child(title)

	var close_x := Button.new()
	close_x.text = "X"
	close_x.tooltip_text = "Close"
	close_x.custom_minimum_size = Vector2(14, 14)
	_apply_font(close_x, BODY_FONT_SIZE)
	_style_button(close_x)
	close_x.pressed.connect(_toggle_popup)
	header.add_child(close_x)

	# Tabs
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	vbox.add_child(tab_row)
	for tab in [TAB_MONSTER, TAB_ITEM]:
		var b := Button.new()
		b.text = "Batomon" if tab == TAB_MONSTER else "Items"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(35, 8)
		_apply_font(b, BODY_FONT_SIZE)
		_style_button(b)
		b.pressed.connect(_on_tab_pressed.bind(tab))
		tab_row.add_child(b)
		_tab_buttons.append({"button": b, "tab": tab})

	# Region dropdown, visually distinct from the tab toggles.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(spacer)
	var region_label := Label.new()
	region_label.text = "Region"
	_apply_font(region_label, BODY_FONT_SIZE)
	tab_row.add_child(region_label)
	_region_option = OptionButton.new()
	_region_option.add_item("All", 0)
	for i in range(REGION_NAMES.size()):
		_region_option.add_item(REGION_NAMES[i], i + 1)
	_apply_font(_region_option, BODY_FONT_SIZE)
	_style_button(_region_option)
	_region_option.custom_minimum_size = Vector2(0, 8)
	# Shrink the dropdown popup to match the compact HUD scale.
	var region_popup := _region_option.get_popup()
	region_popup.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	if _text_font != null:
		region_popup.add_theme_font_override("font", _text_font)
	region_popup.add_theme_constant_override("v_separation", 0)
	region_popup.add_theme_constant_override("item_start_padding", 2)
	region_popup.add_theme_constant_override("item_end_padding", 2)
	_region_option.item_selected.connect(_on_region_selected)
	tab_row.add_child(_region_option)

	# Batomon-only filters (hidden on the Items tab).
	_filters_box = VBoxContainer.new()
	_filters_box.add_theme_constant_override("separation", 1)
	vbox.add_child(_filters_box)

	var rarity_label := Label.new()
	rarity_label.text = "Rarity"
	_apply_font(rarity_label, BODY_FONT_SIZE)
	_filters_box.add_child(rarity_label)
	var rarity_flow := HFlowContainer.new()
	rarity_flow.add_theme_constant_override("h_separation", 1)
	rarity_flow.add_theme_constant_override("v_separation", 1)
	_filters_box.add_child(rarity_flow)
	_add_filter_button(rarity_flow, "All", "", _rarity_buttons, _on_rarity_pressed)
	for rarity in RARITY_NAMES:
		_add_filter_button(rarity_flow, rarity, rarity, _rarity_buttons, _on_rarity_pressed, RARITY_COLORS.get(rarity, Color.TRANSPARENT))

	var type_label := Label.new()
	type_label.text = "Type"
	_apply_font(type_label, BODY_FONT_SIZE)
	_filters_box.add_child(type_label)
	_type_flow = HFlowContainer.new()
	_type_flow.add_theme_constant_override("h_separation", 1)
	_type_flow.add_theme_constant_override("v_separation", 1)
	_filters_box.add_child(_type_flow)
	_add_filter_button(_type_flow, "All", "", _type_buttons, _on_type_pressed)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_rows_box = GridContainer.new()
	_rows_box.columns = LIST_COLUMNS
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("h_separation", 4)
	_rows_box.add_theme_constant_override("v_separation", 0)
	scroll.add_child(_rows_box)

	# Initial state: Batomon tab, "All" filters.
	for entry in _tab_buttons:
		entry["button"].button_pressed = (entry["tab"] == _tab)
	_filters_box.visible = (_tab == TAB_MONSTER)
	_sync_filter_buttons(_rarity_buttons, _rarity_filter)
	_sync_filter_buttons(_type_buttons, _type_filter)


func _add_filter_button(parent: Control, text: String, value: String, store: Array, handler: Callable, color: Color = Color.TRANSPARENT) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 7)
	_apply_font(b, BODY_FONT_SIZE)
	_style_button(b, color)
	b.pressed.connect(handler.bind(value))
	parent.add_child(b)
	store.append({"button": b, "value": value})


## Compact button styling so the popup controls match the small HUD scale.
func _style_button(b: Button, color: Color = Color.TRANSPARENT) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_COLOR
	normal.border_color = BORDER_COLOR
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(1)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = BORDER_COLOR
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, normal)
	b.add_theme_stylebox_override("pressed", pressed)
	var text_color := color if color != Color.TRANSPARENT else VALUE_COLOR
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", BG_COLOR)
	b.add_theme_color_override("font_hover_pressed_color", BG_COLOR)


func _sync_filter_buttons(buttons: Array, selected: String) -> void:
	for entry in buttons:
		entry["button"].button_pressed = (entry["value"] == selected)


func _toggle_popup() -> void:
	_popup_open = not _popup_open
	_popup.visible = _popup_open
	if _popup_open:
		_ensure_catalog()
		_position_panel()
		_rebuild_rows()


func _on_tab_pressed(tab: String) -> void:
	_tab = tab
	for entry in _tab_buttons:
		entry["button"].button_pressed = (entry["tab"] == tab)
	_filters_box.visible = (tab == TAB_MONSTER)
	_rebuild_rows()


func _on_rarity_pressed(value: String) -> void:
	_rarity_filter = value
	_sync_filter_buttons(_rarity_buttons, value)
	_rebuild_rows()


func _on_type_pressed(value: String) -> void:
	_type_filter = value
	_sync_filter_buttons(_type_buttons, value)
	_rebuild_rows()


func _on_region_selected(index: int) -> void:
	_region_filter = "" if index == 0 else REGION_NAMES[index - 1]
	_rebuild_rows()


## The catalog is loaded lazily so the GameDatabase autoload is guaranteed to
## exist (the mod may initialize before it).
func _ensure_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	_load_catalog()
	_rebuild_type_buttons()


func _load_catalog() -> void:
	_catalog.clear()
	_available_types.clear()
	var db = get_node_or_null("/root/GameDatabase")
	if db == null:
		return
	var seen := {}
	var type_set := {}
	# Map set id -> set display name so species can be filtered by region (set).
	var set_region_map := {}
	if "sets_db" in db:
		var sets = db.get("sets_db")
		if sets is Array:
			for s in sets:
				if s == null:
					continue
				var sid := str(s.get("id")) if "id" in s else ""
				if sid.is_empty():
					continue
				var sname := str(s.get("name")) if "name" in s else ""
				var skey := str(s.get("name_key")) if "name_key" in s else ""
				set_region_map[sid] = sname if not sname.is_empty() else skey
	if db.has_method("get_all_species"):
		for species in db.get_all_species():
			if species == null:
				continue
			var key := ""
			if "name_key" in species:
				key = str(species.get("name_key"))
			elif "id" in species:
				key = str(species.get("id"))
			if key.is_empty() or seen.has("m:" + key):
				continue
			var display := _display_name("monster", key)
			if display.strip_edges().is_empty() or _is_excluded_name(display):
				continue
			seen["m:" + key] = true
			var tier := int(species.get("tier")) if "tier" in species else 0
			var types: Array = []
			if "types" in species:
				var raw_types = species.get("types")
				if raw_types is Array:
					for t in raw_types:
						var tname := _resolve_type(t)
						if tname.is_empty() or tname.to_lower() in EXCLUDED_TYPES:
							continue
						if not types.has(tname):
							types.append(tname)
							type_set[tname] = true
			var icon = species.get("texture") if "texture" in species else null
			_catalog.append({
				"kind": "monster", "key": key, "name": display,
				"tier": tier, "types": types,
				"icon": icon if icon is Texture2D else null,
				"region": _extract_region(species, set_region_map),
			})
	if "items_db" in db:
		var items = db.get("items_db")
		if items is Array:
			for item in items:
				if item == null:
					continue
				var key := str(item.get("id")) if "id" in item else ""
				if key.is_empty() or seen.has("i:" + key):
					continue
				seen["i:" + key] = true
				var tier := int(item.get("tier")) if "tier" in item else 0
				var icon = item.get("icon") if "icon" in item else null
				_catalog.append({
					"kind": "item", "key": key, "name": _display_name("item", key),
					"tier": tier, "types": [],
					"icon": icon if icon is Texture2D else null,
				})
	_available_types = type_set.keys()
	_available_types.sort()
	_catalog.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)


func _rebuild_type_buttons() -> void:
	# Keep the "All" button (index 0); rebuild the dynamic type buttons.
	while _type_buttons.size() > 1:
		var entry = _type_buttons.pop_back()
		entry["button"].queue_free()
	for type_name in _available_types:
		_add_filter_button(_type_flow, type_name, type_name, _type_buttons, _on_type_pressed)
	_sync_filter_buttons(_type_buttons, _type_filter)


func _resolve_type(type_resource) -> String:
	if _formatter != null:
		return _formatter.resolve_type_name(type_resource)
	return ""


func _extract_region(species, set_region_map: Dictionary) -> String:
	# Direct region fields first (if the game ever adds one).
	for field in ["region", "regions", "home_region", "area", "zone", "origin"]:
		if not (field in species):
			continue
		var value = species.get(field)
		if value is String and not value.is_empty():
			return value
		if value is Array and not value.is_empty():
			return str(value[0])
		if value is Object and is_instance_valid(value):
			if "id" in value:
				return str(value.get("id"))
			if "name" in value:
				return str(value.get("name"))
	# Otherwise the region is the species' set (Jinto/Pantra).
	if "sets" in species:
		var sets = species.get("sets")
		if sets is Array:
			for set_entry in sets:
				var sid := ""
				if set_entry is String:
					sid = set_entry
				elif set_entry is Object and is_instance_valid(set_entry) and "id" in set_entry:
					sid = str(set_entry.get("id"))
				if sid.is_empty():
					continue
				if set_region_map.has(sid):
					return str(set_region_map[sid])
				return sid
	return ""


func _is_excluded_name(name: String) -> bool:
	var lower := name.to_lower()
	for part in EXCLUDED_NAME_PARTS:
		if lower.contains(part):
			return true
	return false


func _display_name(kind: String, key: String) -> String:
	if _formatter != null:
		return _formatter.format_species_name(key) if kind == "monster" else _formatter.format_item_name(key)
	return key


func _rebuild_rows() -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	for entry in _catalog:
		if str(entry["kind"]) != _tab:
			continue
		if _tab == TAB_MONSTER and not _passes_monster_filters(entry):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var icon_tex = entry.get("icon")
		if icon_tex is Texture2D:
			var icon := TextureRect.new()
			icon.texture = icon_tex
			icon.custom_minimum_size = Vector2(12, 12)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
		var cb := CheckBox.new()
		cb.text = str(entry["name"])
		cb.button_pressed = is_watched(entry["kind"], entry["key"])
		cb.custom_minimum_size.y = ROW_HEIGHT
		_apply_font(cb, BODY_FONT_SIZE)
		cb.add_theme_constant_override("h_separation", 2)
		# Remove the default stylebox padding so rows stay dense.
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			cb.add_theme_stylebox_override(state, empty)
		# Keep the check icon a fixed width so toggling cannot resize the row/text.
		cb.add_theme_constant_override("icon_max_width", 12)
		cb.toggled.connect(_on_entry_toggled.bind(entry["kind"], entry["key"]))
		row.add_child(cb)
		_rows_box.add_child(row)


func _passes_monster_filters(entry: Dictionary) -> bool:
	if not _rarity_filter.is_empty():
		var rarity: String = RARITY_BY_TIER.get(int(entry.get("tier", 0)), "")
		if rarity != _rarity_filter:
			return false
	if not _type_filter.is_empty():
		var types: Array = entry.get("types", [])
		if not types.has(_type_filter):
			return false
	if not _region_filter.is_empty():
		var region := str(entry.get("region", "")).to_lower()
		if not region.contains(_region_filter.to_lower()):
			return false
	return true


func _on_entry_toggled(on: bool, kind: String, key: String) -> void:
	var bucket: Dictionary = selection.get(kind, {})
	if on:
		bucket[key] = true
	else:
		bucket.erase(key)
	selection[kind] = bucket
	_save_selection()


func is_watched(kind: String, key: String) -> bool:
	return selection.get(kind, {}).has(key)


func _load_selection() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	selection["monster"] = _parse_ids(str(cfg.get_value("watchlist", "monsters", "")))
	selection["item"] = _parse_ids(str(cfg.get_value("watchlist", "items", "")))


func _save_selection() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("watchlist", "monsters", _format_ids(selection["monster"]))
	cfg.set_value("watchlist", "items", _format_ids(selection["item"]))
	cfg.save(CFG_PATH)


static func _parse_ids(csv: String) -> Dictionary:
	var out := {}
	for part in csv.split(",", false):
		var key := part.strip_edges()
		if not key.is_empty():
			out[key] = true
	return out


static func _format_ids(ids: Dictionary) -> String:
	var keys: Array = ids.keys()
	keys.sort()
	return ",".join(keys)


## Small self-drawn button. A plain Control has no content minimum, so its size
## is exactly BTN_SIZE (unlike a Button, which clamps to text + theme padding).
class WatchlistButton extends Control:
	const Style = preload("../core/style.gd")
	var font: Font
	var font_size := 7
	var on_press: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "Watchlist"

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Style.BG_COLOR, true)
		draw_rect(Rect2(Vector2.ZERO, size), Style.BORDER_COLOR, false, 1.0)
		if font != null:
			var text := "WL"
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var th := font.get_height(font_size)
			draw_string(font, Vector2((size.x - tw) * 0.5, (size.y + th) * 0.5 - 2.0),
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Style.VALUE_COLOR)

	func _gui_input(event) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if on_press.is_valid():
				on_press.call()
			accept_event()
