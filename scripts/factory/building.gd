class_name Building
extends Node3D
## Shared base for Loader, Smelter, Forge.

enum Status { IDLE, WORKING, OUTPUT_BLOCKED, INPUT_JAMMED, OVERFLOWING }

signal item_emitted(material_id: int)
signal status_changed(new_status: int)

@export var footprint_size: Vector2i = Vector2i(2, 2)   # cells in X,Z
@export var rotation_steps: int = 0                     # 0..3, applied in 90° steps around +Y
@export var idle_bob_amplitude: float = 0.02
@export var idle_bob_freq_hz: float = 4.0

var origin_cell: Vector3i        # set on placement; "front-left" cell of the footprint
var status: int = Status.IDLE :
	set(v):
		if status != v:
			status = v
			status_changed.emit(v)
			_update_audio()

var _bob_origin_y: float = 0.0
var _body_mesh: MeshInstance3D = null
var _output_port: MeshInstance3D = null
var _emissive_material: StandardMaterial3D = null
var _hum_loop: AudioStreamPlayer3D = null
var _emit_click: AudioStreamPlayer3D = null
var _has_bob_origin: bool = false

func _enter_tree() -> void:
	# _enter_tree fires before _ready of children but after position is set;
	# we capture the place-time Y here.
	pass

func _ready() -> void:
	_bob_origin_y = position.y
	_has_bob_origin = true
	_body_mesh = find_child("Body", true, false) as MeshInstance3D
	_output_port = find_child("OutputPort", true, false) as MeshInstance3D
	if _body_mesh != null:
		var mat: Material = _body_mesh.material_override
		if mat is StandardMaterial3D:
			_emissive_material = mat as StandardMaterial3D
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

func _on_emit_pulse(material_id: int) -> void:
	if _output_port != null:
		var tw: Tween = create_tween()
		tw.tween_property(_output_port, "scale", Vector3.ONE * 1.2, 0.075)
		tw.tween_property(_output_port, "scale", Vector3.ONE, 0.075)
	if _emit_click != null and _emit_click.stream != null:
		var tier: int = MaterialDefs.TIER.get(material_id, 1)
		_emit_click.pitch_scale = 0.8 + 0.2 * tier   # T1=1.0, T2=1.2, T3=1.4
		_emit_click.play()

func _update_audio() -> void:
	if _hum_loop == null:
		return
	var should_play: bool = (status == Status.WORKING)
	if should_play and not _hum_loop.playing and _hum_loop.stream != null:
		_hum_loop.play()
	elif not should_play and _hum_loop.playing:
		_hum_loop.stop()

# Subclasses override these:
func get_input_cells() -> Array[Vector3i]:
	return []

func get_output_cells() -> Array[Vector3i]:
	return []

func get_footprint_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x: int in footprint_size.x:
		for z: int in footprint_size.y:
			cells.append(origin_cell + Vector3i(x, 0, z))
	return cells

# Called by FactoryWorld on each tick.
func tick(_tick_index: int) -> void:
	pass

# Called by FactoryWorld when an item arrives at one of our input cells.
# Return true to accept (we take ownership), false to reject (item stays put).
func try_accept_item(_item: FactoryItem, _from_cell: Vector3i) -> bool:
	return false

# Helper: given a local-space offset in the 0-rotation frame, return the world cell.
func cell_for_local_offset(local: Vector3i) -> Vector3i:
	var rotated: Vector3i = _rotate_offset(local, rotation_steps)
	return origin_cell + rotated

func _rotate_offset(v: Vector3i, steps: int) -> Vector3i:
	var s: int = steps & 3
	var x: int = v.x
	var z: int = v.z
	for _i: int in s:
		var nx: int = -z
		var nz: int = x
		x = nx
		z = nz
	return Vector3i(x, v.y, z)
