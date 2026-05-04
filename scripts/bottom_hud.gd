extends Control
## Bottom-center HUD: a row of slots (3 in standard mode, 6 in build mode) plus
## a stamina bar below. Swaps slot contents when BuildController.active flips.

const SLOT_SIZE: Vector2 = Vector2(48, 48)

const _BuildPieceDefs: GDScript = preload("res://scripts/factory/build_piece_defs.gd")

const STANDARD_SLOTS: Array = [
	["res://assets/icons/hotbar/tool_pickaxe.svg",   "Pickaxe"],
	["res://assets/icons/hotbar/tool_scanner.svg",   "Ore Scanner"],
	["res://assets/icons/hotbar/tool_flashlight.svg","Flashlight"],
	["res://assets/icons/hotbar/tool_weapon.svg",    "Weapon"],
]
# Index of the weapon slot inside STANDARD_SLOTS; greyed out when no weapon is
# owned + equipped, lit up otherwise.
const WEAPON_SLOT_INDEX: int = 3

const _WeaponDefs: GDScript = preload("res://scripts/weapon_defs.gd")

# Build slots are derived live from BuildController.get_quickbar() so
# rebinding via the catalog UI updates the bar without a const change.
func _build_slots() -> Array:
	var out: Array = []
	var qb: Array = BuildController.get_quickbar()
	for kind: Variant in qb:
		var def: Dictionary = _BuildPieceDefs.by_id(StringName(String(kind)))
		if def.is_empty():
			out.append(["", "(empty)"])
		else:
			out.append([String(def.get("icon", "")), String(def.get("name", String(kind)))])
	return out

# Style for inactive slot panel
static var _slot_style: StyleBoxFlat = null
static var _slot_style_selected: StyleBoxFlat = null

@onready var _slots_row: HBoxContainer = $Panel/Vbox/SlotsRow
@onready var _stamina_bar: ProgressBar = $Panel/Vbox/StaminaBar
@onready var _health_bar: ProgressBar = $Panel/Vbox/HealthBar

var _slots: Array = []   # current slot Panel nodes (active set)
var _stamina: Node = null
var _health: Node = null
var _miner: Node = null
# Lazy reference to the screen-spanning damage flash overlay added to the HUD
# CanvasLayer in main.tscn. We don't host it here because BottomHud's root is
# anchored to a 120px-tall strip at the bottom and a child can't escape it.
var _damage_flash: ColorRect = null

const MODAL_GROUPS: Array[String] = ["machine_ui", "pause_menu", "inventory_overlay", "vendor_ui", "contract_ui", "boat_vendor_ui", "claim_vendor_ui", "item_shop_ui", "passive_tree_ui", "build_catalog_ui", "storage_crate_ui", "workbench_ui", "company_panel_ui"]

func _ready() -> void:
	_init_styles()
	BuildController.active_changed.connect(_on_build_mode_changed)
	BuildController.selection_changed.connect(_on_build_selection)
	if BuildController.has_signal("quickbar_changed"):
		BuildController.quickbar_changed.connect(_on_quickbar_changed)
	_populate(STANDARD_SLOTS)
	_highlight(0)
	# Hook stamina (looks for /root/Main/Player/Stamina)
	_stamina = get_node_or_null("/root/Main/Player/Stamina")
	if _stamina != null and _stamina.has_signal("stamina_changed"):
		_stamina.stamina_changed.connect(_on_stamina_changed)
		_stamina_bar.min_value = 0.0
		_stamina_bar.max_value = float(_stamina.max_value)
		_stamina_bar.value = _stamina.current
	# Hook the player's standard-mode tool selection.
	var player: Node = get_node_or_null("/root/Main/Player")
	if player != null and player.has_signal("tool_changed"):
		player.tool_changed.connect(_on_player_tool_changed)
		_highlight(player.get("current_tool"))
	# Hook the player's Health for the new health bar.
	_health = get_node_or_null("/root/Main/Player/Health")
	if _health != null and _health.has_signal("health_changed"):
		_health.health_changed.connect(_on_health_changed)
		var mv: int = int(_health.call("max_value")) if _health.has_method("max_value") else 100
		_health_bar.max_value = float(mv)
		_health_bar.value = float(_health.get("current"))
	# Hook the miner so we know when the equipped weapon changes (lights /
	# greys the weapon slot icon).
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner != null and _miner.has_signal("shop_inventory_changed"):
		_miner.shop_inventory_changed.connect(_refresh_standard_slots)
	# DamageFlash lives on the HUD layer (sibling). Resolved lazily so order
	# of node creation in main.tscn doesn't matter.
	_damage_flash = get_node_or_null("/root/Main/HUD/DamageFlash") as ColorRect
	if _damage_flash != null:
		_damage_flash.modulate.a = 0.0
	set_process(true)

func _on_player_tool_changed(new_tool: int) -> void:
	if not BuildController.active:
		_highlight(new_tool)

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

func _on_health_changed(current: float, max_v: int) -> void:
	if _health_bar == null:
		return
	_health_bar.max_value = float(max_v)
	_health_bar.value = current

# Brief red overlay pulse on damage. Player calls this through duck-typing.
func flash_damage(_amount: float) -> void:
	if _damage_flash == null:
		return
	_damage_flash.modulate.a = 0.55
	var tween: Tween = create_tween()
	tween.tween_property(_damage_flash, "modulate:a", 0.0, 0.45)

# Re-render the standard hotbar so the weapon slot's enabled/disabled state
# matches the current equipped_items dict.
func _refresh_standard_slots() -> void:
	if BuildController.active:
		return
	_populate(STANDARD_SLOTS)
	var player: Node = get_node_or_null("/root/Main/Player")
	var idx: int = player.get("current_tool") if player != null else 0
	_highlight(idx)

func _on_build_mode_changed(is_active: bool) -> void:
	if is_active:
		_populate(_build_slots())
		_highlight(BuildController.current_slot)
	else:
		_populate(STANDARD_SLOTS)
		var player: Node = get_node_or_null("/root/Main/Player")
		var idx: int = player.get("current_tool") if player != null else 0
		_highlight(idx)

func _on_build_selection(selected_index: int) -> void:
	if BuildController.active:
		_highlight(selected_index)

func _on_quickbar_changed() -> void:
	# Catalog rebound a slot — refresh the bar in place if we're showing it.
	if BuildController.active:
		_populate(_build_slots())
		_highlight(BuildController.current_slot)

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
	# Grey out the weapon slot when no weapon is equipped + show the equipped
	# weapon's name in the tooltip when it is.
	if spec == STANDARD_SLOTS and _slots.size() > WEAPON_SLOT_INDEX:
		var weapon_slot: Panel = _slots[WEAPON_SLOT_INDEX]
		var equipped_id: String = _equipped_weapon_id()
		if equipped_id == "":
			weapon_slot.modulate = Color(1, 1, 1, 0.35)
			weapon_slot.tooltip_text = "Weapon (none equipped)"
		else:
			weapon_slot.modulate = Color(1, 1, 1, 1)
			var def: Dictionary = _WeaponDefs.by_id(equipped_id)
			weapon_slot.tooltip_text = "Weapon: %s" % String(def.get("name", equipped_id))

func _equipped_weapon_id() -> String:
	if _miner == null:
		_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner == null:
		return ""
	var equipped: Dictionary = _miner.get("equipped_items")
	if equipped == null:
		return ""
	return String(equipped.get("weapon", ""))

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
