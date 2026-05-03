extends Node
## Autoload. Owns build mode state, ghost preview, raycast, place/remove dispatch.

enum Tool { LOADER, SMELTER, FORGE, BELT, MERGER, SPLITTER }

signal active_changed(active: bool)
signal selection_changed(selected_tool: int)
signal link_state_changed(awaiting_dest: bool)

const RAYCAST_LENGTH: float = 50.0
const WORLD_RADIUS_CELLS: int = 150
const WORLD_Y_MIN: int = -50
const WORLD_Y_MAX: int = 100
const TERRAIN_LAYER_MASK: int = 1   # voxel terrain
const FACTORY_LAYER_MASK: int = 4   # placed buildings + belts (collision_layer = 4)
const PORT_PICK_RADIUS: float = 1.0   # max distance from raycast hit to a port

const NO_CELL: Vector3i = Vector3i(-2147483648, -2147483648, -2147483648)

var active: bool = false :
	set(v):
		if active != v:
			active = v
			active_changed.emit(v)
var current_tool: int = Tool.LOADER
var ghost_rotation_steps: int = 0

# Belt-link mode state
var _link_source_port: Port = null   # set after first click on an output port

var _ghost_node: Node3D = null
var _link_preview: MeshInstance3D = null
var _link_target_indicator: MeshInstance3D = null   # locks onto the port the cursor is over
var _link_source_indicator: MeshInstance3D = null   # marks the locked source port (after first click)
var _player: Node3D = null
var _player_camera: Camera3D = null

const PORT_LOCK_COLOR_TARGET: Color = Color(0.25, 1.0, 0.4, 1)
const PORT_LOCK_COLOR_SOURCE: Color = Color(0.45, 0.85, 1.0, 1)

func _ready() -> void:
	set_process(true)

func bind_player(player: Node3D, camera: Camera3D) -> void:
	_player = player
	_player_camera = camera

func _process(_delta: float) -> void:
	if not active or _player_camera == null:
		return
	if current_tool == Tool.BELT:
		_clear_ghost()
		_update_link_preview()
	else:
		_clear_all_link_visuals()
		_update_ghost_position()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("build_toggle"):
		active = not active
		if not active:
			_clear_ghost()
			_clear_all_link_visuals()
			_link_source_port = null
			link_state_changed.emit(false)
		return
	if not active:
		return
	if event.is_action_pressed("build_slot_1"):
		_select_tool(Tool.LOADER)
	elif event.is_action_pressed("build_slot_2"):
		_select_tool(Tool.SMELTER)
	elif event.is_action_pressed("build_slot_3"):
		_select_tool(Tool.FORGE)
	elif event.is_action_pressed("build_slot_4"):
		_select_tool(Tool.BELT)
	elif event.is_action_pressed("build_slot_5"):
		_select_tool(Tool.MERGER)
	elif event.is_action_pressed("build_slot_6"):
		_select_tool(Tool.SPLITTER)
	elif event.is_action_pressed("ui_cancel"):
		# Cancel a half-finished link
		if current_tool == Tool.BELT and _link_source_port != null:
			_link_source_port = null
			link_state_changed.emit(false)
	elif event.is_action_pressed("build_rotate"):
		ghost_rotation_steps = (ghost_rotation_steps + 1) & 3
		_refresh_ghost()
	elif event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			ghost_rotation_steps = (ghost_rotation_steps + 1) & 3
			_refresh_ghost()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ghost_rotation_steps = (ghost_rotation_steps - 1) & 3
			_refresh_ghost()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if Input.is_action_pressed("build_remove"):
				_try_remove()
			else:
				if current_tool == Tool.BELT:
					_try_link_click()
				else:
					_try_place()

func _select_tool(t: int) -> void:
	current_tool = t
	if current_tool != Tool.BELT:
		_link_source_port = null
		link_state_changed.emit(false)
	selection_changed.emit(current_tool)
	_refresh_ghost()

# --- Ghost preview (placement tools) ---

func _clear_ghost() -> void:
	if _ghost_node != null:
		_ghost_node.queue_free()
		_ghost_node = null

