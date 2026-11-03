class_name PaperArt
extends RefCounted

const PAPER_SHADER: Shader = preload("res://shaders/paper.gdshader")
const INK := Color("4b3530")


static func material(color: Color, grain_strength: float = 0.03) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = PAPER_SHADER
	result.set_shader_parameter("base_color", color)
	result.set_shader_parameter("grain_strength", grain_strength)
	return result


static func standard_material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 1.0
	result.metallic = 0.0
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result


static func box(
		name_value: String,
		size: Vector3,
		color: Color,
		position_value: Vector3 = Vector3.ZERO,
		rotation_degrees_value: Vector3 = Vector3.ZERO
	) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_value
	var mesh_value := BoxMesh.new()
	mesh_value.size = size
	node.mesh = mesh_value
	node.material_override = material(color)
	node.position = position_value
	node.rotation_degrees = rotation_degrees_value
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


static func cylinder(
		name_value: String,
		radius: float,
		height: float,
		color: Color,
		position_value: Vector3 = Vector3.ZERO,
		radial_segments: int = 20
	) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_value
	var mesh_value := CylinderMesh.new()
	mesh_value.top_radius = radius
	mesh_value.bottom_radius = radius
	mesh_value.height = height
	mesh_value.radial_segments = radial_segments
	node.mesh = mesh_value
	node.material_override = material(color)
	node.position = position_value
	return node


static func flat_shape(
		name_value: String,
		points: PackedVector2Array,
		color: Color,
		z_offset: float = 0.0,
		outline_width: float = 0.035,
		outline_color: Color = INK
	) -> Node3D:
	var root := Node3D.new()
	root.name = name_value
	if outline_width > 0.0:
		var outline := MeshInstance3D.new()
		outline.name = "InkEdge"
		outline.mesh = _polygon_mesh(_expand_polygon(points, outline_width))
		outline.material_override = material(outline_color, 0.025)
		outline.position.z = z_offset - 0.006
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(outline)
	var fill := MeshInstance3D.new()
	fill.name = "Paper"
	fill.mesh = _polygon_mesh(points)
	fill.material_override = material(color)
	fill.position.z = z_offset
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(fill)
	return root


static func circle_points(center: Vector2, radius: float, segments: int = 24, y_scale: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments:
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * y_scale))
	return points


static func rounded_rect_points(rect: Rect2, radius: float, corner_steps: int = 4) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers := [
		Vector2(rect.end.x - radius, rect.position.y + radius),
		Vector2(rect.end.x - radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.position.y + radius),
	]
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner in 4:
		for step in corner_steps + 1:
			var angle: float = starts[corner] + (PI * 0.5 * float(step) / float(corner_steps))
			points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _polygon_mesh(points: PackedVector2Array) -> ArrayMesh:
	var mesh_value := ArrayMesh.new()
	if points.size() < 3:
		return mesh_value
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var min_point := points[0]
	var max_point := points[0]
	for point in points:
		min_point.x = min(min_point.x, point.x)
		min_point.y = min(min_point.y, point.y)
		max_point.x = max(max_point.x, point.x)
		max_point.y = max(max_point.y, point.y)
	var dimensions := max_point - min_point
	dimensions.x = max(dimensions.x, 0.001)
	dimensions.y = max(dimensions.y, 0.001)
	for point in points:
		vertices.append(Vector3(point.x, point.y, 0.0))
		normals.append(Vector3(0.0, 0.0, 1.0))
		uvs.append((point - min_point) / dimensions)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(points)
	mesh_value.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh_value


static func _expand_polygon(points: PackedVector2Array, width: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= float(max(points.size(), 1))
	var expanded := PackedVector2Array()
	for point in points:
		var direction := point - center
		var distance := direction.length()
		if distance > 0.0001:
			expanded.append(point + direction / distance * width)
		else:
			expanded.append(point)
	return expanded
