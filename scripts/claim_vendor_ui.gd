extends Control
## Modal land-claim window. Header shows vendor level + XP, then either an
## "Owned claim" panel (with release button + remaining ore estimate) or
## nothing if no claim is owned, then a list of available islands at the
## vendor's current level.

const ORE_ICONS: Dictionary = {
	MaterialDefs.MaterialId.STONE:    "res://assets/icons/factory/item_stone.svg",
	MaterialDefs.MaterialId.IRON_ORE: "res://assets/icons/factory/item_iron_ore.svg",
	MaterialDefs.MaterialId.GOLD_ORE: "res://assets/icons/factory/item_gold_ore.svg",
}
const TIER_COLOR: Dictionary = {
	1: Color(0.65, 0.45, 0.25, 1),     # bronze
	2: Color(0.78, 0.80, 0.85, 1),     # silver
	3: Color(0.95, 0.78, 0.30, 1),     # gold
	4: Color(0.55, 0.85, 0.95, 1),     # platinum
	5: Color(0.85, 0.55, 1.00, 1),     # diamond
}
static var _icon_cache: Dictionary = {}

static func _icon_for(mid: int) -> Texture2D:
	if _icon_cache.has(mid):
		return _icon_cache[mid]
	if not ORE_ICONS.has(mid):
		return null
	var tex: Texture2D = load(ORE_ICONS[mid]) as Texture2D
	_icon_cache[mid] = tex
	return tex

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _level_label: Label = $Panel/Vbox/LevelRow/LevelLabel
@onready var _xp_bar: ProgressBar = $Panel/Vbox/LevelRow/XPBar
@onready var _xp_label: Label = $Panel/Vbox/LevelRow/XPLabel
@onready var _owned_section: VBoxContainer = $Panel/Vbox/Scroll/V/OwnedSection
@onready var _available_section: VBoxContainer = $Panel/Vbox/Scroll/V/AvailableSection

var _board: Node = null
var _miner: Node = null

var _card_style: StyleBoxFlat = null
var _card_owned_style: StyleBoxFlat = null

func _ready() -> void:
	visible = false
	add_to_group("claim_vendor_ui")
	_close_btn.pressed.connect(close)
	_card_style = _make_card_style(Color(0.13, 0.15, 0.18, 0.7), Color(0.22, 0.30, 0.22, 1))
	_card_owned_style = _make_card_style(Color(0.13, 0.22, 0.16, 0.85), Color(0.45, 0.85, 0.40, 1))

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
	s.content_margin_left = 10
	s.content_margin_top = 8
	s.content_margin_right = 10
	s.content_margin_bottom = 8
	return s

func open(board: Node) -> void:
	_board = board
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _board != null and not _board.changed.is_connected(_refresh):
		_board.changed.connect(_refresh)
	if _miner != null and not _miner.gold_currency_changed.is_connected(_on_gold_changed):
		_miner.gold_currency_changed.connect(_on_gold_changed)
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _board != null and _board.changed.is_connected(_refresh):
		_board.changed.disconnect(_refresh)
	if _miner != null and _miner.gold_currency_changed.is_connected(_on_gold_changed):
		_miner.gold_currency_changed.disconnect(_on_gold_changed)
	_board = null
	_miner = null

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
	# Header level/xp.
	_level_label.text = "LEVEL %d  (%s)" % [_board.level, ClaimDef.tier(_board.level).label]
	if _board.level >= 5:
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_label.text = "MAX"
	else:
		_xp_bar.max_value = float(_board.xp_to_next())
		_xp_bar.value = float(_board.xp)
		_xp_label.text = "%d / %d XP" % [_board.xp, _board.xp_to_next()]
	# Owned section.
	for c: Node in _owned_section.get_children():
		c.queue_free()
	if _board.has_owned():
		_owned_section.add_child(_section_header("YOUR CLAIM"))
		_owned_section.add_child(_make_owned_card(_board.owned_island()))
	# Available section.
	for c: Node in _available_section.get_children():
		c.queue_free()
	var avail: Array = _board.available()
	_available_section.add_child(_section_header("AVAILABLE  (%d)" % avail.size()))
	if avail.is_empty() and _board.has_owned():
		var none: Label = Label.new()
		none.text = "Release your current claim to buy another."
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_available_section.add_child(none)
	elif avail.is_empty():
		var none: Label = Label.new()
		none.text = "Come back after I've found more claims to sell."
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_available_section.add_child(none)
	for isle: Dictionary in avail:
		_available_section.add_child(_make_available_card(isle))

func _section_header(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55, 1))
	return lbl

