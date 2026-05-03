extends Control
## Full-screen popup map. Toggle with M. Doesn't pause the game and doesn't
## release the mouse — player can keep walking and looking around. Shows the
## explored map area, scroll-wheel to zoom in/out, NPC icons overlaid, the
## player as a rotating arrow at their world position, and a compass dial in
## the header.

const PLAYER_MARKER_SIZE: float = 10.0
const PLAYER_MARKER_COLOR: Color = Color(1, 0.85, 0.4, 1)
const COMPASS_RADIUS: float = 26.0
const NPC_ICON_RADIUS: float = 3.5
const NPC_ICON_OUTLINE: Color = Color(0.05, 0.05, 0.08, 1)

const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 6.0
const ZOOM_STEP: float = 1.25

@onready var _map_area: Control = $Panel/Vbox/MapArea
@onready var _compass: Control = $Panel/Vbox/HeaderRow/Compass

var _player: Node3D = null
var _zoom: float = 1.0   # 1 = whole grid; higher = closer-up around the player

func _ready() -> void:
	add_to_group("map_popup")
	visible = false
	_map_area.draw.connect(_draw_map)
	_map_area.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# MapArea needs to actually receive scroll-wheel events for zoom.
	_map_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_area.gui_input.connect(_on_map_input)
	_compass.draw.connect(_draw_compass)
	call_deferred("_subscribe")
	set_process(true)

func _subscribe() -> void:
	_player = get_node_or_null("/root/Main/Player") as Node3D

