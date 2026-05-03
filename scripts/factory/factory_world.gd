extends Node
## Autoload. Owns the cell registry (for buildings only — belts are spline-based)
## and the 10 Hz simulation tick.

const TICK_HZ: float = 10.0
const TICK_DT: float = 1.0 / TICK_HZ

signal tick_emitted(tick_index: int)
signal cell_registered(cell: Vector3i, owner: Node3D)
signal cell_unregistered(cell: Vector3i)

# Cell registry: building footprint cells -> Building instance.
# Belts no longer occupy cells — they're spline-based BeltLink Node3Ds tracked
# in `_links` instead.
var _cells: Dictionary = {}              # Vector3i -> Building
var _links: Array[BeltLink] = []
var _tick_accumulator: float = 0.0
var _tick_index: int = 0
var item_pool: ItemPool

const KIND_TO_SCENE: Dictionary = {
	&"loader": "res://scenes/factory/loader.tscn",
	&"smelter": "res://scenes/factory/smelter.tscn",
	&"forge": "res://scenes/factory/forge.tscn",
	&"splitter": "res://scenes/factory/splitter.tscn",
	&"merger": "res://scenes/factory/merger.tscn",
}

func _ready() -> void:
	item_pool = ItemPool.new()
	item_pool.name = "ItemPool"
	add_child(item_pool)
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
	cell_registered.emit(cell, owner)
	return true

func unregister_cell(cell: Vector3i) -> void:
	if not _cells.has(cell):
		return
	_cells.erase(cell)
	cell_unregistered.emit(cell)

# --- Building placement ---

func place(kind: StringName, origin_cell: Vector3i, rotation_steps: int) -> bool:
	var scene_path: String = KIND_TO_SCENE.get(kind, "")
	if scene_path == "":
		push_warning("FactoryWorld.place: unknown kind %s" % kind)
		return false
	var ps: PackedScene = load(scene_path)
	var node: Node3D = ps.instantiate()
	if not (node is Building):
		push_error("FactoryWorld.place: %s did not instantiate as a Building" % kind)
		node.queue_free()
		return false
	var bld: Building = node as Building
	bld.origin_cell = origin_cell
	bld.rotation_steps = rotation_steps
	bld.position = Vector3(origin_cell.x, origin_cell.y, origin_cell.z)
	bld.rotation = Vector3(0, -PI / 2 * rotation_steps, 0)
	get_tree().current_scene.add_child(bld)
	var cells_to_register: Array[Vector3i] = bld.get_footprint_cells()
	for c: Vector3i in cells_to_register:
		if not register_cell(c, bld):
			push_error("FactoryWorld.place: cell collision at %s — rolling back" % c)
			for c2: Vector3i in cells_to_register:
				unregister_cell(c2)
			bld.queue_free()
			return false
	_auto_flatten(cells_to_register, origin_cell.y)
	return true

func remove(cell: Vector3i) -> void:
	var owner: Node3D = get_cell_owner(cell)
	if owner == null:
		return
	if owner is Building:
		var bld: Building = owner as Building
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
		# Tear down any belt links attached to this building's ports
		for p: Port in bld.ports:
			if p.attached_link != null:
				var link: BeltLink = p.attached_link as BeltLink
				_links.erase(link)
				link.teardown()
		var to_remove: Array[Vector3i] = bld.get_footprint_cells()
		for c: Vector3i in to_remove:
			unregister_cell(c)
		bld.queue_free()

# --- Belt link API ---

func create_link(source: Port, dest: Port) -> BeltLink:
	if source == null or dest == null:
		return null
	if source.kind != Port.KIND_OUTPUT or dest.kind != Port.KIND_INPUT:
		return null
	if source.attached_link != null or dest.attached_link != null:
		return null
	var link: BeltLink = BeltLink.new()
	get_tree().current_scene.add_child(link)
	link.setup(source, dest)
	_links.append(link)
	return link

func remove_link(link: BeltLink) -> void:
	if link == null:
		return
	_links.erase(link)
	link.teardown()

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

# --- Drops ---

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
	_tick_links()
	_tick_buildings()

func _tick_links() -> void:
	for link: BeltLink in _links:
		link.tick(TICK_DT)

func _tick_buildings() -> void:
	var seen: Dictionary = {}
	for c: Vector3i in _cells:
		var owner: Node3D = _cells[c]
		if owner is Building and not seen.has(owner):
			seen[owner] = true
			(owner as Building).tick(_tick_index)
