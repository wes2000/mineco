extends Control
## Modal recipe panel. Bound to one Building at a time. Opened via E by player.

const SLOT_SIZE: Vector2 = Vector2(52, 52)
const DEPOSIT_SLOT_SIZE: Vector2 = Vector2(40, 40)
const INPUT_SLOTS_FIXED: int = 4
const OUTPUT_SLOTS_FIXED: int = 4

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

# Status -> badge background color
const STATUS_COLORS: Dictionary = {
	Building.Status.IDLE:           Color(0.40, 0.42, 0.48, 1),
	Building.Status.WORKING:        Color(0.20, 0.65, 0.35, 1),
	Building.Status.OUTPUT_BLOCKED: Color(0.85, 0.65, 0.20, 1),
	Building.Status.INPUT_JAMMED:   Color(0.80, 0.30, 0.30, 1),
	Building.Status.OVERFLOWING:    Color(0.85, 0.20, 0.50, 1),
}

const FLAME_ICON_PATH: String = "res://assets/icons/factory/flame.svg"

@onready var _name_label: Label = $Panel/Vbox/HeaderRow/Name
@onready var _status_badge_panel: PanelContainer = $Panel/Vbox/HeaderRow/StatusBadgePanel
@onready var _status_badge_label: Label = $Panel/Vbox/HeaderRow/StatusBadgePanel/StatusBadge
@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _recipe_select: OptionButton = $Panel/Vbox/RecipeRow/RecipeSelect
@onready var _input_col: PanelContainer = $Panel/Vbox/QueuesRow/InputCol
@onready var _processing_col: PanelContainer = $Panel/Vbox/QueuesRow/ProcessingCol
@onready var _output_col: PanelContainer = $Panel/Vbox/QueuesRow/OutputCol
@onready var _input_slots: HBoxContainer = $Panel/Vbox/QueuesRow/InputCol/V/Slots
@onready var _output_slots: HBoxContainer = $Panel/Vbox/QueuesRow/OutputCol/V/Slots
@onready var _processing_slots: HBoxContainer = $Panel/Vbox/QueuesRow/ProcessingCol/V/Slots
@onready var _input_take_btn: Button = $Panel/Vbox/QueuesRow/InputCol/V/TakeBtn
@onready var _output_take_btn: Button = $Panel/Vbox/QueuesRow/OutputCol/V/TakeBtn
@onready var _processing_flame: TextureRect = $Panel/Vbox/QueuesRow/ProcessingCol/V/FlameRow/Flame
@onready var _processing_countdown: Label = $Panel/Vbox/QueuesRow/ProcessingCol/V/FlameRow/Countdown
@onready var _deposit_panel: VBoxContainer = $Panel/Vbox/DepositPanel
@onready var _upgrade_row: PanelContainer = $Panel/Vbox/UpgradeRow
@onready var _upgrade_level_lbl: Label = $Panel/Vbox/UpgradeRow/H/LevelLabel
@onready var _upgrade_cost_lbl: Label = $Panel/Vbox/UpgradeRow/H/CostLabel
@onready var _upgrade_btn: Button = $Panel/Vbox/UpgradeRow/H/UpgradeBtn

const _MachineUpgradeDefs: GDScript = preload("res://scripts/factory/machine_upgrade_defs.gd")

var _bound_building: Building = null
var _badge_style: StyleBoxFlat = null

# Panel half-height presets — the deposit-less variant matches the loader's
# effective queue column height by shrinking the panel itself.
const PANEL_HALF_HEIGHT_WITH_DEPOSIT: float = 280.0
const PANEL_HALF_HEIGHT_NO_DEPOSIT: float = 200.0

@onready var _panel: Panel = $Panel

