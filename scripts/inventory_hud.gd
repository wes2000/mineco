extends Label

@export var miner_path: NodePath = "/root/Main/Player/Miner"

var _miner: Node = null

func _ready() -> void:
	_miner = get_node_or_null(miner_path)
	if _miner == null:
		push_error("InventoryHUD: Miner not found at " + str(miner_path))
		return
	_miner.inventory_changed.connect(_on_changed)
	if _miner.has_signal("extended_inventory_changed"):
		_miner.extended_inventory_changed.connect(_refresh)
	_refresh()

func _on_changed(_s: int, _i: int, _g: int) -> void:
	_refresh()

func _refresh() -> void:
	if _miner == null:
		return
	text = "T1  Stone: %d   Iron Ore: %d   Gold Ore: %d\nT2  Brick: %d   Iron Ingot: %d   Gold Ingot: %d\nT3  Block: %d   Iron Bar: %d   Gold Bar: %d" % [
		_miner.stone, _miner.iron, _miner.gold,
		_miner.brick, _miner.iron_ingot, _miner.gold_ingot,
		_miner.block, _miner.iron_bar, _miner.gold_bar,
	]
