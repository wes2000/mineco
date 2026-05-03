class_name Forge
extends Building

const OVERFLOW_RADIUS: float = 5.0
const OVERFLOW_CAP: int = 50

@export var recipe_input: int = MaterialDefs.MaterialId.BRICK   # one of TIER_2_MATERIALS

var _input_item: FactoryItem = null
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
	if _input_item != null:
		return false
	_input_item = item
	return true

func tick(_tick_index: int) -> void:
	if _is_overflowing():
		status = Status.OVERFLOWING
		return
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	if _input_material != -1:
		if not _try_emit():
			status = Status.OUTPUT_BLOCKED
			return
		_input_material = -1
	if _input_item == null:
		status = Status.IDLE
		return
	if _input_item.material_id != recipe_input:
		status = Status.INPUT_JAMMED
		return
	_input_material = _input_item.material_id
	FactoryWorld.item_pool.release(_input_item)
	_input_item = null
	_cycle_remaining_ticks = MaterialDefs.FORGE_TICKS[_input_material]
	status = Status.WORKING

func _try_emit() -> bool:
	var out_material: int = MaterialDefs.FORGE_RECIPE[_input_material]
	var out_port: Port = ports[1]
	if out_port.attached_link == null:
		return false
	var link: BeltLink = out_port.attached_link as BeltLink
	if not link.can_accept():
		return false
	var item: FactoryItem = FactoryWorld.item_pool.acquire(out_material)
	link.push_item(item)
	item_emitted.emit(out_material)
	return true

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
