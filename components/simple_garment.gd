@tool
class_name SimpleDollGarment3D
extends "res://components/garment_shell.gd"


func rebuild() -> void:
	_pending = false
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var body := [Vector3(waist_height, 0.285, 0.202), Vector3(1.52, 0.263, 0.194),
		Vector3(1.72, 0.252, 0.18), Vector3(1.83, 0.21, 0.145),
		Vector3(1.90, 0.15, 0.11), Vector3(1.93, 0.105, 0.095)]
	_append_part(body, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, vertices, normals, indices, arm_weights)
	set_meta("torso_index_count", indices.size())
	for side in [-1.0, 1.0]:
		# Simple nested forms match the approved doll, without a sculpted armpit patch.
		# Extra rings at the elbow/shoulder preserve a continuous bend without
		# changing the approved bell-sleeve silhouette or adding a shoulder ball.
		var sleeve := [Vector3(1.195,.14,.144),Vector3(1.35,.124,.13),
			Vector3(1.42,.111,.123),Vector3(1.48,.100,.118),Vector3(1.55,.087,.111),
			Vector3(1.64,.083,.103),Vector3(1.72,.080,.095),Vector3(1.78,.069,.081),
			Vector3(1.83,.060,.070)]
		var centers := [.30,.286,.276,.268,.258,.225,.195,.165,.14]
		for i in sleeve.size():
			var influence := 1.0 - smoothstep(1.20, 1.80, sleeve[i].x)
			sleeve[i].y *= lerpf(1.0, cuff_width, influence)
			sleeve[i].z *= lerpf(1.0, cuff_width, influence)
			sleeve[i].x = 1.83 - (1.83 - sleeve[i].x) * sleeve_length
			centers[i] *= side
		_append_part(sleeve, centers, side, vertices, normals, indices, arm_weights)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = result
	set_meta("garment_component", "simple_shell")
	set_meta("garment_arm_weights", arm_weights)
	geometry_rebuilt.emit()


func _append_part(rings: Array, centers: Array, side: float, vertices: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> void:
	const SEGMENTS := 32
	var start := vertices.size()
	for row in rings.size():
		var ring: Vector3 = rings[row]
		var previous: Vector3 = rings[maxi(row - 1, 0)]
		var next: Vector3 = rings[mini(row + 1, rings.size() - 1)]
		var dy := maxf(next.x - previous.x, 0.001)
		var dx: float = (centers[mini(row + 1, rings.size() - 1)] - centers[maxi(row - 1, 0)]) * body_width
		for column in SEGMENTS:
			var angle := TAU * column / SEGMENTS
			var point := Vector3((centers[row] + sin(angle) * ring.y) * body_width, ring.x, cos(angle) * ring.z)
			var normal := Vector3(sin(angle) / (ring.y * body_width), 0, cos(angle) / ring.z)
			normal.y = -(normal.x * (dx + sin(angle) * (next.y - previous.y) * body_width)
				+ normal.z * cos(angle) * (next.z - previous.z)) / dy
			vertices.append(point)
			normals.append(normal.normalized())
			arm_weights.append(side * (1.0 - smoothstep(1.63, 1.83, point.y)))
	for row in rings.size() - 1:
		for column in SEGMENTS:
			var a := start + row * SEGMENTS + column
			var b := start + (row + 1) * SEGMENTS + column
			var c := start + row * SEGMENTS + (column + 1) % SEGMENTS
			var d := start + (row + 1) * SEGMENTS + (column + 1) % SEGMENTS
			indices.append_array(PackedInt32Array([a, b, c, c, b, d]))
