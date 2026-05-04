extends Control
## Build catalog overlay (brief 05). Opened with G in build mode. Lists every
## piece in BuildPieceDefs grouped by category. Clicking a row makes it the
## active placement; clicking a row then a number key 1-6 binds it to that
## quickbar slot.

const _BuildPieceDefs: GDScript = preload("res://scripts/factory/build_piece_defs.gd")
const _MD: GDScript = preload("res://scripts/factory/material_defs.gd")

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

const CATEGORIES: Array = [
	[&"factory",   "Factory"],
	[&"structure", "Structure"],
	[&"utility",   "Utility"],
]

var _panel_style: StyleBoxFlat = null
var _row_style: StyleBoxFlat = null
var _row_style_selected: StyleBoxFlat = null

@onready var _panel: Panel = $Panel
@onready var _close_btn: Button = $Panel/Vbox/Header/CloseBtn
@onready var _hint_lbl: Label = $Panel/Vbox/HintRow/Hint
@onready var _tabs: TabContainer = $Panel/Vbox/Tabs

# Tracks the most recently clicked piece so a follow-up number key binds it.
var _selected_piece: StringName = &""

func _ready() -> void:
	add_to_group("build_catalog_ui")
	visible = false
	_init_styles()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_close_btn.pressed.connect(close)
	_populate()
	# Refresh affordability when inventory changes (only while open).
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		if miner.has_signal("inventory_changed") and not miner.inventory_changed.is_connected(_on_inv_changed):
			miner.inventory_changed.connect(_on_inv_changed)
		if miner.has_signal("extended_inventory_changed") and not miner.extended_inventory_changed.is_connected(_repopulate_if_open):
			miner.extended_inventory_changed.connect(_repopulate_if_open)
	# Listen for blueprint unlocks so locked rows update when the player
	# turns in the corresponding contract.
	var unlocks: Node = get_node_or_null("/root/Unlocks")
	if unlocks != null and unlocks.has_signal("unlocked"):
		if not unlocks.unlocked.is_connected(_on_unlocked):
			unlocks.unlocked.connect(_on_unlocked)

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_populate()
	_update_hint()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_selected_piece = &""

func _on_inv_changed(_s: int, _i: int, _g: int) -> void:
	_repopulate_if_open()

func _on_unlocked(_id: String) -> void:
	_repopulate_if_open()

func _repopulate_if_open() -> void:
	if visible:
		_populate()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		accept_event()
		return
	# Number keys: bind selected piece to that slot.
	if _selected_piece == &"":
		return
	var slot: int = -1
	if event.is_action_pressed("build_slot_1"): slot = 0
	elif event.is_action_pressed("build_slot_2"): slot = 1
	elif event.is_action_pressed("build_slot_3"): slot = 2
	elif event.is_action_pressed("build_slot_4"): slot = 3
	elif event.is_action_pressed("build_slot_5"): slot = 4
	elif event.is_action_pressed("build_slot_6"): slot = 5
	if slot >= 0:
		BuildController.bind_slot(slot, _selected_piece)
		_update_hint("Bound %s to slot %d" % [_name_of(_selected_piece), slot + 1])
		accept_event()

func _populate() -> void:
	# Tear down existing tabs first; rebuild from scratch.
	for child: Node in _tabs.get_children():
		child.queue_free()
	for entry: Array in CATEGORIES:
		var cat: StringName = entry[0]
		var title: String = String(entry[1])
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.name = title
		var rows: VBoxContainer = VBoxContainer.new()
		rows.add_theme_constant_override("separation", 4)
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		_tabs.add_child(scroll)
		for piece: Dictionary in _BuildPieceDefs.by_category(cat):
			rows.add_child(_make_row(piece))

