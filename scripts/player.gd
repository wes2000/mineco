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
@onready var _weapon: Node3D = $Camera3D/Weapon
@onready var _health: Node = $Health

# Set when in a boat; cleared on exit. While set, all the player walking +
# tool input is suppressed and the boat handles W/S/A/D itself.
var _driving_boat: Node = null
@onready var _capsule_shape: CapsuleShape3D = ($CollisionShape3D.shape as CapsuleShape3D).duplicate() as CapsuleShape3D

var _crouch_lerp: float = 0.0   # 0=standing, 1=fully crouched

# Standard-mode tool selection. -1 = nothing equipped (no LMB action).
# 0 = Pickaxe, 1 = Ore Scanner, 2 = Flashlight, 3 = Weapon (only if owned).
const TOOL_NONE: int = -1
const TOOL_PICKAXE: int = 0
const TOOL_SCANNER: int = 1
const TOOL_FLASHLIGHT: int = 2
const TOOL_WEAPON: int = 3

var current_tool: int = TOOL_PICKAXE
signal tool_changed(new_tool: int)

# Multiplayer transform broadcast throttle. _physics_process ticks at 60 Hz;
# we broadcast at ~20 Hz (every 3 frames) when online to keep bandwidth
# reasonable while still giving smooth remote movement.
var _mp_broadcast_accum: float = 0.0
const _MP_BROADCAST_INTERVAL: float = 1.0 / 20.0  # seconds

# Town respawn position. Player.tscn places us at (0, 30, 0); on death we
# warp back here and the SpawnGate-style ground catch then drops us safely.
const RESPAWN_POSITION: Vector3 = Vector3(0.0, 30.0, 0.0)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	BuildController.bind_player(self, _camera)
	_pickup_area.body_entered.connect(_on_pickup)
	_miner.material_pickup.connect(_on_material_pickup)
	# Combat: be hittable by anything that respects the damageables layer +
	# group so future enemies can damage the player through the same API.
	add_to_group("damageables")
	# Player CharacterBody3D originally only collided as layer 1 (default).
	# Add bit 4 ("damageables", 1<<3 = 8) so weapon raycasts could find us
	# (mostly cosmetic for v1 — the weapon excludes its owning body — but it
	# means future enemy code can target Player via the same mask).
	collision_layer |= 1 << 3
	if _health != null:
		_health.died.connect(_on_player_died)
		_health.damaged.connect(_on_player_damaged)
	# Re-sync the weapon mesh whenever the player buys / equips a different
	# weapon at the shop, even if the weapon slot is currently active.
	if _miner != null and _miner.has_signal("shop_inventory_changed"):
		_miner.shop_inventory_changed.connect(_on_shop_inventory_changed)
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
	# Sync the pickaxe + weapon meshes to whatever Miner currently has equipped
	# (e.g. on a fresh boot before a save load — defaults are no-pickaxe and
	# no-weapon, so set_pickaxe_id("") loads the fallback model).
	_sync_pickaxe_from_equipped()
	_sync_weapon_from_equipped()
	_apply_tool_visuals()
	tool_changed.emit(current_tool)

func get_save_data() -> Dictionary:
	var d: Dictionary = {
		"position": [global_position.x, global_position.y, global_position.z],
		"rotation_y": rotation.y,
		"current_tool": current_tool,
	}
	if _health != null and _health.has_method("get_save_data"):
		d["health"] = _health.call("get_save_data")
	return d

func apply_save_data(data: Dictionary) -> void:
	var pos: Array = data.get("position", [])
	var teleported: bool = false
	if pos.size() == 3:
		global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		teleported = true
	if data.has("rotation_y"):
		rotation.y = float(data["rotation_y"])
	if data.has("current_tool"):
		_select_tool(int(data["current_tool"]))
	if data.has("health") and _health != null and _health.has_method("apply_save_data"):
		_health.call("apply_save_data", data["health"])
	# Equipping a weapon during load needs the Weapon node to know its def, so
	# push that through after Miner has restored equipped_items.
	_sync_weapon_from_equipped()
	# If the saved position is on a far island, the chunks under it haven't
	# streamed in yet — without re-engaging SpawnGate the player would fall
	# through the void waiting for the mesh.
	if teleported:
		var gate: Node = get_tree().get_first_node_in_group("spawn_gate")
		if gate != null and gate.has_method("suspend_until_ground"):
			gate.call("suspend_until_ground")