func _ready() -> void:
	visible = false
	add_to_group("machine_ui")
	_recipe_select.item_selected.connect(_on_recipe_selected)
	_input_take_btn.pressed.connect(_on_take_input)
	_output_take_btn.pressed.connect(_on_take_output)
	_close_btn.pressed.connect(unbind)
	_upgrade_btn.pressed.connect(_on_upgrade_pressed)
	var flame_tex: Texture2D = load(FLAME_ICON_PATH) as Texture2D
	if flame_tex != null:
		_processing_flame.texture = flame_tex
	# Duplicate the badge style so per-instance color edits don't leak
	var existing: StyleBox = _status_badge_panel.get_theme_stylebox("panel")
	if existing is StyleBoxFlat:
		_badge_style = (existing as StyleBoxFlat).duplicate() as StyleBoxFlat
		_status_badge_panel.add_theme_stylebox_override("panel", _badge_style)
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
	_input_col.visible = true
	_processing_col.visible = (building is Smelter) or (building is Forge) or _is_crusher(building)
	if building is Loader:
		(building as Loader).hopper_changed.connect(_on_hopper_changed)
		_deposit_panel.visible = true
		_resize_panel(PANEL_HALF_HEIGHT_WITH_DEPOSIT)
	else:
		_deposit_panel.visible = false
		_resize_panel(PANEL_HALF_HEIGHT_NO_DEPOSIT)
	_refresh()
	building.status_changed.connect(_on_status_changed)
	building.queue_changed.connect(_on_queue_changed)
	building.processing_changed.connect(_on_processing_changed)
	building.upgrade_level_changed.connect(_on_upgrade_level_changed)
	# Track inventory so the upgrade button enables/disables as gold/materials change.
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		if miner.has_signal("inventory_changed") and not miner.inventory_changed.is_connected(_on_inv_changed_for_upgrade):
			miner.inventory_changed.connect(_on_inv_changed_for_upgrade)
		if miner.has_signal("extended_inventory_changed") and not miner.extended_inventory_changed.is_connected(_on_ext_inv_changed_for_upgrade):
			miner.extended_inventory_changed.connect(_on_ext_inv_changed_for_upgrade)
		if miner.has_signal("gold_currency_changed") and not miner.gold_currency_changed.is_connected(_on_gold_changed_for_upgrade):
			miner.gold_currency_changed.connect(_on_gold_changed_for_upgrade)

func unbind() -> void:
	if _bound_building != null:
		if _bound_building.status_changed.is_connected(_on_status_changed):
			_bound_building.status_changed.disconnect(_on_status_changed)
		if _bound_building.queue_changed.is_connected(_on_queue_changed):
			_bound_building.queue_changed.disconnect(_on_queue_changed)
		if _bound_building.processing_changed.is_connected(_on_processing_changed):
			_bound_building.processing_changed.disconnect(_on_processing_changed)
		if _bound_building.upgrade_level_changed.is_connected(_on_upgrade_level_changed):
			_bound_building.upgrade_level_changed.disconnect(_on_upgrade_level_changed)
		if _bound_building is Loader:
			var ldr: Loader = _bound_building as Loader
			if ldr.hopper_changed.is_connected(_on_hopper_changed):
				ldr.hopper_changed.disconnect(_on_hopper_changed)
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		if miner.has_signal("inventory_changed") and miner.inventory_changed.is_connected(_on_inv_changed_for_upgrade):
			miner.inventory_changed.disconnect(_on_inv_changed_for_upgrade)
		if miner.has_signal("extended_inventory_changed") and miner.extended_inventory_changed.is_connected(_on_ext_inv_changed_for_upgrade):
			miner.extended_inventory_changed.disconnect(_on_ext_inv_changed_for_upgrade)
		if miner.has_signal("gold_currency_changed") and miner.gold_currency_changed.is_connected(_on_gold_changed_for_upgrade):
			miner.gold_currency_changed.disconnect(_on_gold_changed_for_upgrade)
	_bound_building = null
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_processing_changed(_n: int) -> void:
	_refresh()

func _resize_panel(half_height: float) -> void:
	_panel.offset_top = -half_height
	_panel.offset_bottom = half_height

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
	elif _is_crusher(_bound_building):
		for mid: int in MaterialDefs.TIER_1_MATERIALS:
			var label3: String = "%s (+%d%% bonus)" % [MaterialDefs.DISPLAY_NAME[mid], int(round(_crusher_bonus_chance(_bound_building) * 100.0))]
			_recipe_select.add_item(label3, mid)
		_select_current_recipe(int(_bound_building.get("recipe_input")))

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
	elif _is_crusher(_bound_building):
		_bound_building.set("recipe_input", mid)
	_refresh()

