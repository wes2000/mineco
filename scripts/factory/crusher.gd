class_name Crusher
extends Building
## Advanced T1 ore processor (brief 09). Takes a T1 ore on input, outputs the
## SAME material on a cycle, with a chance to drop a bonus copy. Gated behind
## Unlocks.has("crusher_blueprint") at the build catalog level.

@export var recipe_input: int = MaterialDefs.MaterialId.STONE   # one of TIER_1_MATERIALS

# Base chance to emit a bonus output on cycle complete. Scales +5% per
# upgrade level so Mk3 = 35%.
const BONUS_CHANCE: float = 0.25
const BONUS_CHANCE_PER_LEVEL: float = 0.05

var _cycle_remaining_ticks: int = 0
var _cycle_total_ticks: int = 0
var _active_input_material: int = -1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	footprint_size = Vector2i(2, 2)
	_rng.randomize()
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

func get_cycle_remaining_ticks() -> int:
	return _cycle_remaining_ticks

func get_cycle_total_ticks() -> int:
	return _cycle_total_ticks

func processing_buffer_cap() -> int:
	return _MachineUpgradeDefs.processing_buffer_cap_for(upgrade_level)

func bonus_chance() -> float:
	return clampf(BONUS_CHANCE + BONUS_CHANCE_PER_LEVEL * float(upgrade_level), 0.0, 1.0)

func get_save_data() -> Dictionary:
	var d: Dictionary = super.get_save_data()
	d["recipe_input"] = recipe_input
	d["cycle_remaining_ticks"] = _cycle_remaining_ticks
	d["cycle_total_ticks"] = _cycle_total_ticks
	d["active_input_material"] = _active_input_material
	return d

func apply_save_data(data: Dictionary) -> void:
	super.apply_save_data(data)
	recipe_input = int(data.get("recipe_input", MaterialDefs.MaterialId.STONE))
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
	# Refill processing buffer from input head while it matches the recipe.
	while processing_buffer_can_accept() and not input_queue.is_empty():
		var head: int = input_queue[0]
		if head != recipe_input:
			status = Status.INPUT_JAMMED
			return
		input_queue.pop_front()
		queue_changed.emit(QUEUE_KIND_INPUT, input_queue.size())
		processing_buffer.append(head)
		processing_changed.emit(processing_buffer.size())
	if processing_buffer.is_empty():
		status = Status.IDLE
		return
	# Need room for at LEAST one output (and ideally two, but if we only have
	# room for one we still cycle and skip the bonus).
	if not output_queue_can_accept():
		status = Status.OUTPUT_BLOCKED
		return
	if _cycle_remaining_ticks <= 0 and _active_input_material == -1:
		_active_input_material = processing_buffer[0]
		_cycle_total_ticks = apply_upgrade_to_cycle(MaterialDefs.CRUSHER_TICKS[_active_input_material])
		_cycle_remaining_ticks = _cycle_total_ticks
	if _cycle_remaining_ticks > 0:
		_cycle_remaining_ticks -= 1
		status = Status.WORKING
		return
	# Cycle complete — emit one base output. The crusher is a yield bonus
	# machine: output material == input material.
	processing_buffer.pop_front()
	processing_changed.emit(processing_buffer.size())
	output_queue_push(_active_input_material)
	item_emitted.emit(_active_input_material)
	# Bonus roll. If we don't have room for the bonus, just drop it.
	if _rng.randf() < bonus_chance() and output_queue_can_accept():
		output_queue_push(_active_input_material)
		item_emitted.emit(_active_input_material)
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
