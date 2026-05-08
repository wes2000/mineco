extends Control
## Top-left always-visible tracker for the player's active contracts. Shows
## each requirement's progress (have / need) and the reward. Hides itself
## entirely when there are no active contracts.

const PANEL_WIDTH: float = 260.0

const MODIFIER_LABELS: Dictionary = {
	"rush_order": "RUSH",
	"bulk_order": "BULK",
	"refined_goods": "REFINED",
}
const MODIFIER_COLORS: Dictionary = {
	"rush_order": Color(0.95, 0.35, 0.30, 1),
	"bulk_order": Color(0.45, 0.65, 0.95, 1),
	"refined_goods": Color(1.0, 0.80, 0.30, 1),
}

# Cached styles (built once)
var _panel_style: StyleBoxFlat = null
var _card_style: StyleBoxFlat = null

var _panel: PanelContainer = null
var _vbox: VBoxContainer = null

var _board: Node = null
var _miner: Node = null

# Live countdown labels keyed by active-list index. Refreshed in _process so
# rush-order timers tick without rebuilding the panel each frame.
var _countdown_labels: Dictionary = {}

func _ready() -> void:
	_build_styles()
	_build_panel()
	# Lookups happen lazily on _process — vendor + miner are spawned later.
	set_process(true)

func _build_styles() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.09, 0.10, 0.13, 0.92)
	_panel_style.border_width_left = 2
	_panel_style.border_width_top = 2
	_panel_style.border_width_right = 2
	_panel_style.border_width_bottom = 2
	_panel_style.border_color = Color(0.20, 0.30, 0.42, 1)
	_panel_style.corner_radius_top_left = 6
	_panel_style.corner_radius_top_right = 6
	_panel_style.corner_radius_bottom_right = 6
	_panel_style.corner_radius_bottom_left = 6
	_panel_style.content_margin_left = 10
	_panel_style.content_margin_top = 8
	_panel_style.content_margin_right = 10
	_panel_style.content_margin_bottom = 8
	_card_style = StyleBoxFlat.new()
	_card_style.bg_color = Color(0.13, 0.20, 0.30, 0.7)
	_card_style.border_width_left = 1
	_card_style.border_width_top = 1
	_card_style.border_width_right = 1
	_card_style.border_width_bottom = 1
	_card_style.border_color = Color(0.40, 0.65, 0.95, 0.9)
	_card_style.corner_radius_top_left = 4
	_card_style.corner_radius_top_right = 4
	_card_style.corner_radius_bottom_left = 4
	_card_style.corner_radius_bottom_right = 4
	_card_style.content_margin_left = 8
	_card_style.content_margin_top = 6
	_card_style.content_margin_right = 8
	_card_style.content_margin_bottom = 6

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(_vbox)
	_panel.visible = false

func _process(_delta: float) -> void:
	# Lazy lookup; vendor + miner come online a bit after world_ready.
	if _board == null:
		var vendor: Node = get_tree().get_first_node_in_group("contract_vendor_npcs")
		if vendor != null and vendor.get("contract_board") != null:
			_board = vendor.contract_board
			if _board.has_signal("changed"):
				_board.changed.connect(_refresh)
			_refresh()
	if _miner == null:
		_miner = get_tree().get_first_node_in_group("player_miner")
		if _miner != null:
			if _miner.has_signal("inventory_changed"):
				_miner.inventory_changed.connect(_on_inv_changed)
			if _miner.has_signal("extended_inventory_changed"):
				_miner.extended_inventory_changed.connect(_refresh)
			_refresh()
	# Tick live countdowns on rush-order cards.
	if _board != null and not _countdown_labels.is_empty():
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
			lbl.text = _format_mmss(remaining)
			if remaining < 60.0:
				lbl.add_theme_color_override("font_color", Color(1, 0.45, 0.40, 1))

func _format_mmss(seconds: float) -> String:
	var s: int = int(round(seconds))
	var m: int = s / 60
	var r: int = s % 60
	return "%02d:%02d" % [m, r]

func _on_inv_changed(_s: int, _i: int, _g: int) -> void:
	_refresh()

func _refresh() -> void:
	if _board == null:
		_panel.visible = false
		return
	_countdown_labels.clear()
	for child: Node in _vbox.get_children():
		child.queue_free()
	if _board.active.is_empty():
		_panel.visible = false
		return
	_panel.visible = true
	var header: Label = Label.new()
	header.text = "ACTIVE CONTRACTS"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 1))
	_vbox.add_child(header)
	for i: int in _board.active.size():
		_vbox.add_child(_make_card(_board.active[i], i))

func _make_card(contract: Dictionary, idx: int = -1) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_style)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	pc.add_child(v)
	# Modifier badge (+ live countdown for rush orders).
	var modifier: String = String(contract.get("modifier", ""))
	if MODIFIER_LABELS.has(modifier):
		var hdr_row: HBoxContainer = HBoxContainer.new()
		hdr_row.add_theme_constant_override("separation", 6)
		var badge: Label = Label.new()
		badge.text = String(MODIFIER_LABELS.get(modifier, modifier.to_upper()))
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", MODIFIER_COLORS.get(modifier, Color(0.7, 0.7, 0.7, 1)))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		badge.add_theme_constant_override("outline_size", 4)
		hdr_row.add_child(badge)
		if modifier == "rush_order":
			var exp_at: float = float(contract.get("expires_at", 0.0))
			var count_lbl: Label = Label.new()
			count_lbl.add_theme_font_size_override("font_size", 10)
			count_lbl.add_theme_color_override("font_color", Color(0.95, 0.65, 0.55, 1))
			count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var initial_remaining: float = max(0.0, exp_at - Time.get_unix_time_from_system())
			count_lbl.text = _format_mmss(initial_remaining)
			hdr_row.add_child(count_lbl)
			if idx >= 0:
				_countdown_labels[idx] = count_lbl
		v.add_child(hdr_row)
	for entry: Array in MaterialDefs.sort_items_by_rarity(contract.items):
		var mid: int = entry[0]
		var needed: int = entry[1]
		var have: int = _miner.get_material_count(mid) if _miner != null else 0
		var lbl: Label = Label.new()
		var done: bool = (have >= needed)
		var check: String = "  ✓" if done else ""
		# Show the player's actual inventory count over the requirement so a
		# single quest doesn't hide the rest of the stack you'd need for
		# overlapping contracts. ✓ when satisfied.
		lbl.text = "%s   %d / %d%s" % [MaterialDefs.DISPLAY_NAME[mid], have, needed, check]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55, 1) if done else Color(0.85, 0.88, 0.92, 1))
		v.add_child(lbl)
	var reward: Label = Label.new()
	reward.text = "+%dg  +%d XP" % [contract.reward_gold, contract.xp]
	reward.add_theme_font_size_override("font_size", 11)
	reward.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	v.add_child(reward)
	return pc
