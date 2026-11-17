extends RefCounted
## Blender-authored source geometry with live procedural enhancements
## for authentic Ukrainian costume & wavy hair faithful to the reference photo.

const SOURCE = preload("res://assets/collections/ukrainian_photo_001/blender_rebuild.json")
static var cache: Dictionary = {}

static func names() -> Array:
	return SOURCE.data.keys()

static func geometry(label: String) -> Dictionary:
	if cache.has(label): return cache[label]
	var raw: Dictionary = SOURCE.data[label]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	for p in raw.uv: uv.append(Vector2(p[0], p[1]))
	for p in raw.vertices: vertices.append(Vector3(p[0], p[1], p[2]))
	for n in raw.normals: normals.append(Vector3(n[0], n[1], n[2]))
	for c in raw.colors: colors.append(Color(c[0], c[1], c[2], c[3]))
	var result := {"uv": uv, "vertices": vertices, "normals": normals, "colors": colors,
		"indices": PackedInt32Array(raw.indices), "arm_weights": PackedFloat32Array(raw.arm_weights), "slot": raw.slot}
	cache[label] = result
	return result

static func hair(parent: Node3D, base_color: Color = Color("4c2c1a")) -> void:
	var data := geometry("ReferenceBob")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = "ReferenceBob"
	node.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/doll_costume.gdshader")
	material.set_shader_parameter("pigment", Color.WHITE)
	material.set_shader_parameter("use_vertex_color", true)
	material.set_shader_parameter("relief_strength", .16)
	node.material_override = material
	parent.add_child(node)
