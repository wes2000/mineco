extends StaticBody3D
class_name TrainingDummy
## Combat sandbox target for testing weapon swings before real enemies exist.
## On `Health.died` it hides itself, queues a respawn after RESPAWN_DELAY, then
## refills HP and reappears so the player can keep practicing without leaving
## town.

const RESPAWN_DELAY: float = 4.0

@onready var _health: Health = $Health
@onready var _mesh_root: Node3D = $MeshRoot

var _respawning: bool = false

func _ready() -> void:
	add_to_group("damageables")
	add_to_group("training_dummies")
	if _health != null:
		_health.died.connect(_on_died)
		_health.damaged.connect(_on_damaged)

func _on_damaged(_amount: float, _source_pos: Vector3, _current: float, _max_v: int) -> void:
	# Tiny visual nudge so hits feel impactful even without a hit-flash shader.
	if _mesh_root != null:
		_mesh_root.position.x = randf_range(-0.05, 0.05)
		_mesh_root.position.z = randf_range(-0.05, 0.05)
		var tween: Tween = create_tween()
		tween.tween_property(_mesh_root, "position", Vector3(0, 0, 0), 0.12)

func _on_died(_source_pos: Vector3) -> void:
	if _respawning:
		return
	_respawning = true
	_set_visible_collidable(false)
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", "Dummy defeated")
	# Use a one-shot SceneTreeTimer so we don't fight pause / resume.
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn)

func _respawn() -> void:
	if _health != null:
		_health.revive_full()
	_set_visible_collidable(true)
	_respawning = false

func _set_visible_collidable(on: bool) -> void:
	visible = on
	# Walk children to disable any collision shapes; cheaper than touching
	# collision_layer because we want the body fully inert while down.
	for child: Node in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not on