func _update_ghost_position() -> void:
	var cell: Vector3i = _raycast_terrain_cell()
	if cell == NO_CELL:
		return
	if _ghost_node == null:
		_refresh_ghost()
	if _ghost_node != null:
		_ghost_node.global_position = Vector3(cell.x, cell.y, cell.z)
		_ghost_node.set_meta("target_cell", cell)
		var placeable: bool = _is_placeable_at(cell)
		_ghost_node.set_meta("placeable", placeable)
		_apply_ghost_color(placeable)

func _refresh_ghost() -> void:
	_clear_ghost()
	if current_tool == Tool.BELT:
		return
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
		Tool.MERGER: return "res://scenes/factory/merger.tscn"
		Tool.SPLITTER: return "res://scenes/factory/splitter.tscn"
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

# --- Belt link mode ---

func _update_link_preview() -> void:
	# Always update the source-port marker if we have one locked in.
	if _link_source_port != null:
		_show_source_indicator(_link_source_port.world_position())
	else:
		_hide_source_indicator()
	# Find what (if anything) we're aiming at on the factory layer.
	var hit: Dictionary = _raycast(FACTORY_LAYER_MASK)
	var bld: Building = null
	var hovered_port: Port = null
	var port_kind_to_find: int = Port.KIND_OUTPUT if _link_source_port == null else Port.KIND_INPUT
	if not hit.is_empty():
		bld = _hit_to_building(hit.collider as Node)
		if bld != null:
			var p: Port = bld.find_closest_port(hit.position, port_kind_to_find)
			if p != null and p.is_free() and p.world_position().distance_to(hit.position) <= PORT_PICK_RADIUS:
				hovered_port = p
	# Update target lock-on indicator
	if hovered_port != null:
		_show_target_indicator(hovered_port.world_position())
	else:
		_hide_target_indicator()
	# Update preview line (only when we already have a source)
	if _link_source_port == null:
		_clear_link_preview()
		return
	var end_pos: Vector3
	if hovered_port != null:
		end_pos = hovered_port.world_position()
	elif not hit.is_empty():
		end_pos = hit.position
	else:
		var t_hit: Dictionary = _raycast(TERRAIN_LAYER_MASK)
		if t_hit.is_empty():
			_clear_link_preview()
			return
		end_pos = t_hit.position
	_draw_link_preview(_link_source_port.world_position(), end_pos, hovered_port != null)

func _draw_link_preview(from: Vector3, to: Vector3, locked_to_port: bool = false) -> void:
	if _link_preview == null:
		_link_preview = MeshInstance3D.new()
		_link_preview.set_process(false)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_link_preview.material_override = mat
		get_tree().current_scene.add_child(_link_preview)
	var mat2: StandardMaterial3D = _link_preview.material_override as StandardMaterial3D
	mat2.albedo_color = Color(0.25, 1.0, 0.4, 0.75) if locked_to_port else Color(1.0, 0.9, 0.3, 0.45)
	var mid: Vector3 = (from + to) * 0.5
	var diff: Vector3 = to - from
	var len: float = max(diff.length(), 0.01)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.08, 0.08, len)
	_link_preview.mesh = box
	_link_preview.global_position = mid
	_link_preview.look_at(to, Vector3.UP)

func _clear_link_preview() -> void:
	if _link_preview != null:
		_link_preview.queue_free()
		_link_preview = null

# --- Port lock-on indicators ---

func _ensure_indicator(existing: MeshInstance3D, color: Color) -> MeshInstance3D:
	if existing != null:
		return existing
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	mi.mesh = sm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var transparent_color: Color = color
	transparent_color.a = 0.85
	mat.albedo_color = transparent_color
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	return mi

func _show_target_indicator(world_pos: Vector3) -> void:
	_link_target_indicator = _ensure_indicator(_link_target_indicator, PORT_LOCK_COLOR_TARGET)
	_link_target_indicator.global_position = world_pos
	_link_target_indicator.visible = true

func _hide_target_indicator() -> void:
	if _link_target_indicator != null:
		_link_target_indicator.visible = false

