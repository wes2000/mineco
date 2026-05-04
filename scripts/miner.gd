extends Node3D

@export var reach: float = 4.0
@export var brush_radius: float = 0.8
# Path to the Shovel under the player's Camera3D.
@export var shovel_path: NodePath = "../Camera3D/Shovel"
# Path to the Stamina node on the player.
@export var stamina_path: NodePath = "../Stamina"

@onready var _camera: Camera3D = get_node("../Camera3D")
@onready var _dirt_audio: AudioStreamPlayer3D = $DigEmitter
@onready var _ore_audio: AudioStreamPlayer3D = $OreHitEmitter
@onready var _shovel: Shovel = get_node(shovel_path)
@onready var _stamina: Stamina = get_node(stamina_path)

var _terrain: VoxelTerrain
var _player: CharacterBody3D
var _voxel_tool: VoxelTool

# World position of the most recent ore deposit hit. The chunk_broken signal
# doesn't carry a position, so we capture it here and read it back when the
# follow-up signal arrives (used to credit destroyed deposits to the owned
# land claim).
var _last_ore_hit_pos: Vector3 = Vector3.ZERO

# Append-only log of every voxel-terrain carve the player has made, so SaveGame
# can replay them on load. Each entry is {pos: [x, y, z], radius: float}.
var _carves: Array = []

var stone: int = 0
var iron: int = 0
var gold: int = 0

# T2/T3 counters (populated by player picking up factory drops, Task 22)
var brick: int = 0
var iron_ingot: int = 0
var gold_ingot: int = 0
var block: int = 0
var iron_bar: int = 0
var gold_bar: int = 0

# Currency (separate from the gold ore stack)
var gold_currency: int = 0

# Vehicles / unlocks
var has_boat: bool = false

signal inventory_changed(s: int, i: int, g: int)
signal extended_inventory_changed
signal material_pickup(material_id: int, amount: int)
signal gold_currency_changed(new_amount: int)

func add_gold_currency(amount: int) -> void:
	gold_currency += amount
	gold_currency_changed.emit(gold_currency)

func get_material_count(material_id: int) -> int:
	match material_id:
		MaterialDefs.MaterialId.STONE: return stone
		MaterialDefs.MaterialId.BRICK: return brick
		MaterialDefs.MaterialId.BLOCK: return block
		MaterialDefs.MaterialId.IRON_ORE: return iron
		MaterialDefs.MaterialId.IRON_INGOT: return iron_ingot
		MaterialDefs.MaterialId.IRON_BAR: return iron_bar
		MaterialDefs.MaterialId.GOLD_ORE: return gold
		MaterialDefs.MaterialId.GOLD_INGOT: return gold_ingot
		MaterialDefs.MaterialId.GOLD_BAR: return gold_bar
	return 0

func remove_material(material_id: int, amount: int) -> int:
	# Returns the amount actually removed.
	var have: int = get_material_count(material_id)
	var taken: int = min(have, amount)
	if taken <= 0:
		return 0
	match material_id:
		MaterialDefs.MaterialId.STONE: stone -= taken
		MaterialDefs.MaterialId.BRICK: brick -= taken
		MaterialDefs.MaterialId.BLOCK: block -= taken
		MaterialDefs.MaterialId.IRON_ORE: iron -= taken
		MaterialDefs.MaterialId.IRON_INGOT: iron_ingot -= taken
		MaterialDefs.MaterialId.IRON_BAR: iron_bar -= taken
		MaterialDefs.MaterialId.GOLD_ORE: gold -= taken
		MaterialDefs.MaterialId.GOLD_INGOT: gold_ingot -= taken
		MaterialDefs.MaterialId.GOLD_BAR: gold_bar -= taken
	inventory_changed.emit(stone, iron, gold)
	extended_inventory_changed.emit()
	return taken

func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_terrain = get_tree().root.get_node("Main/VoxelTerrain") as VoxelTerrain
	if _terrain != null:
		_voxel_tool = _terrain.get_voxel_tool()
		_voxel_tool.mode = VoxelTool.MODE_REMOVE
	_shovel.swing_hit_frame.connect(_on_hit_frame)
	add_to_group("player_miner")

func _process(_delta: float) -> void:
	if BuildController.active:
		return   # build mode suppresses mining (LMB belongs to placement)
	# Only swing if the player has the pickaxe equipped.
	if _player == null or _player.get("current_tool") != 0:   # 0 = TOOL_PICKAXE
		return
	if Input.is_action_pressed("mine"):
		_shovel.try_swing(_stamina)

func _on_hit_frame() -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var origin: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	var end: Vector3 = origin + forward * reach
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	# Hit both default terrain colliders and mining_targets (deposits).
	query.collision_mask = 0b11
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return  # whiff: no audio, no effect
	var collider = hit.collider
	if collider is OreDeposit:
		var hit_pos: Vector3 = (collider as Node3D).global_position
		# Land claims gate mining on the offshore islands. If this deposit
		# sits inside a claim island that the player doesn't own, refuse the
		# swing (still play the audio so the feedback is "you tried").
		if _is_locked_claim_deposit(hit_pos):
			_ore_audio.play()
			return
		if not collider.chunk_broken.is_connected(_on_chunk_broken):
			collider.chunk_broken.connect(_on_chunk_broken)
		_last_ore_hit_pos = hit_pos
		collider.take_damage(_shovel.get_effective_damage())
		_ore_audio.play()
	else:
		# Plain voxel terrain — carve dirt for traversal, no inventory credit.
		if _voxel_tool != null:
			var r: float = brush_radius * (Admin.radius_multiplier if Admin.big_radius else 1.0)
			_voxel_tool.do_sphere(hit.position, r)
			_carves.append({
				"pos": [hit.position.x, hit.position.y, hit.position.z],
				"radius": r,
			})
		_dirt_audio.play()

