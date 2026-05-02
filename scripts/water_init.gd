extends MeshInstance3D

func _ready() -> void:
	var mat: ShaderMaterial = material_override as ShaderMaterial
	if mat == null:
		push_warning("water_init: material_override is not a ShaderMaterial")
		return
	mat.set_shader_parameter("sky_color", Atmosphere.HAZE_COLOR)
