extends Control
## Bottom-center HUD: a row of slots (3 in standard mode, 6 in build mode) plus
## a stamina bar below. Swaps slot contents when BuildController.active flips.

const SLOT_SIZE: Vector2 = Vector2(48, 48)

const STANDARD_SLOTS: Array = [
	["res://assets/icons/hotbar/tool_pickaxe.svg",   "Pickaxe"],
	["res://assets/icons/hotbar/tool_scanner.svg",   "Ore Scanner"],
	["res://assets/icons/hotbar/tool_flashlight.svg","Flashlight"],
]
const BUILD_SLOTS: Array = [
	["res://assets/icons/hotbar/build_loader.svg",   "Loader"],
	["res://assets/icons/hotbar/build_smelter.svg",  "Smelter"],
	["res://assets/icons/hotbar/build_forge.svg",    "Forge"],
	["res://assets/icons/hotbar/build_belt.svg",     "Belt"],
	["res://assets/icons/hotbar/build_merger.svg",   "Merger"],
	["res://assets/icons/hotbar/build_splitter.svg", "Splitter"],
]

# Style for inactive slot panel
static var _slot_style: StyleBoxFlat = null
static var _slot_style_selected: StyleBoxFlat = null

@onready var _slots_row: HBoxContainer = $Panel/Vbox/SlotsRow
@onready var _stamina_bar: ProgressBar = $Panel/Vbox/StaminaBar

var _slots: Array = []   # current slot Panel nodes (active set)
var _stamina: Node = null

const MODAL_GROUPS: Array[String] = ["machine_ui", "pause_menu", "inventory_overlay", "vendor_ui"]

func _ready() -> void:
	_init_styles()
	BuildController.active_changed.connect(_on_build_mode_changed)
	BuildController.selection_changed.connect(_on_build_selection)
	_populate(STANDARD_SLOTS)
	_highlight(0)
	# Hook stamina (looks for /root/Main/Player/Stamina)
	_stamina = get_node_or_null("/root/Main/Player/Stamina")
	if _stamina != null and _stamina.has_signal("stamina_changed"):
		_stamina.stamina_changed.connect(_on_stamina_changed)
		_stamina_bar.min_value = 0.0
		_stamina_bar.max_value = float(_stamina.max_value)
		_stamina_bar.value = _stamina.current
	set_process(true)

func _process(_delta: float) -> void:
	# Hide while any modal UI is open so the hotbar doesn't overlap their panels.
	var any_modal: bool = false
	for group_name: String in MODAL_GROUPS:
		var node: Node = get_tree().get_first_node_in_group(group_name)
		if node != null and node is Control and (node as Control).visible:
			any_modal = true
			break
	visible = not any_modal

func _on_stamina_changed(current: float, max_v: int) -> void:
	_stamina_bar.max_value = float(max_v)
	_stamina_bar.value = current

func _on_build_mode_changed(is_active: bool) -> void:
	if is_active:
		_populate(BUILD_SLOTS)
		_highlight(BuildController.current_tool)
	else:
		_populate(STANDARD_SLOTS)
		_highlight(0)

func _on_build_selection(selected_tool: int) -> void:
	if BuildController.active:
		_highlight(selected_tool)

func _populate(spec: Array) -> void:
	for child: Node in _slots_row.get_children():
		child.queue_free()
	_slots.clear()
	for i: int in spec.size():
		var entry: Array = spec[i]
		var slot: Panel = _make_slot(entry[0], i + 1)
		slot.tooltip_text = entry[1]
		_slots_row.add_child(slot)
		_slots.append(slot)

func _highlight(index: int) -> void:
	for i: int in _slots.size():
		var slot: Panel = _slots[i]
		slot.add_theme_stylebox_override("panel", _slot_style_selected if i == index else _slot_style)

func _make_slot(icon_path: String, hotkey_num: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.add_theme_stylebox_override("panel", _slot_style)
	# Icon
	var tex: Texture2D = load(icon_path) as Texture2D
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
	# Hotkey number, top-right
	var key_lbl: Label = Label.new()
	key_lbl.text = str(hotkey_num)
	key_lbl.add_theme_font_size_override("font_size", 11)
	key_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45, 1))
	key_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	key_lbl.add_theme_constant_override("outline_size", 4)
	key_lbl.anchor_left = 1.0
	key_lbl.anchor_top = 0.0
	key_lbl.anchor_right = 1.0
	key_lbl.anchor_bottom = 0.0
	key_lbl.offset_left = -16
	key_lbl.offset_top = 1
	key_lbl.offset_right = -2
	key_lbl.offset_bottom = 16
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(key_lbl)
	return panel

func _init_styles() -> void:
	if _slot_style != null:
		return
	_slot_style = StyleBoxFlat.new()
	_slot_style.bg_color = Color(0.13, 0.15, 0.18, 1)
	_slot_style.border_width_left = 1
	_slot_style.border_width_top = 1
	_slot_style.border_width_right = 1
	_slot_style.border_width_bottom = 1
	_slot_style.border_color = Color(0.22, 0.25, 0.30, 1)
	_slot_style.corner_radius_top_left = 4
	_slot_style.corner_radius_top_right = 4
	_slot_style.corner_radius_bottom_right = 4
	_slot_style.corner_radius_bottom_left = 4
	_slot_style_selected = StyleBoxFlat.new()
	_slot_style_selected.bg_color = Color(0.20, 0.27, 0.36, 1)
	_slot_style_selected.border_width_left = 2
	_slot_style_selected.border_width_top = 2
	_slot_style_selected.border_width_right = 2
	_slot_style_selected.border_width_bottom = 2
	_slot_style_selected.border_color = Color(0.95, 0.85, 0.45, 1)
	_slot_style_selected.corner_radius_top_left = 4
	_slot_style_selected.corner_radius_top_right = 4
	_slot_style_selected.corner_radius_bottom_right = 4
	_slot_style_selected.corner_radius_bottom_left = 4
