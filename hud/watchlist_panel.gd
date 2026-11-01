extends "comfort_panel.gd"
## Watchlist panel: tabbed Batomon/Items catalog with mouse-driven Rarity, Type
## and Region filters, selection, and persistence.
##
## No text inputs: the game handles hotkeys globally (R = reroll), so a focused
## text field would let typed letters trigger shop actions. All filtering is
## clickable. Filters only affect what is displayed; saved selections are never
## changed by filtering.

const CFG_PATH := "user://creature_comforts/watchlist.cfg"
const BTN_SIZE := 20
const LEFT_RATIO := 0.27
const BOTTOM_OFFSET_RATIO := 0.60

const POPUP_WIDTH := 352.0
const POPUP_HEIGHT := 300.0

const TITLE_FONT_SIZE := 12
const BODY_FONT_SIZE := 7
const ROW_HEIGHT := 10.0
const LIST_COLUMNS := 3
const ICON_Y_OFFSET := 2.5  # sprites sit slightly high so they line up with names

const TAB_MONSTER := "monster"
const TAB_ITEM := "item"

## Tier -> rarity display name; the keys double as the filter row's order.
const RARITY_BY_TIER := {1: "Common", 2: "Uncommon", 3: "Rare", 4: "Super Rare", 5: "Legendary", 6: "Mythical"}
const RARITY_COLORS := Style.RARITY_COLORS_BY_NAME

# Placeholder/non-Batomon entries that should not appear in the watchlist.
const EXCLUDED_NAME_PARTS := ["mysterious", "null", "egg", "missing"]
const EXCLUDED_TYPES := ["all", "null"]

# Known regions. The run's own region is appended at runtime when it is not
# listed here.
const REGION_NAMES := ["Jinto", "Pantra"]
const RunRegion = preload("../core/run_region.gd")
const RunData = preload("../core/run_data.gd")
const SavedBuilds = preload("../core/saved_builds.gd")
const SavedBuildsPanel = preload("saved_builds_panel.gd")
const UiSound = preload("../core/ui_sound.gd")

## { "monster": { name_key: true }, "item": { id: true } }
var selection := {"monster": {}, "item": {}}

var _formatter = null
var _catalog: Array = []  # {kind, key, name, tier, types, icon, region?}
var _catalog_index := {}  # "kind:key" -> catalog entry, for saved-build previews
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
var _region_map := {}      # set/pack id -> region display name (from the catalog)
var _applied_region := ""  # last auto-applied region, so we only override on change
var _snapshot_button: Button
var _tracked_count_label: Label
var _builds_button: Button
var _save_button: Button
var _builds_panel: SavedBuildsPanel
var _click_sound = null
var _tracked_only := false
var _tracked_only_check: CheckBox
var _rows_box: GridContainer
var _popup_open := false
var _rows_dirty := true

# Shared row styleboxes, built once by _ensure_row_styles().
var _blank_style: StyleBoxEmpty
var _row_style_a: StyleBoxFlat
var _row_style_b: StyleBoxFlat
var _row_hover_style: StyleBoxFlat
var _row_pressed_style: StyleBoxFlat


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
	_apply_tooltip_theme()
	_connect_viewport_resize(_on_viewport_resized)


## Tooltips are drawn with the TooltipLabel theme type, which per-control theme
## overrides cannot reach, and the game's default size is far too large at this
## HUD scale. Half of the inherited size stays readable without covering the
## panel. Assigned to the panel so every tooltip in its subtree picks it up.
func _apply_tooltip_theme() -> void:
	var inherited := get_theme_font_size("font_size", "TooltipLabel")
	if inherited <= 0:
		inherited = ThemeDB.fallback_font_size
	var tooltip_theme := Theme.new()
	tooltip_theme.set_font_size("font_size", "TooltipLabel", maxi(6, roundi(inherited * 0.5)))
	if _text_font != null:
		tooltip_theme.set_font("font", "TooltipLabel", _text_font)
	theme = tooltip_theme


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
	# Clamp to the viewport so the popup cannot overflow on small base resolutions.
	var w := minf(POPUP_WIDTH, vs.x - 16.0)
	var h := minf(POPUP_HEIGHT, vs.y - 16.0)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.size = Vector2(w, h)
	_panel.position = Vector2(
		roundf((vs.x - w) * 0.5),
		roundf((vs.y - h) * 0.5))
	if _builds_panel != null:
		_builds_panel.layout(Rect2(_panel.position, _panel.size))


