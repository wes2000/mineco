extends VoxelGeneratorScript
class_name IslandVoxelGenerator

# --- Hand-placed offshore claim islands ---
#
# Position is the (x, z) world center; radius is the falloff outer edge in
# meters; height is the peak the noise can reach over center. Tier is a label
# the claim system reads to know how rich an island is (1 = poor, 5 = elite).
# Y stays inside the existing voxel terrain bounds AABB(-208 .. +208 on x/z).
const CLAIM_ISLANDS: Array = [
	# Bigger footprints + much lower peaks so slopes are walkable. Concretely:
	# height / ((1 - falloff_inner) * min(radius_x, radius_z)) is the avg
	# slope on the long side; we keep it under ~0.55 (≈ 28°) so the player
	# can walk up without skidding.
	{
		"id": "kelp_cay", "name": "Kelp Cay", "tier": 1,
		"center": Vector2( 260.0, -150.0),
		"radius_x": 55.0, "radius_z": 30.0, "rotation": 0.6,
		"height": 5.0, "noise_freq": 1.7, "noise_amp": 0.45,
		"falloff_inner": 0.6, "peak_pow": 1.0,
	},
	{
		"id": "tin_atoll", "name": "Tin Atoll", "tier": 1,
		"center": Vector2(-160.0, -160.0),
		"radius_x": 42.0, "radius_z": 48.0, "rotation": -0.3,
		"height": 4.5, "noise_freq": 1.9, "noise_amp": 0.55,
		"falloff_inner": 0.55, "peak_pow": 0.95,
	},
	{
		"id": "smelters_isle", "name": "Smelter's Isle", "tier": 2,
		"center": Vector2( 290.0, 200.0),
		"radius_x": 55.0, "radius_z": 55.0, "rotation": 0.0,
		"height": 7.0, "noise_freq": 1.5, "noise_amp": 0.4,
		"falloff_inner": 0.65, "peak_pow": 1.0,
	},
	{
		"id": "ironback", "name": "Ironback", "tier": 3,
		"center": Vector2(-260.0, 240.0),
		"radius_x": 70.0, "radius_z": 32.0, "rotation": 1.1,
		"height": 9.0, "noise_freq": 1.7, "noise_amp": 0.45,
		"falloff_inner": 0.6, "peak_pow": 1.0,
	},
	{
		"id": "veinmount", "name": "Veinmount", "tier": 4,
		"center": Vector2( 60.0, -300.0),
		"radius_x": 55.0, "radius_z": 50.0, "rotation": 0.0,
		"height": 11.0, "noise_freq": 1.4, "noise_amp": 0.4,
		"falloff_inner": 0.62, "peak_pow": 1.05,
	},
	{
		"id": "diadem_keep", "name": "Diadem Keep", "tier": 5,
		"center": Vector2(-280.0, -40.0),
		"radius_x": 68.0, "radius_z": 60.0, "rotation": -0.7,
		"height": 13.0, "noise_freq": 1.5, "noise_amp": 0.45,
		"falloff_inner": 0.6, "peak_pow": 1.0,
	},
]

# --- Tunables (editable on the .tres in inspector) ---

@export var noise_seed: int = 0
@export var size: float = 300.0          # island diameter (square footprint, centered)
@export var max_height: float = 18.0
@export var water_level: float = 0.0     # used only by edge_bias math; visible water plane is in scene

@export_group("Noise")
@export var noise_frequency: float = 0.008
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5

@export_group("Falloff (radial smoothstep, fractions of size/2)")
@export var falloff_inner: float = 0.45
@export var falloff_outer: float = 0.95
@export var edge_bias: float = 5.0       # pushes outer ring underwater

# --- Derived ---

const VOXEL_SIZE: float = 1.0   # plain VoxelTerrain @ LOD0

var _noise: FastNoiseLite

func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = noise_octaves
	_noise.fractal_lacunarity = noise_lacunarity
	_noise.fractal_gain = noise_gain

# --- Static helpers for callers reading CLAIM_ISLANDS ---

# Conservative bounding radius — actual footprint is the rotated ellipse
# defined by radius_x / radius_z, but a containing circle of this size is
# enough for "is this point inside the island" checks (mining lock,
# scatter rejection).
static func island_max_radius(isle: Dictionary) -> float:
	return max(float(isle.radius_x), float(isle.radius_z))

# True if (x, z) sits inside the island's elliptical footprint.
static func point_inside_island(isle: Dictionary, x: float, z: float) -> bool:
	var dx: float = x - float(isle.center.x)
	var dz: float = z - float(isle.center.y)
	var rot: float = float(isle.rotation)
	var lx: float = dx * cos(rot) - dz * sin(rot)
	var lz: float = dx * sin(rot) + dz * cos(rot)
	var nx: float = lx / float(isle.radius_x)
	var nz: float = lz / float(isle.radius_z)
	return (nx * nx + nz * nz) < 1.0

