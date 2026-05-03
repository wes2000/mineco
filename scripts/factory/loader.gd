class_name Loader
extends Building
## Player-fed hopper that emits one selected material onto its attached belt link.

const HOPPER_CAP: int = 999

signal hopper_changed(material_id: int, new_count: int)

var hopper: Dictionary = {}     # material_id -> int
var selected_material: int = MaterialDefs.MaterialId.STONE
var _cycle_remaining_ticks: int = 0

func _ready() -> void:
	footprint_size = Vector2i(2, 2)
	for mid: int in MaterialDefs.TIER_1_MATERIALS:
		hopper[mid] = 0
	# Single output port on the front face, centered on the 2x2 footprint
	var p: Port = Port.new()
	p.owner_building = self
	p.local_position = Vector3(1.0, 0.5, 1.95)   # matches OutputPort mesh in scene
	p.local_facing = Vector3(0, 0, 1)
	p.kind = Port.KIND_OUTPUT
	ports.append(p)
	super._ready()

func deposit(material_id: int, amount: int) -> int:
	var current: int = hopper.get(material_id, 0)
	var new_amount: int = min(current + amount, HOPPER_CAP)
	var accepted: int = new_amount - current
	hopper[material_id] = new_amount
	hopper_changed.emit(material_id, new_amount)
	return accepted

func tick(_tick_index: int) -> void:
	if hopper.get(selected_material, 0) <= 0:
		status = Status.IDLE
		return
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	var out_port: Port = ports[0]
	if out_port.attached_link == null:
		status = Status.OUTPUT_BLOCKED
		return
	var link: BeltLink = out_port.attached_link as BeltLink
	if not link.can_accept():
		status = Status.OUTPUT_BLOCKED
		return
	var item: FactoryItem = FactoryWorld.item_pool.acquire(selected_material)
	link.push_item(item)
	hopper[selected_material] -= 1
	hopper_changed.emit(selected_material, hopper[selected_material])
	item_emitted.emit(selected_material)
	_cycle_remaining_ticks = MaterialDefs.LOADER_EMIT_TICKS[selected_material]
	status = Status.WORKING
