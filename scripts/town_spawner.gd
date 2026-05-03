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

func _ready() -> void:
	var gate: Node = get_node_or_null(spawn_gate_path)
	if gate != null and gate.has_signal("world_ready"):
		gate.world_ready.connect(_spawn)
	else:
		# Fallback: spawn after a short delay so the terrain has time to mesh.
		await get_tree().create_timer(2.0).timeout
		_spawn()

func _spawn() -> void:
	for offset: Vector2 in HUT_OFFSETS:
		var hut: Node3D = hut_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(hut)
		var ground_y: float = _find_ground_y(offset.x, offset.y)
		hut.global_position = Vector3(offset.x, ground_y, offset.y)
		hut.rotation.y = randf_range(0.0, TAU)
	for i: int in NPC_OFFSETS.size():
		var offset: Vector2 = NPC_OFFSETS[i]
		var npc: Node3D = npc_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(npc)
		var ground_y: float = _find_ground_y(offset.x, offset.y)
		# Spawn 1m above the ground; gravity will settle them.
		npc.global_position = Vector3(offset.x, ground_y + 1.0, offset.y)
		npc.rotation.y = randf_range(0.0, TAU)
		# Color the shirt for variety
		var body_mesh: MeshInstance3D = npc.find_child("Body", true, false) as MeshInstance3D
		if body_mesh != null:
			var shirt_mat: StandardMaterial3D = StandardMaterial3D.new()
			shirt_mat.albedo_color = NPC_SHIRT_COLORS[i % NPC_SHIRT_COLORS.size()]
			shirt_mat.roughness = 0.95
			body_mesh.material_override = shirt_mat

func _find_ground_y(x: float, z: float) -> float:
	# Cast a ray from high up straight down through the world to find the
	# voxel terrain surface. Returns a fallback Y if nothing is hit.
	var space: PhysicsDirectSpaceState3D = get_tree().current_scene.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(x, 100.0, z), Vector3(x, -50.0, z))
	query.collision_mask = 1   # terrain layer only
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return 5.0
	return hit.position.y