func _apply_font(control: Control, size: int) -> void:
	if _text_font != null:
		control.add_theme_font_override("font", _text_font)
	control.add_theme_font_size_override("font_size", size)


func _build_ui() -> void:
	_ensure_row_styles()
	_click_sound = UiSound.new()
	_click_sound.setup(self, _sound_path("click.ogg"))
	# Custom-drawn control (not a Button) so BTN_SIZE fully controls the size;
	# a Button clamps to its text + theme padding minimum.
	_button = WatchlistButton.new()
	_button.font = _text_font
	_button.font_size = BODY_FONT_SIZE
	_button.icon = _load_texture("../assets/icons/watchlist.png")
	_button.style_box = _build_hud_box()
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
	# Fully opaque background so the shop/bench cannot show through.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#18232D")
	panel_style.set_corner_radius_all(3)
	panel_style.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", panel_style)
	_popup.add_child(_panel)

	# Saved Builds is a separate modal layer over the popup, not a third tab.
	_builds_panel = SavedBuildsPanel.new()
	_builds_panel.setup(_text_font, _catalog_lookup, _play_click)
	_builds_panel.load_requested.connect(_on_build_load_requested)
	_popup.add_child(_builds_panel)

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

	var close_x := CloseButton.new()
	close_x.on_press = _toggle_popup
	# Keep it square inside the (taller) title row.
	close_x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(close_x)

	# Tabs
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	vbox.add_child(tab_row)
	for tab in [TAB_MONSTER, TAB_ITEM]:
		var b := Button.new()
		b.text = "Batomon" if tab == TAB_MONSTER else "Items"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
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
	# Index 0 is "All"; every other entry filters by its own label.
	_region_option = OptionButton.new()
	_region_option.focus_mode = Control.FOCUS_NONE
	for region_name in ["All"] + REGION_NAMES:
		_region_option.add_item(region_name)
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
	var tiers: Array = RARITY_BY_TIER.keys()
	tiers.sort()
	for tier in tiers:
		var rarity := str(RARITY_BY_TIER[tier])
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

	# Toolbar: one-time team snapshot, tracked count, and the Tracked Only view.
	_toolbar_box(vbox)

	# Subtle boundary between the toolbar and the scrollable list.
	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.12)
	divider.custom_minimum_size.y = 1
	vbox.add_child(divider)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_rows_box = GridContainer.new()
	_rows_box.columns = LIST_COLUMNS
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("h_separation", 4)
	_rows_box.add_theme_constant_override("v_separation", 1)
	scroll.add_child(_rows_box)

	# Initial state: Batomon tab, "All" filters.
	_sync_tab_buttons()
	_sync_tab_visibility()
	_sync_filter_buttons(_rarity_buttons, _rarity_filter)
	_sync_filter_buttons(_type_buttons, _type_filter)
	_sync_tracked_only_state()
	_update_save_button_state()


