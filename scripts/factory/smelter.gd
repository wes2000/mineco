class_name Smelter
extends Building

@export var recipe_input: int = MaterialDefs.MaterialId.STONE   # one of TIER_1_MATERIALS

var _cycle_remaining_ticks: int = 0
var _input_material: int = -1   # currently smelting (mid-cycle)

func _ready() -> void:
	footprint_size = Vector2i(2, 2)
	var pin: Port = Port.new()
	pin.owner_building = self
	pin.local_position = Vector3(1.0, 0.5, 0.05)
	pin.local_facing = Vector3(0, 0, -1)
	pin.kind = Port.KIND_INPUT
	ports.append(pin)
	var pout: Port = Port.new()
	pout.owner_building = self
	pout.local_position = Vector3(1.0, 0.5, 1.95)
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
	# Mid-cycle: keep counting down
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	# Cycle just finished — push result to output_queue
	if _input_material != -1:
		if not output_queue_can_accept():
			status = Status.OUTPUT_BLOCKED
			return
		var out_material: int = MaterialDefs.SMELT_RECIPE[_input_material]
		output_queue_push(out_material)
		item_emitted.emit(out_material)
		_input_material = -1
	# Try to start a new cycle from input_queue head
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
	_cycle_remaining_ticks = MaterialDefs.SMELTER_TICKS[_input_material]
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
