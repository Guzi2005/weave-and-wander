extends RefCounted


static func bind_layer(layer: MeshInstance3D, sources: Array) -> void:
	var arrays := layer.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var triangles: PackedInt32Array = layer.get_meta("skin_layer_triangles", PackedInt32Array())
	var barycentric: PackedVector3Array = layer.get_meta("skin_layer_barycentric", PackedVector3Array())
	var authored_source_ids: PackedInt32Array = layer.get_meta("skin_layer_source_index", PackedInt32Array())
	var source_ids := PackedInt32Array()
	var surfaces: Array = []
	for source in sources:
		var surface: Array = source.mesh.surface_get_arrays(0)
		if surface[Mesh.ARRAY_INDEX] == null:
			surface[Mesh.ARRAY_INDEX] = PackedInt32Array(range(surface[Mesh.ARRAY_VERTEX].size()))
		surfaces.append(surface)
	var authored := triangles.size() == vertices.size() * 3 and barycentric.size() == vertices.size()
	var unmapped := 0
	for i in vertices.size():
		var source_index := 0
		var triangle: PackedInt32Array
		var bary: Vector3
		if authored:
			triangle = triangles.slice(i * 3, i * 3 + 3)
			bary = barycentric[i]
			if authored_source_ids.size() == vertices.size():
				source_index = authored_source_ids[i]
		else:
			var hit := _project_front(vertices[i], surfaces)
			if hit.is_empty():
				unmapped += 1
				source_ids.append(-1)
				triangles.append_array(PackedInt32Array([0, 0, 0]))
				barycentric.append(Vector3.ZERO)
				continue
			source_index = hit[0]
			triangle = hit[1]
			bary = hit[2]
			triangles.append_array(triangle)
			barycentric.append(bary)
		source_ids.append(source_index)
		var surface: Array = surfaces[source_index]
		if not authored and layer.has_meta("skin_layer_clearance"):
			var source_vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = surface[Mesh.ARRAY_NORMAL]
			var contact := Vector3.ZERO
			var normal := Vector3.ZERO
			for corner in 3:
				contact += source_vertices[triangle[corner]] * bary[corner]
				normal += source_normals[triangle[corner]] * bary[corner]
			vertices[i].z = contact.z + float(layer.get_meta("skin_layer_clearance"))
			normals[i] = normal.normalized()
		var inherited := interpolate_weights(surface, triangle, bary)
		for slot in 4:
			ids[i * 4 + slot] = inherited[0][slot]
			weights[i * 4 + slot] = inherited[1][slot]
	arrays[Mesh.ARRAY_BONES] = ids
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	layer.mesh = mesh
	var paths := PackedStringArray()
	for source in sources:
		paths.append(str(layer.get_path_to(source)))
	layer.set_meta("skin_layer_sources", paths)
	layer.set_meta("skin_layer_triangles", triangles)
	layer.set_meta("skin_layer_barycentric", barycentric)
	layer.set_meta("skin_layer_source_index", source_ids)
	layer.set_meta("skin_layer_unmapped", unmapped)
	if unmapped > 0:
		push_warning("Unmapped clothing vertices on %s: %d" % [layer.name, unmapped])


static func interpolate_weights(surface: Array, triangle: PackedInt32Array, bary: Vector3) -> Array:
	var source_bones: PackedInt32Array = surface[Mesh.ARRAY_BONES]
	var source_weights: PackedFloat32Array = surface[Mesh.ARRAY_WEIGHTS]
	var combined: Dictionary = {}
	for corner in 3:
		for slot in 4:
			var index := triangle[corner] * 4 + slot
			var bone := source_bones[index]
			var weight := source_weights[index] * bary[corner]
			combined[bone] = combined.get(bone, 0.0) + maxf(weight, 0.0)
	var ranked: Array = combined.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		return a < b if is_equal_approx(combined[a], combined[b]) else combined[a] > combined[b])
	var ids := PackedInt32Array([0, 0, 0, 0])
	var weights := PackedFloat32Array([0, 0, 0, 0])
	var total := 0.0
	for slot in mini(4, ranked.size()):
		ids[slot] = ranked[slot]
		weights[slot] = combined[ranked[slot]]
		total += weights[slot]
	for slot in 4:
		weights[slot] /= maxf(total, 0.000001)
	return [ids, weights]


static func _project_front(point: Vector3, surfaces: Array) -> Array:
	var closest_z := -INF
	var result: Array = []
	for source_index in surfaces.size():
		var surface: Array = surfaces[source_index]
		var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			if point.x < minf(a.x, minf(b.x, c.x)) - 0.00001 or point.x > maxf(a.x, maxf(b.x, c.x)) + 0.00001:
				continue
			if point.y < minf(a.y, minf(b.y, c.y)) - 0.00001 or point.y > maxf(a.y, maxf(b.y, c.y)) + 0.00001:
				continue
			var hit = Geometry3D.segment_intersects_triangle(Vector3(point.x, point.y, 2), Vector3(point.x, point.y, -2), a, b, c)
			if hit != null and hit.z > closest_z:
				closest_z = hit.z
				result = [source_index, indices.slice(i, i + 3), Geometry3D.get_triangle_barycentric_coords(hit, a, b, c)]
	return result