func _process(_delta: float) -> void:
	if visible:
		_map_area.queue_redraw()
		_compass.queue_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map_toggle"):
		toggle()
		accept_event()
	elif visible and event.is_action_pressed("ui_cancel"):
		# Esc closes the map IF no other modal is in front of us. The pause
		# menu's _input runs at the same priority but its handler only fires
		# when it's already visible, so closing the map first is fine.
		hide_map()
		accept_event()

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clamp(_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_map_area.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clamp(_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_map_area.accept_event()

func toggle() -> void:
	if visible:
		hide_map()
	else:
		show_map()

func show_map() -> void:
	visible = true
	# We DON'T release the mouse — the player keeps moving / looking through
	# the overlay. Mouse stays captured, the map is decorative on top.

func hide_map() -> void:
	visible = false

# --- Drawing ---

func _draw_map() -> void:
	var size: Vector2 = _map_area.size
	# Background fog rect.
	_map_area.draw_rect(Rect2(Vector2.ZERO, size), MapData.FOG_COLOR)
	if MapData == null or MapData.texture == null:
		return
	var grid: float = float(MapData.GRID_SIZE)
	var dim: float = min(size.x, size.y)
	var origin: Vector2 = (size - Vector2(dim, dim)) * 0.5
	var dst: Rect2 = Rect2(origin, Vector2(dim, dim))
	# Compute the source sub-rect: at zoom=1 we draw the entire grid; at higher
	# zooms we sample a window centered on the player.
	var view_cells: float = grid / _zoom
	var cx_cells: float = grid * 0.5
	var cz_cells: float = grid * 0.5
	if _player != null and _zoom > 1.0:
		var ppos: Vector3 = _player.global_position
		cx_cells = (ppos.x + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
		cz_cells = (ppos.z + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
	# Clamp the window so it never falls off the grid edge.
	var sx: float = clamp(cx_cells - view_cells * 0.5, 0.0, grid - view_cells)
	var sz: float = clamp(cz_cells - view_cells * 0.5, 0.0, grid - view_cells)
	var src: Rect2 = Rect2(sx, sz, view_cells, view_cells)
	_map_area.draw_texture_rect_region(MapData.texture, dst, src)
	# Border around the map area.
	_map_area.draw_rect(dst, Color(0.2, 0.22, 0.28, 1), false, 2.0)
	# NPC dots (under the player marker so the player stays on top).
	_draw_npc_icons(dst, src, grid)
	# Player marker.
	if _player != null:
		var pixel: Vector2 = _world_to_pixel(_player.global_position, dst, src, grid)
		var heading: Vector3 = -_player.global_basis.z
		var ang: float = atan2(heading.x, -heading.z)
		_draw_player_marker(pixel, ang)
	# Zoom indicator.
	if _zoom > 1.0:
		_map_area.draw_string(
			ThemeDB.fallback_font, dst.position + Vector2(8, 16),
			"%dx" % roundi(_zoom),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.85, 0.88, 0.92, 0.85),
		)

func _world_to_pixel(world_pos: Vector3, dst: Rect2, src: Rect2, grid: float) -> Vector2:
	# Convert world XZ → cell coords → fraction within the source rect → pixel.
	var cx: float = (world_pos.x + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
	var cz: float = (world_pos.z + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
	var u: float = (cx - src.position.x) / src.size.x
	var v: float = (cz - src.position.y) / src.size.y
	return dst.position + Vector2(u * dst.size.x, v * dst.size.y)

func _draw_npc_icons(dst: Rect2, src: Rect2, grid: float) -> void:
	for n: Node in get_tree().get_nodes_in_group("npcs"):
		if not (n is Node3D):
			continue
		var n3: Node3D = n
		var pos: Vector3 = n3.global_position
		var cx: float = (pos.x + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
		var cz: float = (pos.z + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
		# Skip NPCs that fall outside the currently-displayed window.
		if cx < src.position.x or cx > src.position.x + src.size.x:
			continue
		if cz < src.position.y or cz > src.position.y + src.size.y:
			continue
		var pixel: Vector2 = _world_to_pixel(pos, dst, src, grid)
		var col: Color = _npc_color(n)
		_map_area.draw_circle(pixel, NPC_ICON_RADIUS + 1.0, NPC_ICON_OUTLINE)
		_map_area.draw_circle(pixel, NPC_ICON_RADIUS, col)

static func _npc_color(npc: Node) -> Color:
	if npc.is_in_group("vendor_npcs"):
		return Color(0.95, 0.78, 0.25, 1)        # gold
	if npc.is_in_group("contract_vendor_npcs"):
		return Color(0.45, 0.65, 0.95, 1)        # navy/cyan
	if npc.is_in_group("boat_vendor_npcs"):
		return Color(0.35, 0.85, 0.85, 1)        # teal
	return Color(0.55, 0.85, 0.45, 1)            # townsfolk green

func _draw_player_marker(center: Vector2, heading_rad: float) -> void:
	var s: float = PLAYER_MARKER_SIZE
	var fwd: Vector2 = Vector2(sin(heading_rad), -cos(heading_rad))
	var right: Vector2 = Vector2(-fwd.y, fwd.x)
	var p0: Vector2 = center + fwd * (s * 1.2)
	var p1: Vector2 = center - fwd * (s * 0.6) + right * (s * 0.8)
	var p2: Vector2 = center - fwd * (s * 0.6) - right * (s * 0.8)
	_map_area.draw_colored_polygon([p0, p1, p2], PLAYER_MARKER_COLOR)
	_map_area.draw_polyline([p0, p1, p2, p0], Color(0.2, 0.15, 0.0, 1), 1.5)

func _draw_compass() -> void:
	var size: Vector2 = _compass.size
	var center: Vector2 = size * 0.5
	var r: float = COMPASS_RADIUS
	# Outer ring
	_compass.draw_arc(center, r, 0.0, TAU, 36, Color(0.45, 0.55, 0.7, 1), 2.0)
	# Player heading: angle from north (-Z) measured CW. heading=0 means facing
	# north; +π/2 means facing east. We rotate the cardinal labels so the
	# letter the player is FACING sits at the top of the compass.
	var heading: float = 0.0
	if _player != null:
		var fwd: Vector3 = -_player.global_basis.z
		heading = atan2(fwd.x, -fwd.z)   # CW from north

	# Cardinal labels positioned around the dial.
	var letters: Array = [["N", 0.0], ["E", PI * 0.5], ["S", PI], ["W", PI * 1.5]]
	for entry: Array in letters:
		# Label angle relative to player: (cardinal_angle - heading), with up = compass forward.
		var rel: float = float(entry[1]) - heading
		var dir: Vector2 = Vector2(sin(rel), -cos(rel))
		var pos: Vector2 = center + dir * (r - 8.0)
		var col: Color = Color(0.95, 0.85, 0.35, 1) if entry[0] == "N" else Color(0.85, 0.88, 0.92, 1)
		_compass.draw_string(
			ThemeDB.fallback_font, pos + Vector2(-5, 5), str(entry[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col,
		)
	# Forward needle (always points UP since the dial rotates around the player)
	_compass.draw_line(center, center + Vector2(0, -r * 0.7), Color(1, 0.85, 0.45, 1), 2.0)
	_compass.draw_circle(center, 2.5, Color(0.95, 0.95, 1.0, 1))
