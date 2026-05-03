class_name Merger
extends Building
## 1×1 building. 3 inputs on -X (left), -Z (back), +X (right). 1 output on +Z (front).
## Items arriving at any input round-robin into the output link.
##
## Items are forwarded immediately on arrival via port_accept_item — no internal
## buffer. Round-robin counter ensures fair scheduling between input links if
## multiple deliver in the same tick.

var _round_robin: int = 0

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	# Inputs: left (-X), back (-Z), right (+X)
	var input_specs: Array = [
		[Vector3(0.05, 0.4, 0.5), Vector3(-1, 0, 0)],
		[Vector3(0.5, 0.4, 0.05), Vector3(0, 0, -1)],
		[Vector3(0.95, 0.4, 0.5), Vector3(1, 0, 0)],
	]
	for entry: Array in input_specs:
		var p: Port = Port.new()
		p.owner_building = self
		p.local_position = entry[0]
		p.local_facing = entry[1]
		p.kind = Port.KIND_INPUT
		ports.append(p)
	# Single output on front
	var pout: Port = Port.new()
	pout.owner_building = self
	pout.local_position = Vector3(0.5, 0.4, 0.95)
	pout.local_facing = Vector3(0, 0, 1)
	pout.kind = Port.KIND_OUTPUT
	ports.append(pout)
	super._ready()

func port_accept_item(item: FactoryItem, _port: Port) -> bool:
	# Forward immediately to output link if it can accept
	var outs: Array[Port] = get_output_ports()
	if outs.is_empty():
		return false
	var op: Port = outs[0]
	if op.attached_link == null:
		return false
	var link: BeltLink = op.attached_link as BeltLink
	if not link.can_accept():
		return false
	link.push_item(item)
	# Bump round-robin so the next time multiple inputs deliver in the same tick,
	# a different input gets first dibs. (Currently each port_accept_item is
	# called sequentially per-link tick, so this is mostly cosmetic — but it
	# keeps the door open for parallel input ticks later.)
	_round_robin = (_round_robin + 1) % 3
	item_emitted.emit(item.material_id)
	status = Status.WORKING
	return true

func tick(_tick_index: int) -> void:
	if status == Status.WORKING:
		status = Status.IDLE
