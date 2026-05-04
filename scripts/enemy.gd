class_name Enemy
extends CharacterBody3D
## Simple melee enemy: detects the player within DETECT_RADIUS, chases, and
## swings on cooldown when within ATTACK_RANGE. No navmesh / pathfinding —
## the voxel terrain is forgiving enough that walking straight at the player
## works for v1. Visibility + physics culling mirrors npc.gd so distant
## islands don't tank perf.
##
## Damage to the enemy goes through the Health child node (so the player's
## weapon raycast hits us via the standard "damageables" pipeline). Damage to
## the player is applied directly by reading the player's Health child.

const DETECT_RADIUS: float = 25.0
const ATTACK_RANGE: float = 1.8
const ATTACK_COOLDOWN: float = 1.2
const VISIBILITY_DIST: float = 96.0
const PHYSICS_ACTIVE_DIST: float = 80.0
# How far below spawn we tolerate before snapping back. Enemies spawn slightly
# above the surface (see IslandEncounters._spawn_one) so a small sag from
# voxel chunk reload is normal — only large drops (chunks not yet meshed)
# trigger the heal.
const SELF_HEAL_BELOW_SPAWN: float = 8.0

@export var max_hp: int = 30
@export var damage: int = 6
@export var move_speed: float = 1.8
@export var island_id: String = ""

signal enemy_killed(island_id: String)

@onready var _health: Node = $Health
@onready var _mesh_root: Node3D = $MeshRoot

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_pos: Vector3
var _player_cached: Node3D = null
var _player_health_cached: Node = null
var _attack_cooldown_until_msec: int = 0
var _is_dead: bool = false
# Per-enemy material clones + their original albedo, so the hit-flash can
# tint each enemy independently and tween back without leaking to other
# instances (the scene file shares one BodyMat / HeadMat sub-resource).
var _flash_materials: Array[StandardMaterial3D] = []
var _flash_base_colors: Array[Color] = []

func _ready() -> void:
	_spawn_pos = global_position
	add_to_group("damageables")
	add_to_group("enemies")
	if _health != null:
		# Configure the Health child to match our stat block. The node is
		# instanced fresh per-enemy so this won't leak across copies.
		_health.set("base_max", max_hp)
		_health.set("current", float(max_hp))
		if _health.has_signal("died"):
			_health.died.connect(_on_died)
		if _health.has_signal("damaged"):
			_health.damaged.connect(_on_damaged)
	_capture_flash_materials()
	_apply_visibility_range_recursive(self)

func _capture_flash_materials() -> void:
	# Walk MeshRoot, duplicate every StandardMaterial3D material_override so
	# the hit-flash can mutate albedo without leaking across enemy instances
	# (scene-level material sub-resources are shared otherwise). Cache each
	# original albedo so the tween can return to the right base color.
	if _mesh_root == null:
		return
	for child: Node in _mesh_root.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi: MeshInstance3D = child
		if not (mi.material_override is StandardMaterial3D):
			continue
		var dup: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		mi.material_override = dup
		_flash_materials.append(dup)
		_flash_base_colors.append(dup.albedo_color)

func configure(opts: Dictionary) -> void:
	# Called by IslandEncounters before _ready (we set vars; _ready then reads
	# them off our Health child). Keeps spawn-site data cleanly out-of-band
	# from inspector defaults.
	if opts.has("hp"):
		max_hp = int(opts.hp)
	if opts.has("damage"):
		damage = int(opts.damage)
	if opts.has("speed"):
		move_speed = float(opts.speed)
	if opts.has("island_id"):
		island_id = String(opts.island_id)

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	# Park at spawn while the player is far away — same trick as npc.gd to
	# avoid running gravity over unstreamed chunks.
	if not _is_player_within(PHYSICS_ACTIVE_DIST):
		global_position = _spawn_pos
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var player: Node3D = _resolve_player()
	if player == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_self_heal_if_void()
		return
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist <= ATTACK_RANGE:
		# In melee — face the player and try to swing.
		velocity.x = 0.0
		velocity.z = 0.0
		_face(player.global_position)
		_try_attack(player)
	elif dist <= DETECT_RADIUS:
		# Chase: walk straight at the player on the XZ plane. Voxel terrain
		# is forgiving enough that we don't need pathfinding for v1.
		var dir: Vector3 = Vector3(to_player.x, 0.0, to_player.z).normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		_face(player.global_position)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	_self_heal_if_void()

