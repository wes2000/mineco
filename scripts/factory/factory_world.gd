extends Node
## Autoload. Owns the cell registry and the 10 Hz simulation tick.

const TICK_HZ: float = 10.0
const TICK_DT: float = 1.0 / TICK_HZ

signal tick_emitted(tick_index: int)
signal cell_registered(cell: Vector3i, owner: Node3D)
signal cell_unregistered(cell: Vector3i)

var _cells: Dictionary = {}              # Vector3i -> Node3D (belt cell or building footprint owner)
var _tick_accumulator: float = 0.0
var _tick_index: int = 0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_tick_accumulator += delta
	while _tick_accumulator >= TICK_DT:
		_tick_accumulator -= TICK_DT
		_tick_index += 1
		tick_emitted.emit(_tick_index)

# --- Cell registry API ---

func is_cell_free(cell: Vector3i) -> bool:
	return not _cells.has(cell)

func get_cell_owner(cell: Vector3i) -> Node3D:
	return _cells.get(cell, null)

func register_cell(cell: Vector3i, owner: Node3D) -> bool:
	if _cells.has(cell):
		push_warning("FactoryWorld: cell %s already registered" % cell)
		return false
	_cells[cell] = owner
	cell_registered.emit(cell, owner)
	return true

func unregister_cell(cell: Vector3i) -> void:
	if not _cells.has(cell):
		return
	_cells.erase(cell)
	cell_unregistered.emit(cell)

# Stubs — implemented in later tasks (Task 13/16):
func place(_kind: StringName, _origin_cell: Vector3i, _rotation_steps: int) -> bool:
	push_warning("FactoryWorld.place not yet implemented")
	return false

func remove(_cell: Vector3i) -> void:
	push_warning("FactoryWorld.remove not yet implemented")

# --- Tick introspection (debug) ---
func get_tick_index() -> int:
	return _tick_index
