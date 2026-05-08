extends Control
## Always-on screen-center crosshair. Reads the equipped crosshair shop item
## from the player's Miner and renders one of a handful of preset shapes via
## _draw. New shapes are added by extending the match in _draw_for_style and
## adding the corresponding entry to ShopItemDefs.

const _ShopDefs: GDScript = preload("res://scripts/shop_item_defs.gd")

var _miner: Node = null
var _style: String = "dot"
var _color: Color = Color(1, 1, 1, 1)

func _ready() -> void:
	# Cover the full screen so _draw can use size/2 for center.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50   # sit above the tachometer / minimap layers but below modals
	set_process(true)

func _process(_delta: float) -> void:
	if _miner == null:
		_miner = get_tree().get_first_node_in_group("player_miner")
		if _miner != null:
			if _miner.has_signal("shop_inventory_changed") and not _miner.shop_inventory_changed.is_connected(_refresh_from_miner):
				_miner.shop_inventory_changed.connect(_refresh_from_miner)
			_refresh_from_miner()

func _refresh_from_miner() -> void:
	if _miner == null:
		return
	var equipped: Dictionary = _miner.equipped_items
	var crosshair_id: String = String(equipped.get(String(_ShopDefs.CAT_CROSSHAIR), _ShopDefs.DEFAULT_CROSSHAIR))
	var item: Dictionary = _ShopDefs.by_id(crosshair_id)
	if item.is_empty():
		_style = "dot"
		_color = Color(1, 1, 1, 1)
	else:
		_style = String(item.get("crosshair_style", "dot"))
		_color = item.get("crosshair_color", Color(1, 1, 1, 1))
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	# Outline color sits underneath so the crosshair stays legible against
	# any background — chunky dark drop-shadow + thin colored stroke.
	var outline: Color = Color(0, 0, 0, 0.85)
	match _style:
		"dot":
			draw_circle(center, 3.0, outline)
			draw_circle(center, 2.0, _color)
		"x":
			_draw_thick_line(center + Vector2(-7, -7), center + Vector2(7, 7), 4.0, outline)
			_draw_thick_line(center + Vector2(-7, 7), center + Vector2(7, -7), 4.0, outline)
			_draw_thick_line(center + Vector2(-7, -7), center + Vector2(7, 7), 2.0, _color)
			_draw_thick_line(center + Vector2(-7, 7), center + Vector2(7, -7), 2.0, _color)
		"t":
			_draw_thick_line(center + Vector2(-8, -7), center + Vector2(8, -7), 4.0, outline)
			_draw_thick_line(center + Vector2(0, -7), center + Vector2(0, 8), 4.0, outline)
			_draw_thick_line(center + Vector2(-8, -7), center + Vector2(8, -7), 2.0, _color)
			_draw_thick_line(center + Vector2(0, -7), center + Vector2(0, 8), 2.0, _color)
		"o":
			draw_arc(center, 7.0, 0, TAU, 32, outline, 3.0, true)
			draw_arc(center, 7.0, 0, TAU, 32, _color, 1.5, true)
		"o_dot":
			draw_arc(center, 7.0, 0, TAU, 32, outline, 3.0, true)
			draw_arc(center, 7.0, 0, TAU, 32, _color, 1.5, true)
			draw_circle(center, 2.5, outline)
			draw_circle(center, 1.5, _color)

func _draw_thick_line(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(a, b, color, width, true)
