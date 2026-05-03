extends Node
## Autoload. Owns the world's exploration grid + a backing Image/ImageTexture
## that the minimap and full-map widgets sample from. Each cell starts as
## fog; on first exploration we sample the terrain Y at the cell's center
## and assign a height-banded color.

const WORLD_RADIUS_M: float = 200.0   # half-extent of map coverage
const CELL_SIZE_M: float = 4.0
const GRID_SIZE: int = int((WORLD_RADIUS_M * 2.0) / CELL_SIZE_M)   # 100x100
const EXPLORE_RADIUS_CELLS: int = 7   # 28m radius around the player
const FOG_COLOR: Color = Color(0.06, 0.07, 0.10, 1)

# Height bands for the cell color sampling.
const COLOR_WATER: Color  = Color(0.18, 0.32, 0.55, 1)
const COLOR_BEACH: Color  = Color(0.78, 0.70, 0.45, 1)
const COLOR_GRASS: Color  = Color(0.22, 0.48, 0.26, 1)
const COLOR_FOREST: Color = Color(0.16, 0.36, 0.20, 1)
const COLOR_ROCK: Color   = Color(0.45, 0.42, 0.38, 1)
const COLOR_SNOW: Color   = Color(0.85, 0.88, 0.93, 1)

signal map_updated

var image: Image = null
var texture: ImageTexture = null
var _explored: PackedByteArray = PackedByteArray()
var _explored_cell_count: int = 0

func _ready() -> void:
	image = Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	image.fill(FOG_COLOR)
	texture = ImageTexture.create_from_image(image)
	_explored.resize(GRID_SIZE * GRID_SIZE)

func world_to_grid(world_x: float, world_z: float) -> Vector2i:
	var gx: int = int(floor((world_x + WORLD_RADIUS_M) / CELL_SIZE_M))
	var gz: int = int(floor((world_z + WORLD_RADIUS_M) / CELL_SIZE_M))
	return Vector2i(gx, gz)

func grid_to_world(gx: int, gz: int) -> Vector2:
	# Returns the (x, z) world position of the cell's center.
	return Vector2(
		float(gx) * CELL_SIZE_M - WORLD_RADIUS_M + CELL_SIZE_M * 0.5,
		float(gz) * CELL_SIZE_M - WORLD_RADIUS_M + CELL_SIZE_M * 0.5,
	)

func is_in_grid(gx: int, gz: int) -> bool:
	return gx >= 0 and gx < GRID_SIZE and gz >= 0 and gz < GRID_SIZE

func is_explored(gx: int, gz: int) -> bool:
	if not is_in_grid(gx, gz):
		return false
	return _explored[gz * GRID_SIZE + gx] != 0

func mark_explored(world_pos: Vector3) -> void:
	var center: Vector2i = world_to_grid(world_pos.x, world_pos.z)
	var dirty: bool = false
	var r: int = EXPLORE_RADIUS_CELLS
	var r_sq: int = r * r
	for dz: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dz * dz > r_sq:
				continue
			var gx: int = center.x + dx
			var gz: int = center.y + dz
			if not is_in_grid(gx, gz):
				continue
			var idx: int = gz * GRID_SIZE + gx
			if _explored[idx] != 0:
				continue
			_explored[idx] = 1
			_explored_cell_count += 1
			image.set_pixel(gx, gz, _compute_cell_color(gx, gz))
			dirty = true
	if dirty:
		texture.update(image)
		map_updated.emit()

# --- Internal ---

func _compute_cell_color(gx: int, gz: int) -> Color:
	var w: Vector2 = grid_to_world(gx, gz)
	var y: float = _sample_ground_y(w.x, w.y)
	if y < 0.5:
		return COLOR_WATER
	if y < 1.8:
		return COLOR_BEACH
	if y < 8.0:
		return COLOR_GRASS
	if y < 14.0:
		return COLOR_FOREST
	if y < 24.0:
		return COLOR_ROCK
	return COLOR_SNOW

func _sample_ground_y(x: float, z: float) -> float:
	var terrain: VoxelTerrain = get_tree().current_scene.find_child("VoxelTerrain", true, false) as VoxelTerrain
	if terrain == null:
		return -1.0
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return -1.0
	var result: VoxelRaycastResult = tool.raycast(Vector3(x, 100.0, z), Vector3(0, -1, 0), 200.0)
	if result == null:
		return -1.0
	# Solid voxel cell midpoint — close enough for biome tinting.
	return float(result.position.y) + 0.5
