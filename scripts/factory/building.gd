class_name Building
extends Node3D
## Shared base for Loader, Smelter, Forge.

enum Status { IDLE, WORKING, OUTPUT_BLOCKED, INPUT_JAMMED, OVERFLOWING }

signal item_emitted(material_id: int)
signal status_changed(new_status: int)

@export var footprint_size: Vector2i = Vector2i(2, 2)   # cells in X,Z
@export var rotation_steps: int = 0                     # 0..3, applied in 90° steps around +Y

var origin_cell: Vector3i        # set on placement; "front-left" cell of the footprint
var status: int = Status.IDLE :
	set(v):
		if status != v:
			status = v
			status_changed.emit(v)

# Subclasses override these:
func get_input_cells() -> Array[Vector3i]:
	return []

func get_output_cells() -> Array[Vector3i]:
	return []

func get_footprint_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x: int in footprint_size.x:
		for z: int in footprint_size.y:
			cells.append(origin_cell + Vector3i(x, 0, z))
	return cells

# Called by FactoryWorld on each tick.
func tick(_tick_index: int) -> void:
	pass

# Called by FactoryWorld when an item arrives at one of our input cells.
# Return true to accept (we take ownership), false to reject (item stays put).
func try_accept_item(_item: FactoryItem, _from_cell: Vector3i) -> bool:
	return false

# Helper: given a local-space offset in the 0-rotation frame, return the world cell.
func cell_for_local_offset(local: Vector3i) -> Vector3i:
	var rotated: Vector3i = _rotate_offset(local, rotation_steps)
	return origin_cell + rotated

func _rotate_offset(v: Vector3i, steps: int) -> Vector3i:
	var s: int = steps & 3
	var x: int = v.x
	var z: int = v.z
	for _i: int in s:
		var nx: int = -z
		var nz: int = x
		x = nx
		z = nz
	return Vector3i(x, v.y, z)
