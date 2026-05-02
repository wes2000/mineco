class_name BeltCell
extends Node3D
## A single placed belt piece. Owns at most one FactoryItem.

enum Kind { STRAIGHT, CORNER, T }

const BELT_SPEED_TICKS: int = 10   # 1 cell per second at 10 Hz

@export var kind: int = Kind.STRAIGHT
@export var facing: Vector3i = Vector3i(0, 0, 1)   # unit vector toward output side

var cell: Vector3i               # set by FactoryWorld on placement
var occupant: FactoryItem = null # current item (or null)
var settle_ticks: int = 0        # ticks remaining before occupant can advance
var blocked_ticks: int = 0       # ticks the occupant has been waiting unable to advance

func get_facing() -> Vector3i:
	return facing

func set_cell_and_facing(c: Vector3i, f: Vector3i) -> void:
	cell = c
	facing = f
	rotation = _facing_to_basis_y_rot(f)

func _facing_to_basis_y_rot(f: Vector3i) -> Vector3:
	if f == Vector3i(0, 0, 1):
		return Vector3.ZERO
	if f == Vector3i(1, 0, 0):
		return Vector3(0, -PI / 2, 0)
	if f == Vector3i(0, 0, -1):
		return Vector3(0, PI, 0)
	if f == Vector3i(-1, 0, 0):
		return Vector3(0, PI / 2, 0)
	return Vector3.ZERO

func cell_center_world() -> Vector3:
	return Vector3(cell.x + 0.5, cell.y + 0.1, cell.z + 0.5)

func is_free() -> bool:
	return occupant == null

func place_item(item: FactoryItem) -> void:
	occupant = item
	settle_ticks = BELT_SPEED_TICKS
	blocked_ticks = 0
	item.place_at(cell, cell_center_world())

func receive_moving_item(item: FactoryItem, prev_center: Vector3, duration_sec: float) -> void:
	occupant = item
	settle_ticks = BELT_SPEED_TICKS
	blocked_ticks = 0
	item._prev_cell_center = prev_center
	item.begin_move_to(cell, cell_center_world(), duration_sec)

func clear_item() -> void:
	occupant = null
	settle_ticks = 0
	blocked_ticks = 0

func can_advance_now() -> bool:
	return occupant != null and settle_ticks <= 0

func tick_settle() -> void:
	if settle_ticks > 0:
		settle_ticks -= 1
