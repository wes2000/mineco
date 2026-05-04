extends Node3D
class_name Shovel
# Note: deliberately NOT named "Tool" — `@tool` is a Godot annotation and
# the bare class name invites confusion. When a pickaxe class arrives,
# either share a parent (e.g., MiningTool) or keep them as siblings.

@export var damage: int = 1
@export var stamina_cost: int = 10
@export var swing_duration: float = 0.7

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _mesh: Node3D = $Mesh
var _swinging: bool = false
# Per-tier pickaxe model paths. Loaded on demand by set_pickaxe_id().
const PICKAXE_GLBS: Dictionary = {
	"":                    "res://assets/models/pickaxe.glb",
	"pickaxe_copper":      "res://assets/models/pickaxe_copper.glb",
	"pickaxe_iron":        "res://assets/models/pickaxe_iron.glb",
	"pickaxe_gold_tipped": "res://assets/models/pickaxe_gold.glb",
	# Deepcore reuses the gold model until a dedicated mesh ships.
	"pickaxe_deepcore":    "res://assets/models/pickaxe_gold.glb",
}
# Same orientation correction the original ShovelGLB used inside the Mesh
# wrapper — the GLB asset's forward axis is flipped relative to ours.
const PICKAXE_LOCAL_XFORM: Transform3D = Transform3D(
	Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(0, 0, 0)
)
var _current_pickaxe_id: String = ""

signal swing_hit_frame
signal swing_started

func _ready() -> void:
	_anim.animation_finished.connect(_on_animation_finished)

# Swaps the visible pickaxe mesh to match the equipped tier. Called by Player
# from _on_shop_inventory_changed and on initial load. Idempotent — re-passing
# the same id is a no-op so we don't re-instantiate every shop refresh.
func set_pickaxe_id(pickaxe_id: String) -> void:
	if pickaxe_id == _current_pickaxe_id and _mesh != null and _mesh.get_child_count() > 0:
		return
	_current_pickaxe_id = pickaxe_id
	if _mesh == null:
		return
	for c: Node in _mesh.get_children():
		c.queue_free()
	var path: String = String(PICKAXE_GLBS.get(pickaxe_id, PICKAXE_GLBS[""]))
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return
	var inst: Node3D = packed.instantiate() as Node3D
	if inst == null:
		return
	inst.transform = PICKAXE_LOCAL_XFORM
	_mesh.add_child(inst)

func try_swing(stamina) -> bool:
	if _swinging: return false
	if not stamina.try_consume(stamina_cost):
		_anim.play("swing_empty")
		return false
	_swinging = true
	swing_started.emit()
	var speed: float = Admin.speed_multiplier if Admin.fast_speed else 1.0
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		speed *= float(stats.call("get_stat", &"mining_swing_speed_mult"))
	_anim.play("swing", -1, speed)
	return true

func get_effective_damage() -> int:
	var dmg: float = float(damage)
	# Admin cheat overrides everything (kept for testing parity); otherwise
	# scale by the player's mining_damage_mult progression stat.
	if Admin.fast_damage:
		return int(dmg * Admin.damage_multiplier)
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		dmg *= float(stats.call("get_stat", &"mining_damage_mult"))
	return max(1, int(round(dmg)))

func _on_animation_finished(_name: String) -> void:
	_swinging = false
	if _anim.current_animation != "idle":
		_anim.play("idle")

# Called by AnimationPlayer call-method track at the strike frame.
func _emit_hit_frame() -> void:
	swing_hit_frame.emit()
