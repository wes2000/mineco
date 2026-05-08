extends Control
## Modal item-shop window. Shows pickaxes, scanners, and utility items as
## category sections inside a scroll container. Each row carries the item's
## price + a Buy or Equip button driven by Miner.owns_item / is_equipped /
## can_buy_item.

# Preload to avoid the parser needing ShopItemDefs in its class_name cache.
const _ShopDefs: GDScript = preload("res://scripts/shop_item_defs.gd")
const _BlueprintDefs: GDScript = preload("res://scripts/blueprint_defs.gd")
const _CrosshairHUD: GDScript = preload("res://scripts/crosshair_hud.gd")

# 5 tabs across the top of the shop. Cosmetics is special: instead of a
# single column it splits into Crosshair shapes (left) and Colors (right).
const TAB_NAMES: Array = ["Pickaxes", "Weapons", "Scanners", "Utility", "Cosmetics"]
const TAB_CATEGORIES: Array[StringName] = [
	&"pickaxe", &"weapon", &"scanner", &"utility", &""   # cosmetics handled separately
]
const TAB_ACCENT: Array[Color] = [
	Color(0.95, 0.65, 0.40, 1),
	Color(0.95, 0.45, 0.45, 1),
	Color(0.55, 0.85, 0.95, 1),
	Color(0.85, 0.85, 0.55, 1),
	Color(0.75, 0.85, 1.0, 1),
]

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _gold_label: Label = $Panel/Vbox/GoldRow/Amount
@onready var _tabs: TabContainer = $Panel/Vbox/Tabs

var _miner: Node = null

var _row_style: StyleBoxFlat = null
var _row_owned_style: StyleBoxFlat = null

func _ready() -> void:
	visible = false
	add_to_group("item_shop_ui")
	_close_btn.pressed.connect(close)
	_row_style = _make_row_style(Color(0.13, 0.15, 0.18, 0.7), Color(0.32, 0.22, 0.18, 1))
	_row_owned_style = _make_row_style(Color(0.13, 0.20, 0.16, 0.85), Color(0.55, 0.85, 0.55, 1))

func _make_row_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left = 8
	s.content_margin_top = 6
	s.content_margin_right = 8
	s.content_margin_bottom = 6
	return s

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner != null:
		if _miner.has_signal("gold_currency_changed") and not _miner.gold_currency_changed.is_connected(_on_gold_changed):
			_miner.gold_currency_changed.connect(_on_gold_changed)
		if _miner.has_signal("shop_inventory_changed") and not _miner.shop_inventory_changed.is_connected(_refresh):
			_miner.shop_inventory_changed.connect(_refresh)
	# Listen for blueprint unlocks while the shop is open so a turn-in that
	# drops a blueprint flips the relevant row from Locked to Buy live.
	var unlocks: Node = get_node_or_null("/root/Unlocks")
	if unlocks != null and unlocks.has_signal("unlocked") and not unlocks.unlocked.is_connected(_on_unlocked):
		unlocks.unlocked.connect(_on_unlocked)
	# Same idea for rank-ups — a promotion mid-shopping should immediately
	# enable rank-gated rows.
	var company: Node = get_node_or_null("/root/CompanyProgress")
	if company != null and company.has_signal("rank_up") and not company.rank_up.is_connected(_on_rank_up):
		company.rank_up.connect(_on_rank_up)
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _miner != null:
		if _miner.has_signal("gold_currency_changed") and _miner.gold_currency_changed.is_connected(_on_gold_changed):
			_miner.gold_currency_changed.disconnect(_on_gold_changed)
		if _miner.has_signal("shop_inventory_changed") and _miner.shop_inventory_changed.is_connected(_refresh):
			_miner.shop_inventory_changed.disconnect(_refresh)
	var unlocks: Node = get_node_or_null("/root/Unlocks")
	if unlocks != null and unlocks.has_signal("unlocked") and unlocks.unlocked.is_connected(_on_unlocked):
		unlocks.unlocked.disconnect(_on_unlocked)
	var company: Node = get_node_or_null("/root/CompanyProgress")
	if company != null and company.has_signal("rank_up") and company.rank_up.is_connected(_on_rank_up):
		company.rank_up.disconnect(_on_rank_up)
	_miner = null

