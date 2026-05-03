extends Control
## Modal pause menu opened with Esc. 5 tabs: Game / Audio / Video / Hotkeys / Admin.
## Replaces the old AdminPanel (F1) and the side-of-screen KeybindsOverlay.

const TAB_GAME: int = 0
const TAB_INVENTORY: int = 1
const TAB_AUDIO: int = 2
const TAB_VIDEO: int = 3
const TAB_HOTKEYS: int = 4
const TAB_ADMIN: int = 5

const SLOT_SIZE: Vector2 = Vector2(64, 64)
const ITEM_COLORS: Dictionary = {
	0: Color(0.6, 0.6, 0.6), 1: Color(0.7, 0.35, 0.25), 2: Color(0.4, 0.4, 0.4),
	3: Color(0.55, 0.4, 0.3), 4: Color(0.7, 0.7, 0.75), 5: Color(0.85, 0.85, 0.9),
	6: Color(0.7, 0.6, 0.2), 7: Color(0.95, 0.8, 0.3), 8: Color(1.0, 0.85, 0.4),
}
const ITEM_ICONS: Dictionary = {
	0: "res://assets/icons/factory/item_stone.svg",
	1: "res://assets/icons/factory/item_brick.svg",
	2: "res://assets/icons/factory/item_block.svg",
	3: "res://assets/icons/factory/item_iron_ore.svg",
	4: "res://assets/icons/factory/item_iron_ingot.svg",
	5: "res://assets/icons/factory/item_iron_bar.svg",
	6: "res://assets/icons/factory/item_gold_ore.svg",
	7: "res://assets/icons/factory/item_gold_ingot.svg",
	8: "res://assets/icons/factory/item_gold_bar.svg",
}
# Mapping each material_id -> the Miner field name that stores its count
const MATERIAL_TO_MINER_FIELD: Dictionary = {
	0: "stone", 1: "brick", 2: "block",
	3: "iron", 4: "iron_ingot", 5: "iron_bar",
	6: "gold", 7: "gold_ingot", 8: "gold_bar",
}
static var _icon_texture_cache: Dictionary = {}

static func _icon_for(material_id: int) -> Texture2D:
	if _icon_texture_cache.has(material_id):
		return _icon_texture_cache[material_id]
	if not ITEM_ICONS.has(material_id):
		return null
	var tex: Texture2D = load(ITEM_ICONS[material_id]) as Texture2D
	_icon_texture_cache[material_id] = tex
	return tex

const KEYBINDS_TEXT: String = "WASD          move
Space            jump
LMB              mine / place / link
Esc                menu / cancel
F1                  admin (menu)
B                    build mode
1                    Loader
2                    Smelter
3                    Forge
4                    Belt link
5                    Merger
6                    Splitter
R / wheel    rotate ghost
X + LMB     remove
E                    machine menu / close menu"

@onready var _tabs: TabContainer = $Panel/Vbox/Tabs
@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn

func _ready() -> void:
	visible = false
	add_to_group("pause_menu")
	_close_btn.pressed.connect(close)
	_build_game_tab()
	_build_inventory_tab()
	_build_audio_tab()
	_build_video_tab()
	_build_hotkeys_tab()
	_build_admin_tab()

func toggle() -> void:
	if visible:
		close()
	else:
		open(TAB_GAME)

func open(tab_index: int = TAB_GAME) -> void:
	_tabs.current_tab = tab_index
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_admin_tab()
	_refresh_inventory_tab()
	# Subscribe to live inventory updates while the menu is open
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		if miner.has_signal("inventory_changed") and not miner.inventory_changed.is_connected(_on_inventory_changed):
			miner.inventory_changed.connect(_on_inventory_changed)
		if miner.has_signal("extended_inventory_changed") and not miner.extended_inventory_changed.is_connected(_refresh_inventory_tab):
			miner.extended_inventory_changed.connect(_refresh_inventory_tab)

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		if miner.has_signal("inventory_changed") and miner.inventory_changed.is_connected(_on_inventory_changed):
			miner.inventory_changed.disconnect(_on_inventory_changed)
		if miner.has_signal("extended_inventory_changed") and miner.extended_inventory_changed.is_connected(_refresh_inventory_tab):
			miner.extended_inventory_changed.disconnect(_refresh_inventory_tab)

func _on_inventory_changed(_s: int, _i: int, _g: int) -> void:
	_refresh_inventory_tab()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		accept_event()

# ---- Tab content builders ----------------------------------------------------

func _placeholder_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68, 1))
	lbl.add_theme_font_size_override("font_size", 18)
	return lbl

