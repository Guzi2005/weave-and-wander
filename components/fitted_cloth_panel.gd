extends RefCounted


static func front_volumes(rows: Array) -> Array:
	var volumes: Array = []
	for index in rows.size()-1:
		var a: Vector3 = rows[index]
		var b: Vector3 = rows[index+1]
		var slope := (b.y-a.y)/(b.x-a.x)
		var intercept := a.y-slope*a.x
		volumes.append([Plane(Vector3.UP,a.x),Plane(Vector3.DOWN,-b.x),
			Plane(Vector3(1,slope,0),-intercept),Plane(Vector3(-1,slope,0),-intercept),
			Plane(Vector3.BACK,0)])
	return volumes


static func build(target: MeshInstance3D, sources: Array, volumes: Array, gap: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var triangles := PackedInt32Array()
	var barycentric := PackedVector3Array()
	var source_ids := PackedInt32Array()
	var paths := PackedStringArray()
	for source_index in sources.size():
		var rule: Dictionary = sources[source_index]
		var source: MeshInstance3D = rule.mesh
		paths.append(str(target.get_path_to(source)))
		var arrays := source.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var directions: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(points.size()))
		var count: int = source.get_meta("torso_index_count",indices.size())
		for offset in range(0,count,3):
			var ids := indices.slice(offset,offset+3)
			var triangle: Array = []
			for corner in 3:
				var bary := Vector3.ZERO
				bary[corner] = 1.0
				triangle.append([points[ids[corner]],directions[ids[corner]],bary])
			triangle = _clip(triangle,Plane(Vector3.UP,rule.get("bottom",-INF)))
			triangle = _clip(triangle,Plane(Vector3.DOWN,-rule.get("top",INF)))
			for volume in volumes:
				var polygon: Array = triangle
				for plane in volume:
					polygon = _clip(polygon,plane)
				# Preserve every underlying triangle edge; a coarse overlay can cut through its own source.
				for fan in range(1,polygon.size()-1):
					for value in [polygon[0],polygon[fan],polygon[fan+1]]:
						var normal: Vector3 = value[1].normalized()
						vertices.append(value[0]+normal*gap)
						normals.append(normal)
						triangles.append_array(ids)
						barycentric.append(value[2])
						source_ids.append(source_index)
	var result := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(range(vertices.size()))
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	target.mesh = result
	target.set_meta("skin_layer_sources",paths)
	target.set_meta("skin_layer_triangles",triangles)
	target.set_meta("skin_layer_barycentric",barycentric)
	target.set_meta("skin_layer_source_index",source_ids)
	target.set_meta("garment_component","fitted_cloth_panel")


static func _clip(polygon: Array, plane: Plane) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Array = polygon.back()
	var before := plane.distance_to(previous[0])
	for current in polygon:
		var after := plane.distance_to(current[0])
		if (before >= 0.0) != (after >= 0.0):
			var weight := before/(before-after)
			result.append([previous[0].lerp(current[0],weight),previous[1].lerp(current[1],weight),previous[2].lerp(current[2],weight)])
		if after >= 0.0:
			result.append(current)
		previous = current
		before = after
	return result