func _on_unlocked(_blueprint_id: String) -> void:
	_refresh()

func _on_rank_up(_new_rank: int, _name: String) -> void:
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
	# Wipe + rebuild the entire tab list. Each tab is a fresh ScrollContainer
	# so Godot can scroll long category lists independently. Tabs are renamed
	# via TabContainer.set_tab_title since the title is on the container, not
	# the child name.
	for c: Node in _tabs.get_children():
		c.queue_free()
	_gold_label.text = "%d g" % (int(_miner.get("gold_currency")) if _miner != null else 0)
	var preserved_tab: int = clampi(_tabs.current_tab, 0, TAB_NAMES.size() - 1)
	for i: int in TAB_NAMES.size():
		var tab_root: ScrollContainer = ScrollContainer.new()
		tab_root.name = TAB_NAMES[i]
		_tabs.add_child(tab_root)
		_tabs.set_tab_title(i, TAB_NAMES[i])
		var cat: StringName = TAB_CATEGORIES[i]
		if cat == &"":
			tab_root.add_child(_build_cosmetics_tab())
		else:
			tab_root.add_child(_build_simple_tab(cat))
	# Restore previous tab selection so a refresh from a buy/equip doesn't
	# yank the player back to Pickaxes.
	_tabs.current_tab = preserved_tab

# Single-column tab body for the existing simple categories. Returns a VBox
# of rows; the parent ScrollContainer handles overflow.
func _build_simple_tab(cat: StringName) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: Dictionary in _ShopDefs.by_category(cat):
		v.add_child(_make_row(item))
	return v

# Cosmetics tab: two columns side-by-side. Left = crosshair shapes, right =
# colors. Both columns scroll inside the parent ScrollContainer if their
# combined height exceeds the panel.
func _build_cosmetics_tab() -> HBoxContainer:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_make_column_header("CROSSHAIRS", TAB_ACCENT[4]))
	for item: Dictionary in _ShopDefs.by_category(_ShopDefs.CAT_CROSSHAIR):
		left.add_child(_make_row(item))
	hbox.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_make_column_header("COLORS", TAB_ACCENT[4]))
	for item: Dictionary in _ShopDefs.by_category(_ShopDefs.CAT_CROSSHAIR_COLOR):
		right.add_child(_make_row(item))
	hbox.add_child(right)
	return hbox

