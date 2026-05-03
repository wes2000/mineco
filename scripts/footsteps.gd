extends Node

@export var step_distance: float = 2.0
@export var sand_threshold_y: float = 1.2  # matches biome shader sand_band
@export var capsule_half_height: float = 0.9  # subtract from body origin to get feet Y
@export var walk_volume_db: float = -36.0
@export var crouch_volume_db: float = -48.0

@onready var _player: CharacterBody3D = get_parent()
@onready var _emitter: AudioStreamPlayer3D = $StepEmitter

var _last_step_pos: Vector3
var _grass: Array[AudioStream]
var _sand: Array[AudioStream]
var _water: Array[AudioStream]

func _ready() -> void:
	_last_step_pos = _player.global_position
	_grass = [
		preload("res://assets/audio/footstep_grass1.ogg"),
		preload("res://assets/audio/footstep_grass2.ogg"),
		preload("res://assets/audio/footstep_grass3.ogg"),
	]
	_sand = [
		preload("res://assets/audio/footstep_sand1.ogg"),
		preload("res://assets/audio/footstep_sand2.ogg"),
		preload("res://assets/audio/footstep_sand3.ogg"),
	]
	_water = [
		preload("res://assets/audio/footstep_water1.ogg"),
		preload("res://assets/audio/footstep_water2.ogg"),
	]

func _physics_process(_delta: float) -> void:
	if not _player.is_on_floor():
		return
	var horiz: Vector3 = Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var last_horiz: Vector3 = Vector3(_last_step_pos.x, 0.0, _last_step_pos.z)
	if horiz.distance_to(last_horiz) >= step_distance:
		_play_step()
		_last_step_pos = _player.global_position

func _play_step() -> void:
	# Feet Y, not body origin — capsule center is half-height above the feet.
	var feet_y: float = _player.global_position.y - capsule_half_height
	var bank: Array[AudioStream]
	if feet_y < 0.0:
		bank = _water
	elif feet_y < sand_threshold_y:
		bank = _sand
	else:
		bank = _grass
	if bank.is_empty():
		return
	var crouching: bool = Input.is_key_pressed(KEY_CTRL)
	_emitter.volume_db = crouch_volume_db if crouching else walk_volume_db
	_emitter.stream = bank.pick_random()
	_emitter.pitch_scale = randf_range(0.85, 1.05) if crouching else randf_range(0.9, 1.1)
	_emitter.play()