## Tools sitting directly above the list: Snapshot Team (Batomon tab only), the
## tracked count for the active tab, the saved-build actions, and the Tracked
## Only view toggle (kept on the far right).
func _toolbar_box(parent: Control) -> void:
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	parent.add_child(toolbar)

	_snapshot_button = Button.new()
	_snapshot_button.text = "Snapshot Team"
	_snapshot_button.tooltip_text = "Replaces your tracked Batomon with the ones currently fielded. Tracked items are kept."
	_snapshot_button.focus_mode = Control.FOCUS_NONE
	_snapshot_button.custom_minimum_size = Vector2(0, 8)
	_apply_font(_snapshot_button, BODY_FONT_SIZE)
	_style_action_button(_snapshot_button)
	_snapshot_button.pressed.connect(_on_snapshot_pressed)
	toolbar.add_child(_snapshot_button)

	_tracked_count_label = Label.new()
	_apply_font(_tracked_count_label, BODY_FONT_SIZE)
	toolbar.add_child(_tracked_count_label)

	_builds_button = Button.new()
	_builds_button.text = "Builds"
	_builds_button.tooltip_text = "Open your saved watchlist builds"
	_builds_button.focus_mode = Control.FOCUS_NONE
	_builds_button.custom_minimum_size = Vector2(0, 8)
	_apply_font(_builds_button, BODY_FONT_SIZE)
	_style_button(_builds_button)
	_builds_button.pressed.connect(_on_builds_pressed)
	toolbar.add_child(_builds_button)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.tooltip_text = "Save the current watchlist as a new build"
	_save_button.focus_mode = Control.FOCUS_NONE
	_save_button.custom_minimum_size = Vector2(0, 8)
	_apply_font(_save_button, BODY_FONT_SIZE)
	_style_save_button(_save_button)
	_save_button.pressed.connect(_on_save_pressed)
	toolbar.add_child(_save_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_tracked_only_check = CheckBox.new()
	_tracked_only_check.text = "Tracked Only"
	_tracked_only_check.tooltip_text = "Show only entries you are tracking"
	_tracked_only_check.focus_mode = Control.FOCUS_NONE
	_style_checkbox(_tracked_only_check)
	_tracked_only_check.toggled.connect(_on_tracked_only_toggled)
	toolbar.add_child(_tracked_only_check)


func _add_filter_button(parent: Control, text: String, value: String, store: Array, handler: Callable, color: Color = Color.TRANSPARENT) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 7)
	_apply_font(b, BODY_FONT_SIZE)
	_style_button(b, color)
	b.pressed.connect(handler.bind(value))
	parent.add_child(b)
	store.append({"button": b, "value": value})


## Action-button styling (Snapshot Team): muted red fill with a brighter red
## border, so it reads as an action rather than as another filter toggle.
func _style_action_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Style.ACTION_BG
	normal.border_color = Style.ACTION_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(1)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Style.ACTION_BG_HOVER
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Style.ACTION_BORDER
	for state in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, VALUE_COLOR)


## Save-button styling: the Snapshot Team treatment in muted green, with white
## text. The disabled state is dimmed so an empty watchlist reads as unavailable.
func _style_save_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Style.SAVE_BG
	normal.border_color = Style.SAVE_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(1)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Style.SAVE_BG_HOVER
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Style.SAVE_BORDER
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Style.SAVE_BG_DISABLED
	disabled.border_color = Style.SAVE_BG_DISABLED
	for state in ["normal", "focus"]:
		b.add_theme_stylebox_override(state, normal)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))


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


func _sync_tab_buttons() -> void:
	for entry in _tab_buttons:
		entry["button"].button_pressed = (entry["tab"] == _tab)


## Controls that only apply to the Batomon tab.
func _sync_tab_visibility() -> void:
	var monster_tab := (_tab == TAB_MONSTER)
	_filters_box.visible = monster_tab
	_snapshot_button.visible = monster_tab


## Compact checkbox with one empty stylebox in EVERY state. States must match:
## different styleboxes carry different content margins, which shifts the tick and
## the label on hover and whenever a toggled checkbox draws with `pressed`
## instead of `normal`.
func _style_checkbox(check: CheckBox) -> void:
	_ensure_row_styles()
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_constant_override("icon_max_width", 12)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		check.add_theme_stylebox_override(state, _blank_style)
	_apply_font(check, BODY_FONT_SIZE)


## Build the shared row styleboxes once. A full catalog rebuild would otherwise
## allocate one set per row (hundreds of resources per rebuild).
func _ensure_row_styles() -> void:
	if _blank_style != null:
		return
	_blank_style = StyleBoxEmpty.new()
	_row_style_a = StyleBoxFlat.new()
	_row_style_a.bg_color = Color("#1e2a36")
	_row_style_a.set_corner_radius_all(2)
	_row_style_a.set_content_margin_all(1)
	_row_style_b = _row_style_a.duplicate()
	_row_style_b.bg_color = Color("#18232D")
	_row_hover_style = StyleBoxFlat.new()
	_row_hover_style.bg_color = Color(1, 1, 1, 0.06)
	_row_hover_style.set_corner_radius_all(2)
	_row_pressed_style = StyleBoxFlat.new()
	_row_pressed_style.bg_color = Color(0.95, 0.61, 0.07, 0.22)
	_row_pressed_style.set_corner_radius_all(2)


func _toggle_popup() -> void:
	_popup_open = not _popup_open
	_popup.visible = _popup_open
	if _popup_open:
		_ensure_catalog()
		_position_panel()
		_sync_player_region()
		if _rows_dirty:
			_rebuild_rows()
	else:
		_close_builds_panel()


