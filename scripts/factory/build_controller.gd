extends Node
## Autoload. Owns build mode state, ghost preview, raycast, place/remove dispatch.

enum Tool { LOADER, SMELTER, FORGE, BELT }
enum BeltSubKind { STRAIGHT, CORNER, T }

signal active_changed(active: bool)
signal selection_changed(selected_tool: int, sub: int)

const RAYCAST_LENGTH: float = 50.0
const WORLD_RADIUS_CELLS: int = 150
const WORLD_Y_MIN: int = -50
const WORLD_Y_MAX: int = 100

var active: bool = false :
	set(v):
		if active != v:
			active = v
			active_changed.emit(v)
var current_tool: int = Tool.LOADER
var current_belt_sub: int = BeltSubKind.STRAIGHT
var ghost_rotation_steps: int = 0

var _ghost_node: Node3D = null
var _player: Node3D = null
var _player_camera: Camera3D = null

func _ready() -> void:
	set_process(true)

func bind_player(player: Node3D, camera: Camera3D) -> void:
	_player = player
	_player_camera = camera

func _process(_delta: float) -> void:
	if not active or _player_camera == null:
		return
	_update_ghost_position()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("build_toggle"):
		active = not active
		if not active and _ghost_node != null:
			_ghost_node.queue_free()
			_ghost_node = null
		return
	if not active:
		return
	if event.is_action_pressed("build_slot_1"):
		current_tool = Tool.LOADER
		selection_changed.emit(current_tool, current_belt_sub)
		_refresh_ghost()
	elif event.is_action_pressed("build_slot_2"):
		current_tool = Tool.SMELTER
		selection_changed.emit(current_tool, current_belt_sub)
		_refresh_ghost()
	elif event.is_action_pressed("build_slot_3"):
		current_tool = Tool.FORGE
		selection_changed.emit(current_tool, current_belt_sub)
		_refresh_ghost()
	elif event.is_action_pressed("build_slot_4"):
		# If already on Belt, advance through Straight/Corner/T. Otherwise switch to Belt.
		if current_tool == Tool.BELT:
			current_belt_sub = (current_belt_sub + 1) % 3
		else:
			current_tool = Tool.BELT
		selection_changed.emit(current_tool, current_belt_sub)
		_refresh_ghost()
	elif event.is_action_pressed("build_rotate"):
		# R always rotates the ghost — belts AND buildings.
		ghost_rotation_steps = (ghost_rotation_steps + 1) & 3
		_refresh_ghost()
	elif event.is_action_pressed("build_place"):
		if Input.is_action_pressed("build_remove"):
			_try_remove()
		else:
			_try_place()

func _update_ghost_position() -> void:
	var cell: Vector3i = _raycast_to_cell()
	if cell == Vector3i(-2147483648, -2147483648, -2147483648):
		return
	if _ghost_node == null:
		_refresh_ghost()
	if _ghost_node != null:
		_ghost_node.global_position = Vector3(cell.x, cell.y, cell.z)
		_ghost_node.set_meta("target_cell", cell)
		var placeable: bool = _is_placeable_at(cell)
		_ghost_node.set_meta("placeable", placeable)
		_apply_ghost_color(placeable)

func _raycast_to_cell() -> Vector3i:
	if _player == null or _player_camera == null:
		return Vector3i(-2147483648, -2147483648, -2147483648)
	var space_state: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var from: Vector3 = _player_camera.global_position
	var to: Vector3 = from + (-_player_camera.global_basis.z) * RAYCAST_LENGTH
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3i(-2147483648, -2147483648, -2147483648)
	var p: Vector3 = hit.position
	# If the surface is roughly horizontal (looking at ground), place ABOVE the
	# hit cell. Otherwise (e.g. wall hit) place at the hit cell.
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var base: Vector3i = Vector3i(floori(p.x), floori(p.y), floori(p.z))
	if normal.y > 0.5:
		base.y += 1   # one cell above the terrain surface
	return base

