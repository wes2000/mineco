extends Node
## One-shot mesh extractor. Run via project_run mode="custom" with
## scene="res://scenes/tools/extract_tree_meshes.tscn". Loads each new tree
## GLB, finds the first MeshInstance3D, and saves its mesh as a .tres
## resource next to the .glb so VoxelInstanceLibraryMultiMeshItem can
## reference it. Quits the editor's game session when done.

const TREES: Array[Dictionary] = [
	{"glb": "res://assets/nature/tree_pine_a.glb",
	 "mesh_path": "res://assets/nature/tree_pine_a.mesh.tres"},
	{"glb": "res://assets/nature/tree_pine_b.glb",
	 "mesh_path": "res://assets/nature/tree_pine_b.mesh.tres"},
	{"glb": "res://assets/nature/tree_oak2.glb",
	 "mesh_path": "res://assets/nature/tree_oak2.mesh.tres"},
	{"glb": "res://assets/nature/tree_cedar.glb",
	 "mesh_path": "res://assets/nature/tree_cedar.mesh.tres"},
]

func _ready() -> void:
	for entry: Dictionary in TREES:
		var glb_path: String = entry["glb"]
		var packed: PackedScene = load(glb_path) as PackedScene
		if packed == null:
			push_warning("extract_tree_meshes: could not load %s" % glb_path)
			continue
		var inst: Node = packed.instantiate()
		var mi: MeshInstance3D = _find_mesh_instance(inst)
		if mi == null or mi.mesh == null:
			push_warning("extract_tree_meshes: no MeshInstance3D in %s" % glb_path)
			inst.queue_free()
			continue
		var mesh: Mesh = mi.mesh.duplicate(true) as Mesh
		var err: int = ResourceSaver.save(mesh, entry["mesh_path"])
		if err != OK:
			push_error("extract_tree_meshes: save failed for %s (err %d)" % [entry["mesh_path"], err])
		else:
			print("extract_tree_meshes: wrote %s (surfaces=%d)" % [entry["mesh_path"], mesh.get_surface_count()])
		inst.queue_free()
	print("extract_tree_meshes: done")
	get_tree().quit()

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c: Node in node.get_children():
		var hit: MeshInstance3D = _find_mesh_instance(c)
		if hit != null:
			return hit
	return null
