class_name FactoryDrop
extends RigidBody3D
## Physics-enabled material drop. Spawned when a belt dead-ends or a building/belt is removed.

@export var material_id: int = -1

const COLORS: Dictionary = {
	0: Color(0.6, 0.6, 0.6),    # STONE
	1: Color(0.7, 0.35, 0.25),  # BRICK
	2: Color(0.4, 0.4, 0.4),    # BLOCK
	3: Color(0.55, 0.4, 0.3),   # IRON_ORE
	4: Color(0.7, 0.7, 0.75),   # IRON_INGOT
	5: Color(0.85, 0.85, 0.9),  # IRON_BAR
	6: Color(0.7, 0.6, 0.2),    # GOLD_ORE
	7: Color(0.95, 0.8, 0.3),   # GOLD_INGOT
	8: Color(1.0, 0.85, 0.4),   # GOLD_BAR
}

func _ready() -> void:
	add_to_group("factory_drops")
	# Re-color the mesh based on material_id
	var mesh: MeshInstance3D = $Mesh as MeshInstance3D
	if mesh != null and COLORS.has(material_id):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = COLORS[material_id]
		mesh.material_override = mat
