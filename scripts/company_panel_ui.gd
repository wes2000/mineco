extends Control
## Modal Company panel. Shows current rank + XP, lifetime stats, the rewards
## ladder (current rank highlighted, future ranks locked), and a stub
## "Prestige" section that won't unlock until v2.
##
## Loose-coupled: the autoload is reached through get_node_or_null so the
## class name doesn't need to be in the parser cache.

const _CompanyScript: GDScript = preload("res://scripts/company_progress.gd")

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _rank_label: Label = $Panel/Vbox/RankRow/RankName
@onready var _xp_bar: ProgressBar = $Panel/Vbox/XpRow/Bar
@onready var _xp_label: Label = $Panel/Vbox/XpRow/Label
@onready var _stats_grid: GridContainer = $Panel/Vbox/Scroll/V/StatsBox/Grid
@onready var _rewards_box: VBoxContainer = $Panel/Vbox/Scroll/V/RewardsBox
@onready var _prestige_label: Label = $Panel/Vbox/Scroll/V/PrestigeBox/Status

var _company: Node = null

var _rank_row_style: StyleBoxFlat = null
var _rank_row_current_style: StyleBoxFlat = null
var _rank_row_locked_style: StyleBoxFlat = null

func _ready() -> void:
	visible = false
	add_to_group("company_panel_ui")
	_close_btn.pressed.connect(close)
	_rank_row_style = _make_row_style(Color(0.13, 0.15, 0.18, 0.7), Color(0.32, 0.32, 0.40, 1))
	_rank_row_current_style = _make_row_style(Color(0.18, 0.22, 0.16, 0.9), Color(0.65, 0.95, 0.55, 1))
	_rank_row_locked_style = _make_row_style(Color(0.10, 0.11, 0.13, 0.7), Color(0.22, 0.22, 0.26, 1))
	_company = get_node_or_null("/root/CompanyProgress")
	if _company != null:
		if _company.has_signal("xp_changed") and not _company.xp_changed.is_connected(_on_xp_changed):
			_company.xp_changed.connect(_on_xp_changed)
		if _company.has_signal("lifetime_changed") and not _company.lifetime_changed.is_connected(_refresh):
			_company.lifetime_changed.connect(_refresh)
		if _company.has_signal("rank_up") and not _company.rank_up.is_connected(_on_rank_up):
			_company.rank_up.connect(_on_rank_up)

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
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("company_panel"):
		close()
		accept_event()

func _on_xp_changed(_xp: int) -> void:
	_refresh()

func _on_rank_up(_new_rank: int, _name: String) -> void:
	_refresh()

func _refresh() -> void:
	if _company == null:
		_company = get_node_or_null("/root/CompanyProgress")
	_refresh_header()
	_refresh_stats()
	_refresh_rewards()
	_refresh_prestige()

func _refresh_header() -> void:
	if _company == null:
		_rank_label.text = "(no company progress)"
		_xp_bar.value = 0
		_xp_label.text = ""
		return
	var rank: int = int(_company.get("rank"))
	var name: String = String(_company.call("rank_name"))
	_rank_label.text = "%s  ·  Rank %d" % [name, rank]
	if rank >= _CompanyScript.RANKS.size():
		_xp_bar.max_value = 1
		_xp_bar.value = 1
		_xp_label.text = "MAX  ·  %d XP" % int(_company.get("company_xp"))
	else:
		var into: int = int(_company.call("xp_into_current_rank"))
		var span: int = int(_company.call("xp_span_current_to_next"))
		_xp_bar.max_value = float(span)
		_xp_bar.value = float(into)
		var nxt: String = String(_company.call("next_rank_name"))
		_xp_label.text = "%d / %d XP to %s" % [into, span, nxt]

