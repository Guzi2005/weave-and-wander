extends RefCounted

var sections: Array = []
var section_names: Array[String] = []


static func model_transform(part: Node3D, root: Node3D) -> Transform3D:
	var result := part.transform
	var parent := part.get_parent() as Node3D
	while parent != root:
		result = parent.transform * result
		parent = parent.get_parent() as Node3D
	return result


func read_body(model: Node3D) -> void:
	sections.clear()
	section_names.clear()
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if str(part.name) not in ["MannequinTorso", "ArmMannequin", "LegMannequin"]:
			continue
		var rows := {}
		var transform := model_transform(part, model)
		for vertex: Vector3 in part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var p := transform * vertex
			var key := roundi(p.y * 100000)
			if not rows.has(key): rows[key] = AABB(p, Vector3.ZERO)
			rows[key] = rows[key].expand(p)
		var keys := rows.keys()
		keys.sort()
		var profile: Array = []
		for key in keys:
			var bounds: AABB = rows[key]
			if minf(bounds.size.x, bounds.size.z) < 0.005: continue
			profile.append([bounds.get_center(), Vector2(bounds.size.x, bounds.size.z) * 0.5])
		sections.append(profile)
		section_names.append(str(part.name))


func project(point: Vector3, gap: float, region := "torso") -> Vector3:
	# Conservative ring envelopes come from the accepted mesh, never resize it.
	for iteration in 3:
		for section_index in sections.size():
			if section_names[section_index] == "ArmMannequin" and region != "arm": continue
			if section_names[section_index] != "ArmMannequin" and region == "arm": continue
			var profile: Array = sections[section_index]
			if point.y < profile[0][0].y or point.y > profile[-1][0].y: continue
			for i in range(1, profile.size()):
				if point.y > profile[i][0].y: continue
				var a: Vector3 = profile[i - 1][0]
				var b: Vector3 = profile[i][0]
				var t := clampf((point.y - a.y) / maxf(b.y - a.y, 0.00001), 0, 1)
				var center := a.lerp(b, t)
				var radius: Vector2 = profile[i - 1][1].lerp(profile[i][1], t) + Vector2.ONE * gap
				var radial := Vector2((point.x - center.x) / radius.x, (point.z - center.z) / radius.y)
				if radial.length_squared() < 1.0:
					if radial.length_squared() < 0.000001: radial = Vector2(0, 1)
					radial = radial.normalized()
					point.x = center.x + radial.x * radius.x
					point.z = center.z + radial.y * radius.y
				break
	return point


