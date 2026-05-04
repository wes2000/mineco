extends Node3D
class_name Weapon
## Player-held weapon node. One scene + script handles every weapon id; the
## visible mesh is swapped on equip and the active def drives damage / range /
## cooldown. Plays a swing animation similar to Shovel.
##
## Owners drive this by calling `set_weapon_id(id)` on equip + LMB-poll
## `try_attack(camera)` while in standard mode with the weapon equipped.

const _WeaponDefs: GDScript = preload("res://scripts/weapon_defs.gd")

# Bit-mask matching collision layer 4 ("damageables", layer 4 in 1-based).
# Player damage raycasts only consider colliders on this layer so we never
# accidentally hit the terrain or factory parts. The training dummy + future
# enemies set their collision_layer accordingly.
const DAMAGEABLE_LAYER_MASK: int = 1 << 3   # 8

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _melee_mesh: Node3D = $MeleeMesh
@onready var _ranged_mesh: Node3D = $RangedMesh
@onready var _hit_audio: AudioStreamPlayer3D = $HitAudio

var _current_id: String = ""
var _current_def: Dictionary = {}
var _cooldown_until_msec: int = 0
var _swinging: bool = false

signal attack_started(def: Dictionary)
signal attack_landed(target: Node, damage: float)

func _ready() -> void:
	_anim.animation_finished.connect(_on_animation_finished)
	# Default hidden until something equips us.
	_apply_visibility()

func set_weapon_id(weapon_id: String) -> void:
	_current_id = weapon_id
	_current_def = _WeaponDefs.by_id(weapon_id) if weapon_id != "" else {}
	_apply_visibility()

func current_id() -> String:
	return _current_id

func current_def() -> Dictionary:
	return _current_def

func _apply_visibility() -> void:
	# Hide everything if no weapon equipped — owner also toggles top-level
	# visibility so this is just a safety net.
	var is_melee: bool = not _current_def.is_empty() and _current_def.get("type", "") == _WeaponDefs.TYPE_MELEE
	var is_ranged: bool = not _current_def.is_empty() and _current_def.get("type", "") == _WeaponDefs.TYPE_RANGED
	if _melee_mesh != null:
		_melee_mesh.visible = is_melee
	if _ranged_mesh != null:
		_ranged_mesh.visible = is_ranged

# Returns true if an attack started this frame. Cooldown + currently-swinging
# gates short-circuit. The actual damage is applied at the swing's hit frame
# via `_emit_hit_frame`.
func try_attack(camera: Camera3D) -> bool:
	if _current_def.is_empty() or camera == null:
		return false
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _cooldown_until_msec:
		return false
	if _swinging:
		return false
	_swinging = true
	_cooldown_until_msec = now_msec + int(round(float(_current_def.get("cooldown", 0.5)) * 1000.0))
	# Cache the camera so the deferred hit-frame call can raycast from the same
	# position the player aimed from. Storing the basis (not the node) avoids
	# stale orientation if the player turns mid-swing — we want the raycast at
	# the hit frame, not at swing start, so re-read the basis there too.
	_pending_camera = camera
	attack_started.emit(_current_def)
	_anim.play("swing")
	return true

var _pending_camera: Camera3D = null

# Called by an AnimationPlayer call-method track on the strike frame.
func _emit_hit_frame() -> void:
	if _pending_camera == null or _current_def.is_empty():
		return
	# Both types use a forward physics raycast on the damageables layer.
	# Ranged just uses a longer reach. v1 keeps it hitscan — projectiles can
	# come later.
	var reach: float = float(_current_def.get("range", 2.0))
	var damage: float = _compute_damage()
	var space: PhysicsDirectSpaceState3D = _pending_camera.get_world_3d().direct_space_state
	var origin: Vector3 = _pending_camera.global_position
	var dir: Vector3 = -_pending_camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach)
	query.collision_mask = DAMAGEABLE_LAYER_MASK
	# Exclude the player so we never self-hit.
	var owner_body: Node = _find_owner_body()
	if owner_body is CollisionObject3D:
		query.exclude = [(owner_body as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		# Whiff — still play the swing audio softly so the player gets feedback.
		if _hit_audio != null:
			_hit_audio.pitch_scale = 0.85
			_hit_audio.volume_db = -18.0
			_hit_audio.play()
		return
	var collider: Node = hit.get("collider")
	var damaged: bool = _try_apply_damage(collider, damage, hit.get("position", origin))
	if damaged and _hit_audio != null:
		_hit_audio.pitch_scale = 1.0
		_hit_audio.volume_db = -8.0
		_hit_audio.play()
		attack_landed.emit(collider, damage)
	_pending_camera = null

func _compute_damage() -> float:
	var base: float = float(_current_def.get("damage", 1))
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		base *= float(stats.call("get_stat", &"weapon_damage_mult"))
	return max(0.0, base)

# Walks up from the collider looking for either a Health child node or a
# `take_damage(amount, source_pos, tags)` method. Returns true if damage was
# applied. Decoupled from any class — supports the dummy now and any future
# enemy that exposes the same shape.
func _try_apply_damage(collider: Node, damage: float, hit_pos: Vector3) -> bool:
	var n: Node = collider
	while n != null:
		# Prefer a sibling/child Health component so the same node can carry
		# extra non-Health behavior.
		for child: Node in n.get_children():
			if child is Health:
				(child as Health).take_damage(damage, hit_pos)
				return true
		# Fall back to a duck-typed take_damage on the node itself. The
		# OreDeposit signature differs (single int) so we only match the
		# 3-arg version to avoid double-mining ore.
		if n.has_method("take_damage_combat"):
			n.call("take_damage_combat", damage, hit_pos, {})
			return true
		n = n.get_parent()
	return false

func _find_owner_body() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n
		n = n.get_parent()
	return null

func _on_animation_finished(_name: String) -> void:
	_swinging = false
	if _anim.current_animation != "idle":
		_anim.play("idle")
