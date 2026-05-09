extends Control
## Modal contract-board window. Shows the vendor's level + XP, the up-to-2
## active contracts (with progress and a Turn-in button), and 5 available
## contracts (with an Activate button). Same panel styling as MachineUI /
## VendorUI / PauseMenu.

const SLOT_SIZE: Vector2 = Vector2(28, 28)

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
static var _icon_cache: Dictionary = {}

static func _icon_for(mid: int) -> Texture2D:
	if _icon_cache.has(mid):
		return _icon_cache[mid]
	if not ITEM_ICONS.has(mid):
		return null
	var tex: Texture2D = load(ITEM_ICONS[mid]) as Texture2D
	_icon_cache[mid] = tex
	return tex

const MODIFIER_LABELS: Dictionary = {
	"rush_order": "RUSH",
	"bulk_order": "BULK",
	"refined_goods": "REFINED",
}
const MODIFIER_COLORS: Dictionary = {
	"rush_order": Color(0.95, 0.35, 0.30, 1),     # red
	"bulk_order": Color(0.45, 0.65, 0.95, 1),     # blue
	"refined_goods": Color(1.0, 0.80, 0.30, 1),   # gold
}

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _level_label: Label = $Panel/Vbox/LevelRow/LevelLabel
@onready var _xp_bar: ProgressBar = $Panel/Vbox/LevelRow/XPBar
@onready var _xp_label: Label = $Panel/Vbox/LevelRow/XPLabel
@onready var _active_section: VBoxContainer = $Panel/Vbox/Scroll/V/ActiveSection
@onready var _available_section: VBoxContainer = $Panel/Vbox/Scroll/V/AvailableSection

var _board: Node = null
var _miner: Node = null

# Cached card style
var _card_style: StyleBoxFlat = null
var _card_active_style: StyleBoxFlat = null

# Per-active-contract countdown labels keyed by active-list index. Refreshed
# in _process so rush orders tick down without rebuilding the whole panel
# each frame.
var _countdown_labels: Dictionary = {}

func _ready() -> void:
	visible = false
	add_to_group("contract_ui")
	_close_btn.pressed.connect(close)
	_card_style = _make_card_style(Color(0.13, 0.15, 0.18, 0.7), Color(0.22, 0.25, 0.30, 1))
	_card_active_style = _make_card_style(Color(0.13, 0.20, 0.30, 0.8), Color(0.40, 0.65, 0.95, 1))
	set_process(true)

func _process(_delta: float) -> void:
	# Tick rush-order countdowns. Cheap — only walks the up-to-2 active
	# contracts. _refresh() rebuilds these labels and _countdown_labels
	# is wiped, so freed labels don't end up here.
	if not visible or _board == null or _countdown_labels.is_empty():
		return
	var now: float = Time.get_unix_time_from_system()
	for idx_v: Variant in _countdown_labels.keys():
		var idx: int = int(idx_v)
		if idx < 0 or idx >= _board.active.size():
			continue
		var lbl: Label = _countdown_labels[idx_v]
		if lbl == null or not is_instance_valid(lbl):
			continue
		var c: Dictionary = _board.active[idx]
		var exp_at: float = float(c.get("expires_at", 0.0))
		if exp_at <= 0.0:
			continue
		var remaining: float = max(0.0, exp_at - now)
		lbl.text = "expires in %s" % _format_mmss(remaining)
		# Tint red when getting tight (<60s).
		if remaining < 60.0:
			lbl.add_theme_color_override("font_color", Color(1, 0.45, 0.40, 1))
		else:
			lbl.add_theme_color_override("font_color", Color(0.95, 0.65, 0.55, 1))

func _format_mmss(seconds: float) -> String:
	var s: int = int(round(seconds))
	var m: int = s / 60
	var r: int = s % 60
	return "%02d:%02d" % [m, r]

func _make_card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = border
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left = 8
	s.content_margin_top = 6
	s.content_margin_right = 8
	s.content_margin_bottom = 6
	return s

