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
		if not collider.chunk_broken.is_connected(_on_chunk_broken):
			collider.chunk_broken.connect(_on_chunk_broken)
		collider.take_damage(_shovel.get_effective_damage())
		_ore_audio.play()
	else:
		# Plain voxel terrain — carve dirt for traversal, no inventory credit.
		if _voxel_tool != null:
			var r: float = brush_radius * (Admin.radius_multiplier if Admin.big_radius else 1.0)
			_voxel_tool.do_sphere(hit.position, r)
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
