extends Control
## Always-on screen-center crosshair. Reads two equipped shop items off the
## player's Miner: a `crosshair` shape and a `crosshair_color` tint. The two
## are independent so any color can be applied to any shape. _draw renders
## the matched style stamped in the equipped color.

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
	# Shape comes from CAT_CROSSHAIR; color from CAT_CROSSHAIR_COLOR. Either
	# slot might point at a stale id post-refactor, so fall back to defaults.
	var shape_id: String = String(equipped.get(String(_ShopDefs.CAT_CROSSHAIR), _ShopDefs.DEFAULT_CROSSHAIR))
	var shape_def: Dictionary = _ShopDefs.by_id(shape_id)
	if shape_def.is_empty():
		shape_def = _ShopDefs.by_id(_ShopDefs.DEFAULT_CROSSHAIR)
	_style = String(shape_def.get("crosshair_style", "dot"))
	var color_id: String = String(equipped.get(String(_ShopDefs.CAT_CROSSHAIR_COLOR), _ShopDefs.DEFAULT_CROSSHAIR_COLOR))
	var color_def: Dictionary = _ShopDefs.by_id(color_id)
	if color_def.is_empty():
		color_def = _ShopDefs.by_id(_ShopDefs.DEFAULT_CROSSHAIR_COLOR)
	_color = color_def.get("crosshair_color", Color(1, 1, 1, 1))
	queue_redraw()

func _draw() -> void:
	_draw_crosshair_at(size * 0.5, _style, _color, 1.0)

# Public so the shop preview can render the same shape/color combo without
# duplicating the case statement. `scale_mul` lets the preview shrink the
# whole shape uniformly inside a smaller swatch box.
static func draw_preview(target: CanvasItem, center: Vector2, style: String, color: Color, scale_mul: float = 1.0) -> void:
	# Outline drop-shadow first.
	_draw_into(target, center, style, Color(0, 0, 0, 0.85), scale_mul, true)
	_draw_into(target, center, style, color, scale_mul, false)

func _draw_crosshair_at(center: Vector2, style: String, color: Color, scale_mul: float) -> void:
	_draw_into(self, center, style, Color(0, 0, 0, 0.85), scale_mul, true)
	_draw_into(self, center, style, color, scale_mul, false)

# `outline` true = thicker dark stroke; false = thinner color stroke. Both
# passes are drawn in the same coordinates so the color sits on top of the
# outline stamp.
static func _draw_into(target: CanvasItem, center: Vector2, style: String, color: Color, scale_mul: float, outline: bool) -> void:
	var outer_w: float = (4.0 if outline else 2.0) * scale_mul
	var ring_w: float = (3.0 if outline else 1.5) * scale_mul
	match style:
		"dot":
			var r: float = (3.0 if outline else 2.0) * scale_mul
			target.draw_circle(center, r, color)
		"x":
			var d: float = 7.0 * scale_mul
			target.draw_line(center + Vector2(-d, -d), center + Vector2(d, d), color, outer_w, true)
			target.draw_line(center + Vector2(-d, d), center + Vector2(d, -d), color, outer_w, true)
		"t":
			var w: float = 8.0 * scale_mul
			var h_top: float = 7.0 * scale_mul
			var h_bot: float = 8.0 * scale_mul
			target.draw_line(center + Vector2(-w, -h_top), center + Vector2(w, -h_top), color, outer_w, true)
			target.draw_line(center + Vector2(0, -h_top), center + Vector2(0, h_bot), color, outer_w, true)
		"o":
			var r: float = 7.0 * scale_mul
			target.draw_arc(center, r, 0.0, TAU, 32, color, ring_w, true)
		"o_dot":
			var r: float = 7.0 * scale_mul
			target.draw_arc(center, r, 0.0, TAU, 32, color, ring_w, true)
			var dr: float = (2.5 if outline else 1.5) * scale_mul
			target.draw_circle(center, dr, color)
		"plus":
			var s: float = 8.0 * scale_mul
			var w: float = (5.0 if outline else 2.5) * scale_mul
			target.draw_line(center + Vector2(-s, 0), center + Vector2(s, 0), color, w, true)
			target.draw_line(center + Vector2(0, -s), center + Vector2(0, s), color, w, true)
		"diamond":
			var d: float = 9.0 * scale_mul
			var pts: PackedVector2Array = PackedVector2Array([
				center + Vector2(0, -d),
				center + Vector2(d, 0),
				center + Vector2(0, d),
				center + Vector2(-d, 0),
				center + Vector2(0, -d),
			])
			for i: int in pts.size() - 1:
				target.draw_line(pts[i], pts[i + 1], color, ring_w, true)
		"smiley":
			# Open ring face + two eye dots + lower arc smile.
			var r: float = 9.0 * scale_mul
			target.draw_arc(center, r, 0.0, TAU, 32, color, ring_w, true)
			var eye_r: float = (1.6 if outline else 1.0) * scale_mul
			target.draw_circle(center + Vector2(-3.0 * scale_mul, -2.0 * scale_mul), eye_r, color)
			target.draw_circle(center + Vector2(3.0 * scale_mul, -2.0 * scale_mul), eye_r, color)
			target.draw_arc(center + Vector2(0, 1.0 * scale_mul), 4.0 * scale_mul, deg_to_rad(20.0), deg_to_rad(160.0), 16, color, ring_w, true)
		"snowman":
			# Three stacked circles: small head / medium torso / large base.
			var head_r: float = 3.5 * scale_mul
			var torso_r: float = 4.5 * scale_mul
			var base_r: float = 5.5 * scale_mul
			target.draw_arc(center + Vector2(0, -8.5 * scale_mul), head_r, 0.0, TAU, 24, color, ring_w, true)
			target.draw_arc(center, torso_r, 0.0, TAU, 24, color, ring_w, true)
			target.draw_arc(center + Vector2(0, 9.5 * scale_mul), base_r, 0.0, TAU, 24, color, ring_w, true)
		"heart":
			# Stylized heart from two arcs + a V at the bottom. Small enough
			# to read as a crosshair, not a graphic.
			var s: float = scale_mul
			target.draw_arc(center + Vector2(-3.0 * s, -2.0 * s), 4.0 * s, deg_to_rad(160.0), deg_to_rad(360.0), 18, color, ring_w, true)
			target.draw_arc(center + Vector2(3.0 * s, -2.0 * s), 4.0 * s, deg_to_rad(180.0), deg_to_rad(380.0), 18, color, ring_w, true)
			target.draw_line(center + Vector2(-7.0 * s, 0.5 * s), center + Vector2(0, 8.0 * s), color, ring_w, true)
			target.draw_line(center + Vector2(7.0 * s, 0.5 * s), center + Vector2(0, 8.0 * s), color, ring_w, true)
