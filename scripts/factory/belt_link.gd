class_name BeltLink
extends Node3D
## A spline-based connection from one output Port to one input Port.
## Items travel along an arc-length parameter (meters from start) at constant speed.

const ITEM_MIN_SPACING_M: float = 0.4
const BELT_SPEED_M_PER_SEC: float = 1.0
const SEG_SPACING_M: float = 0.5
const SEG_BOX_SIZE: Vector3 = Vector3(0.4, 0.05, 0.3)
const SEG_COLOR: Color = Color(0.25, 0.25, 0.3, 1)
const COLLIDER_RADIUS: float = 0.25
const COLLISION_LAYER_FACTORY: int = 4

var source_port: Port = null
var dest_port: Port = null
var curve: Curve3D = null
var _curve_length: float = 0.0
var items: Array[Dictionary] = []   # entries: {"item": FactoryItem, "arc_meters": float}

# Internal: shared mesh/material for segment markers
static var _seg_mesh: BoxMesh = null
static var _seg_mat: StandardMaterial3D = null

func setup(s: Port, d: Port) -> void:
	source_port = s
	dest_port = d
	s.attached_link = self
	d.attached_link = self
	_build_curve()
	_build_visuals()
	set_process(true)

func teardown() -> void:
	# Drop any items in transit on the ground
	for entry: Dictionary in items:
		var item: FactoryItem = entry["item"]
		var arc: float = entry["arc_meters"]
		var pos: Vector3 = curve.sample_baked(arc, false) if curve != null else global_position
		FactoryWorld.spawn_drop(item.material_id, pos, Vector3(0, 0.5, 0))
		FactoryWorld.item_pool.release(item)
	items.clear()
	if source_port != null and source_port.attached_link == self:
		source_port.attached_link = null
	if dest_port != null and dest_port.attached_link == self:
		dest_port.attached_link = null
	queue_free()

func _build_curve() -> void:
	curve = Curve3D.new()
	var start_pos: Vector3 = source_port.world_position()
	var end_pos: Vector3 = dest_port.world_position()
	var src_facing: Vector3 = source_port.world_facing()
	var dst_facing: Vector3 = dest_port.world_facing()
	var dist: float = start_pos.distance_to(end_pos)
	var handle_len: float = max(dist / 3.0, 0.5)
	# Detect a "wrap-around" case: the dest port is on the far side of the dest
	# building relative to the source. Symptom: dest_facing points roughly the
	# same direction as source→dest (both point away from source). In that case,
	# inserting an intermediate waypoint that swings out lateral to the
	# straight line lets the curve route AROUND the dest building instead of
	# through it.
	var src_to_dst: Vector3 = end_pos - start_pos
	var src_to_dst_norm: Vector3 = src_to_dst.normalized() if src_to_dst.length() > 0.001 else Vector3.FORWARD
	var wrap_dot: float = dst_facing.dot(src_to_dst_norm)
	if wrap_dot > 0.3:
		# Compute lateral perpendicular in the XZ plane
		var perp: Vector3 = Vector3(-src_to_dst_norm.z, 0, src_to_dst_norm.x).normalized()
		# Choose the side that pushes AWAY from the dest building's center
		var dst_bld: Node3D = dest_port.owner_building as Node3D
		if dst_bld != null:
			var bld_to_perp_pos: Vector3 = dst_bld.global_position - end_pos
			if perp.dot(bld_to_perp_pos) > 0:
				perp = -perp
		# Offset distance proportional to dest building footprint + clearance
		var bld_radius: float = 1.5
		if dst_bld != null and dst_bld is Building:
			bld_radius = max((dst_bld as Building).footprint_size.x, (dst_bld as Building).footprint_size.y) * 0.8 + 1.0
		var wp: Vector3 = (start_pos + end_pos) * 0.5 + perp * bld_radius
		# Tangents at the waypoint follow the perpendicular direction so the
		# curve smoothly arcs through the side
		var wp_handle: float = max(dist / 4.0, 0.8)
		var wp_in: Vector3 = -src_to_dst_norm * wp_handle
		var wp_out: Vector3 = src_to_dst_norm * wp_handle
		var src_tangent: Vector3 = src_facing * handle_len
		var dst_in: Vector3 = -dst_facing * handle_len
		curve.add_point(start_pos, Vector3.ZERO, src_tangent)
		curve.add_point(wp, wp_in, wp_out)
		curve.add_point(end_pos, dst_in, Vector3.ZERO)
	else:
		var start_tangent: Vector3 = src_facing * handle_len
		var end_in_tangent: Vector3 = -dst_facing * handle_len
		curve.add_point(start_pos, Vector3.ZERO, start_tangent)
		curve.add_point(end_pos, end_in_tangent, Vector3.ZERO)
	_curve_length = curve.get_baked_length()