## Close the popup without toggling. Called when the shop overlay gate hides the
## reminder layer (shop exit, modal overlay, pause) so a stale modal cannot
## reappear on the next shop visit.
func close_popup() -> void:
	if not _popup_open:
		return
	_popup_open = false
	_popup.visible = false
	_close_builds_panel()


## While the popup is open it is modal: swallow keyboard input so the game's
## global hotkeys (R = reroll, etc.) cannot act on the shop behind it. Esc closes
## the Saved Builds layer first, then the popup, instead of opening the game's
## Settings menu.
func _input(event) -> void:
	if not _popup_open:
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _builds_panel != null and _builds_panel.is_open():
			_close_builds_panel()
		else:
			close_popup()
	get_viewport().set_input_as_handled()


func _on_tab_pressed(tab: String) -> void:
	_tab = tab
	_sync_tab_buttons()
	_sync_tab_visibility()
	_rebuild_rows()


func _on_rarity_pressed(value: String) -> void:
	_exit_tracked_only()
	_rarity_filter = value
	_sync_filter_buttons(_rarity_buttons, value)
	_rebuild_rows()


func _on_type_pressed(value: String) -> void:
	_exit_tracked_only()
	_type_filter = value
	_sync_filter_buttons(_type_buttons, value)
	_rebuild_rows()


## Tracked Only is an independent viewing mode: it shows every tracked entry for
## the active tab and ignores the Rarity/Type/Region filters. The filters keep
## their values and are dimmed while the mode is active.
func _on_tracked_only_toggled(on: bool) -> void:
	_tracked_only = on
	_sync_tracked_only_state()
	_rebuild_rows()


## Leave Tracked Only when the player picks a filter, then let the caller apply it.
func _exit_tracked_only() -> void:
	if not _tracked_only:
		return
	_tracked_only = false
	_sync_tracked_only_state()


func _sync_tracked_only_state() -> void:
	var dim := Color(1, 1, 1, 0.4) if _tracked_only else Color.WHITE
	if _filters_box != null:
		_filters_box.modulate = dim
	if _region_option != null:
		_region_option.modulate = dim
	if _tracked_only_check != null:
		_tracked_only_check.set_pressed_no_signal(_tracked_only)


## One-time capture: replaces tracked Batomon with the currently fielded team.
## Deliberately not a sync - later team changes leave the list alone. Active
## filters are ignored and tracked items are untouched. An empty team is a no-op
## so the list cannot be wiped by accident.
func _on_snapshot_pressed() -> void:
	var run = RunData.get_run_data()
	if run == null or not ("team" in run):
		return
	var team = run.get("team")
	if not (team is Array):
		return
	var keys := team_species_keys(team)
	if keys.is_empty():
		return
	var tracked := {}
	for key in keys:
		tracked[key] = true
	selection["monster"] = tracked
	_save_selection()
	_rebuild_rows()


## Unique species keys of a team array. Entries are MonsterInstance-like objects
## (or dictionaries) exposing `data.name_key`; empty slots and duplicate species
## are skipped.
static func team_species_keys(team: Array) -> Array:
	var keys: Array = []
	for monster in team:
		var data = _entry_field(monster, "data")
		if data == null:
			continue
		var raw_key = _entry_field(data, "name_key")
		if raw_key == null:
			continue
		var key := str(raw_key).strip_edges()
		if key.is_empty() or keys.has(key):
			continue
		keys.append(key)
	return keys


## Field lookup for game objects or dictionaries; null when missing or freed.
static func _entry_field(obj, field: String):
	if obj == null or not (obj is Object or obj is Dictionary):
		return null
	if obj is Object and not is_instance_valid(obj):
		return null
	if not (field in obj):
		return null
	return obj.get(field)


func _update_tracked_count() -> void:
	if _tracked_count_label != null:
		_tracked_count_label.text = "%d tracked" % selection.get(_tab, {}).size()
	_update_save_button_state()


## Save is only meaningful with something tracked. Counts both tabs, since a
## build always captures Batomon and items together.
func _update_save_button_state() -> void:
	if _save_button == null:
		return
	_save_button.disabled = _total_tracked() == 0


func _total_tracked() -> int:
	return selection.get("monster", {}).size() + selection.get("item", {}).size()


