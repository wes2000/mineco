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
@onready var _pickup_shape: CollisionShape3D = $PickupArea/CollisionShape3D
# Captured at _ready so PICKUP_RADIUS_BONUS adds to the original sphere
# rather than to whatever the previous perk left it at.
var _pickup_base_radius: float = 1.5
@onready var _shovel: Node3D = $Camera3D/Shovel
@onready var _scanner_mesh: Node3D = $Camera3D/Scanner
@onready var _flashlight_mesh: Node3D = $Camera3D/Flashlight

# Set when in a boat; cleared on exit. While set, all the player walking +
# tool input is suppressed and the boat handles W/S/A/D itself.
var _driving_boat: Node = null
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
	# Same precaution for the pickup sphere — give us our own copy so resizing
	# from a perk doesn't leak across instances, then capture its base radius.
	if _pickup_shape != null and _pickup_shape.shape is SphereShape3D:
		var dup: SphereShape3D = (_pickup_shape.shape as SphereShape3D).duplicate() as SphereShape3D
		_pickup_shape.shape = dup
		_pickup_base_radius = dup.radius
	_apply_pickup_radius()
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null and stats.has_signal("stats_changed"):
		stats.stats_changed.connect(_apply_pickup_radius)
	# Defer the initial tool sync so listeners (BottomHud, miner) hear the value.
	call_deferred("_emit_initial_tool")

func _apply_pickup_radius() -> void:
	if _pickup_shape == null or not (_pickup_shape.shape is SphereShape3D):
		return
	var bonus: float = 0.0
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		bonus = float(stats.call("get_stat", &"pickup_radius_bonus"))
	(_pickup_shape.shape as SphereShape3D).radius = max(0.1, _pickup_base_radius + bonus)

func _emit_initial_tool() -> void:
	_apply_tool_visuals()
	tool_changed.emit(current_tool)

func get_save_data() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"rotation_y": rotation.y,
		"current_tool": current_tool,
	}

func apply_save_data(data: Dictionary) -> void:
	var pos: Array = data.get("position", [])
	if pos.size() == 3:
		global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	if data.has("rotation_y"):
		rotation.y = float(data["rotation_y"])
	if data.has("current_tool"):
		_select_tool(int(data["current_tool"]))

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
	elif event.is_action_pressed("passive_tree"):
		var ui: Node = get_tree().get_first_node_in_group("passive_tree_ui")
		if ui != null and ui.has_method("toggle"):
			ui.call("toggle")
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
	# Driving a boat? E exits regardless of anything else around.
	if _driving_boat != null:
		_driving_boat.call("exit")
		_driving_boat = null
		return
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
	# 1b2) Claim vendor NPC within 4m? Open the land-claim board.
	var claim_vendor: Npc = _find_nearest_in_group("claim_vendor_npcs", 4.0)
	if claim_vendor != null and claim_vendor.claim_board != null:
		var clu: Node = get_tree().get_first_node_in_group("claim_vendor_ui")
		if clu != null and clu.has_method("open"):
			clu.call("open", claim_vendor.claim_board)
			return
	# 1b3) Item shop NPC within 4m? Open the item shop.
	var item_shop: Npc = _find_nearest_in_group("item_shop_npcs", 4.0)
	if item_shop != null:
		var su: Node = get_tree().get_first_node_in_group("item_shop_ui")
		if su != null and su.has_method("open"):
			su.call("open")
			return
	# 1c) Boat vendor NPC within 4m? Open the boat vendor window.
	var boat_vendor: Npc = _find_nearest_in_group("boat_vendor_npcs", 4.0)
	if boat_vendor != null:
		var bu: Node = get_tree().get_first_node_in_group("boat_vendor_ui")
		if bu != null and bu.has_method("open"):
			bu.call("open")
			return
	# 1d) Boat within 4m? Climb in (only if we own one).
	var nearby_boat: Node = _find_nearest_boat(4.5)
	if nearby_boat != null:
		if not _miner.get("has_boat"):
			return  # silent — boat vendor sign should be enough hint
		nearby_boat.call("enter", self)
		_driving_boat = nearby_boat
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
		if bld_hit != null:
			if _try_open_special_ui(bld_hit):
				return
			if ui != null and ui.has_method("bind_to"):
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
	if best != null:
		if _try_open_special_ui(best):
			return
		if ui != null and ui.has_method("bind_to"):
			ui.call("bind_to", best)

# Storage crates / workbenches use their own modal panels rather than the
# generic machine UI. Returns true if `bld` was handled by one of them.
func _try_open_special_ui(bld: Building) -> bool:
	var script: Script = bld.get_script()
	var script_path: String = script.resource_path if script != null else ""
	if script_path.ends_with("storage_crate.gd"):
		var su: Node = get_tree().get_first_node_in_group("storage_crate_ui")
		if su != null and su.has_method("bind_to"):
			su.call("bind_to", bld)
			return true
	# Workbench uses the shared Structure script with kind == &"workbench".
	if bld.get("kind") == &"workbench":
		var wu: Node = get_tree().get_first_node_in_group("workbench_ui")
		if wu != null and wu.has_method("open"):
			wu.call("open")
			return true
	return false

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

func _find_nearest_boat(max_distance: float) -> Node:
	var origin: Vector3 = global_position
	var max_sq: float = max_distance * max_distance
	var best: Node = null
	var best_d: float = max_sq
	for n: Node in get_tree().get_nodes_in_group("boats"):
		if n is Node3D:
			var d_sq: float = (n as Node3D).global_position.distance_squared_to(origin)
			if d_sq < best_d:
				best_d = d_sq
				best = n
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
				var sprint_mul: float = SPRINT_MULTIPLIER
				var stats: Node = get_node_or_null("/root/PlayerStats")
				if stats != null:
					sprint_mul *= float(stats.call("get_stat", &"sprint_speed_mult"))
				speed = SPEED * sprint_mul

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
