class_name Npc
extends CharacterBody3D
## A simple wandering NPC. Some are vendors (player can sell items via E).

@export var walk_speed: float = 1.4
@export var wander_radius: float = 9.0
@export var walk_time_min: float = 2.0
@export var walk_time_max: float = 5.0
@export var idle_time_min: float = 1.5
@export var idle_time_max: float = 3.5
@export var is_vendor: bool = false
@export var is_contract_vendor: bool = false
@export var is_boat_vendor: bool = false
@export var is_claim_vendor: bool = false
@export var is_item_shop: bool = false
# Which town-NPC visual variant to load. -1 (default) means use the vendor
# model — used by the dockmaster and any out-of-town NPC. 0..3 picks one of
# the four town variants in _NPC_VARIANTS (red / green / blue / yellow).
@export var visual_variant: int = -1

# Set on _ready when is_contract_vendor — the per-vendor contract state.
var contract_board: ContractBoard = null
# Set on _ready when is_claim_vendor — the per-vendor land-claim state.
# Untyped (Node) so the editor's class cache doesn't need to resolve
# ClaimVendorBoard to parse this file on first import.
var claim_board: Node = null

enum State { WALK, IDLE }

# Distance past which the NPC is hidden (visibility_range_end) and physics
# is parked at spawn — keeps the player from seeing distant NPCs falling
# through unstreamed chunks before they pop into view. Kept well inside
# the terrain mesher's reliable-near-player radius.
const VISIBILITY_DIST: float = 144.0
const PHYSICS_ACTIVE_DIST: float = 80.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_pos: Vector3
var _heading: Vector3 = Vector3(0, 0, 1)
var _state: int = State.IDLE
var _state_remaining: float = 0.0
var _player_cached: Node3D = null
# Set by Player while a vendor UI is open against this NPC. While true the
# NPC stops wandering and slowly turns to look at `face_target` so the
# player can complete the conversation without chasing them around.
var is_frozen: bool = false
var face_target: Node3D = null
# Procedural fake-walk bob. The NPC GLBs are unrigged static meshes — no
# AnimationPlayer to drive — so while WALKing we sin-bob the Visual node's
# y/z to suggest a gait. Visual local position is reset to (0, 1.125, 0) on
# IDLE so the feet match the capsule bottom.
const _WALK_BOB_AMPLITUDE: float = 0.06
const _WALK_TILT_AMPLITUDE: float = 0.08
const _WALK_BOB_HZ: float = 2.4
var _walk_phase: float = 0.0
var _visual_root: Node3D = null
const _VISUAL_REST_Y: float = 1.4

# Town NPC variants — one per index 0..3. The town spawner assigns each of
# its four NPC slots a different variant so they read as distinct people.
# Out-of-town NPCs (dockmaster) use the vendor mesh.
const _NPC_VENDOR_GLB: PackedScene = preload("res://assets/models/npc_vendor.glb")
const _NPC_VARIANTS: Array[PackedScene] = [
	preload("res://assets/models/npc_red.glb"),
	preload("res://assets/models/npc_green.glb"),
	preload("res://assets/models/npc_blue.glb"),
	preload("res://assets/models/npc_town.glb"),  # original / yellow
]
# Cached after _spawn_visual so apply_shirt_tint can recolor the right meshes.
var _visual_meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	# Capture the post-physics-settle spawn so wander_radius is anchored to the
	# actual ground position, not the slightly-elevated drop position.
	_spawn_pos = global_position
	# Generic group used by the map widgets for icon overlays.
	add_to_group("npcs")
	# Vendor lookups go through the 'vendor_npcs' group. Joining here means the
	# town spawner only has to flip is_vendor and we'll show up next frame.
	if is_vendor:
		add_to_group("vendor_npcs")
	if is_contract_vendor:
		add_to_group("contract_vendor_npcs")
		contract_board = ContractBoard.new()
		contract_board.name = "ContractBoard"
		add_child(contract_board)
	if is_boat_vendor:
		add_to_group("boat_vendor_npcs")
	if is_claim_vendor:
		add_to_group("claim_vendor_npcs")
		# Instantiate via load() to avoid needing the class_name to be in the
		# parser's class cache at npc.gd parse time.
		var board_script: GDScript = load("res://scripts/claim_vendor_board.gd")
		claim_board = board_script.new()
		claim_board.name = "ClaimBoard"
		add_child(claim_board)
	if is_item_shop:
		add_to_group("item_shop_npcs")
	_spawn_visual()
	_apply_visibility_range_recursive(self)
	_begin_walk()