func open(board: Node) -> void:
	if HostOnlyGuard.block_if_guest("Contract Board"):
		return
	_board = board
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _board.has_signal("changed") and not _board.changed.is_connected(_refresh):
		_board.changed.connect(_refresh)
	if _miner != null:
		if not _miner.inventory_changed.is_connected(_on_inv_changed):
			_miner.inventory_changed.connect(_on_inv_changed)
		if _miner.has_signal("extended_inventory_changed") and not _miner.extended_inventory_changed.is_connected(_refresh):
			_miner.extended_inventory_changed.connect(_refresh)
		# Refresh-button affordability tracks gold; rebuild on gold changes too.
		if _miner.has_signal("gold_currency_changed") and not _miner.gold_currency_changed.is_connected(_on_gold_changed):
			_miner.gold_currency_changed.connect(_on_gold_changed)
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _board != null and _board.has_signal("changed") and _board.changed.is_connected(_refresh):
		_board.changed.disconnect(_refresh)
	if _miner != null:
		if _miner.inventory_changed.is_connected(_on_inv_changed):
			_miner.inventory_changed.disconnect(_on_inv_changed)
		if _miner.has_signal("extended_inventory_changed") and _miner.extended_inventory_changed.is_connected(_refresh):
			_miner.extended_inventory_changed.disconnect(_refresh)
		if _miner.has_signal("gold_currency_changed") and _miner.gold_currency_changed.is_connected(_on_gold_changed):
			_miner.gold_currency_changed.disconnect(_on_gold_changed)
	_board = null
	_miner = null

func _on_inv_changed(_s: int, _i: int, _g: int) -> void:
	_refresh()

func _on_gold_changed(_amount: int) -> void:
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("machine_interact"):
		close()
		accept_event()

func _refresh() -> void:
	if _board == null:
		return
	_countdown_labels.clear()
	_level_label.text = "LEVEL %d" % _board.level
	_xp_bar.max_value = float(_board.xp_to_next())
	_xp_bar.value = float(_board.xp)
	_xp_label.text = "%d / %d XP" % [_board.xp, _board.xp_to_next()]
	# Active section
	for c: Node in _active_section.get_children():
		c.queue_free()
	var active_header: Label = _section_header("ACTIVE  (%d / %d)" % [_board.active.size(), _board.ACTIVE_MAX])
	_active_section.add_child(active_header)
	if _board.active.is_empty():
		var none: Label = Label.new()
		none.text = "No active contracts. Activate one below."
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_active_section.add_child(none)
	for i: int in _board.active.size():
		_active_section.add_child(_make_card(_board.active[i], i, true))
	# Available section (header + refresh button on a single row)
	for c: Node in _available_section.get_children():
		c.queue_free()
	var avail_header_row: HBoxContainer = HBoxContainer.new()
	avail_header_row.add_theme_constant_override("separation", 8)
	var avail_lbl: Label = _section_header("AVAILABLE")
	avail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_header_row.add_child(avail_lbl)
	var refresh_btn: Button = Button.new()
	refresh_btn.text = "Refresh  (%dg)" % _board.REFRESH_COST
	refresh_btn.disabled = _miner == null or int(_miner.get("gold_currency")) < _board.REFRESH_COST
	refresh_btn.pressed.connect(func() -> void:
		if _board.has_method("refresh") and _miner != null:
			_board.refresh(_miner)
	)
	avail_header_row.add_child(refresh_btn)
	_available_section.add_child(avail_header_row)
	for i: int in _board.available.size():
		_available_section.add_child(_make_card(_board.available[i], i, false))

func _section_header(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 1))
	return lbl