func _on_status_changed(new_status: int) -> void:
	_set_status_badge(new_status)

func _on_queue_changed(_kind: int, _new_count: int) -> void:
	_refresh()

func _set_status_badge(status: int) -> void:
	_status_badge_label.text = String(Building.Status.find_key(status))
	if _badge_style != null:
		_badge_style.bg_color = STATUS_COLORS.get(status, Color(0.4, 0.4, 0.45, 1))

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
	elif _is_crusher(_bound_building):
		type_name = "Crusher"
	_name_label.text = type_name
	_set_status_badge(_bound_building.status)
	if _bound_building is Loader:
		_render_fixed_slots(_input_slots, _hopper_to_slot_list((_bound_building as Loader).hopper), INPUT_SLOTS_FIXED)
		_input_take_btn.text = "Take hopper"
		_input_take_btn.disabled = _hopper_total((_bound_building as Loader).hopper) == 0
	else:
		_render_fixed_slots(_input_slots, _queue_to_slot_list(_bound_building.input_queue), INPUT_SLOTS_FIXED)
		_input_take_btn.text = "Take input"
		_input_take_btn.disabled = _bound_building.input_queue.is_empty()
	_render_processing_slots(_processing_slots, _bound_building.processing_buffer)
	_render_fixed_slots(_output_slots, _queue_to_slot_list(_bound_building.output_queue), OUTPUT_SLOTS_FIXED)
	_output_take_btn.text = "Take output"
	_output_take_btn.disabled = _bound_building.output_queue.is_empty()
	if _bound_building is Loader:
		_refresh_deposit_panel()
	_refresh_upgrade_panel()

# Returns Array of [material_id, count] pairs grouped by material_id, preserving
# first-occurrence order in the queue.
func _queue_to_slot_list(queue: Array) -> Array:
	var counts: Dictionary = {}
	var order: Array = []
	for mid: int in queue:
		if not counts.has(mid):
			counts[mid] = 0
			order.append(mid)
		counts[mid] = counts[mid] + 1
	var out: Array = []
	for mid: int in order:
		out.append([mid, counts[mid]])
	return out

func _hopper_to_slot_list(hopper: Dictionary) -> Array:
	var out: Array = []
	for mid: int in MaterialDefs.TIER_1_MATERIALS:
		var c: int = hopper.get(mid, 0)
		if c > 0:
			out.append([mid, c])
	return out

func _hopper_total(hopper: Dictionary) -> int:
	var t: int = 0
	for k: int in hopper:
		t += hopper[k]
	return t

func _render_fixed_slots(parent: HBoxContainer, slot_list: Array, fixed_count: int) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
	for i: int in fixed_count:
		if i < slot_list.size():
			var entry: Array = slot_list[i]
			parent.add_child(_make_slot(entry[0], entry[1]))
		else:
			parent.add_child(_make_slot(-1, 0))

func _render_processing_slots(parent: HBoxContainer, buffer: Array) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
	# Cap how many slot tiles we render so the column stays compact even at
	# Mk3 (8 cap). Show the actual cap up to a soft visual ceiling.
	var visible_slots: int = min(_bound_building.processing_buffer_cap() if _bound_building != null else Building.PROCESSING_BUFFER_MAX, 5)
	for i: int in visible_slots:
		if i < buffer.size():
			parent.add_child(_make_slot(buffer[i], 0))   # count=0 hides the count overlay
		else:
			parent.add_child(_make_slot(-1, 0))

