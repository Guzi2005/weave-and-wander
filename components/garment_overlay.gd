@tool
class_name FittedWaistcoat3D
extends MeshInstance3D

@export var mount_surface: NodePath:
	set(value):
		mount_surface = value
		_queue_rebuild()
@export_range(0.10, 0.5, 0.01) var front_opening := 0.23:
	set(value):
		front_opening = clampf(value, 0.1, 0.5)
		_queue_rebuild()
@export_range(0.08, 0.35, 0.01) var armhole_cut := 0.30:
	set(value):
		armhole_cut = clampf(value, 0.08, 0.35)
		_queue_rebuild()
@export var border_material: Material:
	set(value):
		border_material = value
		_queue_rebuild()
@export_range(0.002, 0.03, 0.001) var layer_gap := 0.011:
	set(value):
		layer_gap = clampf(value, 0.002, 0.03)
		_queue_rebuild()

var _pending := false


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if is_inside_tree() and not _pending:
		_pending = true
		rebuild.call_deferred()


func rebuild() -> void:
	_pending = false
	var source := get_node_or_null(mount_surface) as MeshInstance3D if not mount_surface.is_empty() else null
	if source == null or source.mesh == null or not source.has_meta("garment_arm_weights"):
		return
	if source.has_signal("geometry_rebuilt") and not source.is_connected("geometry_rebuilt", _queue_rebuild):
		source.connect("geometry_rebuilt", _queue_rebuild)
	for child in get_children(): child.free()
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var arm_weights: PackedFloat32Array = source.get_meta("garment_arm_weights")
	var cloth: Array = []
	var border: Array = []
	# A sleeveless overlay belongs to the torso, not the nested sleeve caps.
	# Sleeve triangles fold through the armhole during a relaxed hanging arm.
	var torso_count: int = source.get_meta("torso_index_count",indices.size())
	for i in range(0, torso_count, 3):
		var polygon: Array = []
		for corner in 3:
			var index := indices[i + corner]
			var bary := Vector3.ZERO
			bary[corner] = 1.0
			polygon.append([vertices[index], normals[index], arm_weights[index], indices.slice(i, i + 3), bary])
		for plane in 3:
			polygon = _clip(polygon, plane)
		cloth.append_array(_triangulate(polygon))
		border.append_array(_triangulate(_clip(polygon, 3)))
	_install(self, cloth, layer_gap)
	var binding := MeshInstance3D.new()
	binding.name = "FrontBinding"
	binding.material_override = border_material
	_install(binding, border, layer_gap + 0.003)
	add_child(binding)
	set_meta("skin_layer_sources", PackedStringArray([str(get_path_to(source))]))
	binding.set_meta("skin_layer_sources", PackedStringArray([str(binding.get_path_to(source))]))
	set_meta("garment_component", "fitted_waistcoat")


func _distance(vertex: Array, plane: int) -> float:
	var point: Vector3 = vertex[0]
	var opening := front_opening + smoothstep(1.48, 1.89, point.y) * 0.61
	var angle := absf(atan2(point.x, point.z))
	match plane:
		0: return armhole_cut - absf(vertex[2])
		1: return angle - opening
		2: return point.y - 1.05
		_: return opening + 0.055 - angle


func _clip(polygon: Array, plane: int) -> Array:
	var result: Array = []
	if polygon.is_empty(): return result
	var previous: Array = polygon.back()
	var before := _distance(previous, plane)
	for current in polygon:
		var after := _distance(current, plane)
		if (before >= 0) != (after >= 0):
			var weight := before / (before - after)
			result.append([previous[0].lerp(current[0], weight),
				previous[1].lerp(current[1], weight).normalized(), lerpf(previous[2], current[2], weight),
				previous[3], previous[4].lerp(current[4], weight)])
		if after >= 0: result.append(current)
		previous = current
		before = after
	return result


func _triangulate(polygon: Array) -> Array:
	var triangles: Array = []
	for i in range(1, polygon.size() - 1):
		triangles.append_array([polygon[0], polygon[i], polygon[i + 1]])
	return triangles


func _install(instance: MeshInstance3D, triangles: Array, offset: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var arm_weights := PackedFloat32Array()
	var source_triangles := PackedInt32Array()
	var source_barycentric := PackedVector3Array()
	for vertex in triangles:
		vertices.append(vertex[0] + vertex[1] * offset)
		normals.append(vertex[1])
		arm_weights.append(vertex[2])
		source_triangles.append_array(vertex[3])
		source_barycentric.append(vertex[4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var result := ArrayMesh.new()
	if not vertices.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = result
	instance.set_meta("garment_arm_weights", arm_weights)
	instance.set_meta("skin_layer_triangles", source_triangles)
	instance.set_meta("skin_layer_barycentric", source_barycentric)