func _spawn_visual() -> void:
	# Pick the visual variant: town spawner stamps visual_variant 0..3 on
	# each of its four town NPC slots so they look distinct; everyone else
	# (dockmaster / future NPCs) defaults to the vendor model.
	var packed: PackedScene
	if visual_variant >= 0 and visual_variant < _NPC_VARIANTS.size():
		packed = _NPC_VARIANTS[visual_variant]
	else:
		packed = _NPC_VENDOR_GLB
	var visual_root: Node3D = get_node_or_null("Visual") as Node3D
	if visual_root == null:
		return
	_visual_root = visual_root
	var inst: Node3D = packed.instantiate() as Node3D
	visual_root.add_child(inst)
	# Cache every MeshInstance3D inside the loaded model so apply_shirt_tint
	# can recolor without re-walking the tree each call. We also duplicate
	# their material_override so per-NPC tints don't leak across instances.
	_visual_meshes.clear()
	_collect_mesh_instances(inst)
	for mi: MeshInstance3D in _visual_meshes:
		var src_mat: Material = mi.material_override if mi.material_override != null else mi.get_active_material(0)
		if src_mat is StandardMaterial3D:
			mi.material_override = (src_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		elif src_mat is BaseMaterial3D:
			mi.material_override = (src_mat as BaseMaterial3D).duplicate() as BaseMaterial3D

func _collect_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_visual_meshes.append(node)
	for c: Node in node.get_children():
		_collect_mesh_instances(c)

# Tints every visual mesh on this NPC. Used by town_spawner to differentiate
# vendor types (gold sell vendor, navy contracts, emerald claim, etc).
func apply_shirt_tint(tint: Color, emission: Color = Color(0, 0, 0, 0), emission_energy: float = 0.0) -> void:
	for mi: MeshInstance3D in _visual_meshes:
		if not (mi.material_override is BaseMaterial3D):
			continue
		var mat: BaseMaterial3D = mi.material_override as BaseMaterial3D
		mat.albedo_color = tint
		if emission.a > 0.0:
			mat.emission_enabled = true
			mat.emission = emission
			mat.emission_energy_multiplier = emission_energy

func _apply_visibility_range_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		var g: GeometryInstance3D = node
		g.visibility_range_end = VISIBILITY_DIST
		g.visibility_range_end_margin = 16.0
	for c: Node in node.get_children():
		_apply_visibility_range_recursive(c)

func _physics_process(delta: float) -> void:
	# Frozen takes precedence over everything — keep this NPC rooted in
	# place, faced at the player, while a vendor UI is open. Skip the wander
	# state machine entirely; gravity + move_and_slide still run so we
	# don't lose ground contact, and the bob settles into idle.
	if is_frozen:
		if _state != State.IDLE:
			_state = State.IDLE
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		else:
			velocity.y = 0.0
		if face_target != null and is_instance_valid(face_target):
			var look: Vector3 = (face_target as Node3D).global_position
			look.y = global_position.y
			if look.distance_squared_to(global_position) > 0.04:
				look_at(look, Vector3.UP)
		move_and_slide()
		_update_walk_bob(delta)
		return
	# Park at spawn while the player is far away — without this NPCs run
	# gravity over unstreamed chunks and visibly fall through the void
	# while the surrounding terrain is still meshing in.
	if not _is_player_within(PHYSICS_ACTIVE_DIST):
		global_position = _spawn_pos
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_state_remaining -= delta
	if _state_remaining <= 0.0:
		if _state == State.WALK:
			_begin_idle()
		else:
			_begin_walk()
	if _state == State.WALK:
		velocity.x = _heading.x * walk_speed
		velocity.z = _heading.z * walk_speed
		# Face the heading
		var target_look: Vector3 = global_position + _heading
		target_look.y = global_position.y
		look_at(target_look, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	_update_walk_bob(delta)
	# Self-heal: voxel chunks unload while the player is far away, leaving the
	# NPC standing on nothing. They fall into the void and stay there once the
	# player returns. Snap them back to spawn if they've dropped unreasonably
	# far below it.
	if global_position.y < _spawn_pos.y - 8.0:
		global_position = _spawn_pos
		velocity = Vector3.ZERO
	# If we've drifted too far from spawn, redirect inward right away.
	var horiz: Vector2 = Vector2(global_position.x - _spawn_pos.x, global_position.z - _spawn_pos.z)
	if horiz.length() > wander_radius:
		var inward: Vector2 = -horiz.normalized()
		_heading = Vector3(inward.x, 0, inward.y)
		_state = State.WALK
		_state_remaining = randf_range(walk_time_min, walk_time_max)

func _begin_walk() -> void:
	var ang: float = randf() * TAU
	_heading = Vector3(cos(ang), 0, sin(ang))
	_state = State.WALK
	_state_remaining = randf_range(walk_time_min, walk_time_max)

func _begin_idle() -> void:
	_state = State.IDLE
	_state_remaining = randf_range(idle_time_min, idle_time_max)

func _is_player_within(dist: float) -> bool:
	if _player_cached == null:
		_player_cached = get_node_or_null("/root/Main/Player") as Node3D
	if _player_cached == null:
		return true   # no player yet — don't pre-emptively freeze
	return global_position.distance_squared_to(_player_cached.global_position) <= dist * dist

# Procedural fake-walk: bob the Visual node up/down + side-to-side tilt while
# WALKing. Settles back to rest pose when IDLE. The GLBs are unrigged static
# meshes, so this is the cheapest way to suggest a gait without sourcing
# rigged + animated character assets.
func _update_walk_bob(delta: float) -> void:
	if _visual_root == null:
		return
	if _state == State.WALK:
		_walk_phase += delta * _WALK_BOB_HZ * TAU
		var bob: float = sin(_walk_phase * 2.0) * _WALK_BOB_AMPLITUDE
		var tilt: float = sin(_walk_phase) * _WALK_TILT_AMPLITUDE
		_visual_root.position = Vector3(0.0, _VISUAL_REST_Y + bob, 0.0)
		_visual_root.rotation = Vector3(0.0, 0.0, tilt)
	else:
		# Ease back to rest so the snap to idle isn't jarring.
		_walk_phase = 0.0
		_visual_root.position = _visual_root.position.lerp(Vector3(0.0, _VISUAL_REST_Y, 0.0), 8.0 * delta)
		_visual_root.rotation = _visual_root.rotation.lerp(Vector3.ZERO, 8.0 * delta)
