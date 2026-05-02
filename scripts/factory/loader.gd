class_name Loader
extends Building
## Player-fed hopper that emits one selected material onto its output belt.

const HOPPER_CAP: int = 999

signal hopper_changed(material_id: int, new_count: int)

var hopper: Dictionary = {}     # material_id -> int
var selected_material: int = MaterialDefs.MaterialId.STONE
var _cycle_remaining_ticks: int = 0

func _ready() -> void:
	footprint_size = Vector2i(2, 2)
	for mid: int in MaterialDefs.TIER_1_MATERIALS:
		hopper[mid] = 0

func get_input_cells() -> Array[Vector3i]:
	return []

func get_output_cells() -> Array[Vector3i]:
	# Single output cell on the "front" face (one cell forward of the footprint center, rotated).
	return [cell_for_local_offset(Vector3i(0, 0, footprint_size.y))]

func deposit(material_id: int, amount: int) -> int:
	# Returns amount actually accepted (capped at HOPPER_CAP).
	var current: int = hopper.get(material_id, 0)
	var new_amount: int = min(current + amount, HOPPER_CAP)
	var accepted: int = new_amount - current
	hopper[material_id] = new_amount
	hopper_changed.emit(material_id, new_amount)
	return accepted

func tick(_tick_index: int) -> void:
	if hopper.get(selected_material, 0) <= 0:
		status = Status.IDLE
		return
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	# Cycle done — try to emit
	var out_cells: Array[Vector3i] = get_output_cells()
	if out_cells.is_empty():
		status = Status.OUTPUT_BLOCKED
		return
	var out_cell: Vector3i = out_cells[0]
	var owner: Node3D = FactoryWorld.get_cell_owner(out_cell)
	if not (owner is BeltCell) or not (owner as BeltCell).is_free():
		status = Status.OUTPUT_BLOCKED
		return
	# Emit
	var item: FactoryItem = FactoryWorld.item_pool.acquire(selected_material)
	var belt: BeltCell = owner as BeltCell
	belt.place_item(item)
	hopper[selected_material] -= 1
	hopper_changed.emit(selected_material, hopper[selected_material])
	item_emitted.emit(selected_material)
	_cycle_remaining_ticks = MaterialDefs.LOADER_EMIT_TICKS[selected_material]
	status = Status.WORKING
