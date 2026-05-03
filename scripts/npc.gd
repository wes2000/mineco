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

# Set on _ready when is_contract_vendor — the per-vendor contract state.
var contract_board: ContractBoard = null
# Set on _ready when is_claim_vendor — the per-vendor land-claim state.
# Untyped (Node) so the editor's class cache doesn't need to resolve
# ClaimVendorBoard to parse this file on first import.
var claim_board: Node = null

enum State { WALK, IDLE }

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_pos: Vector3
var _heading: Vector3 = Vector3(0, 0, 1)
var _state: int = State.IDLE
var _state_remaining: float = 0.0

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
	_begin_walk()

func _physics_process(delta: float) -> void:
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
