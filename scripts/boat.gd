class_name Boat
extends CharacterBody3D
## Simple arcade boat. Stays clamped to water level (Y=0). W/S accelerate
## (bounded forward/back); A/D yaw. Player enters/exits via E from the player
## controller. While driving, player is teleported to the helm each frame and
## player walking input is suppressed.

const WATER_LEVEL_Y: float = 0.0
const MAX_SPEED: float = 14.0      # m/s forward
const MAX_REVERSE: float = 6.0     # m/s reverse
const ACCEL: float = 5.5
const REVERSE_ACCEL: float = 4.5
const DRAG: float = 1.2            # natural decel when no input
const TURN_SPEED: float = 1.7      # rad/s at full speed
const TURN_MIN_FACTOR: float = 0.25  # turn responsiveness when nearly stopped

signal driving_started
signal driving_stopped

var current_speed: float = 0.0
var is_driving: bool = false
var _player: Node3D = null

@onready var _helm: Node3D = $Helm

func _ready() -> void:
	add_to_group("boats")

func enter(player: Node3D) -> void:
	if is_driving:
		return
	is_driving = true
	_player = player
	# Suppress player physics so it doesn't fight the teleport-to-helm.
	if _player.has_method("set_physics_process"):
		_player.set_physics_process(false)
	driving_started.emit()

func exit() -> void:
	if not is_driving:
		return
	is_driving = false
	current_speed = 0.0
	if _player != null:
		# Drop the player off on the right-hand side of the boat, slightly above
		# the deck so they don't spawn inside the hull.
		var side: Vector3 = global_basis.x * 2.4
		var drop_pos: Vector3 = global_position + side + Vector3(0, 1.5, 0)
		_player.global_position = drop_pos
		if _player.has_method("set_physics_process"):
			_player.set_physics_process(true)
	_player = null
	driving_stopped.emit()

func _physics_process(delta: float) -> void:
	if not is_driving:
		# Idle bob would go here; keep simple and just clamp to water level.
		global_position.y = WATER_LEVEL_Y
		return
	# Throttle (W = forward, S = reverse). Walking actions reused so they
	# work without registering new input bindings.
	var throttle: float = 0.0
	if Input.is_action_pressed("move_forward"):
		throttle += 1.0
	if Input.is_action_pressed("move_back"):
		throttle -= 1.0
	if throttle > 0.0:
		current_speed = min(current_speed + ACCEL * delta * throttle, MAX_SPEED)
	elif throttle < 0.0:
		current_speed = max(current_speed + REVERSE_ACCEL * delta * throttle, -MAX_REVERSE)
	else:
		# Natural drag toward zero
		if current_speed > 0.0:
			current_speed = max(0.0, current_speed - DRAG * delta)
		elif current_speed < 0.0:
			current_speed = min(0.0, current_speed + DRAG * delta)
	# Steering: A = left, D = right. Reverse swaps the steering feel naturally
	# because turning a stationary boat is hard, but we always rotate the boat
	# regardless of speed sign so it can pivot at low speed.
	var steer: float = 0.0
	if Input.is_action_pressed("move_left"):
		steer += 1.0
	if Input.is_action_pressed("move_right"):
		steer -= 1.0
	var speed_norm: float = clamp(abs(current_speed) / MAX_SPEED, 0.0, 1.0)
	var turn_factor: float = TURN_MIN_FACTOR + (1.0 - TURN_MIN_FACTOR) * speed_norm
	# Reverse: invert steering so the bow swings the right way (real-boat feel).
	if current_speed < 0.0:
		steer = -steer
	rotate_y(steer * TURN_SPEED * turn_factor * delta)
	# Move forward in the boat's facing direction
	var forward: Vector3 = -global_basis.z
	velocity = forward * current_speed
	# Snap to water level — no buoyancy sim, just lock Y.
	global_position.y = WATER_LEVEL_Y
	move_and_slide()
	# Teleport player to helm (player physics is suspended).
	if _player != null and _helm != null:
		_player.global_position = _helm.global_position
	# Player._physics_process is suspended while driving, so the fog-of-war
	# reveal stops too. Drive it from here using the boat's position.
	if MapData != null:
		MapData.mark_explored(global_position)