func _select_tool(t: int) -> void:
	# Weapon slot only equips if the player actually owns + equipped one.
	if t == TOOL_WEAPON and not _has_equipped_weapon():
		return
	# Pressing the same tool key again puts the tool away (toggle off).
	if current_tool == t:
		current_tool = TOOL_NONE
	else:
		current_tool = t
	_apply_tool_visuals()
	tool_changed.emit(current_tool)

func _on_shop_inventory_changed() -> void:
	_sync_weapon_from_equipped()
	_sync_pickaxe_from_equipped()
	# If the weapon was unequipped while the slot was active, fall back to no
	# tool so the empty mesh isn't held up.
	if current_tool == TOOL_WEAPON and not _has_equipped_weapon():
		current_tool = TOOL_NONE
		_apply_tool_visuals()
		tool_changed.emit(current_tool)

func _sync_pickaxe_from_equipped() -> void:
	if _shovel == null or not _shovel.has_method("set_pickaxe_id"):
		return
	if _miner == null:
		return
	var equipped: Dictionary = _miner.get("equipped_items")
	var pid: String = String(equipped.get("pickaxe", "")) if equipped != null else ""
	_shovel.call("set_pickaxe_id", pid)

func _has_equipped_weapon() -> bool:
	var equipped: Dictionary = _miner.get("equipped_items") if _miner != null else {}
	return equipped != null and equipped.has("weapon") and String(equipped["weapon"]) != ""

func _sync_weapon_from_equipped() -> void:
	if _weapon == null or not _weapon.has_method("set_weapon_id"):
		return
	if _miner == null:
		return
	var equipped: Dictionary = _miner.get("equipped_items")
	var wid: String = String(equipped.get("weapon", "")) if equipped != null else ""
	_weapon.call("set_weapon_id", wid)

func _apply_tool_visuals() -> void:
	if _shovel != null:
		_shovel.visible = (current_tool == TOOL_PICKAXE)
	if _scanner_mesh != null:
		_scanner_mesh.visible = (current_tool == TOOL_SCANNER)
	if _flashlight_mesh != null:
		_flashlight_mesh.visible = (current_tool == TOOL_FLASHLIGHT)
	if _weapon != null:
		_weapon.visible = (current_tool == TOOL_WEAPON)
		# Sync the displayed mesh to the equipped weapon id every time we draw
		# the weapon — equipping a different one in the shop while the slot is
		# active should swap immediately.
		if current_tool == TOOL_WEAPON:
			_sync_weapon_from_equipped()
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
	elif event.is_action_pressed("company_panel"):
		var co_ui: Node = get_tree().get_first_node_in_group("company_panel_ui")
		if co_ui != null and co_ui.has_method("toggle"):
			co_ui.call("toggle")
	elif event.is_action_pressed("release_mouse"):
		# Quick mouse-release toggle for editor inspector use without opening
		# any UI / pausing the world. Press again to recapture.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not BuildController.active:
		# Tool slots in standard mode (build mode owns these keys when active).
		if event.is_action_pressed("build_slot_1"):
			_select_tool(TOOL_PICKAXE)
		elif event.is_action_pressed("build_slot_2"):
			_select_tool(TOOL_SCANNER)
		elif event.is_action_pressed("build_slot_3"):
			_select_tool(TOOL_FLASHLIGHT)
		elif event.is_action_pressed("build_slot_4"):
			# Weapon slot — only does anything if the player owns + equipped one.
			_select_tool(TOOL_WEAPON)
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
	# Pick the SINGLE closest vendor NPC across every vendor group, so a
	# claim vendor 1 m away wins over a sell vendor 2.5 m away even if the
	# code originally checked sellers first. Range tightened to 2.5 m so
	# the player has to actually walk up to a specific NPC.
	var nearest: Npc = _find_nearest_vendor(2.5)
	if nearest != null:
		if _try_open_for_vendor(nearest):
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

# Vendor groups that interaction can dispatch to. Order is irrelevant — we
# only use it as a set to walk and the closest NPC across all groups wins.
const _VENDOR_GROUPS: Array[String] = [
	"vendor_npcs",
	"contract_vendor_npcs",
	"claim_vendor_npcs",
	"item_shop_npcs",
	"boat_vendor_npcs",
]

