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

const KIND_TO_SCENE: Dictionary = {
	&"loader": "res://scenes/factory/loader.tscn",
	&"smelter": "res://scenes/factory/smelter.tscn",
	&"forge": "res://scenes/factory/forge.tscn",
	&"belt_straight": "res://scenes/factory/belt_straight.tscn",
	&"belt_corner": "res://scenes/factory/belt_corner.tscn",
	&"belt_t": "res://scenes/factory/belt_t.tscn",
}

func place(kind: StringName, origin_cell: Vector3i, rotation_steps: int) -> bool:
	var scene_path: String = KIND_TO_SCENE.get(kind, "")
	if scene_path == "":
		push_warning("FactoryWorld.place: unknown kind %s" % kind)
		return false
	var ps: PackedScene = load(scene_path)
	var node: Node3D = ps.instantiate()
	get_tree().current_scene.add_child(node)
	var cells_to_register: Array[Vector3i] = []
	if node is Building:
		var bld: Building = node as Building
		bld.origin_cell = origin_cell
		bld.rotation_steps = rotation_steps
		bld.global_position = Vector3(origin_cell.x, origin_cell.y, origin_cell.z)
		bld.rotation = Vector3(0, -PI / 2 * rotation_steps, 0)
		cells_to_register = bld.get_footprint_cells()
	elif node is BeltCell:
		var bc: BeltCell = node as BeltCell
		var facing: Vector3i = _auto_facing_for(origin_cell, bc.kind)
		bc.set_cell_and_facing(origin_cell, facing)
		bc.global_position = Vector3(origin_cell.x, origin_cell.y, origin_cell.z)
		cells_to_register = [origin_cell]
	# Register footprint
	for c: Vector3i in cells_to_register:
		if not register_cell(c, node):
			push_error("FactoryWorld.place: cell collision at %s — rolling back" % c)
			for c2: Vector3i in cells_to_register:
				unregister_cell(c2)
			node.queue_free()
			return false
	_auto_flatten(cells_to_register, origin_cell.y)
	# Re-orient belt neighbours of every newly-registered cell
	for c: Vector3i in cells_to_register:
		_reorient_belt_neighbours(c)
	return true

func remove(cell: Vector3i) -> void:
	var owner: Node3D = get_cell_owner(cell)
	if owner == null:
		return
	var to_remove: Array[Vector3i] = []
	if owner is Building:
		var bld: Building = owner as Building
		to_remove = bld.get_footprint_cells()
		# Refund Loader hopper to player Miner
		if bld is Loader:
			var loader: Loader = bld as Loader
			var miner: Node = get_tree().get_first_node_in_group("player_miner")
			if miner != null:
				if loader.hopper.get(MaterialDefs.MaterialId.STONE, 0) > 0:
					miner.set("stone", miner.get("stone") + loader.hopper[MaterialDefs.MaterialId.STONE])
				if loader.hopper.get(MaterialDefs.MaterialId.IRON_ORE, 0) > 0:
					miner.set("iron", miner.get("iron") + loader.hopper[MaterialDefs.MaterialId.IRON_ORE])
				if loader.hopper.get(MaterialDefs.MaterialId.GOLD_ORE, 0) > 0:
					miner.set("gold", miner.get("gold") + loader.hopper[MaterialDefs.MaterialId.GOLD_ORE])
				if miner.has_signal("inventory_changed"):
					miner.inventory_changed.emit(miner.get("stone"), miner.get("iron"), miner.get("gold"))
		# Drop items in input/output cells
		var port_cells: Array = bld.get_input_cells() + bld.get_output_cells()
		for cell_to_check: Vector3i in port_cells:
			var n_owner: Node3D = get_cell_owner(cell_to_check)
			if n_owner is BeltCell:
				var bc: BeltCell = n_owner as BeltCell
				if bc.occupant != null:
					var item: FactoryItem = bc.occupant
					var mid: int = item.material_id
					bc.clear_item()
					item_pool.release(item)
					spawn_drop(mid, bc.cell_center_world() + Vector3(0, 0.3, 0))
	elif owner is BeltCell:
		var bc2: BeltCell = owner as BeltCell
		to_remove = [bc2.cell]
		if bc2.occupant != null:
			var item2: FactoryItem = bc2.occupant
			var mid2: int = item2.material_id
			bc2.clear_item()
			item_pool.release(item2)
			spawn_drop(mid2, bc2.cell_center_world() + Vector3(0, 0.3, 0))
	for c: Vector3i in to_remove:
		unregister_cell(c)
	owner.queue_free()
	# Re-orient any belt neighbours that lost a connection
	for c: Vector3i in to_remove:
		_reorient_belt_neighbours(c)