func _show_source_indicator(world_pos: Vector3) -> void:
	_link_source_indicator = _ensure_indicator(_link_source_indicator, PORT_LOCK_COLOR_SOURCE)
	_link_source_indicator.global_position = world_pos
	_link_source_indicator.visible = true

func _hide_source_indicator() -> void:
	if _link_source_indicator != null:
		_link_source_indicator.visible = false

func _clear_all_link_visuals() -> void:
	_clear_link_preview()
	_hide_target_indicator()
	_hide_source_indicator()

func _try_link_click() -> void:
	var hit: Dictionary = _raycast(FACTORY_LAYER_MASK)
	if hit.is_empty():
		return
	var bld: Building = _hit_to_building(hit.collider as Node)
	if bld == null:
		return
	if _link_source_port == null:
		# First click — pick an output port
		var port: Port = bld.find_closest_port(hit.position, Port.KIND_OUTPUT)
		if port == null or port.world_position().distance_to(hit.position) > PORT_PICK_RADIUS:
			return
		if not port.is_free():
			return
		_link_source_port = port
		link_state_changed.emit(true)
	else:
		# Second click — pick an input port and finalize
		var port: Port = bld.find_closest_port(hit.position, Port.KIND_INPUT)
		if port == null or port.world_position().distance_to(hit.position) > PORT_PICK_RADIUS:
			return
		if not port.is_free():
			return
		FactoryWorld.create_link(_link_source_port, port)
		_link_source_port = null
		link_state_changed.emit(false)

func _hit_to_building(n: Node) -> Building:
	# Climb the parent chain looking for a Building (StaticBody is a child of the building Node3D).
	while n != null:
		if n is Building:
			return n
		n = n.get_parent()
	return null

# --- Raycast helpers ---

func _raycast_terrain_cell() -> Vector3i:
	var hit: Dictionary = _raycast(TERRAIN_LAYER_MASK)
	if hit.is_empty():
		return NO_CELL
	var p: Vector3 = hit.position
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var base: Vector3i = Vector3i(floori(p.x), floori(p.y), floori(p.z))
	if normal.y > 0.5:
		base.y += 1
	return base

func _raycast(layer_mask: int) -> Dictionary:
	if _player == null or _player_camera == null:
		return {}
	var space_state: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var from: Vector3 = _player_camera.global_position
	var to: Vector3 = from + (-_player_camera.global_basis.z) * RAYCAST_LENGTH
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collision_mask = layer_mask
	return space_state.intersect_ray(query)

func _is_placeable_at(cell: Vector3i) -> bool:
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
		Tool.MERGER, Tool.SPLITTER:
			return Vector2i(1, 1)
		_:
			return Vector2i(1, 1)

# --- Place / remove ---

func _try_place() -> void:
	if _ghost_node == null or not _ghost_node.has_meta("placeable") or not _ghost_node.get_meta("placeable"):
		return
	var origin_cell: Vector3i = _ghost_node.get_meta("target_cell")
	var kind_name: StringName = _tool_to_kind_name()
	if kind_name == &"":
		return
	FactoryWorld.place(kind_name, origin_cell, ghost_rotation_steps)

func _try_remove() -> void:
	# Try a factory-layer raycast. If it hits a belt link's segment, remove the
	# whole link. If it hits a building, remove that building's footprint.
	var hit: Dictionary = _raycast(FACTORY_LAYER_MASK)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta("belt_link"):
		var link: BeltLink = collider.get_meta("belt_link") as BeltLink
		FactoryWorld.remove_link(link)
		return
	var bld: Building = _hit_to_building(hit.collider as Node)
	if bld != null:
		# Find any registered cell of this building and remove it
		FactoryWorld.remove(bld.origin_cell)

func _tool_to_kind_name() -> StringName:
	match current_tool:
		Tool.LOADER: return &"loader"
		Tool.SMELTER: return &"smelter"
		Tool.FORGE: return &"forge"
		Tool.MERGER: return &"merger"
		Tool.SPLITTER: return &"splitter"
	return &""
