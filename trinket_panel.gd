extends PanelContainer
## TrinketPanel - Collapsible panel displaying owned trinkets in shop
## Positioned below ReminderLabel, shows trinket counts sorted by quantity
## Each trinket line carries a compact effect description via tooltip on hover.

## TrinketDescriptions - Catalog of trinket summaries for display
## Maps trinket IDs to compact effect descriptions
## Trinket ID → compact summary mapping
## IDs are snake_case runtime identifiers (e.g., "fire_bell", "gold_trophy")
const DESCRIPTIONS := {
	"alpha_crown": "Battle start: team matches top-middle damage this battle.",
	"ancient_plume": "Battle start, solo monster: +1 multicast permanently; consumes trinket.",
	"arcade_coins": "+10 free rerolls.",
	"barbell": "+5,000 HP.",
	"bargain_bin": "First Common monster bought each day is free.",
	"blitz_bell": "Shop monsters: +25% CD speed.",
	"blue_incense": "Next 5 shops: Rare monsters only.",
	"boxing_glove": "Victory: team +5 damage permanently.",
	"bug_net": "Shop Bug monsters cost 3 gold less.",
	"candy_jar": "Battle start: your Common/Uncommon monsters reach Lv3 permanently.",
	"dryad_charm": "+30% HP.",
	"earth_crest": "Battle start: right column +10% shield permanently.",
	"echo_bell": "Zero-cost item purchases activate once more.",
	"echo_charm": "Your monsters' On Bought abilities activate once more.",
	"excalibur": "Team +350 damage.",
	"fake_diamond": "Next defeat: +40 gold.",
	"fancy_sword": "Team +3% damage per owned trinket.",
	"fire_bell": "Shop Fire monsters: +5 burn.",
	"fire_orb": "Your Fire monsters: +3 burn.",
	"fool_gold": "Income +15 gold; shops stop stocking items.",
	"giant_club": "Monsters with CD >=5s: +70% stats, except CD/multicast.",
	"gold_bar": "Income +10 gold.",
	"gold_bracelet": "Day start: random monster +8 sell value.",
	"gold_incense": "Next 5 shops: Legendary monsters only.",
	"gold_nugget": "Income +3 gold.",
	"gold_trophy": "Victory: +8 gold.",
	"gold_o_matic": "Income +30 gold.",
	"greedy_gloves": "Next trinket gift: take every option.",
	"grow_lamp": "Your Grass monsters level up with 2 copies.",
	"haste_crown": "Top-middle: +20% CD speed.",
	"haste_orb": "Team +10% CD speed.",
	"hero_sword": "Team +12 damage.",
	"holy_grail": "Victory: +100 gold.",
	"junk": "No effect.",
	"kaleidoscope": "Monsters sharing no type with allies: +25% CD speed.",
	"link_cable": "All teammates count as adjacent.",
	"locked_box": "Next defeat: random non-unique trinket of your shop rank's highest rarity.",
	"market_license": "Shop rank +1.",
	"master_crown": "Top-middle: +80% stats, except CD/multicast.",
	"mega_duplicator": "Next non-unique gift trinket: +2 copies.",
	"mega_upgrade_disc": "Monster reaches Lv3: +1 level; consumes trinket.",
	"membership_card": "+1 item use per day.",
	"metal_bat": "Battle start: highest-CD monster +50% damage this battle.",
	"meteorite": "Battle start: abilityless monsters +20 damage permanently.",
	"metronome": "Each cast: caster +10 damage this battle.",
	"mighty_bell": "Shop monsters: +300 damage.",
	"mini_duplicator": "Next non-unique gift trinket: +1 copy.",
	"momentum_flag": "Battle start: left column +8% CD speed permanently.",
	"mysterious_charm": "+25% HP.",
	"mysterious_chest": "Defeat: random non-unique Legendary trinket.",
	"mysterious_gem": "Team +20% damage.",
	"mysterious_mask": "Choose a trainer; gain their ability.",
	"mystic_incense": "Next shop includes a Mythical monster.",
	"piggy_bank": "Day end: +1 gold per 10 gold held.",
	"poison_bell": "Shop Toxic monsters: +6 poison.",
	"poison_orb": "Your Toxic monsters: +3 poison.",
	"power_band": "First monster bought each day: +20 damage.",
	"power_bell": "Shop monsters: +25 damage.",
	"power_crown": "Top-middle: +20 damage.",
	"power_pouch": "Buy an item: team +2 damage.",
	"purple_incense": "Next 5 shops: Super Rare monsters only.",
	"quick_bell": "Shop monsters: +4% CD speed.",
	"quick_flag": "Left column: +4% CD speed.",
	"rainbow_berry": "Team +4 damage per distinct team type.",
	"rainbow_pearl": "All shop monsters are shiny.",
	"rally_flag": "Battle start: left column +12 damage permanently.",
	"razor_beak": "Your Flying monsters: +1 multicast.",
	"repeater_charm": "Your monsters' On Battle Start abilities activate once more.",
	"research_notes": "Legendary monsters appear much more often in shops.",
	"rigged_dice": "First shop each day: only highest-rarity monsters/items allowed by rank.",
	"rocket_boots": "Shop monsters gain Flying type.",
	"sapphire_amulet": "+25% healing received.",
	"sapphire_ring": "Shop monsters: +10% heal.",
	"scrap_sword": "Team +2 damage per owned Common trinket.",
	"sea_crest": "Battle start: right column +10% heal permanently.",
	"silver_watch": "Merge level-up: that monster +12% CD speed.",
	"small_club": "Monsters with CD >=5s: +20% damage.",
	"speed_crest": "Right column: +15% CD speed.",
	"speed_whistle": "Next monster bought: +12% CD speed.",
	"tempo_charm": "Battle start: random monster +4% CD speed permanently.",
	"terrarium": "Your Bug monsters: +20% damage.",
	"topaz_amulet": "+25% shielding received.",
	"topaz_ring": "Shop monsters: +10% shield.",
	"training_weights": "+100 HP.",
	"treasure_map": "Next trinket gift: options gain 1 rarity tier.",
	"ultra_duplicator": "Each non-unique gift trinket: +1 copy.",
	"upgrade_disc": "Next monster bought: +1 level; consumes trinket.",
	"vip_pass": "Shops exclude Common/Uncommon stock.",
	"warhorn": "Battle start: team +10 damage permanently.",
	"winged_crown": "Top-middle: +1 multicast.",
	"winged_fossil": "Your Flying monsters: +25% stats, except CD/multicast.",
	"wood_sword": "Team +5 damage.",
	"zenith_stone": "Stat gains +80%; excludes multicast and percentage bonuses.",
}

