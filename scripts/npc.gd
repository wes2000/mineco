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

# Vendor flag → swap to the vendor mesh on _ready. Townsfolk get the plain
# townsfolk mesh; everyone with a vendor flag gets the vendor mesh and is
# tinted via apply_shirt_tint() from town_spawner.
const _NPC_TOWN_GLB: PackedScene = preload("res://assets/models/npc_town.glb")
const _NPC_VENDOR_GLB: PackedScene = preload("res://assets/models/npc_vendor.glb")
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
	# Pick the vendor model for any vendor flag, otherwise the townsfolk model.
	var any_vendor: bool = is_vendor or is_contract_vendor or is_boat_vendor or is_claim_vendor or is_item_shop
	var packed: PackedScene = _NPC_VENDOR_GLB if any_vendor else _NPC_TOWN_GLB
	var visual_root: Node3D = get_node_or_null("Visual") as Node3D
	if visual_root == null:
		return
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