func _make_slot(material_id: int, count: int, slot_size: Vector2 = SLOT_SIZE) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = slot_size
	# Dim material color fill behind the icon
	var fill: ColorRect = ColorRect.new()
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 4
	fill.offset_top = 4
	fill.offset_right = -4
	fill.offset_bottom = -4
	if material_id < 0:
		fill.color = Color(0.10, 0.11, 0.13, 0.7)
	else:
		var c: Color = ITEM_COLORS.get(material_id, Color.WHITE)
		fill.color = Color(c.r * 0.30, c.g * 0.30, c.b * 0.30, 1)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	if material_id >= 0:
		var tex: Texture2D = _icon_for(material_id)
		if tex != null:
			var icon: TextureRect = TextureRect.new()
			icon.texture = tex
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
	if count > 0:
		var lbl: Label = Label.new()
		lbl.text = str(count)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.anchor_left = 1.0
		lbl.anchor_top = 1.0
		lbl.anchor_right = 1.0
		lbl.anchor_bottom = 1.0
		lbl.offset_left = -26
		lbl.offset_top = -20
		lbl.offset_right = -3
		lbl.offset_bottom = -3
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(lbl)
	return panel

func _on_take_input() -> void:
	if _bound_building == null:
		return
	if _bound_building is Loader:
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
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	_deposit_panel.add_child(header)
	var rows: Array = [
		[MaterialDefs.MaterialId.STONE, "stone"],
		[MaterialDefs.MaterialId.IRON_ORE, "iron"],
		[MaterialDefs.MaterialId.GOLD_ORE, "gold"],
	]
	for row: Array in rows:
		var mid: int = row[0]
		var miner_field: String = row[1]
		var inv_count: int = miner.get(miner_field)
		var hopper_count: int = loader.hopper.get(mid, 0)
		# Skip rows where the player has none AND the hopper has none
		# (keeps the panel uncluttered).
		_deposit_panel.add_child(_make_deposit_row(mid, miner_field, inv_count, hopper_count))

func _make_deposit_row(material_id: int, miner_field: String, inv_count: int, hopper_count: int) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _deposit_row_style())
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	pc.add_child(hbox)
	# Icon slot
	var icon_slot: Panel = _make_slot(material_id, inv_count, DEPOSIT_SLOT_SIZE)
	hbox.add_child(icon_slot)
	# Label
	var label: Label = Label.new()
	label.text = "%s\nInventory: %d" % [MaterialDefs.DISPLAY_NAME[material_id], inv_count]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(label)
	# Hopper count
	var hopper_lbl: Label = Label.new()
	hopper_lbl.text = "→ %d / %d" % [hopper_count, (_bound_building as Loader).effective_hopper_cap()]
	hopper_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hopper_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85, 1))
	hbox.add_child(hopper_lbl)
	# Buttons
	var btn_10: Button = Button.new()
	btn_10.text = "+10"
	btn_10.disabled = (inv_count == 0)
	btn_10.pressed.connect(_do_deposit.bind(material_id, miner_field, 10))
	hbox.add_child(btn_10)
	var btn_all: Button = Button.new()
	btn_all.text = "All"
	btn_all.disabled = (inv_count == 0)
	btn_all.pressed.connect(_do_deposit.bind(material_id, miner_field, 999999))
	hbox.add_child(btn_all)
	return pc

# Cache one styled box for deposit rows (cheap to share — they don't mutate).
var _cached_deposit_row_style: StyleBoxFlat = null
func _deposit_row_style() -> StyleBoxFlat:
	if _cached_deposit_row_style != null:
		return _cached_deposit_row_style
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.13, 0.15, 0.18, 0.6)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.content_margin_left = 6
	s.content_margin_top = 4
	s.content_margin_right = 6
	s.content_margin_bottom = 4
	_cached_deposit_row_style = s
	return s

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

# --- Upgrade panel ---------------------------------------------------------

const _CrusherScript: GDScript = preload("res://scripts/factory/crusher.gd")

func _is_crusher(b: Object) -> bool:
	return b != null and b.get_script() == _CrusherScript

func _crusher_bonus_chance(b: Building) -> float:
	if not _is_crusher(b):
		return 0.0
	if b.has_method("bonus_chance"):
		return float(b.call("bonus_chance"))
	return 0.25

