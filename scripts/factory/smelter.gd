class_name Smelter
extends Building

@export var recipe_input: int = MaterialDefs.MaterialId.STONE   # one of TIER_1_MATERIALS

var _input_item: FactoryItem = null
var _cycle_remaining_ticks: int = 0
var _input_material: int = -1   # the material being processed in the current cycle

func _ready() -> void:
	footprint_size = Vector2i(2, 2)

func get_input_cells() -> Array[Vector3i]:
	return [cell_for_local_offset(Vector3i(0, 0, -1))]   # one cell behind footprint origin row

func get_output_cells() -> Array[Vector3i]:
	return [cell_for_local_offset(Vector3i(0, 0, footprint_size.y))]

func try_accept_item(item: FactoryItem, _from_cell: Vector3i) -> bool:
	if _input_item != null:
		return false
	_input_item = item
	return true

func tick(_tick_index: int) -> void:
	# Currently working?
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	# Cycle done — emit T2 if we were working
	if _input_material != -1:
		if not _try_emit():
			status = Status.OUTPUT_BLOCKED
			return
		_input_material = -1
	# Try to start a new cycle if we have an input
	if _input_item == null:
		status = Status.IDLE
		return
	if _input_item.material_id != recipe_input:
		status = Status.INPUT_JAMMED
		return
	_input_material = _input_item.material_id
	FactoryWorld.item_pool.release(_input_item)
	_input_item = null
	_cycle_remaining_ticks = MaterialDefs.SMELTER_TICKS[_input_material]
	status = Status.WORKING

func _try_emit() -> bool:
	var out_material: int = MaterialDefs.SMELT_RECIPE[_input_material]
	var out_cells: Array[Vector3i] = get_output_cells()
	if out_cells.is_empty():
		return false
	var out_cell: Vector3i = out_cells[0]
	var owner: Node3D = FactoryWorld.get_cell_owner(out_cell)
	if owner == null or not (owner is BeltCell):
		return false
	var belt: BeltCell = owner as BeltCell
	if not belt.is_free():
		return false
	var item: FactoryItem = FactoryWorld.item_pool.acquire(out_material)
	belt.place_item(item)
	item_emitted.emit(out_material)
	return true