signal minimized_changed(minimized: bool)

const HEADER_HEIGHT := 15.0
const BUTTON_SIZE := 11.0
const LINE_HEIGHT := 10.0
const FONT_SIZE := 8
const ANIM_SEC := 0.14
const DRAG_THRESHOLD := 3.0

const BG_COLOR := Color("#1a2332")  # Dark navy
const HEADER_COLOR := Color("#2c3e50")  # Darker blue-grey
const BORDER_COLOR := Color("#3498db")  # Blue
const TEXT_COLOR := Color("#ecf0f1")  # Light grey
const SHADOW_COLOR := Color("#2c3e50")
const INK_COLOR := Color("#ecf0f1")

const TOP_MARGIN := 18.0  # Below reminder label
const LEFT_MARGIN := 55.0  # Aligned with reminder label
const MIN_PANEL_WIDTH := 150.0
const FALLBACK_VIEWPORT_WIDTH := 480.0
const RIGHT_MARGIN := 4.0  # Gap kept between panel and viewport edge
const TEXT_PADDING := 16.0  # Left inset + shadow + right breathing room
const MAX_VISIBLE_LINES := 10  # Maximum trinkets to show before scrolling

var minimized := false
var reveal := 1.0  # 1 = expanded, 0 = minimized (animated)
var _panel_width := MIN_PANEL_WIDTH  # Fits the widest line, clamped to viewport
var _trinket_entries: Array = []  # Array of {name: String, count: int}
var _panel_style: StyleBoxFlat
var _header_style: StyleBoxFlat

