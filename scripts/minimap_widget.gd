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
	# Player marker at the center of the minimap. Heading angle is measured
	# clockwise from north (-Z): facing -Z -> 0, facing +X -> +PI/2.
	var heading: Vector3 = -_player.global_basis.z
	var ang: float = atan2(heading.x, -heading.z)
	_draw_player_marker(size * 0.5, ang)

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
