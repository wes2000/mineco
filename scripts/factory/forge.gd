class_name Forge
extends Building

const OVERFLOW_RADIUS: float = 5.0
const OVERFLOW_CAP: int = 50

@export var recipe_input: int = MaterialDefs.MaterialId.BRICK   # one of TIER_2_MATERIALS

var _cycle_remaining_ticks: int = 0
var _cycle_total_ticks: int = 0
var _active_input_material: int = -1

func _ready() -> void:
	footprint_size = Vector2i(3, 3)
	var pin: Port = Port.new()
	pin.owner_building = self
	pin.local_position = Vector3(1.5, 0.6, 0.05)
	pin.local_facing = Vector3(0, 0, -1)
	pin.kind = Port.KIND_INPUT
	ports.append(pin)
	var pout: Port = Port.new()
	pout.owner_building = self
	pout.local_position = Vector3(1.5, 0.6, 2.95)
	pout.local_facing = Vector3(0, 0, 1)
	pout.kind = Port.KIND_OUTPUT
	ports.append(pout)
	super._ready()

func get_cycle_remaining_ticks() -> int:
	return _cycle_remaining_ticks

func get_cycle_total_ticks() -> int:
	return _cycle_total_ticks

func processing_buffer_cap() -> int:
	return _MachineUpgradeDefs.processing_buffer_cap_for(upgrade_level)

func get_save_data() -> Dictionary:
	var d: Dictionary = super.get_save_data()
	d["recipe_input"] = recipe_input
	d["cycle_remaining_ticks"] = _cycle_remaining_ticks
	d["cycle_total_ticks"] = _cycle_total_ticks
	d["active_input_material"] = _active_input_material
	return d

func apply_save_data(data: Dictionary) -> void:
	super.apply_save_data(data)
	recipe_input = int(data.get("recipe_input", MaterialDefs.MaterialId.BRICK))
	_cycle_remaining_ticks = int(data.get("cycle_remaining_ticks", 0))
	_cycle_total_ticks = int(data.get("cycle_total_ticks", 0))
	_active_input_material = int(data.get("active_input_material", -1))

func port_accept_item(item: FactoryItem, _port: Port) -> bool:
	if not input_queue_can_accept():
		return false
	input_queue_push(item.material_id)
	FactoryWorld.item_pool.release(item)
	return true

func tick(_tick_index: int) -> void:
	_drain_output_to_link()
	if _is_overflowing():
		status = Status.OVERFLOWING
		return
	while processing_buffer_can_accept() and not input_queue.is_empty():
		var head: int = input_queue[0]
		if head != recipe_input:
			status = Status.INPUT_JAMMED
			return
		input_queue.pop_front()
		queue_changed.emit(QUEUE_KIND_INPUT, input_queue.size())
		processing_buffer.append(head)
		processing_changed.emit(processing_buffer.size())
	# Need a full batch in the buffer before a cycle can run.
	if processing_buffer.size() < MaterialDefs.RECIPE_INPUT_PER_OUTPUT:
		status = Status.IDLE
		return
	if not output_queue_can_accept():
		status = Status.OUTPUT_BLOCKED
		return
	if _cycle_remaining_ticks <= 0 and _active_input_material == -1:
		_active_input_material = processing_buffer[0]
		_cycle_total_ticks = apply_upgrade_to_cycle(MaterialDefs.FORGE_TICKS[_active_input_material])
		_cycle_remaining_ticks = _cycle_total_ticks
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	# Cycle complete — consume a full batch, emit one output.
	for _i: int in MaterialDefs.RECIPE_INPUT_PER_OUTPUT:
		processing_buffer.pop_front()
	processing_changed.emit(processing_buffer.size())
	var out_material: int = MaterialDefs.FORGE_RECIPE[_active_input_material]
	output_queue_push(out_material)
	item_emitted.emit(out_material)
	_active_input_material = -1
	_cycle_total_ticks = 0
	status = Status.IDLE

func _drain_output_to_link() -> void:
	if output_queue.is_empty():
		return
	var out_port: Port = ports[1]
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

func _is_overflowing() -> bool:
	var count: int = 0
	var origin: Vector3 = global_position
	for node: Node in get_tree().get_nodes_in_group("factory_drops"):
		if node is RigidBody3D:
			if (node as RigidBody3D).global_position.distance_to(origin) <= OVERFLOW_RADIUS:
				count += 1
				if count > OVERFLOW_CAP:
					return true
	return false
