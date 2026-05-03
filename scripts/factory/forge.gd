class_name Forge
extends Building

const OVERFLOW_RADIUS: float = 5.0
const OVERFLOW_CAP: int = 50

@export var recipe_input: int = MaterialDefs.MaterialId.BRICK   # one of TIER_2_MATERIALS

var _cycle_remaining_ticks: int = 0
var _input_material: int = -1

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
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	if _input_material != -1:
		if not output_queue_can_accept():
			status = Status.OUTPUT_BLOCKED
			return
		var out_material: int = MaterialDefs.FORGE_RECIPE[_input_material]
		output_queue_push(out_material)
		item_emitted.emit(out_material)
		_input_material = -1
	if input_queue.is_empty():
		status = Status.IDLE
		return
	var head: int = input_queue[0]
	if head != recipe_input:
		status = Status.INPUT_JAMMED
		return
	if not output_queue_can_accept():
		status = Status.OUTPUT_BLOCKED
		return
	_input_material = input_queue.pop_front()
	queue_changed.emit(QUEUE_KIND_INPUT, input_queue.size())
	_cycle_remaining_ticks = MaterialDefs.FORGE_TICKS[_input_material]
	status = Status.WORKING

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