func _refresh_stats() -> void:
	for c: Node in _stats_grid.get_children():
		c.queue_free()
	if _company == null:
		return
	var pairs: Array = [
		["Lifetime gold earned", int(_company.get("lifetime_gold_earned"))],
		["Contracts completed", int(_company.get("contracts_completed"))],
		["Claims cleared", int(_company.get("claims_cleared"))],
		["Enemies defeated", int(_company.get("enemies_defeated"))],
		["Factory items produced", int(_company.get("factory_items_produced"))],
		["Blueprints found", int(_company.get("blueprints_found"))],
	]
	for entry: Array in pairs:
		var k: Label = Label.new()
		k.text = String(entry[0])
		k.add_theme_font_size_override("font_size", 12)
		k.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85, 1))
		_stats_grid.add_child(k)
		var v: Label = Label.new()
		v.text = "%d" % int(entry[1])
		v.add_theme_font_size_override("font_size", 12)
		v.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats_grid.add_child(v)

func _refresh_rewards() -> void:
	for c: Node in _rewards_box.get_children():
		c.queue_free()
	var current_rank: int = 1
	var current_xp: int = 0
	if _company != null:
		current_rank = int(_company.get("rank"))
		current_xp = int(_company.get("company_xp"))
	for r_def: Dictionary in _CompanyScript.RANKS:
		var r_id: int = int(r_def.id)
		var r_name: String = String(r_def.name)
		var threshold: int = int(r_def.threshold)
		var unlocked: bool = current_rank >= r_id
		var is_current: bool = current_rank == r_id
		var pc: PanelContainer = PanelContainer.new()
		if is_current:
			pc.add_theme_stylebox_override("panel", _rank_row_current_style)
		elif unlocked:
			pc.add_theme_stylebox_override("panel", _rank_row_style)
		else:
			pc.add_theme_stylebox_override("panel", _rank_row_locked_style)
		var v: VBoxContainer = VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		pc.add_child(v)
		var title_row: HBoxContainer = HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 8)
		v.add_child(title_row)
		var name_lbl: Label = Label.new()
		name_lbl.text = "Rank %d  ·  %s" % [r_id, r_name]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)
		if is_current:
			name_lbl.add_theme_color_override("font_color", Color(0.65, 0.95, 0.55, 1))
		elif unlocked:
			name_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6, 1))
		title_row.add_child(name_lbl)
		var threshold_lbl: Label = Label.new()
		if r_id == 1:
			threshold_lbl.text = "Starting rank"
		else:
			threshold_lbl.text = "%d XP" % threshold
		threshold_lbl.add_theme_font_size_override("font_size", 11)
		threshold_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85, 1))
		title_row.add_child(threshold_lbl)
		var rewards: Array = _CompanyScript.reward_labels_for_rank(r_id)
		var rewards_text: String = ""
		if rewards.is_empty():
			rewards_text = "—"
		else:
			rewards_text = ",  ".join(rewards)
		var rewards_lbl: Label = Label.new()
		rewards_lbl.text = rewards_text
		rewards_lbl.add_theme_font_size_override("font_size", 11)
		if unlocked:
			rewards_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7, 1))
		else:
			rewards_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6, 1))
		rewards_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(rewards_lbl)
		# Locked / "X XP to go" hint.
		if not unlocked:
			var hint: Label = Label.new()
			hint.text = "Locked  ·  %d XP to go" % max(0, threshold - current_xp)
			hint.add_theme_font_size_override("font_size", 10)
			hint.add_theme_color_override("font_color", Color(0.65, 0.6, 0.6, 1))
			v.add_child(hint)
		_rewards_box.add_child(pc)

func _refresh_prestige() -> void:
	if _prestige_label == null:
		return
	var current_rank: int = 1
	if _company != null:
		current_rank = int(_company.get("rank"))
	var max_rank: int = _CompanyScript.RANKS.size()
	if current_rank >= max_rank:
		_prestige_label.text = "Prestige reset coming soon — your rank rewards stay live in the meantime."
		_prestige_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.95, 1))
	else:
		_prestige_label.text = "Available at Mine Co. Director (rank %d) — coming soon" % max_rank
		_prestige_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1))
