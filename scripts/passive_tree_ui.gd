extends Control
## Modal passive-tree window. Six tabs (one per branch). Each tab lists every
## perk in that branch with name, current/max rank, cost for the next rank,
## description, lock status, and a Buy button.

const _PerkDefs: GDScript = preload("res://scripts/passive_perk_defs.gd")

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _gold_label: Label = $Panel/Vbox/GoldRow/Amount
@onready var _tabs: TabContainer = $Panel/Vbox/Tabs

var _miner: Node = null

# Branch -> VBoxContainer that holds the rows for that branch.
var _branch_lists: Dictionary = {}

var _row_style: StyleBoxFlat = null
var _row_owned_style: StyleBoxFlat = null
var _row_locked_style: StyleBoxFlat = null

func _ready() -> void:
	visible = false
	add_to_group("passive_tree_ui")
	_close_btn.pressed.connect(close)
	_row_style = _make_row_style(Color(0.13, 0.15, 0.18, 0.7), Color(0.32, 0.32, 0.45, 1))
	_row_owned_style = _make_row_style(Color(0.13, 0.20, 0.16, 0.85), Color(0.55, 0.85, 0.55, 1))
	_row_locked_style = _make_row_style(Color(0.10, 0.11, 0.13, 0.7), Color(0.22, 0.22, 0.26, 1))
	_build_tabs()
	# Listen to PassiveTree changes so a buy from elsewhere refreshes the UI.
	var tree: Node = get_node_or_null("/root/PassiveTree")
	if tree != null and tree.has_signal("changed") and not tree.changed.is_connected(_refresh):
		tree.changed.connect(_refresh)

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

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner != null and _miner.has_signal("gold_currency_changed"):
		if not _miner.gold_currency_changed.is_connected(_on_gold_changed):
			_miner.gold_currency_changed.connect(_on_gold_changed)
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _miner != null and _miner.has_signal("gold_currency_changed"):
		if _miner.gold_currency_changed.is_connected(_on_gold_changed):
			_miner.gold_currency_changed.disconnect(_on_gold_changed)
	_miner = null

func _on_gold_changed(_amount: int) -> void:
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("passive_tree"):
		close()
		accept_event()

# --- Build / refresh ------------------------------------------------------

func _build_tabs() -> void:
	# Clean any existing tab children (the .tscn ships with no Tabs children;
	# we add one Control per branch here so the catalog stays the source of
	# truth for branch order).
	for c: Node in _tabs.get_children():
		c.queue_free()
	_branch_lists.clear()
	for branch: StringName in _PerkDefs.BRANCH_ORDER:
		var page: Control = Control.new()
		page.name = _PerkDefs.branch_name(branch)
		_tabs.add_child(page)
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.anchor_right = 1.0
		scroll.anchor_bottom = 1.0
		page.add_child(scroll)
		var v: VBoxContainer = VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 6)
		scroll.add_child(v)
		_branch_lists[branch] = v

func _refresh() -> void:
	_gold_label.text = "%d g" % (int(_miner.get("gold_currency")) if _miner != null else 0)
	for branch: StringName in _PerkDefs.BRANCH_ORDER:
		var list: VBoxContainer = _branch_lists.get(branch, null)
		if list == null:
			continue
		for c: Node in list.get_children():
			c.queue_free()
		for perk: Dictionary in _PerkDefs.by_branch(branch):
			list.add_child(_make_row(perk))

func _make_row(perk: Dictionary) -> PanelContainer:
	var tree: Node = get_node_or_null("/root/PassiveTree")
	var rank: int = 0
	if tree != null:
		rank = int(tree.call("current_rank", String(perk.id)))
	var max_rank: int = int(perk.max_rank)
	var maxed: bool = rank >= max_rank
	var owned: bool = rank > 0
	var meets: bool = true
	if tree != null:
		# Use the perk-defs helper directly with the autoload's current rank
		# dict — peek via a probe call so we don't need to expose internals.
		var owned_ranks: Dictionary = {}
		for d: Dictionary in _PerkDefs.ITEMS:
			var r: int = int(tree.call("current_rank", String(d.id)))
			if r > 0:
				owned_ranks[String(d.id)] = r
		meets = _PerkDefs.meets_requirements(perk, owned_ranks)

	var pc: PanelContainer = PanelContainer.new()
	if not meets:
		pc.add_theme_stylebox_override("panel", _row_locked_style)
	elif owned:
		pc.add_theme_stylebox_override("panel", _row_owned_style)
	else:
		pc.add_theme_stylebox_override("panel", _row_style)

	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)

	# Title row: name + rank pip.
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	v.add_child(title_row)
	var name_lbl: Label = Label.new()
	name_lbl.text = String(perk.name)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", _PerkDefs.branch_color(perk.branch))
	title_row.add_child(name_lbl)
	var rank_lbl: Label = Label.new()
	rank_lbl.text = "Rank %d / %d" % [rank, max_rank]
	rank_lbl.add_theme_font_size_override("font_size", 12)
	rank_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
	title_row.add_child(rank_lbl)

	# Description.
	var desc_lbl: Label = Label.new()
	desc_lbl.text = String(perk.description)
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85, 1))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc_lbl)

	# Action row: cost / lock note + Buy button.
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	v.add_child(action_row)
	var info_lbl: Label = Label.new()
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.add_theme_font_size_override("font_size", 12)
	if maxed:
		info_lbl.text = "MAX"
		info_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55, 1))
	elif not meets:
		info_lbl.text = "Locked  ·  requires %s" % _requires_text(perk)
		info_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.6, 1))
	else:
		info_lbl.text = "%d g  ·  next rank %d" % [int(perk.cost), rank + 1]
		info_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	action_row.add_child(info_lbl)

	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(120, 30)
	if maxed:
		btn.text = "Maxed"
		btn.disabled = true
	else:
		btn.text = "Buy"
		var can_afford: bool = tree != null and bool(tree.call("can_buy", String(perk.id), _miner))
		btn.disabled = not can_afford
		btn.pressed.connect(func() -> void:
			var t: Node = get_node_or_null("/root/PassiveTree")
			if t != null:
				t.call("buy", String(perk.id), _miner)
		)
	action_row.add_child(btn)
	return pc

func _requires_text(perk: Dictionary) -> String:
	var names: Array[String] = []
	for req: Variant in perk.get("requires", []):
		var d: Dictionary = _PerkDefs.by_id(String(req))
		names.append(String(d.get("name", req)))
	return ", ".join(names)
