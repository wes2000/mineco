extends Control
## Inventory popup shown while Tab is held. Centered translucent panel —
## three sections stacked: the 3×3 material grid (T1/T2/T3 × Stone/Iron/Gold),
## currently-equipped shop items, and a live readout of the most player-
## visible PlayerStats values. Mouse stays captured so the player can keep
## moving while peeking.

const _ShopDefs: GDScript = preload("res://scripts/shop_item_defs.gd")

const SLOT_SIZE: Vector2 = Vector2(36, 36)
const EQUIP_SLOT_SIZE: Vector2 = Vector2(40, 40)

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

var _panel: Panel = null
var _slots: Dictionary = {}   # material_id -> Panel
var _equipped_row: HBoxContainer = null
var _stats_grid: GridContainer = null

# Stats shown in the character panel. Each entry: (PlayerStats key, label,
# format hint). format hint: "mult" → shows "+12%" deviation from 1.0,
# "bonus" → shows "+N" raw add, "max_with_base" → uses cached base from
# Stamina (special-cased below).
const STATS_DISPLAY: Array = [
	[&"mining_damage_mult",      "Mining damage",   "mult"],
	[&"mining_swing_speed_mult", "Swing speed",     "mult"],
	[&"dig_radius_mult",         "Dig radius",      "mult"],
	[&"sprint_speed_mult",       "Sprint speed",    "mult"],
	[&"stamina_max_bonus",       "Stamina bonus",   "bonus"],
	[&"stamina_regen_mult",      "Stamina regen",   "mult"],
	[&"scanner_range_mult",      "Scanner range",   "mult"],
	[&"scanner_ping_speed_mult", "Scanner ping",    "mult"],
	[&"sell_value_mult",         "Sell value",      "mult"],
	[&"contract_reward_mult",    "Contract reward", "mult"],
	[&"factory_speed_mult",      "Factory speed",   "mult"],
	[&"boat_speed_mult",         "Boat speed",      "mult"],
	[&"pickup_radius_bonus",     "Pickup radius",   "bonus"],
]

func _ready() -> void:
	visible = false
	add_to_group("inventory_overlay")
	_build_panel()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_overlay"):
		_show_overlay()
	elif event.is_action_released("inventory_overlay"):
		_hide_overlay()

func _show_overlay() -> void:
	visible = true
	_refresh()
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		if miner.has_signal("inventory_changed") and not miner.inventory_changed.is_connected(_on_inv_changed):
			miner.inventory_changed.connect(_on_inv_changed)
		if miner.has_signal("extended_inventory_changed") and not miner.extended_inventory_changed.is_connected(_refresh):
			miner.extended_inventory_changed.connect(_refresh)
		if miner.has_signal("shop_inventory_changed") and not miner.shop_inventory_changed.is_connected(_refresh):
			miner.shop_inventory_changed.connect(_refresh)
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null and stats.has_signal("stats_changed") and not stats.stats_changed.is_connected(_refresh):
		stats.stats_changed.connect(_refresh)

func _hide_overlay() -> void:
	visible = false
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		if miner.has_signal("inventory_changed") and miner.inventory_changed.is_connected(_on_inv_changed):
			miner.inventory_changed.disconnect(_on_inv_changed)
		if miner.has_signal("extended_inventory_changed") and miner.extended_inventory_changed.is_connected(_refresh):
			miner.extended_inventory_changed.disconnect(_refresh)
		if miner.has_signal("shop_inventory_changed") and miner.shop_inventory_changed.is_connected(_refresh):
			miner.shop_inventory_changed.disconnect(_refresh)
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null and stats.has_signal("stats_changed") and stats.stats_changed.is_connected(_refresh):
		stats.stats_changed.disconnect(_refresh)

func _on_inv_changed(_s: int, _i: int, _g: int) -> void:
	_refresh()

func _refresh() -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		return
	for mid: int in _slots:
		var field: String = MATERIAL_TO_MINER_FIELD.get(mid, "")
		var count: int = miner.get(field) if field != "" else 0
		var slot: Panel = _slots[mid]
		var lbl: Label = slot.get_node_or_null("CountLabel") as Label
		if lbl != null:
			lbl.text = str(count)
			lbl.modulate = Color(1, 1, 1, 1) if count > 0 else Color(0.55, 0.6, 0.65, 1)
	_refresh_equipped(miner)
	_refresh_stats()

func _refresh_equipped(miner: Node) -> void:
	if _equipped_row == null:
		return
	for c: Node in _equipped_row.get_children():
		c.queue_free()
	# Equip-slot items first (one per category), then any owned utility.
	var ordered_ids: Array[String] = []
	for cat: Variant in miner.get("equipped_items").keys():
		ordered_ids.append(String(miner.get("equipped_items")[cat]))
	for owned_id: String in miner.get("owned_items"):
		var d: Dictionary = _ShopDefs.by_id(owned_id)
		if d.is_empty():
			continue
		if not _ShopDefs.is_equip_category(d.category) and not ordered_ids.has(owned_id):
			ordered_ids.append(owned_id)
	if ordered_ids.is_empty():
		var none: Label = Label.new()
		none.text = "No items yet — visit the item shop in town."
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
		_equipped_row.add_child(none)
		return
	for owned_id: String in ordered_ids:
		var item: Dictionary = _ShopDefs.by_id(owned_id)
		if item.is_empty():
			continue
		_equipped_row.add_child(_make_equipped_chip(item))

