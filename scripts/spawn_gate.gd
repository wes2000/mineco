extends Node

signal world_ready

@export var voxel_terrain: NodePath
@export var player: NodePath

var _terrain: VoxelTerrain
var _player: CharacterBody3D

func _ready() -> void:
	_player = get_node(player) as CharacterBody3D
	_terrain = get_node(voxel_terrain) as VoxelTerrain
	if _player == null or _terrain == null:
		push_error("SpawnGate: voxel_terrain or player path is invalid")
		return
	# Freeze player physics until something solid exists below the spawn.
	_player.set_physics_process(false)

func _process(_delta: float) -> void:
	if _player == null or _terrain == null:
		return
	if _player.is_physics_processing():
		return
	# Cast a downward ray from above the player; when it hits, the chunk under
	# spawn has finished meshing and we can let the player fall.
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(_player.global_position.x, 100.0, _player.global_position.z),
		Vector3(_player.global_position.x, -50.0, _player.global_position.z)
	)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		_player.set_physics_process(true)
		set_process(false)
		world_ready.emit()