func _on_chunk_broken(material: int, amount: int, _stage: int) -> void:
	var pickup_id: int = -1
	match material:
		OreDeposit.OreType.STONE:
			stone += amount
			pickup_id = MaterialDefs.MaterialId.STONE
		OreDeposit.OreType.IRON:
			iron  += amount
			pickup_id = MaterialDefs.MaterialId.IRON_ORE
		OreDeposit.OreType.GOLD:
			gold  += amount
			pickup_id = MaterialDefs.MaterialId.GOLD_ORE
	inventory_changed.emit(stone, iron, gold)
	if pickup_id != -1:
		material_pickup.emit(pickup_id, amount)
	_credit_owned_claim(material, amount)

func _is_locked_claim_deposit(world_pos: Vector3) -> bool:
	# Returns true if the deposit at world_pos sits inside a claim island
	# that the player does NOT currently own. Owned-island deposits and
	# main-island deposits return false (mining allowed).
	var owned_id: String = ""
	var npc: Node = get_tree().get_first_node_in_group("claim_vendor_npcs")
	if npc != null:
		var board: Node = npc.get("claim_board")
		if board != null and board.has_owned():
			owned_id = String(board.owned_island().id)
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		if IslandVoxelGenerator.point_inside_island(isle, world_pos.x, world_pos.z):
			return String(isle.id) != owned_id
	return false

func _credit_owned_claim(ore_type: int, amount: int) -> void:
	# Find the claim vendor's board (one per game) and let it decide whether
	# the most recent hit fell inside the owned island radius. Board lookup
	# is untyped so the parser doesn't need ClaimVendorBoard's class cache.
	var npc: Node = get_tree().get_first_node_in_group("claim_vendor_npcs")
	if npc == null:
		return
	var board: Node = npc.get("claim_board")
	if board == null or not board.has_owned():
		return
	var isle: Dictionary = board.owned_island()
	if not IslandVoxelGenerator.point_inside_island(isle, _last_ore_hit_pos.x, _last_ore_hit_pos.z):
		return
	board.credit_mining(ore_type, amount)

func get_save_data() -> Dictionary:
	return {
		"materials": {
			"stone": stone, "brick": brick, "block": block,
			"iron": iron, "iron_ingot": iron_ingot, "iron_bar": iron_bar,
			"gold": gold, "gold_ingot": gold_ingot, "gold_bar": gold_bar,
		},
		"gold_currency": gold_currency,
		"has_boat": has_boat,
		"carves": _carves.duplicate(true),
	}

func apply_save_data(data: Dictionary) -> void:
	var m: Dictionary = data.get("materials", {})
	stone = int(m.get("stone", 0))
	brick = int(m.get("brick", 0))
	block = int(m.get("block", 0))
	iron = int(m.get("iron", 0))
	iron_ingot = int(m.get("iron_ingot", 0))
	iron_bar = int(m.get("iron_bar", 0))
	gold = int(m.get("gold", 0))
	gold_ingot = int(m.get("gold_ingot", 0))
	gold_bar = int(m.get("gold_bar", 0))
	gold_currency = int(data.get("gold_currency", 0))
	has_boat = bool(data.get("has_boat", false))
	# Preserve the carve log itself so future saves include earlier carves.
	# Replay is done lazily by SaveGame once nearby chunks are streamed in.
	_carves = []
	for c: Variant in data.get("carves", []):
		if c is Dictionary:
			_carves.append(c)
	inventory_changed.emit(stone, iron, gold)
	extended_inventory_changed.emit()
	gold_currency_changed.emit(gold_currency)

# Replays every saved carve onto the voxel terrain. Best-effort: chunks that
# aren't yet loaded won't take, but the player will see the dug terrain
# wherever chunks have streamed in by the time this is called.
func replay_carves() -> void:
	if _voxel_tool == null:
		return
	for c: Variant in _carves:
		if not (c is Dictionary):
			continue
		var pos_arr: Array = c.get("pos", [])
		if pos_arr.size() != 3:
			continue
		var radius: float = float(c.get("radius", brush_radius))
		_voxel_tool.do_sphere(
			Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])),
			radius,
		)

func add_factory_material(material_id: int, amount: int) -> void:
	# Used by FactoryDrop pickup. material_id is MaterialDefs.MaterialId enum value.
	match material_id:
		MaterialDefs.MaterialId.STONE: stone += amount
		MaterialDefs.MaterialId.BRICK: brick += amount
		MaterialDefs.MaterialId.BLOCK: block += amount
		MaterialDefs.MaterialId.IRON_ORE: iron += amount
		MaterialDefs.MaterialId.IRON_INGOT: iron_ingot += amount
		MaterialDefs.MaterialId.IRON_BAR: iron_bar += amount
		MaterialDefs.MaterialId.GOLD_ORE: gold += amount
		MaterialDefs.MaterialId.GOLD_INGOT: gold_ingot += amount
		MaterialDefs.MaterialId.GOLD_BAR: gold_bar += amount
	inventory_changed.emit(stone, iron, gold)
	extended_inventory_changed.emit()
	material_pickup.emit(material_id, amount)
