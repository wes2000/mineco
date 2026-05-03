extends Node3D
class_name OreGenerator

@export var generator_seed: int = 1337
@export var island_radius: float = 145.0
@export var underground_y_band: Vector2 = Vector2(-60.0, -2.0)

@export var surface_grid_step: float = 6.0
@export var surface_jitter: float = 2.5
@export var stone_deposits: int = 80
@export var iron_deposits: int = 20
@export var gold_deposits: int = 7

@export var stone_small_scn: PackedScene
@export var stone_medium_scn: PackedScene
@export var stone_large_scn: PackedScene
@export var iron_small_scn: PackedScene
@export var iron_large_scn: PackedScene
@export var gold_small_scn: PackedScene
@export var gold_large_scn: PackedScene
@export var surface_rock_scn: PackedScene

@export var voxel_terrain_path: NodePath
@export var island_generator_path: NodePath

var _rng: RandomNumberGenerator
var _island_generator: IslandVoxelGenerator
var _ore_noise: FastNoiseLite

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = generator_seed
	_ore_noise = load("res://assets/ore_noise.tres") as FastNoiseLite

func generate() -> void:
	var terrain := get_node(voxel_terrain_path) as VoxelTerrain
	if terrain == null:
		push_error("OreGenerator: VoxelTerrain not found at " + str(voxel_terrain_path))
		return
	_island_generator = terrain.generator as IslandVoxelGenerator
	if _island_generator == null:
		push_error("OreGenerator: terrain.generator is not an IslandVoxelGenerator")
		return
	_scatter_surface_rocks()
	_scatter_underground_by_rank(terrain)
	_scatter_claim_island_ore()

func _scatter_surface_rocks() -> void:
	# Use the deterministic island height directly — independent of voxel chunk streaming.
	var grid_min: int = int(-island_radius)
	var grid_max: int = int(island_radius)
	var placed: int = 0
	var x: int = grid_min
	while x <= grid_max:
		var z: int = grid_min
		while z <= grid_max:
			var jx: float = _rng.randf_range(-surface_jitter, surface_jitter)
			var jz: float = _rng.randf_range(-surface_jitter, surface_jitter)
			var px: float = float(x) + jx
			var pz: float = float(z) + jz
			if sqrt(px * px + pz * pz) > island_radius:
				z += int(surface_grid_step)
				continue
			var h: float = _island_generator._height(px, pz)
			# Skip points below water (the visible water plane sits at y=0).
			if h < 0.2:
				z += int(surface_grid_step)
				continue
			var rock := surface_rock_scn.instantiate() as Node3D
			rock.position = Vector3(px, h, pz)
			rock.rotation.y = _rng.randf() * TAU
			add_child(rock)
			placed += 1
			z += int(surface_grid_step)
		x += int(surface_grid_step)
	print("OreGenerator: placed %d surface rocks" % placed)

func _scatter_underground_by_rank(terrain: VoxelTerrain) -> void:
	# Sample many underground candidates, sort by ore-noise value, then assign:
	# the top gold_deposits → gold, next iron_deposits → iron, the rest → stone.
	# This guarantees placement counts AND clusters each material in the
	# noise band that matches its shader tint. The actual noise-value cuts
	# get pushed to the shader so the visual bands line up with placement.
	var total: int = stone_deposits + iron_deposits + gold_deposits
	var pool_target: int = total * 8
	var pool: Array = []
	var attempts: int = 0
	var max_attempts: int = pool_target * 4
	while pool.size() < pool_target and attempts < max_attempts:
		attempts += 1
		var p: Vector3 = _random_underground_position()
		if not _is_solid_voxel(p):
			continue
		var n: float = _ore_noise.get_noise_3d(p.x, p.y, p.z)
		pool.append({"p": p, "n": n})

	pool.sort_custom(func(a, b): return a.n > b.n)

	var stone_pool: Array = [stone_small_scn, stone_medium_scn, stone_large_scn]
	var iron_pool: Array = [iron_small_scn, iron_large_scn]
	var gold_pool: Array = [gold_small_scn, gold_large_scn]
	var idx: int = 0

	for i in range(gold_deposits):
		if idx >= pool.size(): break
		_instantiate_deposit(gold_pool.pick_random(), pool[idx].p)
		idx += 1
	var iron_cut_idx: int = idx
	for i in range(iron_deposits):
		if idx >= pool.size(): break
		_instantiate_deposit(iron_pool.pick_random(), pool[idx].p)
		idx += 1
	var stone_cut_idx: int = idx
	for i in range(stone_deposits):
		if idx >= pool.size(): break
		_instantiate_deposit(stone_pool.pick_random(), pool[idx].p)
		idx += 1

	# Push the actual noise-value cuts to the shader so visual bands match.
	if pool.size() > 0:
		var mat: ShaderMaterial = terrain.material_override as ShaderMaterial
		if mat != null:
			var gold_cut: float = pool[min(gold_deposits - 1, pool.size() - 1)].n if gold_deposits > 0 else 1.0
			var iron_cut: float = pool[min(iron_cut_idx + iron_deposits - 1, pool.size() - 1)].n if iron_deposits > 0 else gold_cut
			# Nudge thresholds slightly below the cut so deposits land inside the colored band.
			mat.set_shader_parameter("ore_gold_threshold", gold_cut - 0.02)
			mat.set_shader_parameter("ore_iron_threshold", iron_cut - 0.02)
			print("OreGenerator: shader thresholds set — iron=%.3f gold=%.3f" % [iron_cut - 0.02, gold_cut - 0.02])

	print("OreGenerator: placed %d gold, %d iron, %d stone deposits (pool %d / %d, attempts %d)" % [
		min(gold_deposits, pool.size()),
		min(iron_deposits, max(0, pool.size() - gold_deposits)),
		min(stone_deposits, max(0, pool.size() - gold_deposits - iron_deposits)),
		pool.size(), pool_target, attempts
	])

