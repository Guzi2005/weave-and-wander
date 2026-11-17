extends "res://components/simple_garment.gd"
static var _cache := {}


func rebuild() -> void:
	_pending = false
	var key := Vector4(waist_height, body_width, sleeve_length, cuff_width)
	if _cache.has(key):
		mesh = _cache[key][0]
		set_meta("garment_arm_weights", _cache[key][1])
		set_meta("torso_index_count", _cache[key][2])
		set_meta("garment_component", "fitted_nested_shell")
		geometry_rebuilt.emit()
		return
	super()
	for pass_index in 3:
		_refine()
	set_meta("garment_component", "fitted_nested_shell")
	_cache[key] = [mesh, get_meta("garment_arm_weights"), get_meta("torso_index_count")]
	geometry_rebuilt.emit()


func _refine() -> void:
	# Refine before panels sample the shell: their triangle bindings stay valid.
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var source: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var arms: PackedFloat32Array = get_meta("garment_arm_weights")
	var edges := {}
	var indices := PackedInt32Array()
	var torso_count: int = get_meta("torso_index_count", source.size())
	var refined_torso := 0
	for i in range(0, source.size(), 3):
		if i == torso_count: refined_torso = indices.size()
		var corners := [source[i], source[i + 1], source[i + 2]]
		var middle: Array[int] = []
		for j in 3:
			var a: int = corners[j]
			var b: int = corners[(j + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if points[a].distance_to(points[b]) <= .10:
				middle.append(-1)
				continue
			if not edges.has(key):
				edges[key] = points.size()
				points.append((points[a] + points[b]) * 0.5)
				normals.append((normals[a] + normals[b]).normalized())
				arms.append((arms[a] + arms[b]) * 0.5)
			middle.append(edges[key])
		if middle == [-1, -1, -1]:
			indices.append_array(PackedInt32Array(corners))
			continue
		var center := points.size()
		points.append((points[corners[0]] + points[corners[1]] + points[corners[2]]) / 3.0)
		normals.append((normals[corners[0]] + normals[corners[1]] + normals[corners[2]]).normalized())
		arms.append((arms[corners[0]] + arms[corners[1]] + arms[corners[2]]) / 3.0)
		var boundary: Array[int] = []
		for j in 3:
			boundary.append(corners[j])
			if middle[j] >= 0: boundary.append(middle[j])
		for j in boundary.size():
			indices.append_array(PackedInt32Array([center, boundary[j], boundary[(j + 1) % boundary.size()]]))
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TANGENT] = null
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	set_meta("garment_arm_weights", arms)
	set_meta("torso_index_count", refined_torso if refined_torso > 0 else indices.size())