# --- Belt auto-orientation ---

func _auto_facing_for(cell: Vector3i, kind: int) -> Vector3i:
	var off: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	var connected: Array[Vector3i] = []
	for o: Vector3i in off:
		if _cells.has(cell + o):
			connected.append(o)
	if connected.is_empty():
		return Vector3i(0, 0, 1)
	if kind == BeltCell.Kind.STRAIGHT:
		for axis: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
			if connected.has(axis) and connected.has(-axis):
				return axis
		return connected[0]
	if kind == BeltCell.Kind.CORNER:
		if connected.size() >= 2:
			return connected[1]
		return connected[0]
	if kind == BeltCell.Kind.T:
		if connected.size() == 3:
			for axis: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
				if connected.has(axis) and connected.has(-axis):
					var trunk_axis: Vector3i = Vector3i(0, 0, 1) if axis == Vector3i(1, 0, 0) else Vector3i(1, 0, 0)
					if connected.has(trunk_axis):
						return trunk_axis
					return -trunk_axis
		return connected[0]
	return Vector3i(0, 0, 1)

func _reorient_belt_neighbours(cell: Vector3i) -> void:
	var off: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	for o: Vector3i in off:
		var n_cell: Vector3i = cell + o
		var n_owner: Node3D = _cells.get(n_cell, null)
		if n_owner is BeltCell:
			var bc: BeltCell = n_owner as BeltCell
			var new_facing: Vector3i = _auto_facing_for(n_cell, bc.kind)
			if new_facing != bc.facing:
				bc.set_cell_and_facing(n_cell, new_facing)

# --- Voxel terrain auto-flatten ---

func _auto_flatten(cells: Array[Vector3i], target_y: int) -> void:
	var terrain: VoxelTerrain = get_tree().current_scene.find_child("VoxelTerrain", true, false) as VoxelTerrain
	if terrain == null:
		push_warning("FactoryWorld._auto_flatten: no VoxelTerrain found; skipping carve")
		return
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	const SOLID_VOXEL: int = 1
	const AIR: int = 0
	for c: Vector3i in cells:
		for dy: int in range(0, 4):
			tool.set_voxel(Vector3i(c.x, target_y + dy, c.z), AIR)
		var below_pos: Vector3i = Vector3i(c.x, target_y - 1, c.z)
		if tool.get_voxel(below_pos) == AIR:
			tool.set_voxel(below_pos, SOLID_VOXEL)

# --- Drops (used by remove() and Task 22) ---

var _drop_scene: PackedScene = preload("res://scenes/factory/factory_drop.tscn")

func spawn_drop(material_id: int, world_pos: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
	var drop: FactoryDrop = _drop_scene.instantiate() as FactoryDrop
	drop.material_id = material_id
	get_tree().current_scene.add_child(drop)
	drop.global_position = world_pos
	if impulse != Vector3.ZERO:
		drop.apply_central_impulse(impulse)

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
	# Phase 3: dead-end drops
	const DEAD_END_DROP_THRESHOLD: int = 2
	for c: Vector3i in belt_cells:
		var bc2: BeltCell = _cells[c] as BeltCell
		if bc2.occupant != null and bc2.blocked_ticks >= DEAD_END_DROP_THRESHOLD:
			var n2: Dictionary = graph.neighbours_of(c, _cells)
			if n2.outputs.is_empty():
				var item: FactoryItem = bc2.occupant
				var mid: int = item.material_id
				var drop_pos: Vector3 = bc2.cell_center_world() + Vector3(bc2.facing.x, 0.2, bc2.facing.z) * 0.6
				var impulse: Vector3 = Vector3(bc2.facing.x, 0.5, bc2.facing.z) * 0.5
				bc2.clear_item()
				item_pool.release(item)
				spawn_drop(mid, drop_pos, impulse)
