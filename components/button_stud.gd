@tool
class_name HalfEllipsoidButton3D
extends MeshInstance3D

@export_range(0.005, 0.2, 0.001) var width := 0.036:
	set(value):
		width = clampf(value, 0.005, 0.2)
		_queue_rebuild()
@export_range(0.005, 0.2, 0.001) var height := 0.044:
	set(value):
		height = clampf(value, 0.005, 0.2)
		_queue_rebuild()
@export_range(0.002, 0.1, 0.001) var depth := 0.009:
	set(value):
		depth = clampf(value, 0.002, 0.1)
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
	var vertices := PackedVector3Array([Vector3(0, 0, depth)])
	var normals := PackedVector3Array([Vector3.BACK])
	var indices := PackedInt32Array()
	const SEGMENTS := 24
	const ROWS := 8
	for row in range(1, ROWS + 1):
		var phi := PI * 0.5 * row / ROWS
		for column in SEGMENTS:
			var theta := TAU * column / SEGMENTS
			vertices.append(Vector3(cos(theta) * sin(phi) * width * 0.5,
				sin(theta) * sin(phi) * height * 0.5, 0.0 if row == ROWS else cos(phi) * depth))
			normals.append(Vector3(cos(theta) * sin(phi) / (width * 0.5),
				sin(theta) * sin(phi) / (height * 0.5), cos(phi) / depth).normalized())
	for column in SEGMENTS:
		indices.append_array(PackedInt32Array([0, 1 + (column + 1) % SEGMENTS, 1 + column]))
	for row in ROWS - 1:
		for column in SEGMENTS:
			var a := 1 + row * SEGMENTS + column
			var b := 1 + row * SEGMENTS + (column + 1) % SEGMENTS
			indices.append_array(PackedInt32Array([a, b, a + SEGMENTS, b, b + SEGMENTS, a + SEGMENTS]))
	# Flat backing is real geometry, not the buried half of a sphere.
	var center := vertices.size()
	vertices.append(Vector3.ZERO)
	normals.append(Vector3.FORWARD)
	for column in SEGMENTS:
		vertices.append(vertices[1 + (ROWS - 1) * SEGMENTS + column])
		normals.append(Vector3.FORWARD)
	for column in SEGMENTS:
		indices.append_array(PackedInt32Array([center, center + 1 + column, center + 1 + (column + 1) % SEGMENTS]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = result
	set_meta("garment_component", "half_ellipsoid_button")