var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _drag_off := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	
	# Create panel background style
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(2)
	_panel_style.set_content_margin_all(2)
	add_theme_stylebox_override("panel", _panel_style)
	
	# Create header style
	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = HEADER_COLOR
	_header_style.set_corner_radius_all(2)
	
	# Position below reminder label
	position = Vector2(LEFT_MARGIN, TOP_MARGIN)
	custom_minimum_size = Vector2(_panel_width, HEADER_HEIGHT + 1)
	
	_apply_size()


func set_trinkets(trinket_ids: Array) -> void:
	"""Update trinket display from array of trinket ID strings."""
	# Count occurrences of each trinket
	var trinket_counts: Dictionary = {}
	for trinket_id in trinket_ids:
		var id_str := str(trinket_id)
		if trinket_counts.has(id_str):
			trinket_counts[id_str] += 1
		else:
			trinket_counts[id_str] = 1
	
	# Convert to array of entries with translated names and descriptions
	_trinket_entries.clear()
	for trinket_id in trinket_counts.keys():
		var display_name := _translate_trinket_name(trinket_id)
		var description := _trinket_description(str(trinket_id))
		_trinket_entries.append({
			"id": str(trinket_id),
			"name": display_name,
			"description": description,
			"count": trinket_counts[trinket_id]
		})
	
	# Sort by count (descending), then alphabetically
	_trinket_entries.sort_custom(func(a, b):
		if a.count != b.count:
			return a.count > b.count
		return a.name < b.name
	)
	
	# Show/hide panel based on trinket count
	if _trinket_entries.is_empty():
		visible = false
	else:
		visible = true
		_update_panel_width()
		_apply_size()
		queue_redraw()


func _line_text(entry: Dictionary) -> String:
	"""Build the display line: [count] Name - Description."""
	if entry.description.is_empty():
		return "[%d] %s" % [entry.count, entry.name]
	return "[%d] %s - %s" % [entry.count, entry.name, entry.description]


func _max_panel_width() -> float:
	"""Widest allowed panel: from its left edge to the viewport's right edge."""
	var viewport_width := FALLBACK_VIEWPORT_WIDTH
	if is_inside_tree():
		viewport_width = get_viewport_rect().size.x
	return maxf(MIN_PANEL_WIDTH, viewport_width - position.x - RIGHT_MARGIN)


func _update_panel_width() -> void:
	"""Resize panel to fit the longest trinket line, clamped to the viewport."""
	var font := get_theme_default_font()
	var widest := 0.0
	for entry in _trinket_entries:
		var line_w := font.get_string_size(_line_text(entry), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		widest = maxf(widest, line_w)
	_panel_width = clampf(widest + TEXT_PADDING, MIN_PANEL_WIDTH, _max_panel_width())


func _translate_trinket_name(trinket_id: String) -> String:
	"""Translate trinket ID to display name, fallback to ID if translation unavailable."""
	# Try translation key pattern: "item.name.{trinket_id}"
	var translation_key := "item.name.%s" % trinket_id
	
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(translation_key)
		if translated != translation_key:
			return translated
	
	# Fallback: capitalize the ID
	return trinket_id.capitalize()


func _trinket_description(trinket_id: String) -> String:
	"""Return the compact effect description for a trinket ID, or empty string."""
	if DESCRIPTIONS.has(trinket_id):
		return DESCRIPTIONS[trinket_id]
	return ""


func full_height() -> float:
	"""Calculate full expanded height based on trinket count."""
	if _trinket_entries.is_empty():
		return HEADER_HEIGHT + 1
	
	var line_count := mini(_trinket_entries.size(), MAX_VISIBLE_LINES)
	return HEADER_HEIGHT + 4 + (line_count * LINE_HEIGHT) + 4


func _apply_size() -> void:
	var target_height := lerpf(HEADER_HEIGHT + 1, full_height(), reveal)
	custom_minimum_size = Vector2(_panel_width, target_height)
	size = Vector2(_panel_width, target_height)


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
		_tween = create_tween().set_ignore_time_scale(true)
		_tween.tween_method(func(v: float):
			reveal = v
			_apply_size()
			queue_redraw(), reveal, target, ANIM_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	minimized_changed.emit(on)


func toggle() -> void:
	set_minimized(not minimized)


func _button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 8 - BUTTON_SIZE - 2, 2), Vector2(BUTTON_SIZE, BUTTON_SIZE))