## Absolute path to a mod sound, resolved from this script's own directory so it
## works regardless of where the mod is installed.
func _sound_path(file_name: String) -> String:
	return str(get_script().resource_path).get_base_dir().path_join("../assets/sounds/" + file_name)


## Shared click feedback for the saved-build buttons. The Saved Builds panel gets
## this as a Callable so it does not need its own player.
func _play_click() -> void:
	if _click_sound != null:
		_click_sound.play()


## Save the whole watchlist (both tabs, ignoring filters and Tracked Only) as a
## new build. The active selection is never modified.
func _on_save_pressed() -> void:
	_play_click()
	var monsters: Array = selection.get("monster", {}).keys()
	var items: Array = selection.get("item", {}).keys()
	if monsters.is_empty() and items.is_empty():
		return
	var store := SavedBuilds.load_store()
	SavedBuilds.create_build(store, monsters, items, int(Time.get_unix_time_from_system()))
	if not SavedBuilds.save_store(store):
		return
	if _builds_panel != null:
		_builds_panel.refresh(store)


func _on_builds_pressed() -> void:
	_play_click()
	if _builds_panel == null:
		return
	if _builds_panel.is_open():
		_close_builds_panel()
		return
	# The preview needs catalog names/tiers/icons, so make sure it is loaded.
	_ensure_catalog()
	_builds_panel.open_panel(SavedBuilds.load_store())


func _close_builds_panel() -> void:
	if _builds_panel != null:
		_builds_panel.close_panel()


## Load replaces the tracked Batomon and items with the build's selections. The
## dictionaries are assigned into the existing `selection` dictionary, which
## shop_highlight shares by reference, so highlighting refreshes on the next
## frame without any notification. The fielded team and the saved build are
## untouched.
func _on_build_load_requested(build: Dictionary) -> void:
	var monsters := {}
	for key in build.get("monsters", []):
		monsters[str(key)] = true
	var items := {}
	for key in build.get("items", []):
		items[str(key)] = true
	selection["monster"] = monsters
	selection["item"] = items
	_save_selection()
	_rebuild_rows()
	_close_builds_panel()


## Catalog entry for a saved-build preview, or null when the id is unknown (e.g.
## a build saved before a catalog change). Unresolved ids still count as tracked.
func _catalog_lookup(kind: String, key: String):
	return _catalog_index.get("%s:%s" % [kind, key], null)


func _on_region_selected(index: int) -> void:
	_exit_tracked_only()
	_apply_region_index(index)
	_rebuild_rows()


## Defaults the Region dropdown to whatever region the run is being played in,
## appending it when REGION_NAMES does not list it. Only applied when the detected
## region changes, so a manual pick sticks for the rest of the run (a different
## detected region re-defaults). `OptionButton.select()` emits nothing.
func _sync_player_region() -> void:
	if _region_option == null:
		return
	var detected := str(RunRegion.detect().get("region", "")).strip_edges()
	if detected.is_empty() or detected == _applied_region:
		return
	_applied_region = detected
	var index := -1
	for i in range(_region_option.item_count):
		if str(_region_option.get_item_text(i)).to_lower() == detected.to_lower():
			index = i
			break
	if index < 0:
		_region_option.add_item(detected)
		index = _region_option.item_count - 1
	_region_option.select(index)
	_apply_region_index(index)


## Index 0 is "All"; every other entry filters by its own label.
func _apply_region_index(index: int) -> void:
	var next := "" if index == 0 else str(_region_option.get_item_text(index))
	if next != _region_filter:
		_region_filter = next
		_rows_dirty = true


## The catalog is loaded lazily so the GameDatabase autoload is guaranteed to
## exist (the mod may initialize before it).
func _ensure_catalog() -> void:
	if _catalog_loaded:
		return
	_load_catalog()
	# GameDatabase may not be ready on the first open; leave the flag unset so a
	# later open retries instead of caching an empty catalog for the session.
	if _catalog.is_empty():
		return
	_catalog_loaded = true
	_rebuild_type_buttons()
	_rows_dirty = true


