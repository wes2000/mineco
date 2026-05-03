extends Control
## Modal recipe panel. Bound to one Building at a time. Opened via E by player.

const SLOT_SIZE: Vector2 = Vector2(56, 56)
const ITEM_COLORS: Dictionary = {
	0: Color(0.6, 0.6, 0.6),    # STONE
	1: Color(0.7, 0.35, 0.25),  # BRICK
	2: Color(0.4, 0.4, 0.4),    # BLOCK
	3: Color(0.55, 0.4, 0.3),   # IRON_ORE
	4: Color(0.7, 0.7, 0.75),   # IRON_INGOT
	5: Color(0.85, 0.85, 0.9),  # IRON_BAR
	6: Color(0.7, 0.6, 0.2),    # GOLD_ORE
	7: Color(0.95, 0.8, 0.3),   # GOLD_INGOT
	8: Color(1.0, 0.85, 0.4),   # GOLD_BAR
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
static var _icon_texture_cache: Dictionary = {}

static func _icon_for(material_id: int) -> Texture2D:
	if not ITEM_ICONS.has(material_id):
		return null
	if _icon_texture_cache.has(material_id):
		return _icon_texture_cache[material_id]
	var tex: Texture2D = load(ITEM_ICONS[material_id]) as Texture2D
	_icon_texture_cache[material_id] = tex
	return tex

const FLAME_ICON_PATH: String = "res://assets/icons/factory/flame.svg"

@onready var _name_label: Label = $Panel/Vbox/Name
@onready var _status_label: Label = $Panel/Vbox/Status
@onready var _recipe_select: OptionButton = $Panel/Vbox/RecipeRow/RecipeSelect
@onready var _input_slots: HBoxContainer = $Panel/Vbox/QueuesRow/InputCol/Slots
@onready var _output_slots: HBoxContainer = $Panel/Vbox/QueuesRow/OutputCol/Slots
@onready var _input_take_btn: Button = $Panel/Vbox/QueuesRow/InputCol/TakeBtn
@onready var _output_take_btn: Button = $Panel/Vbox/QueuesRow/OutputCol/TakeBtn
@onready var _input_col: VBoxContainer = $Panel/Vbox/QueuesRow/InputCol
@onready var _processing_col: VBoxContainer = $Panel/Vbox/QueuesRow/ProcessingCol
@onready var _processing_slots: HBoxContainer = $Panel/Vbox/QueuesRow/ProcessingCol/Slots
@onready var _processing_flame: TextureRect = $Panel/Vbox/QueuesRow/ProcessingCol/FlameRow/Flame
@onready var _processing_countdown: Label = $Panel/Vbox/QueuesRow/ProcessingCol/FlameRow/Countdown
@onready var _deposit_panel: VBoxContainer = $Panel/Vbox/DepositPanel

var _bound_building: Building = null

func _ready() -> void:
	visible = false
	add_to_group("machine_ui")
	_recipe_select.item_selected.connect(_on_recipe_selected)
	_input_take_btn.pressed.connect(_on_take_input)
	_output_take_btn.pressed.connect(_on_take_output)
	var flame_tex: Texture2D = load(FLAME_ICON_PATH) as Texture2D
	if flame_tex != null:
		_processing_flame.texture = flame_tex
	set_process(true)

func _process(_delta: float) -> void:
	if not visible or _bound_building == null:
		return
	# Live update of flame visibility + countdown text (per-frame so the timer
	# decrements smoothly between sim ticks).
	var working: bool = (_bound_building.status == Building.Status.WORKING)
	_processing_flame.visible = working
	if working:
		var rem_ticks: int = _bound_building.get_cycle_remaining_ticks()
		_processing_countdown.text = "%.1fs" % (float(rem_ticks) * FactoryWorld.TICK_DT)
	else:
		_processing_countdown.text = ""

func bind_to(building: Building) -> void:
	if _bound_building != null:
		unbind()
	_bound_building = building
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_populate_recipes()
	_input_col.visible = true   # All buildings show INPUT (Loader's input = hopper)
	# PROCESSING column only meaningful for Smelter/Forge (they have a cycle)
	_processing_col.visible = (building is Smelter) or (building is Forge)
	if building is Loader:
		(building as Loader).hopper_changed.connect(_on_hopper_changed)
		_deposit_panel.visible = true
	else:
		_deposit_panel.visible = false
	_refresh()
	building.status_changed.connect(_on_status_changed)
	building.queue_changed.connect(_on_queue_changed)
	building.processing_changed.connect(_on_processing_changed)

func unbind() -> void:
	if _bound_building != null:
		if _bound_building.status_changed.is_connected(_on_status_changed):
			_bound_building.status_changed.disconnect(_on_status_changed)
		if _bound_building.queue_changed.is_connected(_on_queue_changed):
			_bound_building.queue_changed.disconnect(_on_queue_changed)
		if _bound_building.processing_changed.is_connected(_on_processing_changed):
			_bound_building.processing_changed.disconnect(_on_processing_changed)
		if _bound_building is Loader:
			var ldr: Loader = _bound_building as Loader
			if ldr.hopper_changed.is_connected(_on_hopper_changed):
				ldr.hopper_changed.disconnect(_on_hopper_changed)
	_bound_building = null
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_processing_changed(_n: int) -> void:
	_refresh()

func _on_hopper_changed(_mid: int, _new_count: int) -> void:
	_refresh()

func _populate_recipes() -> void:
	_recipe_select.clear()
	if _bound_building is Loader:
		for mid: int in MaterialDefs.TIER_1_MATERIALS:
			_recipe_select.add_item(MaterialDefs.DISPLAY_NAME[mid], mid)
		_select_current_recipe((_bound_building as Loader).selected_material)
	elif _bound_building is Smelter:
		for mid: int in MaterialDefs.SMELT_RECIPE:
			var label: String = "%s -> %s" % [MaterialDefs.DISPLAY_NAME[mid], MaterialDefs.DISPLAY_NAME[MaterialDefs.SMELT_RECIPE[mid]]]
			_recipe_select.add_item(label, mid)
		_select_current_recipe((_bound_building as Smelter).recipe_input)
	elif _bound_building is Forge:
		for mid: int in MaterialDefs.FORGE_RECIPE:
			var label2: String = "%s -> %s" % [MaterialDefs.DISPLAY_NAME[mid], MaterialDefs.DISPLAY_NAME[MaterialDefs.FORGE_RECIPE[mid]]]
			_recipe_select.add_item(label2, mid)
		_select_current_recipe((_bound_building as Forge).recipe_input)

func _select_current_recipe(target: int) -> void:
	for i: int in _recipe_select.item_count:
		if _recipe_select.get_item_id(i) == target:
			_recipe_select.select(i)
			return

func _on_recipe_selected(idx: int) -> void:
	var mid: int = _recipe_select.get_item_id(idx)
	if _bound_building is Loader:
		(_bound_building as Loader).selected_material = mid
	elif _bound_building is Smelter:
		(_bound_building as Smelter).recipe_input = mid
	elif _bound_building is Forge:
		(_bound_building as Forge).recipe_input = mid
	_refresh()

func _on_status_changed(new_status: int) -> void:
	_status_label.text = "Status: %s" % Building.Status.find_key(new_status)

func _on_queue_changed(_kind: int, _new_count: int) -> void:
	_refresh()

func _refresh() -> void:
	if _bound_building == null:
		return
	var type_name: String = "Building"
	if _bound_building is Loader:
		type_name = "Loader"
	elif _bound_building is Smelter:
		type_name = "Smelter"
	elif _bound_building is Forge:
		type_name = "Forge"
	_name_label.text = type_name
	_status_label.text = "Status: %s" % Building.Status.find_key(_bound_building.status)
	if _bound_building is Loader:
		_render_hopper_slots(_input_slots, (_bound_building as Loader).hopper)
		_input_take_btn.text = "Take hopper"
		_input_take_btn.disabled = _hopper_total((_bound_building as Loader).hopper) == 0
	else:
		_render_slots(_input_slots, _bound_building.input_queue)
		_input_take_btn.text = "Take input"
		_input_take_btn.disabled = _bound_building.input_queue.is_empty()
	_render_processing_slots(_processing_slots, _bound_building.processing_buffer)
	_render_slots(_output_slots, _bound_building.output_queue)
	_output_take_btn.text = "Take output"
	_output_take_btn.disabled = _bound_building.output_queue.is_empty()
	if _bound_building is Loader:
		_refresh_deposit_panel()

func _render_processing_slots(parent: HBoxContainer, buffer: Array) -> void:
	# Always render exactly PROCESSING_BUFFER_MAX slots so the column has a
	# stable width — fill the first N with items, leave the rest as empty
	# placeholders.
	for child: Node in parent.get_children():
		child.queue_free()
	for i: int in Building.PROCESSING_BUFFER_MAX:
		if i < buffer.size():
			parent.add_child(_make_slot(buffer[i], 0))   # count=0 hides the count overlay
		else:
			parent.add_child(_make_slot(-1, 0))

func _hopper_total(hopper: Dictionary) -> int:
	var t: int = 0
	for k: int in hopper:
		t += hopper[k]
	return t

func _render_hopper_slots(parent: HBoxContainer, hopper: Dictionary) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
	var any: bool = false
	for mid: int in MaterialDefs.TIER_1_MATERIALS:
		var c: int = hopper.get(mid, 0)
		if c > 0:
			parent.add_child(_make_slot(mid, c))
			any = true
	if not any:
		parent.add_child(_make_slot(-1, 0))

func _render_slots(parent: HBoxContainer, queue: Array) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
	# Group by material_id, preserving first-occurrence order
	var counts: Dictionary = {}
	var order: Array = []
	for mid: int in queue:
		if not counts.has(mid):
			counts[mid] = 0
			order.append(mid)
		counts[mid] = counts[mid] + 1
	if order.is_empty():
		# Render one empty slot as a placeholder
		parent.add_child(_make_slot(-1, 0))
		return
	for mid: int in order:
		parent.add_child(_make_slot(mid, counts[mid]))

func _make_slot(material_id: int, count: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	# Dim material color fill behind the icon
	var fill: ColorRect = ColorRect.new()
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 4
	fill.offset_top = 4
	fill.offset_right = -4
	fill.offset_bottom = -4
	if material_id < 0:
		fill.color = Color(0.15, 0.15, 0.18, 1)
	else:
		var c: Color = ITEM_COLORS.get(material_id, Color.WHITE)
		fill.color = Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, 1)
	panel.add_child(fill)
	# Icon overlay
	if material_id >= 0:
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
	# Count overlay (bottom-right)
	if count > 0:
		var lbl: Label = Label.new()
		lbl.text = str(count)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.anchor_left = 1.0
		lbl.anchor_top = 1.0
		lbl.anchor_right = 1.0
		lbl.anchor_bottom = 1.0
		lbl.offset_left = -28
		lbl.offset_top = -22
		lbl.offset_right = -4
		lbl.offset_bottom = -4
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(lbl)
	return panel

func _on_take_input() -> void:
	if _bound_building == null:
		return
	if _bound_building is Loader:
		# Withdraw the entire hopper back to the player's inventory
		var ldr: Loader = _bound_building as Loader
		var miner: Node = get_tree().get_first_node_in_group("player_miner")
		if miner == null:
			return
		var mapping: Array = [
			[MaterialDefs.MaterialId.STONE, "stone"],
			[MaterialDefs.MaterialId.IRON_ORE, "iron"],
			[MaterialDefs.MaterialId.GOLD_ORE, "gold"],
		]
		for entry: Array in mapping:
			var mid: int = entry[0]
			var field: String = entry[1]
			var n: int = ldr.hopper.get(mid, 0)
			if n > 0:
				miner.set(field, miner.get(field) + n)
				ldr.hopper[mid] = 0
				ldr.hopper_changed.emit(mid, 0)
		if miner.has_signal("inventory_changed"):
			miner.inventory_changed.emit(miner.get("stone"), miner.get("iron"), miner.get("gold"))
		_refresh()
		return
	var taken: Array[int] = _bound_building.take_all_from_queue(Building.QUEUE_KIND_INPUT)
	_credit_player(taken)

func _on_take_output() -> void:
	if _bound_building == null:
		return
	var taken: Array[int] = _bound_building.take_all_from_queue(Building.QUEUE_KIND_OUTPUT)
	_credit_player(taken)

func _credit_player(materials: Array[int]) -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		return
	for mid: int in materials:
		miner.add_factory_material(mid, 1)

func _refresh_deposit_panel() -> void:
	for child: Node in _deposit_panel.get_children():
		child.queue_free()
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		var warn: Label = Label.new()
		warn.text = "(no player_miner found)"
		_deposit_panel.add_child(warn)
		return
	var loader: Loader = _bound_building as Loader
	var header: Label = Label.new()
	header.text = "DEPOSIT FROM INVENTORY"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deposit_panel.add_child(header)
	var rows: Array = [
		[MaterialDefs.MaterialId.STONE, "stone"],
		[MaterialDefs.MaterialId.IRON_ORE, "iron"],
		[MaterialDefs.MaterialId.GOLD_ORE, "gold"],
	]
	for row: Array in rows:
		var mid: int = row[0]
		var miner_field: String = row[1]
		var hbox: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		var hopper_count: int = loader.hopper.get(mid, 0)
		var inv_count: int = miner.get(miner_field)
		label.text = "%s — Inv: %d / Hopper: %d / %d" % [
			MaterialDefs.DISPLAY_NAME[mid], inv_count, hopper_count, Loader.HOPPER_CAP]
		label.custom_minimum_size = Vector2(300, 0)
		hbox.add_child(label)
		var btn_10: Button = Button.new()
		btn_10.text = "+10"
		btn_10.pressed.connect(_do_deposit.bind(mid, miner_field, 10))
		hbox.add_child(btn_10)
		var btn_all: Button = Button.new()
		btn_all.text = "All"
		btn_all.pressed.connect(_do_deposit.bind(mid, miner_field, 999999))
		hbox.add_child(btn_all)
		_deposit_panel.add_child(hbox)

func _do_deposit(material_id: int, miner_field: String, requested: int) -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null or _bound_building == null:
		return
	var loader: Loader = _bound_building as Loader
	var available: int = miner.get(miner_field)
	var to_deposit: int = min(requested, available)
	if to_deposit <= 0:
		return
	var accepted: int = loader.deposit(material_id, to_deposit)
	miner.set(miner_field, available - accepted)
	if miner.has_signal("inventory_changed"):
		miner.inventory_changed.emit(miner.get("stone"), miner.get("iron"), miner.get("gold"))
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("machine_interact"):
		# Esc OR a second press of E closes the panel.
		unbind()
		accept_event()