func _upgrade_kind_for(b: Building) -> StringName:
	if b is Loader: return &"loader"
	if b is Smelter: return &"smelter"
	if b is Forge: return &"forge"
	if _is_crusher(b): return &"crusher"
	return &""

func _on_upgrade_level_changed(_lvl: int) -> void:
	_refresh()

func _on_inv_changed_for_upgrade(_s: int, _i: int, _g: int) -> void:
	_refresh_upgrade_panel()

func _on_ext_inv_changed_for_upgrade() -> void:
	_refresh_upgrade_panel()

func _on_gold_changed_for_upgrade(_g: int) -> void:
	_refresh_upgrade_panel()

func _refresh_upgrade_panel() -> void:
	if _bound_building == null:
		_upgrade_row.visible = false
		return
	var kind: StringName = _upgrade_kind_for(_bound_building)
	if kind == &"":
		_upgrade_row.visible = false
		return
	_upgrade_row.visible = true
	var lvl: int = _bound_building.upgrade_level
	_upgrade_level_lbl.text = _MachineUpgradeDefs.level_label(lvl)
	if _MachineUpgradeDefs.is_maxed(lvl):
		_upgrade_cost_lbl.text = "(max tier)"
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "Maxed"
		return
	var step: Dictionary = _MachineUpgradeDefs.next_upgrade_for(kind, lvl)
	if step.is_empty():
		_upgrade_cost_lbl.text = "(no upgrade)"
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "Upgrade"
		return
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	var gold_cost: int = int(step.get("gold", 0))
	var mats: Dictionary = step.get("materials", {})
	# Build cost label string
	var parts: Array[String] = []
	parts.append("%dg" % gold_cost)
	for mid_v: Variant in mats.keys():
		var mid: int = int(mid_v)
		var qty: int = int(mats[mid_v])
		var have: int = miner.call("get_material_count", mid) if miner != null else 0
		var name: String = String(MaterialDefs.DISPLAY_NAME.get(mid, str(mid)))
		var ok: bool = have >= qty
		var tag: String = "" if ok else "!"
		parts.append("%s %d/%d%s" % [name, have, qty, tag])
	var have_gold: int = int(miner.get("gold_currency")) if miner != null else 0
	_upgrade_cost_lbl.text = ("→ %s   (gold %d/%d  " % [_MachineUpgradeDefs.level_label(lvl + 1), have_gold, gold_cost]) + ", ".join(parts.slice(1)) + ")"
	_upgrade_btn.text = "Upgrade → %s" % _MachineUpgradeDefs.level_label(lvl + 1)
	_upgrade_btn.disabled = not _can_afford_upgrade(miner, gold_cost, mats)

func _can_afford_upgrade(miner: Node, gold_cost: int, mats: Dictionary) -> bool:
	if miner == null:
		return false
	if int(miner.get("gold_currency")) < gold_cost:
		return false
	for mid_v: Variant in mats.keys():
		var have: int = int(miner.call("get_material_count", int(mid_v)))
		if have < int(mats[mid_v]):
			return false
	return true

func _on_upgrade_pressed() -> void:
	if _bound_building == null:
		return
	var kind: StringName = _upgrade_kind_for(_bound_building)
	if kind == &"":
		return
	var lvl: int = _bound_building.upgrade_level
	if _MachineUpgradeDefs.is_maxed(lvl):
		return
	var step: Dictionary = _MachineUpgradeDefs.next_upgrade_for(kind, lvl)
	if step.is_empty():
		return
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	var gold_cost: int = int(step.get("gold", 0))
	var mats: Dictionary = step.get("materials", {})
	if not _can_afford_upgrade(miner, gold_cost, mats):
		return
	# Charge
	miner.call("add_gold_currency", -gold_cost)
	for mid_v: Variant in mats.keys():
		miner.call("remove_material", int(mid_v), int(mats[mid_v]))
	_bound_building.set_upgrade_level(lvl + 1)
	# Small confirmation feedback via the pickup feed if available.
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", "Upgraded to %s" % _MachineUpgradeDefs.level_label(lvl + 1))
	_refresh()
