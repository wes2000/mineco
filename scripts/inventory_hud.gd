extends Label

@export var miner_path: NodePath = "/root/Main/Player/Miner"

func _ready() -> void:
	var miner: Node = get_node_or_null(miner_path)
	if miner == null:
		push_error("InventoryHUD: Miner not found at " + str(miner_path))
		return
	miner.inventory_changed.connect(_on_changed)
	# Read initial state directly — sidesteps _ready ordering between Miner and HUD.
	_on_changed(miner.stone, miner.iron, miner.gold)

func _on_changed(s: int, i: int, g: int) -> void:
	text = "Stone: %d   Iron: %d   Gold: %d" % [s, i, g]
