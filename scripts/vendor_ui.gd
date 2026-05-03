extends Control
## Modal sell window. Opened by E on a vendor NPC. Lists every material the
## player has > 0 of, with Sell-10 and Sell-All buttons, and credits gold to
## Miner.gold_currency.

const SLOT_SIZE: Vector2 = Vector2(40, 40)

# Per-unit sell prices in gold. Higher tier = higher value, rarer = higher value.
const PRICES: Dictionary = {
	0: 1,    # STONE
	1: 4,    # BRICK         (T2 stone)
	2: 12,   # BLOCK         (T3 stone)
	3: 3,    # IRON_ORE
	4: 10,   # IRON_INGOT    (T2 iron)
	5: 30,   # IRON_BAR      (T3 iron)
	6: 10,   # GOLD_ORE
	7: 30,   # GOLD_INGOT    (T2 gold)
	8: 90,   # GOLD_BAR      (T3 gold)
}

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
const SELL_ORDER: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _rows: VBoxContainer = $Panel/Vbox/Scroll/Rows

var _miner: Node = null

# Cache row styling
var _row_style: StyleBoxFlat = null

func _ready() -> void:
	visible = false
	add_to_group("vendor_ui")
	_close_btn.pressed.connect(close)
	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = Color(0.13, 0.15, 0.18, 0.7)
	_row_style.corner_radius_top_left = 3
	_row_style.corner_radius_top_right = 3
	_row_style.corner_radius_bottom_left = 3
	_row_style.corner_radius_bottom_right = 3
	_row_style.content_margin_left = 6
	_row_style.content_margin_top = 4
	_row_style.content_margin_right = 6
	_row_style.content_margin_bottom = 4

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner != null:
		if not _miner.inventory_changed.is_connected(_on_inv_changed):
			_miner.inventory_changed.connect(_on_inv_changed)
		if _miner.has_signal("extended_inventory_changed") and not _miner.extended_inventory_changed.is_connected(_refresh):
			_miner.extended_inventory_changed.connect(_refresh)
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _miner != null:
		if _miner.inventory_changed.is_connected(_on_inv_changed):
			_miner.inventory_changed.disconnect(_on_inv_changed)
		if _miner.has_signal("extended_inventory_changed") and _miner.extended_inventory_changed.is_connected(_refresh):
			_miner.extended_inventory_changed.disconnect(_refresh)
	_miner = null

func _on_inv_changed(_s: int, _i: int, _g: int) -> void:
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("machine_interact"):
		close()
		accept_event()

func _refresh() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	if _miner == null:
		return
	var any_row: bool = false
	for mid: int in SELL_ORDER:
		var count: int = _miner.get_material_count(mid)
		if count <= 0:
			continue
		_rows.add_child(_make_row(mid, count))
		any_row = true
	if not any_row:
		var empty: Label = Label.new()
		empty.text = "(no items to sell)"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
		_rows.add_child(empty)

func _make_row(material_id: int, count: int) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _row_style)
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	pc.add_child(hbox)
	hbox.add_child(_make_slot(material_id))
	# Name + count
	var label: Label = Label.new()
	label.text = "%s × %d" % [MaterialDefs.DISPLAY_NAME[material_id], count]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(label)
	# Price
	var price: int = PRICES.get(material_id, 0)
	var price_lbl: Label = Label.new()
	price_lbl.text = "%dg ea" % price
	price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	hbox.add_child(price_lbl)
	# Buttons
	var btn_10: Button = Button.new()
	btn_10.text = "Sell 10"
	btn_10.disabled = (count < 1)
	btn_10.pressed.connect(_do_sell.bind(material_id, 10))
	hbox.add_child(btn_10)
	var btn_all: Button = Button.new()
	btn_all.text = "Sell all"
	btn_all.pressed.connect(_do_sell.bind(material_id, count))
	hbox.add_child(btn_all)
	return pc

func _make_slot(material_id: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	var fill: ColorRect = ColorRect.new()
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 3
	fill.offset_top = 3
	fill.offset_right = -3
	fill.offset_bottom = -3
	var c: Color = ITEM_COLORS.get(material_id, Color.WHITE)
	fill.color = Color(c.r * 0.30, c.g * 0.30, c.b * 0.30, 1)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	if ITEM_ICONS.has(material_id):
		var icon: TextureRect = TextureRect.new()
		icon.texture = load(ITEM_ICONS[material_id]) as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
	return panel

func _do_sell(material_id: int, requested: int) -> void:
	if _miner == null:
		return
	var sold: int = _miner.remove_material(material_id, requested)
	if sold <= 0:
		return
	var earned: int = sold * PRICES.get(material_id, 0)
	_miner.add_gold_currency(earned)
	# inventory_changed -> _refresh runs automatically via signal