# Returns the closest Npc in any vendor group within `max_distance`, or
# null. De-dupes across groups in case an NPC is multiply-tagged.
func _find_nearest_vendor(max_distance: float) -> Npc:
	var origin: Vector3 = global_position
	var max_sq: float = max_distance * max_distance
	var best: Npc = null
	var best_d: float = max_sq
	var seen: Dictionary = {}
	for g: String in _VENDOR_GROUPS:
		for n: Node in get_tree().get_nodes_in_group(g):
			if not (n is Npc):
				continue
			var key: int = n.get_instance_id()
			if seen.has(key):
				continue
			seen[key] = true
			var d_sq: float = (n as Node3D).global_position.distance_squared_to(origin)
			if d_sq < best_d:
				best_d = d_sq
				best = n as Npc
	return best

# Dispatch to the right vendor UI based on which group(s) the NPC belongs
# to. Returns true on success so the caller can short-circuit. Also kicks
# off the freeze + face_target so the NPC stops wandering during the
# conversation.
func _try_open_for_vendor(npc: Npc) -> bool:
	var ui: Node = null
	var open_args: Array = []
	if npc.is_in_group("vendor_npcs"):
		ui = get_tree().get_first_node_in_group("vendor_ui")
	elif npc.is_in_group("contract_vendor_npcs") and npc.contract_board != null:
		ui = get_tree().get_first_node_in_group("contract_ui")
		open_args = [npc.contract_board]
	elif npc.is_in_group("claim_vendor_npcs") and npc.claim_board != null:
		ui = get_tree().get_first_node_in_group("claim_vendor_ui")
		open_args = [npc.claim_board]
	elif npc.is_in_group("item_shop_npcs"):
		ui = get_tree().get_first_node_in_group("item_shop_ui")
	elif npc.is_in_group("boat_vendor_npcs"):
		ui = get_tree().get_first_node_in_group("boat_vendor_ui")
	if ui == null or not ui.has_method("open"):
		return false
	ui.callv("open", open_args)
	_start_vendor_freeze(npc)
	return true

# Freeze management. The frozen NPC is captured here so _process can
# auto-release on the frame the player closes the menu (mouse recaptured).
var _frozen_vendor: Npc = null

func _start_vendor_freeze(npc: Npc) -> void:
	if _frozen_vendor != null and _frozen_vendor != npc:
		_end_vendor_freeze()
	_frozen_vendor = npc
	npc.is_frozen = true
	npc.face_target = self

func _end_vendor_freeze() -> void:
	if _frozen_vendor == null:
		return
	if is_instance_valid(_frozen_vendor):
		_frozen_vendor.is_frozen = false
		_frozen_vendor.face_target = null
	_frozen_vendor = null

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

func _process(_delta: float) -> void:
	# Vendor freeze auto-release: cursor coming back to CAPTURED means every
	# modal closed, so the NPC can resume wandering. Done before the
	# weapon-attack early-exits so it always runs even in build mode.
	if _frozen_vendor != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_end_vendor_freeze()
	# Weapon attack — gated on standard mode + weapon equipped + owns one.
	if BuildController.active or current_tool != TOOL_WEAPON:
		return
	# Modal UI -> mouse becomes visible; suppress LMB attack so menu clicks
	# don't double-fire as a swing on whatever's behind the panel.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _weapon == null or not _weapon.has_method("try_attack"):
		return
	if Input.is_action_pressed("mine"):
		_weapon.call("try_attack", _camera)

# --- Damage / death --------------------------------------------------------

func _on_player_damaged(amount: float, _src: Vector3, _cur: float, _max_v: int) -> void:
	# Pulse a brief red overlay via the bottom HUD's optional helper. Kept
	# untyped so Hud can decide how to render it.
	var hud: Node = get_node_or_null("/root/Main/HUD/BottomHud")
	if hud != null and hud.has_method("flash_damage"):
		hud.call("flash_damage", amount)
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", "Took %d damage" % int(round(amount)))

func _on_player_died(_src: Vector3) -> void:
	# v1 respawn: warp to town spawn + restore full HP. No item loss.
	global_position = RESPAWN_POSITION
	velocity = Vector3.ZERO
	if _health != null and _health.has_method("revive_full"):
		_health.call("revive_full")
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", "You died — respawned in town")

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
	# Multiplayer: broadcast our transform so RemotePlayers on other peers
	# can mirror us. No-op when offline (Net.is_online returns false).
	if Net != null and Net.is_online():
		_mp_broadcast_accum += delta
		if _mp_broadcast_accum >= _MP_BROADCAST_INTERVAL:
			_mp_broadcast_accum = 0.0
			var anim_state: String = "walking" if velocity.length_squared() > 0.04 else "idle"
			Net.recv_remote_transform.rpc(global_position, rotation.y, current_tool, anim_state)

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
