class_name FactoryItem
extends Node3D
## A single material item riding on belts. Pooled — never directly freed.

@export var material_id: int = -1   # MaterialDefs.MaterialId enum value

var _current_cell: Vector3i
var _prev_cell_center: Vector3
var _current_cell_center: Vector3
var _move_start_time: float = 0.0
var _move_duration: float = 0.0   # 0 = stationary

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if _move_duration <= 0.0:
		global_position = _current_cell_center
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var t: float = clamp((now - _move_start_time) / _move_duration, 0.0, 1.0)
	global_position = _prev_cell_center.lerp(_current_cell_center, t)

func place_at(cell: Vector3i, world_center: Vector3) -> void:
	_current_cell = cell
	_current_cell_center = world_center
	_prev_cell_center = world_center
	_move_duration = 0.0
	global_position = world_center

func begin_move_to(target_cell: Vector3i, target_center: Vector3, duration_sec: float) -> void:
	_prev_cell_center = _current_cell_center
	_current_cell = target_cell
	_current_cell_center = target_center
	_move_start_time = Time.get_ticks_msec() / 1000.0
	_move_duration = duration_sec

func current_cell() -> Vector3i:
	return _current_cell