func apply(doll: Node3D, profile: Resource) -> void:
	read_body(doll.body_rig)
	var contact := preload("res://scripts/cloth_body_contact.gd").new()
	contact.build_rest_envelopes()
	var originals := {}
	var layers: Array[MeshInstance3D] = []
	for part: MeshInstance3D in doll.body_rig.find_children("*", "MeshInstance3D", true, false):
		originals[part] = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for part: MeshInstance3D in doll.body_rig.find_children("*", "MeshInstance3D", true, false):
		if part.get_meta("is_underbody", false): continue
		if part.has_meta("skin_layer_sources"):
			layers.append(part)
			continue
		var ancestor := part.get_parent()
		var is_head := false
		var is_arm := false
		while ancestor != doll.body_rig:
			is_head = is_head or str(ancestor.name) in ["HeadRig", "Shoe"]
			is_arm = is_arm or str(ancestor.name) in ["ArmLeft", "ArmRight"]
			ancestor = ancestor.get_parent()
		if is_head or str(part.name) in ["Neck", "Calf", "Mitten", "Thumb"]: continue
		var transform := model_transform(part, doll.body_rig)
		var inverse := transform.affine_inverse()
		var arrays := part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var before_shape := PackedVector3Array()
		var shape: Resource = doll.skirt_shape if str(part.name) == "LongSkirt" else (doll.shell_shape if str(part.name) == "TailoredShell" else null)
		var rest_model := PackedVector3Array()
		var fit_model := PackedVector3Array()
		var shape_mask := PackedByteArray()
		var weights: PackedFloat32Array = part.get_meta("garment_arm_weights", PackedFloat32Array())
		for i in vertices.size():
			var p := transform * vertices[i]
			var original_arm := absf(weights[i]) if not weights.is_empty() else 0.0
			var sleeve := absf(weights[i]) if not weights.is_empty() else (1.0 if is_arm else 0.0)
			p.y += doll.arm_raise_at(p.y) * sleeve
			var margin: float = profile.body_clearance()
			if str(part.name) == "StandingCollar": margin += profile.layer_gap
			vertices[i] = inverse * project(p, margin, "arm" if original_arm > .7 or is_arm else "torso")
			before_shape.append(vertices[i])
			if shape != null and shape.enabled and shape.bridge_tension > 0 and sleeve <= .001:
				var s := clampf((shape.root_height - p.y) / maxf(.001, shape.root_height - shape.hem_height), 0, 1)
				var strength: float = shape._sample(shape.contour_strength, s)
				if strength > 0 and p.y >= shape.hem_height and p.y < shape.root_height:
					var q := transform * vertices[i]
					var outward := Vector3(q.x, 0, q.z).normalized()
					var supported: Vector3 = contact.project(q, margin, false, outward)
					vertices[i] = inverse * q.lerp(supported, clampf(shape.bridge_tension * strength, 0, 1))
			rest_model.append(p)
			fit_model.append(transform * vertices[i])
			shape_mask.append(1 if sleeve <= .001 else 0)
		if shape != null and shape.enabled:
			var shaped: PackedVector3Array = shape.fit(rest_model, fit_model, shape_mask)
			for i in vertices.size(): vertices[i] = inverse * shaped[i]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if shape != null and shape.enabled: arrays[Mesh.ARRAY_NORMAL] = _normals(arrays, before_shape)
		var result := ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		part.mesh = result
		if not weights.is_empty(): part.set_meta("garment_arm_weights", weights)
		part.set_meta("accepted_body_fit", true)
		part.set_meta("body_clearance", profile.body_clearance())
	# Preserve each overlay's authored separation from the same fitted triangles.
	var finished := {}
	for layer in layers:
		_refit_layer(layer, originals, finished)
	_attach_details(doll, originals)


