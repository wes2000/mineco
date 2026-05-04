extends Node3D
class_name Shovel
# Note: deliberately NOT named "Tool" — `@tool` is a Godot annotation and
# the bare class name invites confusion. When a pickaxe class arrives,
# either share a parent (e.g., MiningTool) or keep them as siblings.

@export var damage: int = 1
@export var stamina_cost: int = 10
@export var swing_duration: float = 0.7

@onready var _anim: AnimationPlayer = $AnimationPlayer
var _swinging: bool = false

signal swing_hit_frame
signal swing_started

func _ready() -> void:
	_anim.animation_finished.connect(_on_animation_finished)

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
