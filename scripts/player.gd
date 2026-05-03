extends CharacterBody3D

const SPEED: float = 5.0
const FLY_SPEED: float = 15.0
const JUMP_VELOCITY: float = 5.0
const MOUSE_SENSITIVITY: float = 0.002
const PITCH_LIMIT: float = deg_to_rad(89.0)

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _miner: Node = $Miner
@onready var _pickup_area: Area3D = $PickupArea

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	BuildController.bind_player(self, _camera)
	_pickup_area.body_entered.connect(_on_pickup)

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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("machine_interact"):
		_try_open_machine_ui()

const FACTORY_LAYER_MASK: int = 4

func _try_open_machine_ui() -> void:
	# Step 1: raycast forward 4m on factory layer; if we hit a queue box,
	# transfer its contents to inventory. If we hit a building (non-queue),
	# open MachineUI for it.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = _camera.global_position
	var to: Vector3 = from + (-_camera.global_transform.basis.z) * 4.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collision_mask = FACTORY_LAYER_MASK
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_meta("queue_kind"):
			var kind: int = int(collider.get_meta("queue_kind"))
			var bld: Building = _hit_to_building(collider as Node)
			if bld != null:
				var taken: Array[int] = bld.take_all_from_queue(kind)
				for mid: int in taken:
					_miner.add_factory_material(mid, 1)
			return
		var bld_hit: Building = _hit_to_building(collider as Node)
		if bld_hit != null:
			var ui: Node = get_tree().get_first_node_in_group("machine_ui")
			if ui != null and ui.has_method("bind_to"):
				ui.call("bind_to", bld_hit)
			return
	# Step 2: fallback — proximity-find closest Building within 4m
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
	if best == null:
		return
	var ui: Node = get_tree().get_first_node_in_group("machine_ui")
	if ui != null and ui.has_method("bind_to"):
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

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