func _normals(arrays: Array, before: PackedVector3Array) -> PackedVector3Array:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var previous: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var result := PackedVector3Array()
	result.resize(points.size())
	var affected := PackedByteArray()
	affected.resize(points.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		if points[a].distance_squared_to(before[a]) + points[b].distance_squared_to(before[b]) + points[c].distance_squared_to(before[c]) > .000000000001:
			affected[a] = 1
			affected[b] = 1
			affected[c] = 1
		var n := (points[b] - points[a]).cross(points[c] - points[a])
		if n.dot(previous[a] + previous[b] + previous[c]) < 0: n = -n
		result[a] += n
		result[b] += n
		result[c] += n
	# Lathed surfaces duplicate UV-seam vertices. Share their normal sums only
	# when position AND authored normal match, leaving deliberate hard edges intact.
	var seams := {}
	var keys: Array = []
	for i in points.size():
		var key := [Vector3i((points[i] * 100000).round()), Vector3i((previous[i] * 10000).round())]
		keys.append(key)
		if not seams.has(key): seams[key] = [Vector3.ZERO, false]
		seams[key][0] += result[i]
		seams[key][1] = seams[key][1] or affected[i] == 1
	for i in result.size():
		var group: Array = seams[keys[i]]
		result[i] = group[0].normalized() if group[1] and group[0].length_squared() > .00000001 else previous[i]
	return result


func _attach_details(doll: Node3D, originals: Dictionary) -> void:
	var source: MeshInstance3D = doll._garment
	if not is_instance_valid(source) or not originals.has(source): return
	var old: PackedVector3Array = originals[source]
	var surface := source.mesh.surface_get_arrays(0)
	var fitted: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = surface[Mesh.ARRAY_NORMAL]
	var faces: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	var adjacent := {}
	var torso_count: int = source.get_meta("torso_index_count", faces.size())
	for face in range(0, torso_count, 3):
		for j in 3:
			var id := faces[face + j]
			if not adjacent.has(id): adjacent[id] = []
			adjacent[id].append(face)
	var bins := {}
	for i in old.size():
		if not adjacent.has(i): continue
		var key := Vector3i((old[i] / .08).floor())
		if not bins.has(key): bins[key] = []
		bins[key].append(i)
	for part: MeshInstance3D in originals:
		if not (str(part.name).begins_with("ApronStrap") or str(part.name).begins_with("Button")): continue
		if part.has_meta("skin_layer_sources"): continue
		var transform := model_transform(part, doll.body_rig)
		var inverse := transform.affine_inverse()
		var arrays := part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = originals[part]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := PackedInt32Array()
		var bary := PackedVector3Array()
		var anchored := part.has_meta("skin_anchor_local")
		for i in vertices.size():
			var p: Vector3 = transform * (part.get_meta("skin_anchor_local") if anchored else vertices[i])
			var key := Vector3i((p / .08).floor())
			var closest := 0
			var distance := INF
			for x in range(-1, 2):
				for y in range(-1, 2):
					for z in range(-1, 2):
						for candidate: int in bins.get(key + Vector3i(x,y,z), []):
							var d := p.distance_squared_to(old[candidate])
							if d < distance:
								distance = d
								closest = candidate
			if not is_finite(distance): continue
			var best_face: int = adjacent[closest][0]
			var best_hit := old[closest]
			for face: int in adjacent[closest]:
				var hit: Vector3 = preload("res://components/basic_garment.gd")._closest_on_triangle(p, old[faces[face]], old[faces[face + 1]], old[faces[face + 2]])
				if p.distance_squared_to(hit) <= distance:
					distance = p.distance_squared_to(hit)
					best_face = face
					best_hit = hit
			var triangle := faces.slice(best_face, best_face + 3)
			var blend := Geometry3D.get_triangle_barycentric_coords(best_hit, old[triangle[0]], old[triangle[1]], old[triangle[2]])
			var contact := Vector3.ZERO
			var normal := Vector3.ZERO
			var original_contact := Vector3.ZERO
			for j in 3:
				contact += fitted[triangle[j]] * blend[j]
				normal += source_normals[triangle[j]] * blend[j]
				original_contact += old[triangle[j]] * blend[j]
			if anchored:
				vertices[i] += inverse.basis * (contact - original_contact)
			else:
				vertices[i] = inverse * (contact + normal.normalized() * .007)
				normals[i] = (transform.basis.transposed() * normal).normalized()
			indices.append_array(triangle)
			bary.append(blend)
		if bary.size() != vertices.size(): continue
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		part.mesh = mesh
		part.set_meta("skin_layer_sources", PackedStringArray([str(part.get_path_to(source))]))
		part.set_meta("skin_layer_triangles", indices)
		part.set_meta("skin_layer_barycentric", bary)


func _refit_layer(layer: MeshInstance3D, originals: Dictionary, finished: Dictionary) -> void:
	if finished.has(layer): return
	var sources: Array[MeshInstance3D] = []
	for path in layer.get_meta("skin_layer_sources"):
		var source := layer.get_node(NodePath(path)) as MeshInstance3D
		if source.has_meta("skin_layer_sources"): _refit_layer(source, originals, finished)
		sources.append(source)
	var triangles: PackedInt32Array = layer.get_meta("skin_layer_triangles", PackedInt32Array())
	var bary: PackedVector3Array = layer.get_meta("skin_layer_barycentric", PackedVector3Array())
	var source_ids: PackedInt32Array = layer.get_meta("skin_layer_source_index", PackedInt32Array())
	var arrays := layer.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var source_vertices: Array = []
	for source in sources:
		source_vertices.append(source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	if triangles.size() == vertices.size() * 3 and bary.size() == vertices.size():
		for i in vertices.size():
			var id := source_ids[i] if source_ids.size() == vertices.size() else 0
			if id < 0: continue
			var source := sources[id]
			var old: PackedVector3Array = originals[source]
			var current: PackedVector3Array = source_vertices[id]
			for j in 3:
				var index := triangles[i * 3 + j]
				vertices[i] += (current[index] - old[index]) * bary[i][j]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var result := ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		layer.mesh = result
	finished[layer] = true