func _make_available_card(isle: Dictionary) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_style)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	# Title row: name + tier label
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	v.add_child(title_row)
	var name_lbl: Label = Label.new()
	name_lbl.text = String(isle.name)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 15)
	title_row.add_child(name_lbl)
	var tier_lbl: Label = Label.new()
	var tier_info: Dictionary = ClaimDef.tier(isle.tier)
	tier_lbl.text = "T%d  %s" % [isle.tier, tier_info.label]
	tier_lbl.add_theme_font_size_override("font_size", 12)
	tier_lbl.add_theme_color_override("font_color", TIER_COLOR.get(int(isle.tier), Color.WHITE))
	title_row.add_child(tier_lbl)
	# Yield estimate row
	v.add_child(_make_yield_row(isle.tier))
	# Buy row
	var buy_row: HBoxContainer = HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	v.add_child(buy_row)
	var price: int = int(tier_info.price)
	var price_lbl: Label = Label.new()
	price_lbl.text = "%d g" % price
	price_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	buy_row.add_child(price_lbl)
	var btn: Button = Button.new()
	btn.text = "Buy claim"
	btn.disabled = (_miner == null) or not _board.can_buy(String(isle.id), _miner)
	if _miner != null and int(_miner.get("gold_currency")) < price:
		btn.text = "Need %d g" % (price - int(_miner.get("gold_currency")))
	if _board.has_owned():
		btn.disabled = true
		btn.text = "Already own a claim"
	btn.pressed.connect(_on_buy.bind(String(isle.id)))
	buy_row.add_child(btn)
	return pc

func _make_owned_card(isle: Dictionary) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_owned_style)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	v.add_child(title_row)
	var name_lbl: Label = Label.new()
	name_lbl.text = "%s  ✓" % String(isle.name)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 15)
	title_row.add_child(name_lbl)
	var tier_lbl: Label = Label.new()
	var tier_info: Dictionary = ClaimDef.tier(isle.tier)
	tier_lbl.text = "T%d  %s" % [isle.tier, tier_info.label]
	tier_lbl.add_theme_font_size_override("font_size", 12)
	tier_lbl.add_theme_color_override("font_color", TIER_COLOR.get(int(isle.tier), Color.WHITE))
	title_row.add_child(tier_lbl)
	# Coordinates so the player can find it.
	var coord_lbl: Label = Label.new()
	coord_lbl.text = "Position: %d, %d   ·   sail there with your boat" % [int(isle.center.x), int(isle.center.y)]
	coord_lbl.add_theme_font_size_override("font_size", 11)
	coord_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
	v.add_child(coord_lbl)
	# Remaining estimate
	v.add_child(_make_remaining_row())
	# Release row
	var rel_row: HBoxContainer = HBoxContainer.new()
	rel_row.add_theme_constant_override("separation", 8)
	v.add_child(rel_row)
	var preview: int = _board.release_xp_preview()
	var preview_lbl: Label = Label.new()
	preview_lbl.text = "Release for +%d XP" % preview
	preview_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55, 1))
	rel_row.add_child(preview_lbl)
	var btn: Button = Button.new()
	btn.text = "Release claim"
	btn.pressed.connect(_on_release)
	rel_row.add_child(btn)
	return pc

func _make_yield_row(tier: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var prefix: Label = Label.new()
	prefix.text = "≈ yield"
	prefix.add_theme_font_size_override("font_size", 11)
	prefix.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
	row.add_child(prefix)
	var yields: Dictionary = ClaimDef.approx_ore_yield(tier)
	for mid: int in [MaterialDefs.MaterialId.STONE, MaterialDefs.MaterialId.IRON_ORE, MaterialDefs.MaterialId.GOLD_ORE]:
		var amt: int = int(yields.get(mid, 0))
		if amt <= 0:
			continue
		row.add_child(_make_ore_chip(mid, amt))
	return row

func _make_remaining_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var prefix: Label = Label.new()
	prefix.text = "remaining"
	prefix.add_theme_font_size_override("font_size", 11)
	prefix.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
	row.add_child(prefix)
	var remaining: Dictionary = _board.owned_remaining_estimate()
	for mid: int in [MaterialDefs.MaterialId.STONE, MaterialDefs.MaterialId.IRON_ORE, MaterialDefs.MaterialId.GOLD_ORE]:
		var amt: int = int(remaining.get(mid, 0))
		row.add_child(_make_ore_chip(mid, amt))
	return row

func _make_ore_chip(mid: int, amt: int) -> HBoxContainer:
	var chip: HBoxContainer = HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	var tex: Texture2D = _icon_for(mid)
	if tex != null:
		var ic: TextureRect = TextureRect.new()
		ic.texture = tex
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(ic)
	var lbl: Label = Label.new()
	lbl.text = "≈ %d" % amt
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
	chip.add_child(lbl)
	return chip

func _on_buy(island_id: String) -> void:
	if _board != null and _miner != null:
		_board.buy(island_id, _miner)

func _on_release() -> void:
	if _board != null:
		_board.release()