func _load_catalog() -> void:
	_catalog.clear()
	_catalog_index.clear()
	_available_types.clear()
	var db = get_node_or_null("/root/GameDatabase")
	if db == null:
		return
	var seen := {}
	var type_set := {}
	_region_map = RunRegion.build_region_map(db)
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
			if display.strip_edges().is_empty() or _is_excluded_key(key):
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
			var entry := {
				"kind": "monster", "key": key, "name": display,
				"tier": tier, "types": types,
				"icon": icon if icon is Texture2D else null,
				"regions": _extract_regions(species),
			}
			_catalog.append(entry)
			_catalog_index["monster:" + key] = entry
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
				var entry := {
					"kind": "item", "key": key, "name": _display_name("item", key),
					"tier": tier, "types": [],
					"icon": icon if icon is Texture2D else null,
				}
				_catalog.append(entry)
				_catalog_index["item:" + key] = entry
	_available_types = type_set.keys()
	_available_types.sort()
	_catalog.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)


func _rebuild_type_buttons() -> void:
	# Keep the "All" button (index 0); rebuild the dynamic type buttons.
	while _type_buttons.size() > 1:
		var entry = _type_buttons.pop_back()
		entry["button"].queue_free()
	for type_name in _available_types:
		_add_filter_button(_type_flow, type_name, type_name, _type_buttons, _on_type_pressed, Style.type_color(type_name))
	_sync_filter_buttons(_type_buttons, _type_filter)


func _resolve_type(type_resource) -> String:
	if _formatter != null:
		return _formatter.resolve_type_name(type_resource)
	return ""


## Species carry no region field: the region is the set they belong to, resolved
## through `_region_map` (set id -> display name). Unmapped ids are used verbatim.
## A species can belong to several sets, so every mapped region is kept.
func _extract_regions(species) -> Array:
	var out: Array = []
	if not ("sets" in species):
		return out
	var sets = species.get("sets")
	if not (sets is Array):
		return out
	for set_entry in sets:
		var sid := ""
		if set_entry is String:
			sid = set_entry
		elif set_entry is Object and is_instance_valid(set_entry) and "id" in set_entry:
			sid = str(set_entry.get("id"))
		if sid.is_empty():
			continue
		var mapped := str(_region_map.get(sid.to_lower(), ""))
		var display := mapped if not mapped.is_empty() else sid
		if not out.has(display):
			out.append(display)
	return out


## Match the raw key against the exclusion list, not the translated display name.
## Splitting on non-alphanumeric characters keeps "eggplant" from matching "egg".
func _is_excluded_key(key: String) -> bool:
	var parts := key.to_lower().replace("_", " ").replace("-", " ").replace(".", " ").split(" ", false)
	for part in parts:
		if part in EXCLUDED_NAME_PARTS:
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
	_update_tracked_count()
	_rows_dirty = false
	var added := 0
	for entry in _catalog:
		if str(entry["kind"]) != _tab:
			continue
		var watched := is_watched(entry["kind"], entry["key"])
		# Tracked Only is a separate mode: show every tracked entry and ignore
		# the Rarity/Type/Region filters.
		if _tracked_only:
			if not watched:
				continue
		elif _tab == TAB_MONSTER and not _passes_monster_filters(entry):
			continue
		_add_entry_row(entry, added, watched)
		added += 1
	if added == 0:
		var empty_label := Label.new()
		if _tracked_only:
			empty_label.text = "Nothing tracked yet."
		elif _tab == TAB_MONSTER:
			empty_label.text = "No Batomon match these filters."
		else:
			empty_label.text = "No items match these filters."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size.x = POPUP_WIDTH - 24
		_apply_font(empty_label, BODY_FONT_SIZE)
		_rows_box.add_child(empty_label)