func _make_column_header(text: String, accent: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", accent)
	return lbl

func _make_row(item: Dictionary) -> PanelContainer:
	var owned: bool = _miner != null and bool(_miner.call("owns_item", String(item.id)))
	var equipped: bool = _miner != null and bool(_miner.call("is_equipped", String(item.id)))
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _row_owned_style if owned else _row_style)
	# Outer hbox: icon column on the left, info column on the right.
	var outer: HBoxContainer = HBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	pc.add_child(outer)
	# Icon — texture for normal items, custom-drawn preview for crosshair
	# shapes / colors (which ship without icon files).
	var icon_tex: Texture2D = _ShopDefs.icon_for(item)
	if icon_tex != null:
		var ic: TextureRect = TextureRect.new()
		ic.texture = icon_tex
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		outer.add_child(ic)
	elif String(item.category) == String(_ShopDefs.CAT_CROSSHAIR):
		outer.add_child(_make_crosshair_shape_preview(String(item.get("crosshair_style", "dot"))))
	elif String(item.category) == String(_ShopDefs.CAT_CROSSHAIR_COLOR):
		outer.add_child(_make_crosshair_color_swatch(item.get("crosshair_color", Color(1, 1, 1, 1))))
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(v)
	# Title row: name + status / equipped badge
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	v.add_child(title_row)
	var name_lbl: Label = Label.new()
	name_lbl.text = String(item.name)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	title_row.add_child(name_lbl)
	if equipped:
		var eq_lbl: Label = Label.new()
		eq_lbl.text = "EQUIPPED"
		eq_lbl.add_theme_font_size_override("font_size", 11)
		eq_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55, 1))
		title_row.add_child(eq_lbl)
	# Description
	var desc_lbl: Label = Label.new()
	desc_lbl.text = String(item.description)
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85, 1))
	v.add_child(desc_lbl)
	# Action row: requirement / price + button
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	v.add_child(action_row)
	var info_lbl: Label = Label.new()
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.add_theme_font_size_override("font_size", 12)
	if not owned:
		info_lbl.text = "%d g" % int(item.price)
		info_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
		# Locked-by-prereq hint, since it's the most common reason a button is disabled.
		# Blueprint gate is checked first so its message wins over the
		# generic "requires <other items>" string when both apply.
		if _miner != null and not _ShopDefs.meets_requirements(item, _miner.owned_items):
			var bp_id: String = _ShopDefs.required_blueprint(item)
			var unlocks: Node = get_node_or_null("/root/Unlocks")
			var bp_locked: bool = bp_id != "" and (unlocks == null or not bool(unlocks.call("has", bp_id)))
			# Rank gate is the most-meaningful late-game lock so it wins over
			# the generic prerequisite list when both fail.
			var req_rank: int = _ShopDefs.required_rank(item)
			var company: Node = get_node_or_null("/root/CompanyProgress")
			var rank_locked: bool = req_rank > 0 and (company == null or int(company.get("rank")) < req_rank)
			if bp_locked:
				info_lbl.text = "%d g  ·  needs %s" % [int(item.price), _BlueprintDefs.name_for(bp_id)]
			elif rank_locked:
				info_lbl.text = "%d g  ·  needs Mine Co. rank %d" % [int(item.price), req_rank]
			else:
				info_lbl.text = "%d g  ·  requires %s" % [int(item.price), _requires_text(item)]
			info_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.6, 1))
	else:
		info_lbl.text = "Owned"
		info_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55, 1))
	action_row.add_child(info_lbl)
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(120, 30)
	if not owned:
		btn.text = "Buy"
		btn.disabled = _miner == null or not bool(_miner.call("can_buy_item", item))
		btn.pressed.connect(func() -> void:
			if _miner != null:
				_miner.call("buy_item", String(item.id))
		)
	elif _ShopDefs.is_equip_category(item.category):
		btn.text = "Equipped" if equipped else "Equip"
		btn.disabled = equipped
		btn.pressed.connect(func() -> void:
			if _miner != null:
				_miner.call("equip_item", String(item.id))
		)
	else:
		# Utility — owned, no equip, button is a placeholder so spacing matches.
		btn.text = "Active"
		btn.disabled = true
	action_row.add_child(btn)
	return pc

func _requires_text(item: Dictionary) -> String:
	var names: Array[String] = []
	for req: Variant in item.get("requires", []):
		var d: Dictionary = _ShopDefs.by_id(String(req))
		names.append(String(d.get("name", req)))
	return ", ".join(names)

# Small Control that custom-draws a crosshair shape (white) at the icon
# position so the row visually communicates what shape it sells. Color
# preview is a separate helper.
func _make_crosshair_shape_preview(style: String) -> Control:
	var preview: Control = Control.new()
	preview.custom_minimum_size = Vector2(36, 36)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.draw.connect(func() -> void:
		_CrosshairHUD.draw_preview(preview, preview.size * 0.5, style, Color(1, 1, 1, 1), 1.0)
	)
	return preview

# Color rows preview as a filled dot tinted with the item's color so the
# rows differ visually beyond the name label.
func _make_crosshair_color_swatch(color: Color) -> Control:
	var preview: Control = Control.new()
	preview.custom_minimum_size = Vector2(36, 36)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.draw.connect(func() -> void:
		_CrosshairHUD.draw_preview(preview, preview.size * 0.5, "dot", color, 2.0)
	)
	return preview
