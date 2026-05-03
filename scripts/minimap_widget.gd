extends Control
## Top-right combined minimap + gold chip. Minimap shows a window of the
## explored area centered on the player; player marker rotates to show facing.

const VIEW_RADIUS_CELLS: int = 12   # samples a 24x24-cell window
const PLAYER_MARKER_SIZE: float = 7.0
const PLAYER_MARKER_COLOR: Color = Color(1, 0.85, 0.4, 1)
const FOG_TINT: Color = Color(0.06, 0.07, 0.10, 1)

@onready var _minimap: Control = $Chip/Vbox/Minimap
@onready var _amount_label: Label = $Chip/Vbox/GoldRow/Amount

var _player: Node3D = null
var _miner: Node = null

func _ready() -> void:
	_minimap.draw.connect(_draw_minimap)
	# Crisp pixels for the cell texture (no linear blur).
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Defer subscriptions a frame so /root/Main/Player is in the tree.
	call_deferred("_subscribe")
	set_process(true)

func _subscribe() -> void:
	_player = get_node_or_null("/root/Main/Player") as Node3D
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner != null and _miner.has_signal("gold_currency_changed"):
		_miner.gold_currency_changed.connect(_on_gold_changed)
		_on_gold_changed(_miner.get("gold_currency"))

func _on_gold_changed(amount: int) -> void:
	_amount_label.text = str(amount)

func _process(_delta: float) -> void:
	# Minimap follows the player and re-draws every frame so the camera-relative
	# arrow (and the cell window) stays in sync.
	_minimap.queue_redraw()

func _draw_minimap() -> void:
	var size: Vector2 = _minimap.size
	# Frame fill — fog by default so unexplored area looks consistent.
	_minimap.draw_rect(Rect2(Vector2.ZERO, size), FOG_TINT)
	if _player == null or MapData == null or MapData.texture == null:
		_draw_player_marker(size * 0.5, 0.0)
		return
	var ppos: Vector3 = _player.global_position
	var center_grid: Vector2i = MapData.world_to_grid(ppos.x, ppos.z)
	var src_rect: Rect2 = Rect2(
		float(center_grid.x - VIEW_RADIUS_CELLS),
		float(center_grid.y - VIEW_RADIUS_CELLS),
		float(VIEW_RADIUS_CELLS * 2),
		float(VIEW_RADIUS_CELLS * 2),
	)
	# Sub-cell offset so the player marker stays exactly at minimap center
	# even between cell boundaries (smoother panning as you walk).
	var cell_pixels: float = size.x / float(VIEW_RADIUS_CELLS * 2)
	var cell_local_x: float = (ppos.x + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M - float(center_grid.x) - 0.5
	var cell_local_z: float = (ppos.z + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M - float(center_grid.y) - 0.5
	src_rect.position += Vector2(cell_local_x, cell_local_z)
	_minimap.draw_texture_rect_region(MapData.texture, Rect2(Vector2.ZERO, size), src_rect)
	# NPC icons (under the player so the player marker stays on top).
	_draw_npc_icons(size, src_rect)
	# Owned-claim pin so the player can spot their island while sailing.
	_draw_claim_pin(size, src_rect)
	# Player marker at the center of the minimap. Heading angle is measured
	# clockwise from north (-Z): facing -Z -> 0, facing +X -> +PI/2.
	var heading: Vector3 = -_player.global_basis.z
	var ang: float = atan2(heading.x, -heading.z)
	_draw_player_marker(size * 0.5, ang)

func _draw_claim_pin(size: Vector2, src_rect: Rect2) -> void:
	var npc: Node = get_tree().get_first_node_in_group("claim_vendor_npcs")
	if npc == null:
		return
	var board: Node = npc.get("claim_board") as Node
	if board == null or not board.has_owned():
		return
	var isle: Dictionary = board.owned_island()
	var cx: float = (float(isle.center.x) + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
	var cz: float = (float(isle.center.y) + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
	if cx < src_rect.position.x or cx > src_rect.position.x + src_rect.size.x:
		return
	if cz < src_rect.position.y or cz > src_rect.position.y + src_rect.size.y:
		return
	var u: float = (cx - src_rect.position.x) / src_rect.size.x
	var v: float = (cz - src_rect.position.y) / src_rect.size.y
	var pixel: Vector2 = Vector2(u * size.x, v * size.y)
	_minimap.draw_circle(pixel, 4.5, Color(0.05, 0.05, 0.08, 1))
	_minimap.draw_circle(pixel, 3.5, Color(0.95, 0.85, 0.30, 1))
	_minimap.draw_circle(pixel, 1.5, Color(0.20, 0.55, 0.30, 1))

func _draw_npc_icons(size: Vector2, src_rect: Rect2) -> void:
	for n: Node in get_tree().get_nodes_in_group("npcs"):
		if not (n is Node3D):
			continue
		var n3: Node3D = n
		var pos: Vector3 = n3.global_position
		var cx: float = (pos.x + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
		var cz: float = (pos.z + MapData.WORLD_RADIUS_M) / MapData.CELL_SIZE_M
		# Skip NPCs outside the visible window.
		if cx < src_rect.position.x or cx > src_rect.position.x + src_rect.size.x:
			continue
		if cz < src_rect.position.y or cz > src_rect.position.y + src_rect.size.y:
			continue
		var u: float = (cx - src_rect.position.x) / src_rect.size.x
		var v: float = (cz - src_rect.position.y) / src_rect.size.y
		var pixel: Vector2 = Vector2(u * size.x, v * size.y)
		var col: Color = _npc_color(n)
		_minimap.draw_circle(pixel, 3.0, Color(0.05, 0.05, 0.08, 1))
		_minimap.draw_circle(pixel, 2.2, col)

static func _npc_color(npc: Node) -> Color:
	if npc.is_in_group("vendor_npcs"):
		return Color(0.95, 0.78, 0.25, 1)
	if npc.is_in_group("contract_vendor_npcs"):
		return Color(0.45, 0.65, 0.95, 1)
	if npc.is_in_group("boat_vendor_npcs"):
		return Color(0.35, 0.85, 0.85, 1)
	return Color(0.55, 0.85, 0.45, 1)

func _draw_player_marker(center: Vector2, heading_rad: float) -> void:
	# Triangle pointing "up" by default, rotated by heading. heading_rad = 0
	# means the player faces -Z (which we treat as north / up on the minimap).
	var s: float = PLAYER_MARKER_SIZE
	var fwd: Vector2 = Vector2(sin(heading_rad), -cos(heading_rad))   # screen up = -Y
	var right: Vector2 = Vector2(-fwd.y, fwd.x)
	var p0: Vector2 = center + fwd * (s * 1.2)
	var p1: Vector2 = center - fwd * (s * 0.6) + right * (s * 0.8)
	var p2: Vector2 = center - fwd * (s * 0.6) - right * (s * 0.8)
	_minimap.draw_colored_polygon([p0, p1, p2], PLAYER_MARKER_COLOR)
	_minimap.draw_polyline([p0, p1, p2, p0], Color(0.2, 0.15, 0.0, 1), 1.5)
