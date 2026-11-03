extends RefCounted
## One render policy for worn accessories, garments and hand-held craft objects.
## Source recipes retain physical material parameters; game output is flat ink.
const SHADER = preload("res://shaders/doll_costume.gdshader")

static func from_source(source: Material) -> Material:
	if not source is StandardMaterial3D: return source
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.resource_name = "Flat ink / " + source.resource_name
	mat.set_shader_parameter("pigment", source.albedo_color)
	mat.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
	mat.set_shader_parameter("use_pigment_map", source.albedo_texture != null)
	if source.albedo_texture != null:
		mat.set_shader_parameter("pigment_map", source.albedo_texture)
	mat.set_meta("render_policy", "ww-flat-ink-v1")
	mat.set_meta("source_material", source.resource_name)
	return mat

static func apply_to(root: Node) -> void:
	for part: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if part.material_override != null:
			part.material_override = from_source(part.material_override)
