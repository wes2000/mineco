extends Control
## Modal deposit/withdraw UI for a single StorageCrate. Opened with E.

const _MD: GDScript = preload("res://scripts/factory/material_defs.gd")
const _StorageCrate: GDScript = preload("res://scripts/factory/storage_crate.gd")

const SELL_ORDER: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _title_lbl: Label = $Panel/Vbox/HeaderRow/Title
@onready var _rows: VBoxContainer = $Panel/Vbox/Scroll/Rows

var _crate: Node = null
var _miner: Node = null
var _row_style: StyleBoxFlat = null

func _ready() -> void:
	visible = false
	add_to_group("storage_crate_ui")
	_close_btn.pressed.connect(close)
	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = Color(0.13, 0.15, 0.18, 0.7)
	_row_style.corner_radius_top_left = 3
	_row_style.corner_radius_top_right = 3
	_row_style.corner_radius_bottom_left = 3
	_row_style.corner_radius_bottom_right = 3
	_row_style.content_margin_left = 6
	_row_style.content_margin_right = 6
	_row_style.content_margin_top = 4
	_row_style.content_margin_bottom = 4

func bind_to(crate: Node) -> void:
	_unbind()
	_crate = crate
	if _crate != null and _crate.has_signal("storage_changed"):
		_crate.storage_changed.connect(_refresh)
	open()

func _unbind() -> void:
	if _crate != null and _crate.has_signal("storage_changed") and _crate.storage_changed.is_connected(_refresh):
		_crate.storage_changed.disconnect(_refresh)
	_crate = null

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner != null:
		if not _miner.inventory_changed.is_connected(_on_inv_changed):
			_miner.inventory_changed.connect(_on_inv_changed)
		if _miner.has_signal("extended_inventory_changed") and not _miner.extended_inventory_changed.is_connected(_refresh):
			_miner.extended_inventory_changed.connect(_refresh)
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _miner != null:
		if _miner.inventory_changed.is_connected(_on_inv_changed):
			_miner.inventory_changed.disconnect(_on_inv_changed)
		if _miner.has_signal("extended_inventory_changed") and _miner.extended_inventory_changed.is_connected(_refresh):
			_miner.extended_inventory_changed.disconnect(_refresh)
	_miner = null
	_unbind()

func _on_inv_changed(_s: int, _i: int, _g: int) -> void:
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("machine_interact"):
		close()
		accept_event()

func _refresh() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	if _crate == null:
		return
	_title_lbl.text = "Storage Crate"
	for mid: int in SELL_ORDER:
		_rows.add_child(_make_row(mid))

func _make_row(material_id: int) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _row_style)
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	pc.add_child(hbox)
	# Name + counts
	var name_lbl: Label = Label.new()
	name_lbl.text = String(_MD.DISPLAY_NAME[material_id])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)
	var inv_count: int = _miner.call("get_material_count", material_id) if _miner != null else 0
	var crate_count: int = int(_crate.call("get_count", material_id))
	var counts_lbl: Label = Label.new()
	counts_lbl.text = "you %d / crate %d" % [inv_count, crate_count]
	counts_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	counts_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
	hbox.add_child(counts_lbl)
	# Buttons — mirror vendor_ui's compact layout.
	var dep10: Button = Button.new()
	dep10.text = "Dep 10"
	dep10.disabled = inv_count <= 0
	dep10.pressed.connect(_on_deposit.bind(material_id, 10))
	hbox.add_child(dep10)
	var dep_all: Button = Button.new()
	dep_all.text = "Dep All"
	dep_all.disabled = inv_count <= 0
	dep_all.pressed.connect(_on_deposit.bind(material_id, inv_count))
	hbox.add_child(dep_all)
	var w10: Button = Button.new()
	w10.text = "Wd 10"
	w10.disabled = crate_count <= 0
	w10.pressed.connect(_on_withdraw.bind(material_id, 10))
	hbox.add_child(w10)
	var w_all: Button = Button.new()
	w_all.text = "Wd All"
	w_all.disabled = crate_count <= 0
	w_all.pressed.connect(_on_withdraw.bind(material_id, crate_count))
	hbox.add_child(w_all)
	return pc

func _on_deposit(material_id: int, amount: int) -> void:
	if _crate == null or _miner == null or amount <= 0:
		return
	var have: int = _miner.call("get_material_count", material_id)
	var requested: int = min(have, amount)
	if requested <= 0:
		return
	var put: int = int(_crate.call("deposit", material_id, requested))
	if put > 0:
		_miner.call("remove_material", material_id, put)

func _on_withdraw(material_id: int, amount: int) -> void:
	if _crate == null or _miner == null or amount <= 0:
		return
	var got: int = int(_crate.call("withdraw", material_id, amount))
	if got > 0:
		_miner.call("add_factory_material", material_id, got)
