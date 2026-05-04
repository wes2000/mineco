class_name Building
extends Node3D
## Shared base for Loader, Smelter, Forge, Splitter, Merger.

enum Status { IDLE, WORKING, OUTPUT_BLOCKED, INPUT_JAMMED, OVERFLOWING }

signal item_emitted(material_id: int)
signal status_changed(new_status: int)

@export var footprint_size: Vector2i = Vector2i(2, 2)   # cells in X,Z
@export var rotation_steps: int = 0                     # 0..3, applied in 90° steps around +Y
@export var idle_bob_amplitude: float = 0.02
@export var idle_bob_freq_hz: float = 4.0

var origin_cell: Vector3i        # set on placement; "front-left" cell of the footprint
# Stable id used by SaveGame to resolve cross-building belt links across
# save → load. Assigned by FactoryWorld on placement and on restore.
var save_id: String = ""
var status: int = Status.IDLE :
	set(v):
		if status != v:
			status = v
			status_changed.emit(v)
			_update_audio()

# Ports — populated by subclasses in _ready()
var ports: Array[Port] = []

# --- Queues ---
# Each queue holds material_id values (int). FIFO. Max 100.
const QUEUE_MAX: int = 100
const PROCESSING_BUFFER_MAX: int = 3

signal queue_changed(kind: int, new_count: int)   # kind: 0=input, 1=output
signal processing_changed(new_count: int)
const QUEUE_KIND_INPUT: int = 0
const QUEUE_KIND_OUTPUT: int = 1

var input_queue: Array[int] = []
var output_queue: Array[int] = []
# Processing buffer = items currently inside the machine, between input_queue
# and the producer that pushes to output_queue. Front item is the one actively
# cycling; remaining items are queued for subsequent cycles.
var processing_buffer: Array[int] = []

var _bob_origin_y: float = 0.0
var _body_mesh: MeshInstance3D = null
var _output_port_visual: MeshInstance3D = null
var _emissive_material: StandardMaterial3D = null
var _fire_material: StandardMaterial3D = null
var _hum_loop: AudioStreamPlayer3D = null
var _emit_click: AudioStreamPlayer3D = null
var _has_bob_origin: bool = false

func _ready() -> void:
	_bob_origin_y = position.y
	_has_bob_origin = true
	_body_mesh = find_child("Body", true, false) as MeshInstance3D
	_output_port_visual = find_child("OutputPort", true, false) as MeshInstance3D
	if _body_mesh != null:
		var mat: Material = _body_mesh.material_override
		if mat is StandardMaterial3D:
			_emissive_material = mat as StandardMaterial3D
	var fire_mesh: MeshInstance3D = find_child("Fire", true, false) as MeshInstance3D
	if fire_mesh != null:
		var fmat: Material = fire_mesh.material_override
		if fmat is StandardMaterial3D:
			# Duplicate so per-building flicker doesn't affect other instances
			_fire_material = (fmat as StandardMaterial3D).duplicate() as StandardMaterial3D
			fire_mesh.material_override = _fire_material
	# Same precaution for the body's emissive material
	if _emissive_material != null:
		_emissive_material = _emissive_material.duplicate() as StandardMaterial3D
		_body_mesh.material_override = _emissive_material
	_hum_loop = find_child("HumLoop", true, false) as AudioStreamPlayer3D
	_emit_click = find_child("EmitClick", true, false) as AudioStreamPlayer3D
	if not item_emitted.is_connected(_on_emit_pulse):
		item_emitted.connect(_on_emit_pulse)
	set_process(true)

func _process(delta: float) -> void:
	if not _has_bob_origin:
		return
	var working: bool = (status == Status.WORKING)
	if working:
		position.y = _bob_origin_y + sin(Time.get_ticks_msec() / 1000.0 * TAU * idle_bob_freq_hz) * idle_bob_amplitude
	else:
		position.y = lerp(position.y, _bob_origin_y, delta * 5.0)
	if _emissive_material != null:
		var target: float = 1.0 if working else 0.0
		_emissive_material.emission_energy_multiplier = lerp(
			_emissive_material.emission_energy_multiplier, target, delta * 5.0)
	if _fire_material != null:
		# Flicker the fire emission with a sin wave + small noise while WORKING.
		var t: float = Time.get_ticks_msec() / 1000.0
		var fire_target: float = (1.6 + sin(t * 8.0) * 0.4 + sin(t * 13.7) * 0.2) if working else 0.0
		_fire_material.emission_energy_multiplier = lerp(
			_fire_material.emission_energy_multiplier, fire_target, delta * 8.0)

