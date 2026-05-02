extends Node
## Autoload. Owns the cell registry and the 10 Hz simulation tick.

const TICK_HZ: float = 10.0
const TICK_DT: float = 1.0 / TICK_HZ
const BELT_SPEED_TICKS: int = 10   # 1 cell per second at 10 Hz

signal tick_emitted(tick_index: int)
signal cell_registered(cell: Vector3i, owner: Node3D)
signal cell_unregistered(cell: Vector3i)

var _cells: Dictionary = {}              # Vector3i -> Node3D (belt cell or building footprint owner)
var _tick_accumulator: float = 0.0
var _tick_index: int = 0
var item_pool: ItemPool
var graph: BeltGraph

func _ready() -> void:
	item_pool = ItemPool.new()
	item_pool.name = "ItemPool"
	add_child(item_pool)
	graph = BeltGraph.new()
	tick_emitted.connect(_on_tick)
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
	if graph != null:
		graph.mark_dirty()
	cell_registered.emit(cell, owner)
	return true

func unregister_cell(cell: Vector3i) -> void:
	if not _cells.has(cell):
		return
	_cells.erase(cell)
	if graph != null:
		graph.mark_dirty()
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

# --- Simulation tick ---

func _on_tick(_idx: int) -> void:
	_tick_belts()
	_tick_buildings()

func _tick_buildings() -> void:
	var seen: Dictionary = {}     # building -> true (avoid double-tick of multi-cell footprints)
	for c: Vector3i in _cells:
		var owner: Node3D = _cells[c]
		if owner is Building and not seen.has(owner):
			seen[owner] = true
			(owner as Building).tick(_tick_index)

func _tick_belts() -> void:
	var belt_cells: Array[Vector3i] = []
	for c: Vector3i in _cells:
		var owner: Node3D = _cells[c]
		if owner is BeltCell:
			belt_cells.append(c)
	if belt_cells.is_empty():
		return
	# Phase 1: settle ticks decrement for every belt cell
	for c: Vector3i in belt_cells:
		(_cells[c] as BeltCell).tick_settle()
	# Phase 2: advancement, in reverse-BFS order (sinks first)
	var ordered: Array[Vector3i] = graph.compute_tick_order(_cells, belt_cells)
	for c: Vector3i in ordered:
		var bc: BeltCell = _cells[c] as BeltCell
		if not bc.can_advance_now():
			continue
		var n: Dictionary = graph.neighbours_of(c, _cells)
		if n.outputs.is_empty():
			bc.blocked_ticks += 1   # Task 22: dead-end drop trigger
			continue
		var target: Vector3i = graph.choose_output(c, n.outputs)
		var target_owner: Node3D = _cells.get(target, null)
		if target_owner == null:
			bc.blocked_ticks += 1
			continue
		var moved: bool = false
		if target_owner is BeltCell:
			var tbc: BeltCell = target_owner as BeltCell
			if tbc.is_free():
				var item: FactoryItem = bc.occupant
				bc.clear_item()
				tbc.receive_moving_item(item, bc.cell_center_world(), float(BELT_SPEED_TICKS) * TICK_DT)
				moved = true
		elif target_owner.has_method("get_input_cells") and target_owner.has_method("try_accept_item"):
			var inputs: Array = target_owner.call("get_input_cells")
			if inputs.has(target):
				if target_owner.call("try_accept_item", bc.occupant, c):
					bc.clear_item()
					moved = true
		if moved:
			graph.confirm_flow(c)
		else:
			bc.blocked_ticks += 1