# --- Math helpers ---

func _radial_falloff(world_x: float, world_z: float) -> float:
	var d: float = sqrt(world_x * world_x + world_z * world_z)
	var t: float = d / (size * 0.5)
	# 1.0 at center → 0.0 outside falloff_outer
	return 1.0 - smoothstep(falloff_inner, falloff_outer, t)

func _height(world_x: float, world_z: float) -> float:
	var n: float = _noise.get_noise_2d(world_x, world_z)         # [-1, 1]
	n = (n + 1.0) * 0.5                                          # [0, 1]
	var h: float = n * max_height * _radial_falloff(world_x, world_z) - edge_bias
	# Stack offshore claim islands on top of the seabed. We take the MAX of
	# every island contribution so an offshore island always rises above any
	# negative seabed value the main-island falloff produced out here.
	for isle: Dictionary in CLAIM_ISLANDS:
		# Rotate the sampling point into the island's local frame so the
		# elliptical footprint can be oriented per island.
		var dx: float = world_x - float(isle.center.x)
		var dz: float = world_z - float(isle.center.y)
		var rot: float = float(isle.rotation)
		var cs: float = cos(rot)
		var sn: float = sin(rot)
		var lx: float = dx * cs - dz * sn
		var lz: float = dx * sn + dz * cs
		# Normalized radius in the ellipse — t=0 at center, t=1 at edge.
		var nx: float = lx / float(isle.radius_x)
		var nz: float = lz / float(isle.radius_z)
		var t: float = sqrt(nx * nx + nz * nz)
		if t >= 1.0:
			continue
		# Falloff from center to edge. falloff_inner controls beach width.
		var fall: float = 1.0 - smoothstep(float(isle.falloff_inner), 1.0, t)
		# peak_pow > 1 sharpens the centre (mountain feel); < 1 broadens it.
		fall = pow(fall, float(isle.peak_pow))
		# Two-octave noise for surface variation, scaled per island.
		var nf: float = float(isle.noise_freq)
		var n1: float = _noise.get_noise_2d(world_x * nf + float(isle.center.x) * 0.7 + 5000.0,
			world_z * nf + float(isle.center.y) * 0.7 - 3000.0)
		var n2: float = _noise.get_noise_2d(world_x * nf * 2.5 - 1234.0,
			world_z * nf * 2.5 + 8765.0)
		var noise01: float = ((n1 + 1.0) * 0.5) * 0.7 + ((n2 + 1.0) * 0.5) * 0.3
		# Mix smooth dome with the noise — high noise_amp = irregular silhouette.
		var amp: float = float(isle.noise_amp)
		var shape: float = (1.0 - amp) + amp * noise01 * 1.6
		var island_h: float = float(isle.height) * fall * shape - 0.5
		if island_h > h:
			h = island_h
	return h

# --- Generator ---

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# CHANNEL_SDF stays at default 16-bit fixed-point (range ~[-1, 1]).
	# We clamp SDF values into that range — only the sign and near-zero values matter for meshing.

	var bsize: Vector3i = out_buffer.get_size()
	var step: float = float(1 << lod) * VOXEL_SIZE
	var origin_world: Vector3 = Vector3(origin_in_voxels) * VOXEL_SIZE

	# Block's world Y span
	var block_y_min: float = origin_world.y
	var block_y_max: float = origin_world.y + float(bsize.y) * step

	# --- Fast paths ---
	# Use the highest possible island peak (main island vs. claim islands) so we
	# don't accidentally fast-path a block to air over a tall offshore island.
	var ceiling: float = max_height
	for isle: Dictionary in CLAIM_ISLANDS:
		if isle.height > ceiling:
			ceiling = isle.height
	if block_y_min >= ceiling:
		# Fully above any possible terrain → all air.
		out_buffer.fill_f(1.0, VoxelBuffer.CHANNEL_SDF)
		return
	if block_y_max <= -edge_bias - 1.0:
		# Fully below any possible terrain → all solid (seabed).
		out_buffer.fill_f(-1.0, VoxelBuffer.CHANNEL_SDF)
		return

	# --- Surface band: per-voxel sample ---
	for z in range(bsize.z):
		var world_z: float = origin_world.z + float(z) * step
		for x in range(bsize.x):
			var world_x: float = origin_world.x + float(x) * step
			var h: float = _height(world_x, world_z)
			for y in range(bsize.y):
				var world_y: float = origin_world.y + float(y) * step
				var sdf: float = clampf(world_y - h, -1.0, 1.0)
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
