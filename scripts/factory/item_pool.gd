class_name ItemPool
extends Node
## Per-material pool of FactoryItem instances. Created by FactoryWorld.

const ITEM_SCENE_PATHS: Dictionary = {
	0: "res://scenes/factory/item_stone.tscn",
	1: "res://scenes/factory/item_brick.tscn",
	2: "res://scenes/factory/item_block.tscn",
	3: "res://scenes/factory/item_iron_ore.tscn",
	4: "res://scenes/factory/item_iron_ingot.tscn",
	5: "res://scenes/factory/item_iron_bar.tscn",
	6: "res://scenes/factory/item_gold_ore.tscn",
	7: "res://scenes/factory/item_gold_ingot.tscn",
	8: "res://scenes/factory/item_gold_bar.tscn",
}

var _free: Dictionary = {}     # material_id -> Array[FactoryItem]
var _scenes: Dictionary = {}   # material_id -> PackedScene (cached)

func _ready() -> void:
	for mid: int in ITEM_SCENE_PATHS:
		_free[mid] = []
		_scenes[mid] = load(ITEM_SCENE_PATHS[mid]) as PackedScene

func acquire(material_id: int) -> FactoryItem:
	var pool: Array = _free.get(material_id, [])
	var item: FactoryItem
	if pool.is_empty():
		item = (_scenes[material_id] as PackedScene).instantiate() as FactoryItem
		add_child(item)
	else:
		item = pool.pop_back() as FactoryItem
	item.visible = true
	item.set_process(true)
	return item

func release(item: FactoryItem) -> void:
	item.visible = false
	item.set_process(false)
	_free[item.material_id].append(item)