func _build_visuals() -> void:
	if _seg_mesh == null:
		_seg_mesh = BoxMesh.new()
		_seg_mesh.size = SEG_BOX_SIZE
		_seg_mat = StandardMaterial3D.new()
		_seg_mat.albedo_color = SEG_COLOR
	var n_segs: int = int(_curve_length / SEG_SPACING_M) + 1
	for i: int in n_segs:
		var arc: float = float(i) * SEG_SPACING_M
		if arc > _curve_length:
			arc = _curve_length
		var pos: Vector3 = curve.sample_baked(arc, false)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = _seg_mesh
		mi.material_override = _seg_mat
		mi.position = pos   # link itself sits at world origin; positions are world coords
		add_child(mi)
		# Add a small collider on each segment so X+LMB delete can find this link
		var sb: StaticBody3D = StaticBody3D.new()
		sb.collision_layer = COLLISION_LAYER_FACTORY
		sb.collision_mask = 0
		sb.set_meta("belt_link", self)
		var cs: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(SEG_BOX_SIZE.x, 0.2, SEG_BOX_SIZE.z)
		cs.shape = shape
		cs.position = pos
		sb.add_child(cs)
		add_child(sb)

func can_accept() -> bool:
	# Can a new item be pushed at arc=0? Only if no item is too close.
	if items.is_empty():
		return true
	var first_arc: float = items[0]["arc_meters"]
	return first_arc >= ITEM_MIN_SPACING_M

func push_item(item: FactoryItem) -> void:
	items.push_front({"item": item, "arc_meters": 0.0})
	if curve != null:
		item.global_position = curve.sample_baked(0.0, false)

func tick(tick_dt: float) -> void:
	if curve == null:
		return
	var step: float = BELT_SPEED_M_PER_SEC * tick_dt
	# Advance from FRONT (highest arc) to BACK (lowest arc).
	# items[0] is the most-recent push (lowest arc). items[-1] is the front.
	# So iterate in reverse.
	var i: int = items.size() - 1
	var prev_arc: float = INF
	while i >= 0:
		var entry: Dictionary = items[i]
		var current: float = entry["arc_meters"]
		var max_arc: float = prev_arc - ITEM_MIN_SPACING_M
		if i == items.size() - 1:
			max_arc = _curve_length
		var new_arc: float = min(current + step, max_arc)
		if new_arc > current:
			items[i]["arc_meters"] = new_arc
		prev_arc = items[i]["arc_meters"]
		i -= 1
	# Front item at end of curve — try to deliver to dest port's building
	if not items.is_empty():
		var front: Dictionary = items[items.size() - 1]
		if front["arc_meters"] >= _curve_length - 0.001:
			var bld: Node = dest_port.owner_building if dest_port != null else null
			if bld != null and bld.has_method("port_accept_item"):
				var accepted: bool = bld.port_accept_item(front["item"], dest_port)
				if accepted:
					items.pop_back()

func _process(_delta: float) -> void:
	# Update item visual positions every frame (smooth, decoupled from sim tick).
	if curve == null:
		return
	for entry: Dictionary in items:
		var p: Vector3 = curve.sample_baked(entry["arc_meters"], false)
		(entry["item"] as FactoryItem).global_position = p
