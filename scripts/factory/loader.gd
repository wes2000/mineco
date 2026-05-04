class_name Loader
extends Building
## Player-fed hopper that produces selected material into its output queue,
## then drains the output queue onto the attached belt link as space allows.

const HOPPER_CAP: int = 999

signal hopper_changed(material_id: int, new_count: int)

var hopper: Dictionary = {}     # material_id -> int
var selected_material: int = MaterialDefs.MaterialId.STONE
var _cycle_remaining_ticks: int = 0

func _ready() -> void:
	footprint_size = Vector2i(2, 2)
	for mid: int in MaterialDefs.TIER_1_MATERIALS:
		hopper[mid] = 0
	var p: Port = Port.new()
	p.owner_building = self
	p.local_position = Vector3(1.0, 0.5, 1.95)
	p.local_facing = Vector3(0, 0, 1)
	p.kind = Port.KIND_OUTPUT
	ports.append(p)
	super._ready()

func get_save_data() -> Dictionary:
	var d: Dictionary = super.get_save_data()
	# JSON keys are strings — store hopper material ids as string keys.
	var hopper_str: Dictionary = {}
	for k: int in hopper.keys():
		hopper_str[str(k)] = int(hopper[k])
	d["hopper"] = hopper_str
	d["selected_material"] = selected_material
	d["cycle_remaining_ticks"] = _cycle_remaining_ticks
	return d

func apply_save_data(data: Dictionary) -> void:
	super.apply_save_data(data)
	hopper = {}
	for mid: int in MaterialDefs.TIER_1_MATERIALS:
		hopper[mid] = 0
	for k: Variant in data.get("hopper", {}).keys():
		var mid: int = int(String(k))
		hopper[mid] = int(data["hopper"][k])
		hopper_changed.emit(mid, hopper[mid])
	selected_material = int(data.get("selected_material", MaterialDefs.MaterialId.STONE))
	_cycle_remaining_ticks = int(data.get("cycle_remaining_ticks", 0))

func deposit(material_id: int, amount: int) -> int:
	var current: int = hopper.get(material_id, 0)
	var new_amount: int = min(current + amount, HOPPER_CAP)
	var accepted: int = new_amount - current
	hopper[material_id] = new_amount
	hopper_changed.emit(material_id, new_amount)
	return accepted

func tick(_tick_index: int) -> void:
	_drain_output_to_link()
	# Generate a new item into output_queue if hopper has stock and queue has space
	if hopper.get(selected_material, 0) <= 0:
		status = Status.IDLE if output_queue.is_empty() else Status.WORKING
		return
	if not output_queue_can_accept():
		status = Status.OUTPUT_BLOCKED
		return
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	output_queue_push(selected_material)
	hopper[selected_material] -= 1
	hopper_changed.emit(selected_material, hopper[selected_material])
	item_emitted.emit(selected_material)
	_cycle_remaining_ticks = scaled_cycle_ticks(MaterialDefs.LOADER_EMIT_TICKS[selected_material])
	status = Status.WORKING

func _drain_output_to_link() -> void:
	if output_queue.is_empty():
		return
	var out_port: Port = ports[0]
	if out_port.attached_link == null:
		return
	var link: BeltLink = out_port.attached_link as BeltLink
	if not link.can_accept():
		return
	var mid: int = output_queue[0]
	var item: FactoryItem = FactoryWorld.item_pool.acquire(mid)
	link.push_item(item)
	output_queue.pop_front()
	queue_changed.emit(QUEUE_KIND_OUTPUT, output_queue.size())
