extends Node
## Spawns a small flock of birds at startup, scattered around the island.

@export var bird_scene: PackedScene = preload("res://scenes/bird.tscn")
@export var bird_count: int = 8
@export var spawn_radius: float = 140.0
@export var spawn_y_min: float = 30.0
@export var spawn_y_max: float = 60.0

func _ready() -> void:
	for i: int in bird_count:
		var bird: Node3D = bird_scene.instantiate() as Node3D
		add_child(bird)
		bird.global_position = _random_spawn_pos()

func _random_spawn_pos() -> Vector3:
	var ang: float = randf() * TAU
	var r: float = sqrt(randf()) * spawn_radius   # uniform-area sample
	return Vector3(cos(ang) * r, randf_range(spawn_y_min, spawn_y_max), sin(ang) * r)