func _build_game_tab() -> void:
	$Panel/Vbox/Tabs/Game.add_child(_placeholder_label("Coming soon"))

# ---- Inventory tab ----------------------------------------------------------

var _inventory_slots: Dictionary = {}   # material_id -> Panel

func _build_inventory_tab() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.add_theme_constant_override("separation", 10)
	$Panel/Vbox/Tabs/Inventory.add_child(box)
	var rows: Array = [
		["T1  —  Mined ore", [MaterialDefs.MaterialId.STONE, MaterialDefs.MaterialId.IRON_ORE, MaterialDefs.MaterialId.GOLD_ORE]],
		["T2  —  Smelted",   [MaterialDefs.MaterialId.BRICK, MaterialDefs.MaterialId.IRON_INGOT, MaterialDefs.MaterialId.GOLD_INGOT]],
		["T3  —  Forged",    [MaterialDefs.MaterialId.BLOCK, MaterialDefs.MaterialId.IRON_BAR, MaterialDefs.MaterialId.GOLD_BAR]],
	]
	for row: Array in rows:
		var header: Label = Label.new()
		header.text = row[0]
		header.add_theme_font_size_override("font_size", 14)
		header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
		box.add_child(header)
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		box.add_child(hbox)
		for mid: int in row[1]:
			var entry: VBoxContainer = VBoxContainer.new()
			entry.add_theme_constant_override("separation", 2)
			var slot: Panel = _make_inventory_slot(mid, 0)
			_inventory_slots[mid] = slot
			entry.add_child(slot)
			var name_lbl: Label = Label.new()
			name_lbl.text = MaterialDefs.DISPLAY_NAME[mid]
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.custom_minimum_size = Vector2(SLOT_SIZE.x + 12, 0)
			name_lbl.add_theme_font_size_override("font_size", 12)
			name_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85, 1))
			entry.add_child(name_lbl)
			hbox.add_child(entry)

func _refresh_inventory_tab() -> void:
	if _inventory_slots.is_empty():
		return
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		return
	for mid: int in _inventory_slots:
		var field: String = MATERIAL_TO_MINER_FIELD.get(mid, "")
		var count: int = miner.get(field) if field != "" else 0
		var slot: Panel = _inventory_slots[mid]
		_update_slot_count(slot, count)

func _make_inventory_slot(material_id: int, count: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	# Dim material-color fill
	var fill: ColorRect = ColorRect.new()
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 4
	fill.offset_top = 4
	fill.offset_right = -4
	fill.offset_bottom = -4
	var c: Color = ITEM_COLORS.get(material_id, Color.WHITE)
	fill.color = Color(c.r * 0.30, c.g * 0.30, c.b * 0.30, 1)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	# Icon
	var tex: Texture2D = _icon_for(material_id)
	if tex != null:
		var icon: TextureRect = TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
	# Count overlay
	var lbl: Label = Label.new()
	lbl.name = "CountLabel"
	lbl.text = str(count)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.anchor_left = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = -32
	lbl.offset_top = -22
	lbl.offset_right = -3
	lbl.offset_bottom = -3
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel

func _update_slot_count(slot: Panel, count: int) -> void:
	var lbl: Label = slot.get_node_or_null("CountLabel") as Label
	if lbl != null:
		lbl.text = str(count)
		lbl.modulate = Color(1, 1, 1, 1) if count > 0 else Color(0.55, 0.6, 0.65, 1)

func _build_audio_tab() -> void:
	$Panel/Vbox/Tabs/Audio.add_child(_placeholder_label("Coming soon"))

func _build_video_tab() -> void:
	$Panel/Vbox/Tabs/Video.add_child(_placeholder_label("Coming soon"))

func _build_hotkeys_tab() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.add_theme_constant_override("separation", 4)
	$Panel/Vbox/Tabs/Hotkeys.add_child(box)
	var header: Label = Label.new()
	header.text = "KEYBINDS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	box.add_child(header)
	var body: Label = Label.new()
	body.text = KEYBINDS_TEXT
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)

# ---- Admin tab (replaces old AdminPanel) ------------------------------------

var _admin_no_stamina_btn: CheckButton
var _admin_noclip_btn: CheckButton
var _admin_fast_speed_btn: CheckButton
var _admin_speed_slider: HSlider
var _admin_speed_label: Label
var _admin_fast_damage_btn: CheckButton
var _admin_damage_slider: HSlider
var _admin_damage_label: Label
var _admin_big_radius_btn: CheckButton
var _admin_radius_slider: HSlider
var _admin_radius_label: Label

