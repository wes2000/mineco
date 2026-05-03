class_name Port
extends RefCounted
## A connection point on a Building. Each port has a local position + facing
## (in the building's un-rotated frame), a kind (input/output), and an
## optional attached BeltLink.

const KIND_INPUT: int = 0
const KIND_OUTPUT: int = 1

var owner_building: Node3D = null
var local_position: Vector3 = Vector3.ZERO
var local_facing: Vector3 = Vector3(0, 0, 1)   # +Z = forward in local frame
var kind: int = KIND_INPUT
var attached_link: Node = null   # BeltLink (Node3D) — typed loosely to avoid circular dep

func world_position() -> Vector3:
	if owner_building == null:
		return local_position
	return owner_building.to_global(local_position)

func world_facing() -> Vector3:
	if owner_building == null:
		return local_facing
	return (owner_building.global_basis * local_facing).normalized()

func is_free() -> bool:
	return attached_link == null
