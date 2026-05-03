class_name Npc
extends CharacterBody3D
## A simple wandering NPC. No interaction yet — just walks around in a small
## radius around its spawn point, occasionally stopping to idle.

@export var walk_speed: float = 1.4
@export var wander_radius: float = 9.0
@export var walk_time_min: float = 2.0
@export var walk_time_max: float = 5.0
@export var idle_time_min: float = 1.5
@export var idle_time_max: float = 3.5

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