func _build_admin_tab() -> void:
	var v: VBoxContainer = VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.add_theme_constant_override("separation", 6)
	$Panel/Vbox/Tabs/Admin.add_child(v)

	_admin_no_stamina_btn = CheckButton.new()
	_admin_no_stamina_btn.text = "No stamina"
	_admin_no_stamina_btn.toggled.connect(func(on: bool) -> void: Admin.no_stamina = on)
	v.add_child(_admin_no_stamina_btn)

	_admin_noclip_btn = CheckButton.new()
	_admin_noclip_btn.text = "Noclip / fly (Space=up, Shift=down)"
	_admin_noclip_btn.toggled.connect(func(on: bool) -> void: Admin.noclip = on)
	v.add_child(_admin_noclip_btn)

	_admin_fast_speed_btn = CheckButton.new()
	_admin_fast_speed_btn.text = "Fast mining speed"
	_admin_fast_speed_btn.toggled.connect(func(on: bool) -> void: Admin.fast_speed = on)
	v.add_child(_admin_fast_speed_btn)
	v.add_child(_make_slider_row("speed"))

	_admin_fast_damage_btn = CheckButton.new()
	_admin_fast_damage_btn.text = "Fast mining damage"
	_admin_fast_damage_btn.toggled.connect(func(on: bool) -> void: Admin.fast_damage = on)
	v.add_child(_admin_fast_damage_btn)
	v.add_child(_make_slider_row("damage"))

	_admin_big_radius_btn = CheckButton.new()
	_admin_big_radius_btn.text = "Big dig radius"
	_admin_big_radius_btn.toggled.connect(func(on: bool) -> void: Admin.big_radius = on)
	v.add_child(_admin_big_radius_btn)
	v.add_child(_make_slider_row("radius"))

	# Give resources row
	var sep: HSeparator = HSeparator.new()
	v.add_child(sep)
	var give_label: Label = Label.new()
	give_label.text = "Give resources (+100):"
	give_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	v.add_child(give_label)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for entry: Array in [
		["Stone", MaterialDefs.MaterialId.STONE],
		["Iron Ore", MaterialDefs.MaterialId.IRON_ORE],
		["Gold Ore", MaterialDefs.MaterialId.GOLD_ORE],
	]:
		var btn: Button = Button.new()
		btn.text = entry[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_give.bind(entry[1]))
		row.add_child(btn)

func _make_slider_row(kind: String) -> HBoxContainer:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var slider: HSlider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl: Label = Label.new()
	lbl.custom_minimum_size = Vector2(60, 0)
	if kind == "speed":
		slider.min_value = 1.0
		slider.max_value = 10.0
		slider.step = 0.5
		slider.value = Admin.speed_multiplier
		_admin_speed_slider = slider
		_admin_speed_label = lbl
		slider.value_changed.connect(func(v: float) -> void:
			Admin.speed_multiplier = v
			_admin_speed_label.text = "x%.1f" % v
		)
		lbl.text = "x%.1f" % Admin.speed_multiplier
	elif kind == "damage":
		slider.min_value = 1.0
		slider.max_value = 300.0
		slider.step = 1.0
		slider.value = Admin.damage_multiplier
		_admin_damage_slider = slider
		_admin_damage_label = lbl
		slider.value_changed.connect(func(v: float) -> void:
			Admin.damage_multiplier = v
			_admin_damage_label.text = "x%d" % int(v)
		)
		lbl.text = "x%d" % int(Admin.damage_multiplier)
	elif kind == "radius":
		slider.min_value = 1.0
		slider.max_value = 20.0
		slider.step = 0.5
		slider.value = Admin.radius_multiplier
		_admin_radius_slider = slider
		_admin_radius_label = lbl
		slider.value_changed.connect(func(v: float) -> void:
			Admin.radius_multiplier = v
			_admin_radius_label.text = "x%.1f" % v
		)
		lbl.text = "x%.1f" % Admin.radius_multiplier
	hbox.add_child(slider)
	hbox.add_child(lbl)
	return hbox

func _refresh_admin_tab() -> void:
	if _admin_no_stamina_btn == null:
		return
	_admin_no_stamina_btn.button_pressed = Admin.no_stamina
	_admin_noclip_btn.button_pressed = Admin.noclip
	_admin_fast_speed_btn.button_pressed = Admin.fast_speed
	_admin_fast_damage_btn.button_pressed = Admin.fast_damage
	_admin_big_radius_btn.button_pressed = Admin.big_radius
	_admin_speed_slider.value = Admin.speed_multiplier
	_admin_damage_slider.value = Admin.damage_multiplier
	_admin_radius_slider.value = Admin.radius_multiplier

func _give(material_id: int) -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		push_warning("PauseMenu: no player_miner found")
		return
	miner.add_factory_material(material_id, 100)