func _instantiate_deposit(prefab: PackedScene, pos: Vector3) -> void:
	var deposit := prefab.instantiate() as OreDeposit
	deposit.position = pos
	add_child(deposit)

# Scatter ore on each offshore claim island per its tier. Tiered counts come
# from ClaimDef.TIER_TABLE so the vendor's "expected yield" matches what's
# actually placed in the world. Deposits sit a few meters under the surface
# of each island, sampled against the deterministic _height function so this
# works before voxel chunks have streamed in.
func _scatter_claim_island_ore() -> void:
	var stone_pool: Array = [stone_small_scn, stone_medium_scn, stone_large_scn]
	var iron_pool: Array = [iron_small_scn, iron_large_scn]
	var gold_pool: Array = [gold_small_scn, gold_large_scn]
	var total_placed: int = 0
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		var info: Dictionary = ClaimDef.tier(isle.tier)
		var deps: Dictionary = info.deposits
		var placed: int = 0
		placed += _scatter_ring_deposits(isle, gold_pool,  deps.gold)
		placed += _scatter_ring_deposits(isle, iron_pool,  deps.iron)
		placed += _scatter_ring_deposits(isle, stone_pool, deps.stone)
		total_placed += placed
		print("OreGenerator: %s (T%d) — placed %d deposits" % [isle.name, isle.tier, placed])
	print("OreGenerator: claim islands total %d deposits" % total_placed)

func _scatter_ring_deposits(isle: Dictionary, prefab_pool: Array, count: int) -> int:
	if count <= 0 or prefab_pool.is_empty():
		return 0
	var placed: int = 0
	var attempts: int = 0
	# Keep deposits inside ~85% of the island radius so they're under solid
	# voxel rather than poking out of the beach edge.
	var max_r: float = isle.radius * 0.85
	while placed < count and attempts < count * 12:
		attempts += 1
		var theta: float = _rng.randf() * TAU
		var r: float = sqrt(_rng.randf()) * max_r
		var x: float = isle.center.x + cos(theta) * r
		var z: float = isle.center.y + sin(theta) * r
		var surface_y: float = _island_generator._height(x, z)
		# Need at least ~3m of solid above the deposit so the player has to dig.
		if surface_y < 3.0:
			continue
		var depth: float = _rng.randf_range(2.5, max(2.6, surface_y - 1.5))
		var y: float = surface_y - depth
		_instantiate_deposit(prefab_pool.pick_random(), Vector3(x, y, z))
		placed += 1
	return placed

func _random_underground_position() -> Vector3:
	var theta: float = _rng.randf() * TAU
	var r: float = sqrt(_rng.randf()) * island_radius
	var x: float = cos(theta) * r
	var z: float = sin(theta) * r
	var y: float = _rng.randf_range(underground_y_band.x, underground_y_band.y)
	return Vector3(x, y, z)

func _is_solid_voxel(pos: Vector3) -> bool:
	# Position is solid if it's BELOW the deterministic island surface height.
	# This sidesteps voxel-chunk streaming — works before chunks have meshed.
	if _island_generator == null: return false
	return pos.y < _island_generator._height(pos.x, pos.z)

func _on_world_ready() -> void:
	generate()