func _on_emit_pulse(material_id: int) -> void:
	if _output_port_visual != null:
		var tw: Tween = create_tween()
		tw.tween_property(_output_port_visual, "scale", Vector3.ONE * 1.2, 0.075)
		tw.tween_property(_output_port_visual, "scale", Vector3.ONE, 0.075)
	if _emit_click != null and _emit_click.stream != null:
		var tier: int = MaterialDefs.TIER.get(material_id, 1)
		_emit_click.pitch_scale = 0.8 + 0.2 * tier
		_emit_click.play()

func _update_audio() -> void:
	if _hum_loop == null:
		return
	var should_play: bool = (status == Status.WORKING)
	if should_play and not _hum_loop.playing and _hum_loop.stream != null:
		_hum_loop.play()
	elif not should_play and _hum_loop.playing:
		_hum_loop.stop()

# --- Footprint ---

func get_footprint_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x: int in footprint_size.x:
		for z: int in footprint_size.y:
			cells.append(origin_cell + Vector3i(x, 0, z))
	return cells

# --- Ports ---

func get_input_ports() -> Array[Port]:
	var out: Array[Port] = []
	for p: Port in ports:
		if p.kind == Port.KIND_INPUT:
			out.append(p)
	return out

func get_output_ports() -> Array[Port]:
	var out: Array[Port] = []
	for p: Port in ports:
		if p.kind == Port.KIND_OUTPUT:
			out.append(p)
	return out

func find_closest_port(world_pos: Vector3, kind: int) -> Port:
	var best: Port = null
	var best_d: float = INF
	for p: Port in ports:
		if p.kind != kind:
			continue
		var d: float = p.world_position().distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = p
	return best

# --- Queue helpers ---

func input_queue_can_accept() -> bool:
	return input_queue.size() < QUEUE_MAX

func input_queue_push(material_id: int) -> bool:
	if not input_queue_can_accept():
		return false
	input_queue.append(material_id)
	queue_changed.emit(QUEUE_KIND_INPUT, input_queue.size())
	return true

func output_queue_can_accept() -> bool:
	return output_queue.size() < QUEUE_MAX

func output_queue_push(material_id: int) -> bool:
	if not output_queue_can_accept():
		return false
	output_queue.append(material_id)
	queue_changed.emit(QUEUE_KIND_OUTPUT, output_queue.size())
	return true

func take_all_from_queue(kind: int) -> Array[int]:
	var taken: Array[int] = []
	if kind == QUEUE_KIND_INPUT:
		taken = input_queue.duplicate()
		input_queue.clear()
		queue_changed.emit(QUEUE_KIND_INPUT, 0)
	elif kind == QUEUE_KIND_OUTPUT:
		taken = output_queue.duplicate()
		output_queue.clear()
		queue_changed.emit(QUEUE_KIND_OUTPUT, 0)
	return taken

# --- Processing buffer / cycle introspection (subclasses override) ---

func processing_buffer_can_accept() -> bool:
	return processing_buffer.size() < PROCESSING_BUFFER_MAX

func get_cycle_remaining_ticks() -> int:
	return 0

func get_cycle_total_ticks() -> int:
	return 0

# --- Sim hooks (subclasses override) ---

func tick(_tick_index: int) -> void:
	pass

# Called by BeltLink when an item arrives at one of our input ports.
# Return true to consume, false to leave on the link.
func port_accept_item(_item: FactoryItem, _port: Port) -> bool:
	return false

# --- Tick scaling ----------------------------------------------------------

# Scales a base cycle length by the factory_speed_mult progression stat,
# clamped to >= 1 tick so cycles always complete. Subclasses call this
# wherever they reset _cycle_remaining_ticks.
func scaled_cycle_ticks(base_ticks: int) -> int:
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats == null:
		return base_ticks
	var mul: float = float(stats.call("get_stat", &"factory_speed_mult"))
	if mul <= 0.001:
		return base_ticks
	return max(1, int(round(float(base_ticks) / mul)))

# --- Save / load -----------------------------------------------------------

# Subclasses MUST call super().get_save_data() and merge so the placement
# slug (kind / origin_cell / rotation_steps / save_id / queues) survives.
func get_save_data() -> Dictionary:
	return {
		"save_id": save_id,
		"input_queue": input_queue.duplicate(),
		"output_queue": output_queue.duplicate(),
		"processing_buffer": processing_buffer.duplicate(),
	}

func apply_save_data(data: Dictionary) -> void:
	if data.has("save_id"):
		save_id = String(data["save_id"])
	input_queue = _coerce_int_array(data.get("input_queue", []))
	output_queue = _coerce_int_array(data.get("output_queue", []))
	processing_buffer = _coerce_int_array(data.get("processing_buffer", []))
	queue_changed.emit(QUEUE_KIND_INPUT, input_queue.size())
	queue_changed.emit(QUEUE_KIND_OUTPUT, output_queue.size())
	processing_changed.emit(processing_buffer.size())

static func _coerce_int_array(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if not (raw is Array):
		return out
	for v: Variant in raw:
		out.append(int(v))
	return out