## One clickable entry: [icon] [name] [checkbox]. The whole row toggles tracking;
## alternating shades separate rows and a selected row gets an orange tint.
##
## The row is a PanelContainer (a real container, so it reports the content's
## minimum size to the GridContainer and lays its children out inside itself)
## with a transparent Button filling it to catch clicks. A plain Button would
## have zero width here and its unmanaged children would overlap their
## neighbours in the grid.
func _add_entry_row(entry: Dictionary, index: int, watched: bool) -> void:
	_ensure_row_styles()
	var shade := _row_style_a if (index / LIST_COLUMNS) % 2 == 0 else _row_style_b

	var row := PanelContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", shade)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 2)
	row.add_child(hbox)

	var icon_tex = entry.get("icon")
	if icon_tex is Texture2D:
		# Fixed-size holder + anchored rect: a container would reset the offsets,
		# but a plain Control keeps the nudge applied so the sprite lines up with
		# the name text instead of the row's centre.
		var icon_slot := Control.new()
		icon_slot.custom_minimum_size = Vector2(12, 12)
		icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon_slot)

		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_slot.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_top = -ICON_Y_OFFSET
		icon.offset_bottom = -ICON_Y_OFFSET

	var label := Label.new()
	label.text = str(entry["name"])
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(label, BODY_FONT_SIZE)
	hbox.add_child(label)

	# Fixed-size holder: a plain Control positions its child by anchors, so the
	# checkbox rect stays exactly 12x12 no matter which state icon it draws.
	# (Inside the HBox, a state change could otherwise resize the row.)
	var check_holder := Control.new()
	check_holder.custom_minimum_size = Vector2(12, 12)
	check_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(check_holder)

	var check := CheckBox.new()
	check.button_pressed = watched
	check.focus_mode = Control.FOCUS_NONE
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_checkbox(check)
	check_holder.add_child(check)
	check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Transparent hit area. PanelContainer stretches every Control child to fill
	# its content rect, so this Button covers the whole row.
	var hit := Button.new()
	hit.toggle_mode = true
	hit.button_pressed = watched
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	for state in ["normal", "focus", "disabled"]:
		hit.add_theme_stylebox_override(state, _blank_style)
	hit.add_theme_stylebox_override("hover", _row_hover_style)
	hit.add_theme_stylebox_override("pressed", _row_pressed_style)
	hit.add_theme_stylebox_override("hover_pressed", _row_pressed_style)
	hit.toggled.connect(_on_entry_toggled.bind(entry["kind"], entry["key"]))
	hit.toggled.connect(func(on): check.button_pressed = on)
	row.add_child(hit)

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
		var filter := _region_filter.to_lower()
		var matched := false
		for region in entry.get("regions", []):
			if str(region).to_lower().contains(filter):
				matched = true
				break
		if not matched:
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
	if _tracked_only:
		# Visible rows and the count both follow the selection; deferred so the row
		# that emitted this signal can be freed safely.
		_rebuild_rows.call_deferred()
	else:
		_update_tracked_count()


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
	# The mod's user directory is created later in mod_main, so make sure it
	# exists before the first save (e.g. a toggle before the first shop poll).
	var abs_dir := ProjectSettings.globalize_path(CFG_PATH.get_base_dir())
	var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("Creature Comforts: cannot create watchlist directory %s: %s" % [abs_dir, error_string(dir_err)])
		return
	var save_err := cfg.save(CFG_PATH)
	if save_err != OK:
		push_warning("Creature Comforts: cannot save watchlist to %s: %s" % [CFG_PATH, error_string(save_err)])


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


## Close (X) button mirroring the rank-odds popup: a gold rounded box with dark
## arms drawn straight onto the canvas, so both popups read as the same widget.
class CloseButton extends Control:
	const Style = preload("../core/style.gd")
	const SIZE := 14.0     # matches rank_odds_panel.CLOSE_BTN
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


## Small self-drawn button. A plain Control has no content minimum, so its size
## is exactly BTN_SIZE (unlike a Button, which clamps to text + theme padding).
class WatchlistButton extends Control:
	const Style = preload("../core/style.gd")
	const ICON_PADDING := 2.0
	var font: Font
	var font_size := 7
	var icon: Texture2D
	# Rounded HUD box supplied by the owning panel (comfort_panel._build_hud_box),
	# so this button matches the rank-odds and income widgets.
	var style_box: StyleBoxFlat
	var on_press: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "Watchlist"

	func _draw() -> void:
		if style_box != null:
			style_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		if icon != null:
			var tex_size := icon.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				# Same inset the rank-odds icon uses, so the rounded border shows.
				var box := Vector2(
					maxf(size.x - ICON_PADDING * 2.0, 1.0),
					maxf(size.y - ICON_PADDING * 2.0, 1.0))
				var draw_size := tex_size * minf(box.x / tex_size.x, box.y / tex_size.y)
				draw_texture_rect(icon, Rect2((size - draw_size) * 0.5, draw_size), false)
				return
		if font != null:
			# Fallback when the asset is missing (e.g. an incomplete install).
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