func _self_heal_if_void() -> void:
	if global_position.y < _spawn_pos.y - SELF_HEAL_BELOW_SPAWN:
		global_position = _spawn_pos
		velocity = Vector3.ZERO

func _face(target: Vector3) -> void:
	var look_t: Vector3 = target
	look_t.y = global_position.y
	if look_t.distance_squared_to(global_position) < 0.0001:
		return
	look_at(look_t, Vector3.UP)

func _try_attack(player: Node3D) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _attack_cooldown_until_msec:
		return
	_attack_cooldown_until_msec = now_msec + int(round(ATTACK_COOLDOWN * 1000.0))
	# Resolve the player's Health and apply damage. Cached because the lookup
	# walks children every call and the player node identity is stable.
	if _player_health_cached == null:
		_player_health_cached = _find_player_health(player)
	if _player_health_cached != null and _player_health_cached.has_method("take_damage"):
		_player_health_cached.call("take_damage", float(damage), global_position, {})
	# Tiny mesh "punch" tween for visual feedback, mirroring the dummy hit jiggle.
	if _mesh_root != null:
		var tween: Tween = create_tween()
		tween.tween_property(_mesh_root, "position",
			Vector3(0, _mesh_root.position.y, 0.15), 0.06)
		tween.tween_property(_mesh_root, "position",
			Vector3(0, _mesh_root.position.y, 0.0), 0.10)

func _find_player_health(player: Node) -> Node:
	# Player.tscn places the Health node directly under the Player root.
	for child: Node in player.get_children():
		if child.name == "Health":
			return child
	# Fallback: any child that has a take_damage method.
	for child: Node in player.get_children():
		if child.has_method("take_damage"):
			return child
	return null

func _resolve_player() -> Node3D:
	if _player_cached != null and is_instance_valid(_player_cached):
		return _player_cached
	# The player_miner group lives on the Miner child of Player. Walk up to
	# the CharacterBody3D so distance + Health both work off the same node.
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null:
		var p: Node = miner.get_parent()
		if p is Node3D:
			_player_cached = p
			return _player_cached
	# Fallback path used by other scripts.
	var player: Node = get_node_or_null("/root/Main/Player")
	if player is Node3D:
		_player_cached = player
	return _player_cached

func _is_player_within(dist: float) -> bool:
	var p: Node3D = _resolve_player()
	if p == null:
		return false   # No player yet — stay parked.
	return global_position.distance_squared_to(p.global_position) <= dist * dist

func _apply_visibility_range_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		var g: GeometryInstance3D = node
		g.visibility_range_end = VISIBILITY_DIST
		g.visibility_range_end_margin = 16.0
	for c: Node in node.get_children():
		_apply_visibility_range_recursive(c)

func _on_damaged(_amount: float, _source_pos: Vector3, _current: float, _max_v: int) -> void:
	# Hit-flash via per-material albedo tween. Node3D has no `modulate`
	# (CanvasItem/Control only), so we tint each MeshInstance3D's duplicated
	# material directly and tween it back to the captured base color.
	if _flash_materials.is_empty():
		return
	for i: int in _flash_materials.size():
		var mat: StandardMaterial3D = _flash_materials[i]
		var base: Color = _flash_base_colors[i]
		# Pop to a hot pink-red flash, then tween back to the original albedo.
		mat.albedo_color = Color(1.0, 0.45, 0.45, base.a)
		var tween: Tween = create_tween()
		tween.tween_property(mat, "albedo_color", base, 0.18)

func _on_died(_source_pos: Vector3) -> void:
	if _is_dead:
		return
	_is_dead = true
	# Tell the encounter tracker first so it can update state even if we
	# get queue_freed before the next frame.
	enemy_killed.emit(island_id)
	# Tiny pickup-feed toast so the player gets confirmation.
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", "Enemy down")
	# Hide + free. We disable physics first so a corpse can't keep colliding.
	set_physics_process(false)
	for child: Node in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	visible = false
	# Defer free so any pending signal listeners finish.
	queue_free()
