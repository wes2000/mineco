extends VoxelGeneratorScript
class_name IslandVoxelGenerator

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

# --- Math helpers ---

func _radial_falloff(world_x: float, world_z: float) -> float:
	var d: float = sqrt(world_x * world_x + world_z * world_z)
	var t: float = d / (size * 0.5)
	# 1.0 at center → 0.0 outside falloff_outer
	return 1.0 - smoothstep(falloff_inner, falloff_outer, t)

func _height(world_x: float, world_z: float) -> float:
	var n: float = _noise.get_noise_2d(world_x, world_z)         # [-1, 1]
	n = (n + 1.0) * 0.5                                          # [0, 1]
	return n * max_height * _radial_falloff(world_x, world_z) - edge_bias

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
	if block_y_min >= max_height:
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
