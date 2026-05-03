extends Node
## Spawns a small village near origin once the world is ready: 4 huts arranged
## in a loose cluster + 4 NPCs wandering between them.

@export var hut_scene: PackedScene = preload("res://scenes/hut.tscn")
@export var npc_scene: PackedScene = preload("res://scenes/npc.tscn")
@export var spawn_gate_path: NodePath = NodePath("../SpawnGate")

# (x, z) offsets from world origin. Cluster diameter ≈ 30m so it sits inside
# the spawn area without crowding the player at (0, 30, 0).
const HUT_OFFSETS: Array[Vector2] = [
	Vector2(-12, -8),
	Vector2(13, -7),
	Vector2(-10, 11),
	Vector2(11, 12),
]
const NPC_OFFSETS: Array[Vector2] = [
	Vector2(-2, 0),
	Vector2(4, -3),
	Vector2(-5, 5),
	Vector2(2, 7),
]
const NPC_SHIRT_COLORS: Array[Color] = [
	Color(0.75, 0.30, 0.30),   # red
	Color(0.30, 0.45, 0.75),   # blue
	Color(0.40, 0.65, 0.35),   # green
	Color(0.85, 0.65, 0.30),   # yellow
]
# Indices into NPC_OFFSETS / NPC_SHIRT_COLORS for special NPCs.
const VENDOR_INDEX: int = 0
const CONTRACT_VENDOR_INDEX: int = 1

# Sink the hut bottom slightly into the terrain so that voxel surface
# irregularities don't leave visible gaps under the box.
const HUT_SINK: float = 0.25

func _ready() -> void:
	var gate: Node = get_node_or_null(spawn_gate_path)
	if gate != null and gate.has_signal("world_ready"):
		gate.world_ready.connect(_spawn)
	else:
		await get_tree().create_timer(2.0).timeout
		_spawn()

func _spawn() -> void:
	# Give distant chunks a beat to stream in past the player chunk that triggered
	# world_ready — the spawner needs ground at points up to ~17m away.
	await get_tree().create_timer(1.5).timeout
	for offset: Vector2 in HUT_OFFSETS:
		var hut: Node3D = hut_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(hut)
		var ground_y: float = await _find_ground_y_robust(offset.x, offset.y)
		hut.global_position = Vector3(offset.x, ground_y - HUT_SINK, offset.y)
		hut.rotation.y = randf_range(0.0, TAU)
	for i: int in NPC_OFFSETS.size():
		var offset: Vector2 = NPC_OFFSETS[i]
		var npc: Npc = npc_scene.instantiate() as Npc
		# Set vendor flags BEFORE add_child so npc._ready() picks them up and
		# joins the right groups on first entry to the tree.
		if i == VENDOR_INDEX:
			npc.is_vendor = true
		elif i == CONTRACT_VENDOR_INDEX:
			npc.is_contract_vendor = true
		get_tree().current_scene.add_child(npc)
		var ground_y: float = await _find_ground_y_robust(offset.x, offset.y)
		npc.global_position = Vector3(offset.x, ground_y + 1.5, offset.y)
		npc.rotation.y = randf_range(0.0, TAU)
		var body_mesh: MeshInstance3D = npc.find_child("Body", true, false) as MeshInstance3D
		if body_mesh != null:
			var shirt_mat: StandardMaterial3D = StandardMaterial3D.new()
			if i == VENDOR_INDEX:
				# Sell vendor: gold shirt with warm emissive trim.
				shirt_mat.albedo_color = Color(0.95, 0.78, 0.25, 1)
				shirt_mat.emission_enabled = true
				shirt_mat.emission = Color(0.6, 0.45, 0.10, 1)
				shirt_mat.emission_energy_multiplier = 0.4
			elif i == CONTRACT_VENDOR_INDEX:
				# Contract vendor: dark navy "business attire" with cool blue trim.
				shirt_mat.albedo_color = Color(0.20, 0.30, 0.55, 1)
				shirt_mat.emission_enabled = true
				shirt_mat.emission = Color(0.10, 0.30, 0.55, 1)
				shirt_mat.emission_energy_multiplier = 0.4
			else:
				shirt_mat.albedo_color = NPC_SHIRT_COLORS[i % NPC_SHIRT_COLORS.size()]
			shirt_mat.roughness = 0.95
			body_mesh.material_override = shirt_mat

# Tries the VoxelTool raycast first (queries voxel data directly — works even
# before chunks have visual collision shapes). Falls back to a physics raycast.
# Retries a few times with small delays if both fail (chunks still streaming).
func _find_ground_y_robust(x: float, z: float) -> float:
	var attempts: int = 6
	while attempts > 0:
		var y: float = _find_ground_y_voxel(x, z)
		if not is_nan(y):
			return y
		y = _find_ground_y_physics(x, z)
		if not is_nan(y):
			return y
		attempts -= 1
		await get_tree().create_timer(0.4).timeout
	push_warning("TownSpawner: gave up finding ground at (%s, %s)" % [x, z])
	return 5.0

func _find_ground_y_voxel(x: float, z: float) -> float:
	var terrain: VoxelTerrain = get_tree().current_scene.find_child("VoxelTerrain", true, false) as VoxelTerrain
	if terrain == null:
		return NAN
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return NAN
	var origin: Vector3 = Vector3(x, 100.0, z)
	var dir: Vector3 = Vector3(0, -1, 0)
	var result: VoxelRaycastResult = tool.raycast(origin, dir, 200.0)
	if result == null:
		return NAN
	# previous_position is the air cell just above the surface voxel.
	# The voxel surface sits at the top face of the solid voxel = previous_position.y.
	return float(result.previous_position.y)

func _find_ground_y_physics(x: float, z: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_tree().current_scene.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(x, 100.0, z), Vector3(x, -50.0, z))
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return hit.position.y
