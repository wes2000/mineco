class_name Smelter
extends Building

@export var recipe_input: int = MaterialDefs.MaterialId.STONE   # one of TIER_1_MATERIALS

var _input_item: FactoryItem = null
var _cycle_remaining_ticks: int = 0
var _input_material: int = -1

func _ready() -> void:
	footprint_size = Vector2i(2, 2)
	# Input on -Z (back), output on +Z (front), both centered on the 2x2 footprint
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
	if _input_item != null:
		return false
	_input_item = item
	return true

func tick(_tick_index: int) -> void:
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
	_cycle_remaining_ticks = MaterialDefs.SMELTER_TICKS[_input_material]
	status = Status.WORKING

func _try_emit() -> bool:
	var out_material: int = MaterialDefs.SMELT_RECIPE[_input_material]
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