func _draw() -> void:
	var ci := get_canvas_item()
	var w := size.x
	
	# Draw header background
	_header_style.draw(ci, Rect2(Vector2(2, 2), Vector2(w - 4, HEADER_HEIGHT)))
	
	# Draw header text
	var total_count := 0
	for entry in _trinket_entries:
		total_count += entry.count
	
	var header_text := "Trinkets (%d)" % total_count
	var font := get_theme_default_font()
	var font_size := FONT_SIZE
	
	# Draw header text with shadow
	var text_pos := Vector2(10, 11)
	draw_string(font, text_pos + Vector2(1, 1), header_text, HORIZONTAL_ALIGNMENT_LEFT, w - 30, font_size, SHADOW_COLOR)
	draw_string(font, text_pos, header_text, HORIZONTAL_ALIGNMENT_LEFT, w - 30, font_size, TEXT_COLOR)
	
	# Draw toggle button
	var btn := _button_rect()
	draw_rect(btn, HEADER_COLOR)
	draw_rect(Rect2(btn.position, Vector2(btn.size.x, 1)), BORDER_COLOR)
	draw_rect(Rect2(btn.position, Vector2(1, btn.size.y)), BORDER_COLOR)
	draw_rect(Rect2(btn.position + Vector2(btn.size.x - 1, 0), Vector2(1, btn.size.y)), BORDER_COLOR)
	draw_rect(Rect2(btn.position + Vector2(0, btn.size.y - 1), Vector2(btn.size.x, 1)), BORDER_COLOR)
	
	# Draw +/- symbol
	var c := btn.get_center().floor()
	draw_rect(Rect2(c.x - 3, c.y, 6, 1), INK_COLOR)
	if minimized:
		draw_rect(Rect2(c.x, c.y - 3, 1, 7), INK_COLOR)
	
	# Draw body content if expanded
	if reveal > 0.01 and not _trinket_entries.is_empty():
		var y_offset := HEADER_HEIGHT + 6
		var visible_count := mini(_trinket_entries.size(), MAX_VISIBLE_LINES)
		
		for i in range(visible_count):
			var entry = _trinket_entries[i]
			var line_text := _line_text(entry)
			var line_pos := Vector2(6, y_offset + (i * LINE_HEIGHT))
			
			# Draw with shadow
			draw_string(font, line_pos + Vector2(1, 1), line_text, HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, SHADOW_COLOR)
			draw_string(font, line_pos, line_text, HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, TEXT_COLOR)
		
		# Draw "..." if more trinkets exist
		if _trinket_entries.size() > MAX_VISIBLE_LINES:
			var more_pos := Vector2(6, y_offset + (visible_count * LINE_HEIGHT))
			draw_string(font, more_pos + Vector2(1, 1), "...", HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, SHADOW_COLOR)
			draw_string(font, more_pos, "...", HORIZONTAL_ALIGNMENT_LEFT, w - 12, font_size, TEXT_COLOR)


func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEADER_HEIGHT + 1:
				return  # Body click, ignore
			_pressing = true
			_dragged = false
			_press_pos = event.position
			_drag_off = event.position
		elif _pressing:
			_pressing = false
			if _dragged:
				# Dragging complete, don't toggle
				pass
			else:
				toggle()
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		if not _dragged and event.position.distance_to(_press_pos) >= DRAG_THRESHOLD:
			_dragged = true
		if _dragged:
			position += event.position - _drag_off
		accept_event()
