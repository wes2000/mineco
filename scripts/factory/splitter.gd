class_name Splitter
extends Building
## 1×1 building. 1 input on -Z (back), 3 outputs on -X (left), +Z (front), +X (right).
## Routes incoming items round-robin between its 3 output links.

var _round_robin: int = 0

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	var pin: Port = Port.new()
	pin.owner_building = self
	pin.local_position = Vector3(0.5, 0.4, 0.05)
	pin.local_facing = Vector3(0, 0, -1)
	pin.kind = Port.KIND_INPUT
	ports.append(pin)
	# Outputs: left (-X), front (+Z), right (+X) — order matters for round-robin
	var positions: Array = [
		[Vector3(0.05, 0.4, 0.5), Vector3(-1, 0, 0)],
		[Vector3(0.5, 0.4, 0.95), Vector3(0, 0, 1)],
		[Vector3(0.95, 0.4, 0.5), Vector3(1, 0, 0)],
	]
	for entry: Array in positions:
		var p: Port = Port.new()
		p.owner_building = self
		p.local_position = entry[0]
		p.local_facing = entry[1]
		p.kind = Port.KIND_OUTPUT
		ports.append(p)
	super._ready()

func port_accept_item(item: FactoryItem, _port: Port) -> bool:
	# Try round-robin: pick the next output, wrap if blocked, give up if all 3 are blocked
	var outs: Array[Port] = get_output_ports()
	for i: int in outs.size():
		var idx: int = (_round_robin + i) % outs.size()
		var op: Port = outs[idx]
		if op.attached_link == null:
			continue
		var link: BeltLink = op.attached_link as BeltLink
		if link.can_accept():
			link.push_item(item)
			_round_robin = (idx + 1) % outs.size()
			item_emitted.emit(item.material_id)
			status = Status.WORKING
			return true
	status = Status.OUTPUT_BLOCKED
	return false

func tick(_tick_index: int) -> void:
	# Splitter is purely reactive — it doesn't run a cycle. Status decays to IDLE
	# if nothing has flowed through recently.
	if status == Status.WORKING:
		status = Status.IDLE