func _make_equipped_chip(item: Dictionary) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var slot: Panel = Panel.new()
	slot.custom_minimum_size = EQUIP_SLOT_SIZE
	var fill: ColorRect = ColorRect.new()
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 3
	fill.offset_top = 3
	fill.offset_right = -3
	fill.offset_bottom = -3
	fill.color = Color(0.13, 0.18, 0.14, 1)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(fill)
	var tex: Texture2D = _ShopDefs.icon_for(item)
	if tex != null:
		var ic: TextureRect = TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.anchor_right = 1.0
		ic.anchor_bottom = 1.0
		ic.offset_left = 4
		ic.offset_top = 4
		ic.offset_right = -4
		ic.offset_bottom = -4
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
	col.add_child(slot)
	var name_lbl: Label = Label.new()
	name_lbl.text = String(item.name)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(EQUIP_SLOT_SIZE.x + 24, 0)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85, 1))
	col.add_child(name_lbl)
	return col

func _refresh_stats() -> void:
	if _stats_grid == null:
		return
	for c: Node in _stats_grid.get_children():
		c.queue_free()
	var stats: Node = get_node_or_null("/root/PlayerStats")
	for entry: Array in STATS_DISPLAY:
		var key: StringName = entry[0]
		var label_text: String = entry[1]
		var hint: String = entry[2]
		var value: float = float(stats.call("get_stat", key)) if stats != null else 0.0
		var lbl: Label = Label.new()
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85, 1))
		_stats_grid.add_child(lbl)
		var val_lbl: Label = Label.new()
		val_lbl.text = _format_stat(value, hint)
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_color_override("font_color", _stat_color(value, hint))
		_stats_grid.add_child(val_lbl)

func _format_stat(value: float, hint: String) -> String:
	if hint == "mult":
		var pct: float = (value - 1.0) * 100.0
		if abs(pct) < 0.05:
			return "—"
		return "%+.0f%%" % pct
	# bonus
	if abs(value) < 0.05:
		return "—"
	return "%+0.1f" % value

func _stat_color(value: float, hint: String) -> Color:
	var neutral: Color = Color(0.55, 0.6, 0.65, 1)
	if hint == "mult":
		if abs(value - 1.0) < 0.0005:
			return neutral
		return Color(0.55, 0.95, 0.55, 1) if value > 1.0 else Color(0.95, 0.55, 0.55, 1)
	if abs(value) < 0.0005:
		return neutral
	return Color(0.55, 0.95, 0.55, 1) if value > 0.0 else Color(0.95, 0.55, 0.55, 1)

func _build_panel() -> void:
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.10, 0.13, 0.92)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.2, 0.22, 0.28, 1)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -240
	_panel.offset_top = -260
	_panel.offset_right = 240
	_panel.offset_bottom = 260
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var v: VBoxContainer = VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 16
	v.offset_top = 14
	v.offset_right = -16
	v.offset_bottom = -14
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var title: Label = Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95, 1))
	v.add_child(title)
	var rows: Array = [
		["T1  —  Mined ore", [MaterialDefs.MaterialId.STONE, MaterialDefs.MaterialId.IRON_ORE, MaterialDefs.MaterialId.GOLD_ORE]],
		["T2  —  Smelted",   [MaterialDefs.MaterialId.BRICK, MaterialDefs.MaterialId.IRON_INGOT, MaterialDefs.MaterialId.GOLD_INGOT]],
		["T3  —  Forged",    [MaterialDefs.MaterialId.BLOCK, MaterialDefs.MaterialId.IRON_BAR, MaterialDefs.MaterialId.GOLD_BAR]],
	]
	for row: Array in rows:
		var header: Label = Label.new()
		header.text = row[0]
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
		v.add_child(header)
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		v.add_child(hbox)
		for mid: int in row[1]:
			var entry: VBoxContainer = VBoxContainer.new()
			entry.add_theme_constant_override("separation", 2)
			var slot: Panel = _make_slot(mid)
			_slots[mid] = slot
			entry.add_child(slot)
			var name_lbl: Label = Label.new()
			name_lbl.text = MaterialDefs.DISPLAY_NAME[mid]
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.custom_minimum_size = Vector2(SLOT_SIZE.x + 12, 0)
			name_lbl.add_theme_font_size_override("font_size", 12)
			name_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85, 1))
			entry.add_child(name_lbl)
			hbox.add_child(entry)
	# Equipped section
	var eq_header: Label = Label.new()
	eq_header.text = "EQUIPPED"
	eq_header.add_theme_font_size_override("font_size", 13)
	eq_header.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55, 1))
	v.add_child(eq_header)
	_equipped_row = HBoxContainer.new()
	_equipped_row.add_theme_constant_override("separation", 10)
	_equipped_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_child(_equipped_row)
	# Stats section
	var st_header: Label = Label.new()
	st_header.text = "STATS"
	st_header.add_theme_font_size_override("font_size", 13)
	st_header.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 1))
	v.add_child(st_header)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4   # label, value, label, value
	_stats_grid.add_theme_constant_override("h_separation", 16)
	_stats_grid.add_theme_constant_override("v_separation", 2)
	v.add_child(_stats_grid)

func _make_slot(material_id: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var lbl: Label = Label.new()
	lbl.name = "CountLabel"
	lbl.text = "0"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.anchor_left = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = -22
	lbl.offset_top = -16
	lbl.offset_right = -2
	lbl.offset_bottom = -2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel
