extends CharacterBody3D

const SPEED: float = 5.0
const SPRINT_MULTIPLIER: float = 1.7
const SPRINT_DRAIN_PER_SEC: float = 28.0   # ~3.5s of full sprint from full stamina
const CROUCH_SPEED: float = 2.4
const FLY_SPEED: float = 15.0
const JUMP_VELOCITY: float = 5.0
const MOUSE_SENSITIVITY: float = 0.002
const PITCH_LIMIT: float = deg_to_rad(89.0)

# Crouch transitions
const STANDING_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.0
const STANDING_CAMERA_Y: float = 0.7
const CROUCH_CAMERA_Y: float = 0.0
const CROUCH_LERP_SPEED: float = 8.0   # 1/seconds — controls how fast crouch animates

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _miner: Node = $Miner
@onready var _stamina: Node = $Stamina
@onready var _pickup_area: Area3D = $PickupArea
@onready var _capsule_shape: CapsuleShape3D = ($CollisionShape3D.shape as CapsuleShape3D).duplicate() as CapsuleShape3D

var _crouch_lerp: float = 0.0   # 0=standing, 1=fully crouched

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/floating_text.tscn")
const PICKUP_TEXT_COLORS: Dictionary = {
	0: Color(0.85, 0.85, 0.9),    # STONE
	1: Color(1.0, 0.55, 0.4),     # BRICK
	2: Color(0.6, 0.6, 0.6),      # BLOCK
	3: Color(0.85, 0.65, 0.5),    # IRON_ORE
	4: Color(0.9, 0.9, 0.95),     # IRON_INGOT
	5: Color(1, 1, 1),            # IRON_BAR
	6: Color(0.9, 0.78, 0.35),    # GOLD_ORE
	7: Color(1, 0.85, 0.4),       # GOLD_INGOT
	8: Color(1, 0.9, 0.5),        # GOLD_BAR
}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	BuildController.bind_player(self, _camera)
	_pickup_area.body_entered.connect(_on_pickup)
	_miner.material_pickup.connect(_on_material_pickup)
	# Use a per-instance capsule resource so crouch height changes don't bleed
	# into other things sharing the same shape resource.
	_collision.shape = _capsule_shape

func _on_material_pickup(material_id: int, amount: int) -> void:
	var ft: Label3D = FLOATING_TEXT_SCENE.instantiate() as Label3D
	get_tree().current_scene.add_child(ft)
	# Spawn just above the player camera with a tiny random horizontal jitter
	var jitter: Vector3 = Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	var spawn: Vector3 = _camera.global_position + Vector3(0, 0.6, 0) + jitter
	var text: String = "+%d %s" % [amount, MaterialDefs.DISPLAY_NAME[material_id]]
	var col: Color = PICKUP_TEXT_COLORS.get(material_id, Color.WHITE)
	ft.call("setup", text, spawn, col)

func _on_pickup(body: Node) -> void:
	if body is FactoryDrop:
		var fd: FactoryDrop = body as FactoryDrop
		_miner.add_factory_material(fd.material_id, 1)
		fd.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		_camera.rotation.x = clamp(_camera.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed("ui_cancel"):
		# No other UI consumed Esc — toggle the pause menu.
		var menu: Node = get_tree().get_first_node_in_group("pause_menu")
		if menu != null and menu.has_method("toggle"):
			menu.toggle()
	elif event.is_action_pressed("machine_interact"):
		_try_open_machine_ui()

const FACTORY_LAYER_MASK: int = 4

func _try_open_machine_ui() -> void:
	# Raycast forward 4m on factory layer; if we hit a building, open MachineUI.
	# Otherwise fall back to proximity-find closest Building within 4m.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = _camera.global_position
	var to: Vector3 = from + (-_camera.global_transform.basis.z) * 4.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collision_mask = FACTORY_LAYER_MASK
	var hit: Dictionary = space.intersect_ray(query)
	var ui: Node = get_tree().get_first_node_in_group("machine_ui")
	if not hit.is_empty():
		var bld_hit: Building = _hit_to_building(hit.get("collider") as Node)
		if bld_hit != null and ui != null and ui.has_method("bind_to"):
			ui.call("bind_to", bld_hit)
			return
	# Fallback: proximity-find closest Building within 4m
	var origin: Vector3 = global_position
	var best: Building = null
	var best_dist_sq: float = 16.0
	var seen: Dictionary = {}
	for cell: Vector3i in FactoryWorld._cells:
		var owner: Node3D = FactoryWorld._cells[cell]
		if owner is Building and not seen.has(owner):
			seen[owner] = true
			var d_sq: float = owner.global_position.distance_squared_to(origin)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = owner as Building
	if best != null and ui != null and ui.has_method("bind_to"):
		ui.call("bind_to", best)

func _hit_to_building(n: Node) -> Building:
	while n != null:
		if n is Building:
			return n
		n = n.get_parent()
	return null

func _physics_process(delta: float) -> void:
	# Sync collision-shape state to admin toggle so re-enabling noclip mid-frame is safe.
	_collision.disabled = Admin.noclip
	if Admin.noclip:
		_fly(delta)
	else:
		_walk(delta)

func _fly(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Camera-relative so flying forward respects pitch (look down + W = dive).
	var basis: Basis = _camera.global_transform.basis
	var dir: Vector3 = basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if Input.is_action_pressed("jump"):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		dir.y -= 1.0
	if dir.length() > 0.001:
		dir = dir.normalized()
	velocity = Vector3.ZERO
	position += dir * FLY_SPEED * delta

func _walk(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Crouch: smoothly interpolate capsule height + camera height.
	var crouching: bool = Input.is_key_pressed(KEY_CTRL)
	var crouch_target: float = 1.0 if crouching else 0.0
	_crouch_lerp = move_toward(_crouch_lerp, crouch_target, CROUCH_LERP_SPEED * delta)
	_apply_crouch()

	if Input.is_action_just_pressed("jump") and is_on_floor() and _crouch_lerp < 0.5:
		velocity.y = JUMP_VELOCITY

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Movement speed: crouch wins, else sprint if held + has stamina, else walk.
	var moving: bool = direction.length_squared() > 0.0001
	var speed: float = SPEED
	if _crouch_lerp > 0.5:
		speed = CROUCH_SPEED
	elif moving and Input.is_key_pressed(KEY_SHIFT):
		if _stamina != null and _stamina.has_method("try_drain"):
			if _stamina.try_drain(SPRINT_DRAIN_PER_SEC, delta):
				speed = SPEED * SPRINT_MULTIPLIER

	if moving:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

func _apply_crouch() -> void:
	var height: float = lerp(STANDING_HEIGHT, CROUCH_HEIGHT, _crouch_lerp)
	_capsule_shape.height = height
	# Keep capsule bottom at the same Y in player frame so the player doesn't
	# float or sink when shrinking.
	_collision.position.y = (height - STANDING_HEIGHT) * 0.5
	# Drop the camera with the crouch.
	_camera.position.y = lerp(STANDING_CAMERA_Y, CROUCH_CAMERA_Y, _crouch_lerp)
