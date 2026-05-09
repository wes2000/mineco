extends Node
## Autoload. Owns the world's exploration grid + a backing Image/ImageTexture
## that the minimap and full-map widgets sample from. Each cell starts as
## fog; on first exploration we sample the terrain Y at the cell's center
## and assign a height-banded color.

const WORLD_RADIUS_M: float = 360.0   # half-extent of map coverage
const CELL_SIZE_M: float = 4.0
const GRID_SIZE: int = int((WORLD_RADIUS_M * 2.0) / CELL_SIZE_M)   # 180x180
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

# Multiplayer: per-tick accumulator of cell indices revealed locally since the
# last broadcast, plus a flush timer. We send these to peers periodically so
# the team's shared map fills in as anyone walks new ground.
var _pending_remote_diff: PackedInt32Array = PackedInt32Array()
var _diff_send_accum: float = 0.0
const _DIFF_SEND_INTERVAL: float = 2.0  # seconds

func _ready() -> void:
	image = Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8)
	image.fill(FOG_COLOR)
	texture = ImageTexture.create_from_image(image)
	_explored.resize(GRID_SIZE * GRID_SIZE)
	set_process(true)

func _process(delta: float) -> void:
	# Cheap when offline: no-op early return (the only path that grows
	# _pending_remote_diff is mark_explored, which only appends when online).
	if Net == null or not Net.is_online():
		return
	_diff_send_accum += delta
	if _diff_send_accum >= _DIFF_SEND_INTERVAL:
		_diff_send_accum = 0.0
		_flush_remote_diff()

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
	# When the explorer is at sea level (e.g. swimming or on a boat) any cell
	# within explore radius that we can't find terrain for must be open water —
	# the void below the surface produces no voxels and no collider, so neither
	# the physics nor the voxel raycast hits anything. Without this, cells out
	# at sea stay fogged forever.
	var explorer_at_sea: bool = world_pos.y < 3.0
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
			# Try to sample terrain. NAN means "couldn't sample, retry later"
			# (e.g. chunks haven't streamed in over a non-water cell). Any real
			# float is a height — including very negative values, which are
			# the seabed under open water and color as COLOR_WATER.
			var w: Vector2 = grid_to_world(gx, gz)
			var y: float = _sample_ground_y(w.x, w.y, explorer_at_sea)
			if is_nan(y):
				continue
			_explored[idx] = 1
			_explored_cell_count += 1
			image.set_pixel(gx, gz, _color_for_height(y))
			dirty = true
			# Multiplayer: queue this cell for broadcast so peers see what we
			# just revealed. Only accumulate when online to keep the offline
			# path zero-cost.
			if Net != null and Net.is_online():
				_pending_remote_diff.append(idx)
	if dirty:
		texture.update(image)
		map_updated.emit()

# --- Internal ---

func get_save_data() -> Dictionary:
	# PackedByteArray + Image bytes both go base64 so JSON stays small and
	# round-trips the binary cleanly. The image colors are recomputed from
	# the explored bytes on load — only the explored mask is the source of
	# truth, the colors are derived next time the player passes through.
	# But we save the rendered colors too, so the map looks identical
	# without re-sampling the world (some cells may not be re-explorable
	# if the chunks aren't loaded right after restart).
	return {
		"grid_size": GRID_SIZE,
		"explored_b64": Marshalls.raw_to_base64(_explored),
		"image_b64": Marshalls.raw_to_base64(image.get_data()),
		"explored_cell_count": _explored_cell_count,
	}

func apply_save_data(data: Dictionary) -> void:
	# Reject if grid dimensions changed since the save was written — the
	# byte layout would no longer line up. The map just stays empty in
	# that case; the player re-walks to reveal.
	if int(data.get("grid_size", 0)) != GRID_SIZE:
		push_warning("MapData.apply_save_data: grid size changed, ignoring saved fog")
		return
	var ex_bytes: PackedByteArray = Marshalls.base64_to_raw(String(data.get("explored_b64", "")))
	if ex_bytes.size() == GRID_SIZE * GRID_SIZE:
		_explored = ex_bytes
	_explored_cell_count = int(data.get("explored_cell_count", 0))
	var img_bytes: PackedByteArray = Marshalls.base64_to_raw(String(data.get("image_b64", "")))
	var expected_size: int = GRID_SIZE * GRID_SIZE * 3   # FORMAT_RGB8
	if img_bytes.size() == expected_size:
		image.set_data(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGB8, img_bytes)
		texture.update(image)
		map_updated.emit()

func _color_for_height(y: float) -> Color:
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

func _sample_ground_y(x: float, z: float, water_if_no_hit: bool) -> float:
	# Returns a height in meters, or NAN if the cell can't be classified yet
	# (chunks not streamed). Returning NAN lets the caller skip and retry;
	# every other return value (including very negative seabed values) is a
	# real height that should be colored.
	var terrain: VoxelTerrain = get_tree().current_scene.find_child("VoxelTerrain", true, false) as VoxelTerrain
	if terrain == null:
		return 0.0 if water_if_no_hit else NAN
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return 0.0 if water_if_no_hit else NAN
	var result: VoxelRaycastResult = tool.raycast(Vector3(x, 100.0, z), Vector3(0, -1, 0), 200.0)
	if result == null:
		# No terrain in this column. If the explorer is at sea level we can
		# safely call it water; otherwise the chunk just hasn't streamed in
		# yet (e.g. mountain edge) and we should retry next call.
		return 0.0 if water_if_no_hit else NAN
	# Solid voxel cell midpoint — close enough for biome tinting. The seabed
	# under open water sits well below 0, which _color_for_height maps to
	# COLOR_WATER, so we don't need to special-case it here.
	return float(result.position.y) + 0.5

# --- Multiplayer broadcast (Phase 1 Task 11) -------------------------------

func _flush_remote_diff() -> void:
	if _pending_remote_diff.is_empty():
		return
	var diff: PackedInt32Array = _pending_remote_diff
	_pending_remote_diff = PackedInt32Array()
	_apply_remote_explored_diff_rpc.rpc(diff)

@rpc("any_peer", "call_remote", "reliable")
func _apply_remote_explored_diff_rpc(idxs: PackedInt32Array) -> void:
	# Apply remote-revealed cells without re-queuing them — _pending_remote_diff
	# is for OUR own newly-walked cells. Echoing remote cells back would loop.
	var dirty: bool = false
	for idx in idxs:
		if idx < 0 or idx >= _explored.size():
			continue
		if _explored[idx] != 0:
			continue
		_explored[idx] = 1
		_explored_cell_count += 1
		var gx: int = idx % GRID_SIZE
		var gz: int = idx / GRID_SIZE
		# Try to color from local terrain. If we can't sample (chunks not
		# streamed), use water as a generic fill — the cell will be marked
		# revealed on the minimap with a placeholder tint until the player
		# gets close enough for a fresh local sample to overwrite it.
		var w: Vector2 = grid_to_world(gx, gz)
		var y: float = _sample_ground_y(w.x, w.y, false)
		var color: Color = COLOR_WATER if is_nan(y) else _color_for_height(y)
		image.set_pixel(gx, gz, color)
		dirty = true
	if dirty:
		texture.update(image)
		map_updated.emit()
