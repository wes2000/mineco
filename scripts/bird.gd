class_name Bird
extends Node3D
## A simple bird that flies in random directions, occasionally turning.
## Stays inside a horizontal radius and altitude band around (0,0,0).

@export var speed: float = 6.0
@export var turn_interval_min: float = 3.0
@export var turn_interval_max: float = 8.0
@export var max_horizontal_radius: float = 200.0
@export var min_y: float = 25.0
@export var max_y: float = 65.0
@export var bob_amplitude: float = 0.4
@export var bob_freq_hz: float = 1.2
@export var roll_amplitude_deg: float = 12.0

var _heading: Vector3 = Vector3(0, 0, 1)   # unit, horizontal (Y=0)
var _bob_phase: float = 0.0
var _next_turn_time: float = 0.0
var _y_drift: float = 0.0
var _base_y: float = 40.0
var _mesh: Node3D = null

func _ready() -> void:
	_mesh = $Mesh as Node3D
	_heading = _random_heading()
	_bob_phase = randf() * TAU
	_base_y = global_position.y
	_y_drift = randf_range(-3.0, 3.0)
	_schedule_next_turn()
	set_process(true)

func _process(delta: float) -> void:
	# Optional turn timer
	_next_turn_time -= delta
	if _next_turn_time <= 0.0:
		_heading = _heading.rotated(Vector3.UP, randf_range(-PI / 3, PI / 3)).normalized()
		_y_drift = randf_range(-3.0, 3.0)
		_schedule_next_turn()
	# Forward motion
	global_position += _heading * speed * delta
	# Soft boundary: if we're too far from origin or out of altitude band, turn back inward
	var horiz: Vector3 = Vector3(global_position.x, 0, global_position.z)
	if horiz.length() > max_horizontal_radius:
		var inward: Vector3 = -horiz.normalized()
		_heading = _heading.lerp(inward, 0.06).normalized()
	_base_y = clamp(_base_y + _y_drift * delta, min_y, max_y)
	if global_position.y < min_y or global_position.y > max_y:
		_y_drift *= -1.0
	# Vertical bob
	_bob_phase += delta * TAU * bob_freq_hz
	var bob: float = sin(_bob_phase) * bob_amplitude
	global_position.y = _base_y + bob
	# Face the heading + add a subtle roll based on turning rate
	look_at(global_position + _heading, Vector3.UP)
	if _mesh != null:
		var roll: float = sin(_bob_phase * 0.5) * deg_to_rad(roll_amplitude_deg)
		_mesh.rotation = Vector3(0, 0, roll)

func _random_heading() -> Vector3:
	var ang: float = randf() * TAU
	return Vector3(cos(ang), 0, sin(ang)).normalized()

func _schedule_next_turn() -> void:
	_next_turn_time = randf_range(turn_interval_min, turn_interval_max)
