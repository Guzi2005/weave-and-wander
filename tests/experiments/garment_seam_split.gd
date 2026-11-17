extends RefCounted

const SkinBinding = preload("res://scripts/layer_skin_binding.gd")


static func _append_edge(arrays: Array, a: int, b: int, t: float, skin_source: Array = []) -> void:
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[slot] == null: continue
		var value = arrays[slot][a].lerp(arrays[slot][b], t)
		if slot == Mesh.ARRAY_NORMAL: value = value.normalized()
		arrays[slot].append(value)
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var first := Vector3(tangents[a * 4], tangents[a * 4 + 1], tangents[a * 4 + 2])
		var second := Vector3(tangents[b * 4], tangents[b * 4 + 1], tangents[b * 4 + 2])
		var tangent := first.lerp(second, t)
		var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][-1]
		tangent = (tangent - normal * tangent.dot(normal)).normalized()
		arrays[Mesh.ARRAY_TANGENT].append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, tangents[a * 4 + 3]]))
	if not skin_source.is_empty():
		var skin := SkinBinding.interpolate_weights(skin_source, PackedInt32Array([a, b, b]), Vector3(1.0 - t, t, 0.0))
		arrays[Mesh.ARRAY_BONES].append_array(skin[0])
		arrays[Mesh.ARRAY_WEIGHTS].append_array(skin[1])


static func split(mesh: ArrayMesh, height: float) -> Dictionary:
	if mesh == null or not is_finite(height) or mesh.get_surface_count() != 1:
		return {"error": "Expected one garment surface and a finite seam height"}
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES or mesh.blend_shape_mode != Mesh.BLEND_SHAPE_MODE_NORMALIZED:
		return {"error": "Expected normalized triangle garment"}
	var source := mesh.surface_get_arrays(0)
	for slot in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		if source[slot] != null: return {"error": "Unsupported garment stream; preserve it before splitting"}
	if source[Mesh.ARRAY_VERTEX] == null or source[Mesh.ARRAY_NORMAL] == null or source[Mesh.ARRAY_INDEX] == null:
		return {"error": "Missing indexed garment geometry"}
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var old_indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	if source[Mesh.ARRAY_TANGENT] != null and source[Mesh.ARRAY_TANGENT].size() != points.size() * 4:
		return {"error": "Invalid tangent stream"}
	if source[Mesh.ARRAY_BONES] == null or source[Mesh.ARRAY_WEIGHTS] == null or source[Mesh.ARRAY_BONES].size() != points.size() * 4 or source[Mesh.ARRAY_WEIGHTS].size() != points.size() * 4:
		return {"error": "Expected four skin influences per vertex"}
	var arrays := source.duplicate(true)
	var shapes: Array = mesh.surface_get_blend_shape_arrays(0).duplicate(true)
	var edges := {}
	var bindings: Array = []
	var indices := PackedInt32Array()
	var cut_faces := 0
	for face in range(0, old_indices.size(), 3):
		var ids := old_indices.slice(face, face + 3)
		var low := minf(points[ids[0]].y, minf(points[ids[1]].y, points[ids[2]].y))
		var high := maxf(points[ids[0]].y, maxf(points[ids[1]].y, points[ids[2]].y))
		if not (low < height - .0000001 and high > height + .0000001):
			indices.append_array(ids)
			continue
		cut_faces += 1
		for side in [-1.0, 1.0]:
			var polygon: Array[int] = []
			for corner in 3:
				var a := ids[corner]
				var b := ids[(corner + 1) % 3]
				var da: float = (points[a].y - height) * side
				var db: float = (points[b].y - height) * side
				if da >= -.0000001: polygon.append(a)
				if (da < -.0000001 and db > .0000001) or (da > .0000001 and db < -.0000001):
					var edge := Vector2i(mini(a, b), maxi(a, b))
					if not edges.has(edge):
						if source[Mesh.ARRAY_TANGENT] != null and source[Mesh.ARRAY_TANGENT][edge.x * 4 + 3] != source[Mesh.ARRAY_TANGENT][edge.y * 4 + 3]:
							return {"error": "Cannot interpolate across a tangent handedness seam"}
						var t := (height - points[edge.x].y) / (points[edge.y].y - points[edge.x].y)
						var id: int = arrays[Mesh.ARRAY_VERTEX].size()
						edges[edge] = id
						_append_edge(arrays, edge.x, edge.y, t, source)
						for shape: Array in shapes: _append_edge(shape, edge.x, edge.y, t)
						bindings.append({"index": id, "edge": [edge.x, edge.y], "weight": t})
					polygon.append(edges[edge])
			for fan in range(1, polygon.size() - 1):
				indices.append_array(PackedInt32Array([polygon[0], polygon[fan], polygon[fan + 1]]))
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.blend_shape_mode = mesh.blend_shape_mode
	for shape in mesh.get_blend_shape_count(): result.add_blend_shape(mesh.get_blend_shape_name(shape))
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	result.surface_set_material(0, mesh.surface_get_material(0))
	return {"error": "", "mesh": result, "height": height, "original_vertices": points.size(),
		"added_vertices": bindings.size(), "cut_faces": cut_faces, "edge_bindings": bindings}
