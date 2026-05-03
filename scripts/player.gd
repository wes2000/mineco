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
@onready var _shovel: Node3D = $Camera3D/Shovel
@onready var _scanner_mesh: Node3D = $Camera3D/Scanner
@onready var _flashlight_mesh: Node3D = $Camera3D/Flashlight
@onready var _capsule_shape: CapsuleShape3D = ($CollisionShape3D.shape as CapsuleShape3D).duplicate() as CapsuleShape3D

var _crouch_lerp: float = 0.0   # 0=standing, 1=fully crouched

# Standard-mode tool selection. -1 = nothing equipped (no LMB action).
# 0 = Pickaxe, 1 = Ore Scanner (NYI), 2 = Flashlight (NYI).
const TOOL_NONE: int = -1
const TOOL_PICKAXE: int = 0
const TOOL_SCANNER: int = 1
const TOOL_FLASHLIGHT: int = 2

var current_tool: int = TOOL_PICKAXE
signal tool_changed(new_tool: int)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	BuildController.bind_player(self, _camera)
	_pickup_area.body_entered.connect(_on_pickup)
	_miner.material_pickup.connect(_on_material_pickup)
	# Use a per-instance capsule resource so crouch height changes don't bleed
	# into other things sharing the same shape resource.
	_collision.shape = _capsule_shape
	# Defer the initial tool sync so listeners (BottomHud, miner) hear the value.
	call_deferred("_emit_initial_tool")

func _emit_initial_tool() -> void:
	_apply_tool_visuals()
	tool_changed.emit(current_tool)

func _select_tool(t: int) -> void:
	# Pressing the same tool key again puts the tool away (toggle off).
	if current_tool == t:
		current_tool = TOOL_NONE
	else:
		current_tool = t
	_apply_tool_visuals()
	tool_changed.emit(current_tool)

func _apply_tool_visuals() -> void:
	if _shovel != null:
		_shovel.visible = (current_tool == TOOL_PICKAXE)
	if _scanner_mesh != null:
		_scanner_mesh.visible = (current_tool == TOOL_SCANNER)
	if _flashlight_mesh != null:
		_flashlight_mesh.visible = (current_tool == TOOL_FLASHLIGHT)
	# Also show/hide the scanner radar overlay + bind us as its player ref.
	var overlay: Node = get_tree().get_first_node_in_group("scanner_overlay")
	if overlay != null:
		if current_tool == TOOL_SCANNER:
			if overlay.has_method("bind_player"):
				overlay.call("bind_player", self)
			if overlay.has_method("show_scanner"):
				overlay.call("show_scanner")
		else:
			if overlay.has_method("hide_scanner"):
				overlay.call("hide_scanner")

func _on_material_pickup(material_id: int, amount: int) -> void:
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_message"):
		feed.call("add_message", material_id, amount)

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
	elif not BuildController.active:
		# Tool slots in standard mode (build mode owns these keys when active).
		if event.is_action_pressed("build_slot_1"):
			_select_tool(TOOL_PICKAXE)
		elif event.is_action_pressed("build_slot_2"):
			_select_tool(TOOL_SCANNER)
		elif event.is_action_pressed("build_slot_3"):
			_select_tool(TOOL_FLASHLIGHT)
		elif event.is_action_pressed("build_rotate") and current_tool == TOOL_SCANNER:
			# R cycles scanner target material when the scanner is out.
			var overlay: Node = get_tree().get_first_node_in_group("scanner_overlay")
			if overlay != null and overlay.has_method("cycle_material"):
				overlay.call("cycle_material")

const FACTORY_LAYER_MASK: int = 4

func _try_open_machine_ui() -> void:
	# 1a) Sell vendor NPC within 4m? Open the sell window.
	var vendor: Npc = _find_nearest_in_group("vendor_npcs", 4.0)
	if vendor != null:
		var vu: Node = get_tree().get_first_node_in_group("vendor_ui")
		if vu != null and vu.has_method("open"):
			vu.call("open")
			return
	# 1b) Contract vendor NPC within 4m? Open the contract board.
	var contract_vendor: Npc = _find_nearest_in_group("contract_vendor_npcs", 4.0)
	if contract_vendor != null and contract_vendor.contract_board != null:
		var cu: Node = get_tree().get_first_node_in_group("contract_ui")
		if cu != null and cu.has_method("open"):
			cu.call("open", contract_vendor.contract_board)
			return
	# 2) Raycast forward on the factory layer to detect a building under the crosshair.
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
	# 3) Proximity-find closest Building within 4m.
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

func _find_nearest_in_group(group_name: String, max_distance: float) -> Npc:
	var origin: Vector3 = global_position
	var max_sq: float = max_distance * max_distance
	var best: Npc = null
	var best_d: float = max_sq
	for n: Node in get_tree().get_nodes_in_group(group_name):
		if n is Npc:
			var d_sq: float = (n as Node3D).global_position.distance_squared_to(origin)
			if d_sq < best_d:
				best_d = d_sq
				best = n as Npc
	return best

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
	# Reveal the map around our current position. The MapData call is a no-op
	# for already-explored cells, so it's cheap to call every physics tick.
	if MapData != null:
		MapData.mark_explored(global_position)

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