func _is_placeable_at(cell: Vector3i) -> bool:
	# The raycast that produced `cell` already proved there's terrain underneath
	# (we offset +1 Y when the hit normal pointed up). So we only need to verify:
	#   (a) world bounds, (b) every footprint cell free in the registry.
	# We do NOT poke voxel channels here — the project uses Transvoxel/SDF, and
	# CHANNEL_TYPE returns 0 everywhere. The raycast is the source of truth.
	var footprint: Array[Vector3i] = _ghost_footprint(cell)
	for c: Vector3i in footprint:
		if c.y < WORLD_Y_MIN or c.y > WORLD_Y_MAX:
			return false
		if c.x * c.x + c.z * c.z > WORLD_RADIUS_CELLS * WORLD_RADIUS_CELLS:
			return false
		if not FactoryWorld.is_cell_free(c):
			return false
	return true

func _ghost_footprint(origin: Vector3i) -> Array[Vector3i]:
	var size: Vector2i = _tool_footprint_size()
	var cells: Array[Vector3i] = []
	for x: int in size.x:
		for z: int in size.y:
			cells.append(origin + Vector3i(x, 0, z))
	return cells

func _tool_footprint_size() -> Vector2i:
	match current_tool:
		Tool.LOADER, Tool.SMELTER:
			return Vector2i(2, 2)
		Tool.FORGE:
			return Vector2i(3, 3)
		_:
			return Vector2i(1, 1)

func _refresh_ghost() -> void:
	if _ghost_node != null:
		_ghost_node.queue_free()
		_ghost_node = null
	var scene_path: String = _ghost_scene_path()
	if scene_path == "":
		return
	var ps: PackedScene = load(scene_path)
	_ghost_node = ps.instantiate()
	_ghost_node.set_process(false)
	_ghost_node.rotation = Vector3(0, -PI / 2 * ghost_rotation_steps, 0)
	get_tree().current_scene.add_child(_ghost_node)

func _ghost_scene_path() -> String:
	match current_tool:
		Tool.LOADER: return "res://scenes/factory/loader.tscn"
		Tool.SMELTER: return "res://scenes/factory/smelter.tscn"
		Tool.FORGE: return "res://scenes/factory/forge.tscn"
		Tool.BELT:
			match current_belt_sub:
				BeltSubKind.STRAIGHT: return "res://scenes/factory/belt_straight.tscn"
				BeltSubKind.CORNER: return "res://scenes/factory/belt_corner.tscn"
				BeltSubKind.T: return "res://scenes/factory/belt_t.tscn"
	return ""

func _apply_ghost_color(placeable: bool) -> void:
	if _ghost_node == null:
		return
	var col: Color = Color(0.3, 1.0, 0.3, 0.5) if placeable else Color(1.0, 0.3, 0.3, 0.5)
	for child: Node in _ghost_node.find_children("*", "MeshInstance3D"):
		var mi: MeshInstance3D = child as MeshInstance3D
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat

func _try_place() -> void:
	if _ghost_node == null or not _ghost_node.has_meta("placeable") or not _ghost_node.get_meta("placeable"):
		return
	var origin_cell: Vector3i = _ghost_node.get_meta("target_cell")
	var kind_name: StringName = _tool_to_kind_name()
	FactoryWorld.place(kind_name, origin_cell, ghost_rotation_steps)

func _try_remove() -> void:
	var cell: Vector3i = _raycast_to_cell()
	if cell == Vector3i(-2147483648, -2147483648, -2147483648):
		return
	FactoryWorld.remove(cell)

func _tool_to_kind_name() -> StringName:
	match current_tool:
		Tool.LOADER: return &"loader"
		Tool.SMELTER: return &"smelter"
		Tool.FORGE: return &"forge"
		Tool.BELT:
			match current_belt_sub:
				BeltSubKind.STRAIGHT: return &"belt_straight"
				BeltSubKind.CORNER: return &"belt_corner"
				BeltSubKind.T: return &"belt_t"
	return &""
