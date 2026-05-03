extends Node3D
## Walks all GeometryInstance3D descendants on _ready and sets a visibility
## range so distant rocks/buildings/dock planks don't pop into view before
## the surrounding voxel terrain has had time to mesh.

@export var range_end: float = 192.0
@export var fade_margin: float = 24.0

func _ready() -> void:
	_apply(self)

func _apply(node: Node) -> void:
	if node is GeometryInstance3D:
		var g: GeometryInstance3D = node
		g.visibility_range_end = range_end
		g.visibility_range_end_margin = fade_margin
	for c: Node in node.get_children():
		_apply(c)