func _make_row(piece: Dictionary) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	var is_selected: bool = (StringName(String(piece.id)) == _selected_piece)
	var locked: bool = _BuildPieceDefs.is_locked(piece)
	pc.add_theme_stylebox_override("panel", _row_style_selected if is_selected else _row_style)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	if locked:
		pc.modulate = Color(1, 1, 1, 0.55)
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	pc.add_child(hbox)
	# Name + description
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)
	var name_lbl: Label = Label.new()
	name_lbl.text = String(piece.get("name", String(piece.id)))
	name_lbl.add_theme_font_size_override("font_size", 14)
	col.add_child(name_lbl)
	var desc_lbl: Label = Label.new()
	if locked:
		var bp_id: String = String(piece.get("requires_blueprint", ""))
		var bp_name: String = bp_id
		# Resolve via BlueprintDefs if available for a friendlier label.
		var BP: GDScript = load("res://scripts/blueprint_defs.gd") as GDScript
		if BP != null:
			bp_name = String(BP.call("name_for", bp_id))
		desc_lbl.text = "Locked — needs %s" % bp_name
		desc_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.45, 1))
	else:
		desc_lbl.text = String(piece.get("description", ""))
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78, 1))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	col.add_child(desc_lbl)
	# Cost
	var cost_box: HBoxContainer = HBoxContainer.new()
	cost_box.add_theme_constant_override("separation", 6)
	hbox.add_child(cost_box)
	var raw_cost: Dictionary = piece.get("cost", {})
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	var affordable: bool = _BuildPieceDefs.can_afford(miner, raw_cost) if not raw_cost.is_empty() else true
	if raw_cost.is_empty():
		var free_lbl: Label = Label.new()
		free_lbl.text = "free"
		free_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
		free_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_box.add_child(free_lbl)
	else:
		var eff: Dictionary = _BuildPieceDefs.effective_cost(raw_cost)
		for mid: Variant in eff.keys():
			var qty: int = int(eff[mid])
			var have: int = miner.call("get_material_count", int(mid)) if miner != null else 0
			var lbl: Label = Label.new()
			lbl.text = "%s %d/%d" % [_short_name(int(mid)), have, qty]
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 11)
			if have < qty:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4, 1))
			else:
				lbl.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7, 1))
			cost_box.add_child(lbl)
	# Action buttons
	var pick_btn: Button = Button.new()
	pick_btn.text = "Locked" if locked else "Equip"
	pick_btn.disabled = locked or not affordable
	pick_btn.tooltip_text = "Equip (held by mouse)"
	pick_btn.pressed.connect(_on_pick.bind(StringName(String(piece.id))))
	hbox.add_child(pick_btn)
	# Make the whole row clickable too — but skip the click for locked pieces
	# so the player can't accidentally equip something they can't place.
	if not locked:
		pc.gui_input.connect(_on_row_input.bind(StringName(String(piece.id))))
	return pc

func _on_row_input(event: InputEvent, piece_id: StringName) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_pick(piece_id)

func _on_pick(piece_id: StringName) -> void:
	_selected_piece = piece_id
	BuildController.select_kind(piece_id)
	_populate()   # refresh selection highlight
	_update_hint()

func _update_hint(override: String = "") -> void:
	if override != "":
		_hint_lbl.text = override
		return
	if _selected_piece == &"":
		_hint_lbl.text = "Click a piece to equip. Then press 1-6 to bind it to that hotbar slot."
	else:
		_hint_lbl.text = "Selected %s — press 1-6 to bind to a hotbar slot, or close to place." % _name_of(_selected_piece)

func _name_of(piece_id: StringName) -> String:
	var def: Dictionary = _BuildPieceDefs.by_id(piece_id)
	return String(def.get("name", String(piece_id)))

func _short_name(material_id: int) -> String:
	# Compact label fits in the row better than full names.
	var n: String = String(_MD.DISPLAY_NAME.get(material_id, ""))
	# Strip "Iron / Gold " prefix to keep things tight.
	return n

func _init_styles() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.09, 0.10, 0.13, 0.96)
	_panel_style.border_width_left = 2
	_panel_style.border_width_top = 2
	_panel_style.border_width_right = 2
	_panel_style.border_width_bottom = 2
	_panel_style.border_color = Color(0.22, 0.25, 0.30, 1)
	_panel_style.corner_radius_top_left = 8
	_panel_style.corner_radius_top_right = 8
	_panel_style.corner_radius_bottom_right = 8
	_panel_style.corner_radius_bottom_left = 8
	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = Color(0.13, 0.15, 0.19, 0.85)
	_row_style.corner_radius_top_left = 4
	_row_style.corner_radius_top_right = 4
	_row_style.corner_radius_bottom_right = 4
	_row_style.corner_radius_bottom_left = 4
	_row_style.content_margin_left = 8
	_row_style.content_margin_right = 8
	_row_style.content_margin_top = 6
	_row_style.content_margin_bottom = 6
	_row_style_selected = _row_style.duplicate() as StyleBoxFlat
	_row_style_selected.bg_color = Color(0.20, 0.27, 0.36, 0.95)
	_row_style_selected.border_width_left = 2
	_row_style_selected.border_width_top = 2
	_row_style_selected.border_width_right = 2
	_row_style_selected.border_width_bottom = 2
	_row_style_selected.border_color = Color(0.95, 0.85, 0.45, 1)