func _make_card(contract: Dictionary, idx: int, is_active: bool) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_active_style if is_active else _card_style)
	# Outer vertical: optional modifier-badge row on top, then the existing
	# items / actions hbox below it.
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	pc.add_child(outer)
	var modifier: String = String(contract.get("modifier", ""))
	if MODIFIER_LABELS.has(modifier):
		outer.add_child(_make_modifier_row(modifier, contract, is_active, idx))
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	outer.add_child(hbox)
	# Items column (icons stacked horizontally + their progress text)
	var items_col: VBoxContainer = VBoxContainer.new()
	items_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_col.add_theme_constant_override("separation", 2)
	hbox.add_child(items_col)
	for entry: Array in MaterialDefs.sort_items_by_rarity(contract.items):
		var mid: int = entry[0]
		var needed: int = entry[1]
		items_col.add_child(_make_item_row(mid, needed, is_active))
	# Reward + button column
	var actions_col: VBoxContainer = VBoxContainer.new()
	actions_col.add_theme_constant_override("separation", 4)
	hbox.add_child(actions_col)
	var reward_lbl: Label = Label.new()
	reward_lbl.text = "%dg  +  %d XP" % [contract.reward_gold, contract.xp]
	reward_lbl.add_theme_font_size_override("font_size", 13)
	reward_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions_col.add_child(reward_lbl)
	# Blueprint-chance hint (only when > 0). Shown as a small line under the
	# reward so it doesn't compete visually with the gold + xp number.
	var chance: float = float(contract.get("blueprint_chance", 0.0))
	if chance > 0.0:
		var bp_lbl: Label = Label.new()
		bp_lbl.text = "%d%% blueprint" % int(round(chance * 100.0))
		bp_lbl.add_theme_font_size_override("font_size", 10)
		bp_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 1))
		bp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		actions_col.add_child(bp_lbl)
	var btn: Button = Button.new()
	if is_active:
		btn.text = "Turn in"
		btn.disabled = (_miner == null) or not _board.can_turn_in(idx, _miner)
		btn.pressed.connect(_on_turn_in.bind(idx))
	else:
		btn.text = "Activate"
		btn.disabled = (_board.active.size() >= _board.ACTIVE_MAX)
		btn.pressed.connect(_on_activate.bind(idx))
	actions_col.add_child(btn)
	return pc

# Modifier badge + (for active rush orders) live countdown. Badge text comes
# from MODIFIER_LABELS and color from MODIFIER_COLORS — defaults handle any
# unknown modifier defensively.
func _make_modifier_row(modifier: String, contract: Dictionary, is_active: bool, idx: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var badge: Label = Label.new()
	badge.text = String(MODIFIER_LABELS.get(modifier, modifier.to_upper()))
	badge.add_theme_font_size_override("font_size", 11)
	var col: Color = MODIFIER_COLORS.get(modifier, Color(0.7, 0.7, 0.7, 1))
	badge.add_theme_color_override("font_color", col)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	badge.add_theme_constant_override("outline_size", 4)
	row.add_child(badge)
	# Countdown only meaningful for active rush orders (expires_at stamped).
	if is_active and modifier == "rush_order":
		var exp_at: float = float(contract.get("expires_at", 0.0))
		var count_lbl: Label = Label.new()
		count_lbl.add_theme_font_size_override("font_size", 11)
		count_lbl.add_theme_color_override("font_color", Color(0.95, 0.65, 0.55, 1))
		count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var initial_remaining: float = max(0.0, exp_at - Time.get_unix_time_from_system())
		count_lbl.text = "expires in %s" % _format_mmss(initial_remaining)
		row.add_child(count_lbl)
		_countdown_labels[idx] = count_lbl
	return row

func _make_item_row(material_id: int, needed: int, show_progress: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# Icon slot
	var slot: Panel = Panel.new()
	slot.custom_minimum_size = SLOT_SIZE
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
	slot.add_child(fill)
	var tex: Texture2D = _icon_for(material_id)
	if tex != null:
		var icon: TextureRect = TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.offset_left = 3
		icon.offset_top = 3
		icon.offset_right = -3
		icon.offset_bottom = -3
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	row.add_child(slot)
	# Label
	var lbl: Label = Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if show_progress:
		var have: int = _miner.get_material_count(material_id) if _miner != null else 0
		# Show actual inventory count over the requirement so overlapping
		# contracts can each see the full stack.
		lbl.text = "%s   %d / %d" % [MaterialDefs.DISPLAY_NAME[material_id], have, needed]
		if have >= needed:
			lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55, 1))
		else:
			lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
	else:
		lbl.text = "%d × %s" % [needed, MaterialDefs.DISPLAY_NAME[material_id]]
		lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
	row.add_child(lbl)
	return row

func _on_activate(idx: int) -> void:
	if _board != null:
		_board.activate(idx)

func _on_turn_in(idx: int) -> void:
	if _board != null and _miner != null:
		_board.turn_in(idx, _miner)
