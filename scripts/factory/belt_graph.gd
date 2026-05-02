class_name BeltGraph
extends RefCounted
## Pure graph logic over FactoryWorld._cells. Mutates only round-robin state.

const HORIZONTAL_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# Per-cell round-robin counter (incremented on successful flow when multiple outputs/inputs).
var _round_robin: Dictionary = {}    # Vector3i -> int

# Cached BFS depth: Vector3i -> int. Recomputed on graph mutation.
var _depth_cache: Dictionary = {}
var _cache_dirty: bool = true

func mark_dirty() -> void:
	_cache_dirty = true

# Returns {"inputs": Array[Vector3i], "outputs": Array[Vector3i]} for this cell,
# derived from neighbour facings + building input/output face metadata.
func neighbours_of(cell: Vector3i, world_cells: Dictionary) -> Dictionary:
	var inputs: Array[Vector3i] = []
	var outputs: Array[Vector3i] = []
	for off: Vector3i in HORIZONTAL_OFFSETS:
		var n_cell: Vector3i = cell + off
		if not world_cells.has(n_cell):
			continue
		var owner: Node3D = world_cells[n_cell]
		var role: int = _neighbour_role_relative_to(n_cell, owner, cell)
		# role: -1 = neighbour feeds INTO cell, +1 = neighbour RECEIVES from cell, 0 = no connection
		if role == -1:
			inputs.append(n_cell)
		elif role == +1:
			outputs.append(n_cell)
	return {"inputs": inputs, "outputs": outputs}

func _neighbour_role_relative_to(neighbour_cell: Vector3i, neighbour_owner: Node3D, from_cell: Vector3i) -> int:
	if neighbour_owner.has_method("get_output_cells"):
		# Building: outputs feed cells outside their output face
		var bld_outputs: Array = neighbour_owner.call("get_output_cells")
		if bld_outputs.has(from_cell):
			return -1   # building outputs INTO from_cell
		var bld_inputs: Array = []
		if neighbour_owner.has_method("get_input_cells"):
			bld_inputs = neighbour_owner.call("get_input_cells")
		if bld_inputs.has(from_cell):
			return +1   # building accepts FROM from_cell
		return 0
	if neighbour_owner.has_method("get_facing"):
		# Belt: facing is a Vector3i unit vector pointing FROM this belt TO its output
		var facing: Vector3i = neighbour_owner.call("get_facing")
		if neighbour_cell + facing == from_cell:
			return -1   # neighbour's output is from_cell, so neighbour feeds in
		if neighbour_cell - facing == from_cell:
			return +1   # neighbour's input is from_cell
		return 0
	return 0

# Round-robin output choice when multiple outputs are valid.
# Caller calls confirm_flow() on success to advance the counter.
func choose_output(from_cell: Vector3i, candidate_outputs: Array[Vector3i]) -> Vector3i:
	if candidate_outputs.is_empty():
		return from_cell    # caller treats this as "no output"
	if candidate_outputs.size() == 1:
		return candidate_outputs[0]
	var counter: int = _round_robin.get(from_cell, 0)
	return candidate_outputs[counter % candidate_outputs.size()]

func confirm_flow(from_cell: Vector3i) -> void:
	_round_robin[from_cell] = _round_robin.get(from_cell, 0) + 1

# Reverse-BFS: Array[Vector3i] of belt cells in tick-processing order (sinks first).
func compute_tick_order(world_cells: Dictionary, belt_cells: Array[Vector3i]) -> Array[Vector3i]:
	if _cache_dirty:
		_recompute_depth(world_cells, belt_cells)
		_cache_dirty = false
	return _ordered(belt_cells)

func _recompute_depth(world_cells: Dictionary, belt_cells: Array[Vector3i]) -> void:
	_depth_cache.clear()
	var sinks: Array[Vector3i] = []
	for c: Vector3i in belt_cells:
		var n: Dictionary = neighbours_of(c, world_cells)
		var has_belt_output: bool = false
		for out_cell: Vector3i in n.outputs:
			var ow: Node3D = world_cells.get(out_cell, null)
			if ow != null and ow.has_method("get_facing"):
				has_belt_output = true
				break
		if not has_belt_output:
			sinks.append(c)
			_depth_cache[c] = 0
	# BFS backwards along input edges
	var frontier: Array[Vector3i] = sinks.duplicate()
	var depth: int = 0
	while not frontier.is_empty():
		depth += 1
		var next_frontier: Array[Vector3i] = []
		for c: Vector3i in frontier:
			var n: Dictionary = neighbours_of(c, world_cells)
			for in_cell: Vector3i in n.inputs:
				var ow: Node3D = world_cells.get(in_cell, null)
				if ow == null or not ow.has_method("get_facing"):
					continue   # only walk belt inputs
				var existing: int = _depth_cache.get(in_cell, -1)
				if existing == -1 or existing > depth:
					_depth_cache[in_cell] = depth
					next_frontier.append(in_cell)
		frontier = next_frontier

func _ordered(belt_cells: Array[Vector3i]) -> Array[Vector3i]:
	var sortable: Array = []
	for c: Vector3i in belt_cells:
		var d: int = _depth_cache.get(c, 999999)   # cycles get INF, processed last
		sortable.append([d, c])
	sortable.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: Array[Vector3i] = []
	for entry: Array in sortable:
		result.append(entry[1])
	return result
