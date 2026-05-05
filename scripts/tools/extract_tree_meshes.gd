extends Node
## One-shot mesh extractor. Run via project_run mode="custom" with
## scene="res://scenes/tools/extract_tree_meshes.tscn". Loads each new tree
## GLB, finds the first MeshInstance3D, and saves its mesh as a .tres
## resource next to the .glb so VoxelInstanceLibraryMultiMeshItem can
## reference it. Quits the editor's game session when done.

const TREES: Array[Dictionary] = [
	# Trees
	{"glb": "res://assets/nature/megakit/CommonTree_1.gltf",
	 "mesh_path": "res://assets/nature/megakit/CommonTree_1.mesh.tres"},
	{"glb": "res://assets/nature/megakit/CommonTree_3.gltf",
	 "mesh_path": "res://assets/nature/megakit/CommonTree_3.mesh.tres"},
	{"glb": "res://assets/nature/megakit/Pine_1.gltf",
	 "mesh_path": "res://assets/nature/megakit/Pine_1.mesh.tres"},
	{"glb": "res://assets/nature/megakit/Pine_3.gltf",
	 "mesh_path": "res://assets/nature/megakit/Pine_3.mesh.tres"},
	{"glb": "res://assets/nature/megakit/TwistedTree_2.gltf",
	 "mesh_path": "res://assets/nature/megakit/TwistedTree_2.mesh.tres"},
	# Bushes
	{"glb": "res://assets/nature/megakit/Bush_Common.gltf",
	 "mesh_path": "res://assets/nature/megakit/Bush_Common.mesh.tres"},
	{"glb": "res://assets/nature/megakit/Bush_Common_Flowers.gltf",
	 "mesh_path": "res://assets/nature/megakit/Bush_Common_Flowers.mesh.tres"},
	{"glb": "res://assets/nature/megakit/Fern_1.gltf",
	 "mesh_path": "res://assets/nature/megakit/Fern_1.mesh.tres"},
	# Grass
	{"glb": "res://assets/nature/megakit/Grass_Common_Tall.gltf",
	 "mesh_path": "res://assets/nature/megakit/Grass_Common_Tall.mesh.tres"},
	{"glb": "res://assets/nature/megakit/Grass_Wispy_Tall.gltf",
	 "mesh_path": "res://assets/nature/megakit/Grass_Wispy_Tall.mesh.tres"},
	{"glb": "res://assets/nature/megakit/Clover_1.gltf",
	 "mesh_path": "res://assets/nature/megakit/Clover_1.mesh.tres"},
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
		var src_mesh: Mesh = mi.mesh
		# Bake the GLB pivot up so the mesh's AABB bottom sits at y=0.
		# VoxelInstanceLibraryMultiMeshItem has no per-item transform offset,
		# so trees authored centered on the origin would render half buried.
		var lift: float = -src_mesh.get_aabb().position.y
		var mesh: ArrayMesh = _lift_mesh(src_mesh, lift)
		var err: int = ResourceSaver.save(mesh, entry["mesh_path"])
		if err != OK:
			push_error("extract_tree_meshes: save failed for %s (err %d)" % [entry["mesh_path"], err])
		else:
			print("extract_tree_meshes: wrote %s (surfaces=%d)" % [entry["mesh_path"], mesh.get_surface_count()])
		inst.queue_free()
	print("extract_tree_meshes: done")
	get_tree().quit()

# Returns a copy of `src` with every vertex shifted by (0, lift, 0) and any
# vertex colors neutralized to white. The MegaKit trees ship with red/orange
# autumn vertex colors that multiply against the leaf texture and turn the
# foliage muddy red — flattening to white lets the texture's own color show.
func _lift_mesh(src: Mesh, lift: float) -> ArrayMesh:
	var out: ArrayMesh = ArrayMesh.new()
	for s: int in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var lifted: PackedVector3Array = PackedVector3Array()
		lifted.resize(verts.size())
		for i: int in verts.size():
			var v: Vector3 = verts[i]
			lifted[i] = Vector3(v.x, v.y + lift, v.z)
		arrays[Mesh.ARRAY_VERTEX] = lifted
		# Strip the vertex-color attribute. The MegaKit trees ship with
		# autumn-tinted COLOR_0 data, and voxel-tools' MultiMesh rendering
		# multiplies it against the leaf texture even though the StandardMaterial3D
		# has vertex_color_use_as_albedo = false, so trees came out muddy red.
		# Removing the attribute entirely means there's nothing to multiply.
		arrays[Mesh.ARRAY_COLOR] = null
		var primitive: int = src.surface_get_primitive_type(s)
		out.add_surface_from_arrays(primitive, arrays)
		var mat: Material = src.surface_get_material(s)
		if mat != null:
			out.surface_set_material(s, mat)
	return out

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c: Node in node.get_children():
		var hit: MeshInstance3D = _find_mesh_instance(c)
		if hit != null:
			return hit
	return null
