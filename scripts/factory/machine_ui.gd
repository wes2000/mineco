extends Control
## Modal recipe panel. Bound to one Building at a time. Opened via E by player.

@onready var _name_label: Label = $Panel/Vbox/Name
@onready var _status_label: Label = $Panel/Vbox/Status
@onready var _input_label: Label = $Panel/Vbox/InputRow/Label
@onready var _output_label: Label = $Panel/Vbox/OutputRow/Label
@onready var _recipe_select: OptionButton = $Panel/Vbox/RecipeSelect
@onready var _deposit_panel: VBoxContainer = $Panel/Vbox/DepositPanel

var _bound_building: Building = null

func _ready() -> void:
	visible = false
	add_to_group("machine_ui")
	_recipe_select.item_selected.connect(_on_recipe_selected)

func bind_to(building: Building) -> void:
	if _bound_building != null:
		unbind()
	_bound_building = building
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_populate_recipes()
	_refresh()
	building.status_changed.connect(_on_status_changed)
	building.queue_changed.connect(_on_queue_changed)
	if building is Loader:
		_deposit_panel.visible = true
		_refresh_deposit_panel()
	else:
		_deposit_panel.visible = false

func unbind() -> void:
	if _bound_building != null:
		if _bound_building.status_changed.is_connected(_on_status_changed):
			_bound_building.status_changed.disconnect(_on_status_changed)
		if _bound_building.queue_changed.is_connected(_on_queue_changed):
			_bound_building.queue_changed.disconnect(_on_queue_changed)
	_bound_building = null
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_queue_changed(_kind: int, _new_count: int) -> void:
	_refresh()

func _populate_recipes() -> void:
	_recipe_select.clear()
	if _bound_building is Loader:
		for mid: int in MaterialDefs.TIER_1_MATERIALS:
			_recipe_select.add_item(MaterialDefs.DISPLAY_NAME[mid], mid)
		var current: int = (_bound_building as Loader).selected_material
		for i: int in _recipe_select.item_count:
			if _recipe_select.get_item_id(i) == current:
				_recipe_select.select(i)
				break
	elif _bound_building is Smelter:
		for mid: int in MaterialDefs.SMELT_RECIPE:
			var label: String = "%s -> %s" % [MaterialDefs.DISPLAY_NAME[mid], MaterialDefs.DISPLAY_NAME[MaterialDefs.SMELT_RECIPE[mid]]]
			_recipe_select.add_item(label, mid)
		var current2: int = (_bound_building as Smelter).recipe_input
		for i: int in _recipe_select.item_count:
			if _recipe_select.get_item_id(i) == current2:
				_recipe_select.select(i)
				break
	elif _bound_building is Forge:
		for mid: int in MaterialDefs.FORGE_RECIPE:
			var label2: String = "%s -> %s" % [MaterialDefs.DISPLAY_NAME[mid], MaterialDefs.DISPLAY_NAME[MaterialDefs.FORGE_RECIPE[mid]]]
			_recipe_select.add_item(label2, mid)
		var current3: int = (_bound_building as Forge).recipe_input
		for i: int in _recipe_select.item_count:
			if _recipe_select.get_item_id(i) == current3:
				_recipe_select.select(i)
				break

func _on_recipe_selected(idx: int) -> void:
	var mid: int = _recipe_select.get_item_id(idx)
	if _bound_building is Loader:
		(_bound_building as Loader).selected_material = mid
	elif _bound_building is Smelter:
		(_bound_building as Smelter).recipe_input = mid
	elif _bound_building is Forge:
		(_bound_building as Forge).recipe_input = mid

func _on_status_changed(new_status: int) -> void:
	_status_label.text = "Status: %s" % Building.Status.find_key(new_status)

func _refresh() -> void:
	if _bound_building == null:
		return
	var type_name: String = "Building"
	if _bound_building is Loader:
		type_name = "Loader"
	elif _bound_building is Smelter:
		type_name = "Smelter"
	elif _bound_building is Forge:
		type_name = "Forge"
	_name_label.text = type_name
	_status_label.text = "Status: %s" % Building.Status.find_key(_bound_building.status)
	var in_count: int = _bound_building.input_queue.size()
	var out_count: int = _bound_building.output_queue.size()
	if _bound_building is Loader:
		_input_label.text = "Input: N/A"
		_output_label.text = "Output queue: %d / %d  (%s)" % [
			out_count, Building.QUEUE_MAX, MaterialDefs.DISPLAY_NAME[(_bound_building as Loader).selected_material]]
	elif _bound_building is Smelter:
		var sm: Smelter = _bound_building as Smelter
		_input_label.text = "Input queue: %d / %d  (recipe: %s)" % [
			in_count, Building.QUEUE_MAX, MaterialDefs.DISPLAY_NAME[sm.recipe_input]]
		_output_label.text = "Output queue: %d / %d  (%s)" % [
			out_count, Building.QUEUE_MAX, MaterialDefs.DISPLAY_NAME[MaterialDefs.SMELT_RECIPE[sm.recipe_input]]]
	elif _bound_building is Forge:
		var fg: Forge = _bound_building as Forge
		_input_label.text = "Input queue: %d / %d  (recipe: %s)" % [
			in_count, Building.QUEUE_MAX, MaterialDefs.DISPLAY_NAME[fg.recipe_input]]
		_output_label.text = "Output queue: %d / %d  (%s)" % [
			out_count, Building.QUEUE_MAX, MaterialDefs.DISPLAY_NAME[MaterialDefs.FORGE_RECIPE[fg.recipe_input]]]

func _refresh_deposit_panel() -> void:
	for child: Node in _deposit_panel.get_children():
		child.queue_free()
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		var warn: Label = Label.new()
		warn.text = "(no player_miner found)"
		_deposit_panel.add_child(warn)
		return
	var loader: Loader = _bound_building as Loader
	var rows: Array = [
		[MaterialDefs.MaterialId.STONE, "stone"],
		[MaterialDefs.MaterialId.IRON_ORE, "iron"],
		[MaterialDefs.MaterialId.GOLD_ORE, "gold"],
	]
	for row: Array in rows:
		var mid: int = row[0]
		var miner_field: String = row[1]
		var hbox: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		var hopper_count: int = loader.hopper.get(mid, 0)
		var inv_count: int = miner.get(miner_field)
		label.text = "%s — Inv: %d / Hopper: %d" % [MaterialDefs.DISPLAY_NAME[mid], inv_count, hopper_count]
		label.custom_minimum_size = Vector2(260, 0)
		hbox.add_child(label)
		var btn_10: Button = Button.new()
		btn_10.text = "+10"
		btn_10.pressed.connect(_do_deposit.bind(mid, miner_field, 10))
		hbox.add_child(btn_10)
		var btn_all: Button = Button.new()
		btn_all.text = "All"
		btn_all.pressed.connect(_do_deposit.bind(mid, miner_field, 999999))
		hbox.add_child(btn_all)
		_deposit_panel.add_child(hbox)

func _do_deposit(material_id: int, miner_field: String, requested: int) -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null or _bound_building == null:
		return
	var loader: Loader = _bound_building as Loader
	var available: int = miner.get(miner_field)
	var to_deposit: int = min(requested, available)
	if to_deposit <= 0:
		return
	var accepted: int = loader.deposit(material_id, to_deposit)
	miner.set(miner_field, available - accepted)
	if miner.has_signal("inventory_changed"):
		miner.inventory_changed.emit(miner.get("stone"), miner.get("iron"), miner.get("gold"))
	_refresh_deposit_panel()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		unbind()
		accept_event()
