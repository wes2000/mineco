extends Node
## Spawns a small village near origin once the world is ready: 4 huts arranged
## in a loose cluster + 4 NPCs wandering between them.

@export var hut_scene: PackedScene = preload("res://scenes/hut.tscn")
@export var npc_scene: PackedScene = preload("res://scenes/npc.tscn")
@export var dock_scene: PackedScene = preload("res://scenes/dock.tscn")
@export var boat_scene: PackedScene = preload("res://scenes/boat.tscn")
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
const CLAIM_VENDOR_INDEX: int = 2

# Sink the hut bottom slightly into the terrain so that voxel surface
# irregularities don't leave visible gaps under the box.
const HUT_SINK: float = 0.40
# Sample radius covering a 3.2m footprint AFTER a worst-case 45° rotation
# (so the rotated corners at √2 × 1.6 ≈ 2.26 are still covered).
const HUT_BOUND_RADIUS: float = 2.26

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
		var ground_y: float = await _find_max_ground_y_in_footprint(offset.x, offset.y)
		hut.global_position = Vector3(offset.x, ground_y - HUT_SINK, offset.y)
		hut.rotation.y = randf_range(0.0, TAU)
	_spawn_dock_and_boat()
	for i: int in NPC_OFFSETS.size():
		var offset: Vector2 = NPC_OFFSETS[i]
		var npc: Npc = npc_scene.instantiate() as Npc
		# Set vendor flags BEFORE add_child so npc._ready() picks them up and
		# joins the right groups on first entry to the tree.
		if i == VENDOR_INDEX:
			npc.is_vendor = true
		elif i == CONTRACT_VENDOR_INDEX:
			npc.is_contract_vendor = true
		elif i == CLAIM_VENDOR_INDEX:
			npc.is_claim_vendor = true
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
			elif i == CLAIM_VENDOR_INDEX:
				# Claim vendor: rich emerald with bright gold-green trim — sets
				# the "land baron" vibe and stands out against the other vendors.
				shirt_mat.albedo_color = Color(0.20, 0.55, 0.30, 1)
				shirt_mat.emission_enabled = true
				shirt_mat.emission = Color(0.55, 0.85, 0.30, 1)
				shirt_mat.emission_energy_multiplier = 0.45
			else:
				shirt_mat.albedo_color = NPC_SHIRT_COLORS[i % NPC_SHIRT_COLORS.size()]
			shirt_mat.roughness = 0.95
			body_mesh.material_override = shirt_mat

# Returns the MAX ground Y across 9 samples (center + 8 around a circle at the
# hut's bounding radius). Anchoring to the high point ensures no corner floats —
# other corners may sink slightly into the terrain, hidden by HUT_SINK. The
# circle pattern is rotation-invariant: any rotation of the hut still has its
# corners covered by the 8 perimeter samples.
func _spawn_dock_and_boat() -> void:
	# Walk outward from origin in the +Z direction until ground Y drops to
	# water level. That gives us the south coastline. Place the dock so its
	# inner end sits on land and its outer end juts into the water; the boat
	# floats just past the outer end; the dockmaster stands on the dock.
	var coast_z: float = 0.0
	for r: int in range(40, 180, 4):
		var y: float = await _find_ground_y_robust(0.0, float(r))
		if y < 0.6:
			coast_z = float(r) - 4.0   # back up one step so we're on land
			break
	if coast_z < 1.0:
		coast_z = 130.0   # fallback if the scan never hit water
	var land_y: float = await _find_ground_y_robust(0.0, coast_z)
	# Dock: 8m long, oriented south (its +Z extends toward the water).
	# Place the dock so its INNER edge sits at the coast, jutting outward.
	var dock_center_z: float = coast_z + 4.0   # half the dock length forward
	var dock: Node3D = dock_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(dock)
	dock.global_position = Vector3(0.0, max(land_y - 0.10, 0.10), dock_center_z)
	# Boat: floats just past the dock's outer end.
	var boat: Node3D = boat_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(boat)
	boat.global_position = Vector3(3.5, 0.0, dock_center_z + 5.0)
	boat.rotation.y = -PI * 0.5   # facing east so the bow points away from shore
	# Dockmaster NPC standing at the inner edge of the dock.
	var npc: Npc = npc_scene.instantiate() as Npc
	npc.is_boat_vendor = true
	npc.wander_radius = 3.0   # keep them on the dock
	# Position MUST be set before add_child — Npc._ready captures _spawn_pos
	# from global_position, and a stale (0,0,0) spawn 130m from the real
	# location makes the NPC immediately try to walk back to origin.
	npc.position = Vector3(-1.0, max(land_y, 0.20) + 1.0, coast_z + 2.0)
	get_tree().current_scene.add_child(npc)
	# Color the dockmaster: white sailor outfit with cool teal trim.
	var body_mesh: MeshInstance3D = npc.find_child("Body", true, false) as MeshInstance3D
	if body_mesh != null:
		var shirt_mat: StandardMaterial3D = StandardMaterial3D.new()
		shirt_mat.albedo_color = Color(0.85, 0.88, 0.92, 1)
		shirt_mat.emission_enabled = true
		shirt_mat.emission = Color(0.20, 0.55, 0.65, 1)
		shirt_mat.emission_energy_multiplier = 0.35
		shirt_mat.roughness = 0.95
		body_mesh.material_override = shirt_mat

func _find_max_ground_y_in_footprint(x: float, z: float) -> float:
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for i: int in 8:
		var ang: float = float(i) * TAU / 8.0
		offsets.append(Vector2(cos(ang), sin(ang)) * HUT_BOUND_RADIUS)
	var best: float = -INF
	for o: Vector2 in offsets:
		var y: float = await _find_ground_y_robust(x + o.x, z + o.y)
		if y > best:
			best = y
	return best

# Tries the physics raycast first (accurate to the meshed visual surface).
# Falls back to a VoxelTool raycast that returns the cell midpoint of the
# solid voxel (only used when chunks haven't been collision-meshed yet).
# Retries with small delays so chunks still streaming get covered.
func _find_ground_y_robust(x: float, z: float) -> float:
	var attempts: int = 6
	while attempts > 0:
		var y: float = _find_ground_y_physics(x, z)
		if not is_nan(y):
			return y
		y = _find_ground_y_voxel(x, z)
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
	# Solid voxel cell spans [position.y, position.y+1). The actual SDF
	# surface sits somewhere inside that cell — pick the midpoint as the
	# best blind estimate (vs previous_position.y which is +1 too high).
	return float(result.position.y) + 0.5

func _find_ground_y_physics(x: float, z: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_tree().current_scene.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(x, 100.0, z), Vector3(x, -50.0, z))
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return hit.position.y
