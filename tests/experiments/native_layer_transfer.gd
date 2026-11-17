extends RefCounted

const FittedPanel = preload("res://components/fitted_cloth_panel.gd")
const LayerBinding = preload("res://scripts/layer_skin_binding.gd")
const RIBBONS := ["HemRibbon", "FineHemRibbon", "WaistRibbon"]
const MAX_BIND_DISTANCE := 0.06

var failures: Array[String] = []
var changed: Array[MeshInstance3D] = []
var order: Array[MeshInstance3D] = []
var sources := {}
var depends := {}
var visiting := {}
var records: Array = []
var max_roundtrip_error := 0.0
var derivations: Array = []
var surface_follow := false
var surface_clearance := 0.0
var surface_records: Array = []


func _radial_hit(points: PackedVector3Array, indices: PackedInt32Array, height: float, direction: Vector2) -> Dictionary:
	var hits: Array[float] = []
	for face in range(0, indices.size(), 3):
		var section: Array[Vector2] = []
		for edge in 3:
			var a := points[indices[face + edge]]
			var b := points[indices[face + (edge + 1) % 3]]
			if absf(a.y - height) < 0.000001: section.append(Vector2(a.x, a.z))
			if absf(b.y - a.y) > 0.000001 and height >= minf(a.y, b.y) - 0.000001 and height <= maxf(a.y, b.y) + 0.000001:
				var p := a.lerp(b, clampf((height - a.y) / (b.y - a.y), 0.0, 1.0))
				section.append(Vector2(p.x, p.z))
		var longest := 0.0
		var start := Vector2.ZERO
		var span := Vector2.ZERO
		for a in section:
			for b in section:
				if a.distance_squared_to(b) > longest:
					longest = a.distance_squared_to(b)
					start = a
					span = b - a
		var denominator := direction.cross(span)
		if absf(denominator) < 1e-10: continue
		var radius := start.cross(span) / denominator
		var along := start.cross(direction) / denominator
		if radius > .01 and along >= -.00001 and along <= 1.00001: hits.append(radius)
	if hits.is_empty(): return {}
	hits.sort()
	if hits[-1] - hits[0] > .00002: return {}
	return {"radius": hits[0]}


func _open_band(points: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var weld := {}
	var ids: Array[int] = []
	for point in points:
		if not weld.has(point): weld[point] = weld.size()
		ids.append(weld[point])
	var edges := {}
	for face in range(0, indices.size(), 3):
		for corner in 3:
			var a := ids[indices[face + corner]]
			var b := ids[indices[face + (corner + 1) % 3]]
			if not _check(a != b, "Collapsed derived band edge"): return {}
			var edge := Vector2i(mini(a, b), maxi(a, b))
			edges[edge] = edges.get(edge, 0) + 1
	var neighbors := {}
	for edge: Vector2i in edges:
		if not _check(edges[edge] <= 2, "Nonmanifold derived band edge"): return {}
		if edges[edge] != 1: continue
		for pair in [[edge.x, edge.y], [edge.y, edge.x]]:
			if not neighbors.has(pair[0]): neighbors[pair[0]] = []
			neighbors[pair[0]].append(pair[1])
	var seen := {}
	var loops: Array[int] = []
	for vertex in neighbors:
		if not _check(neighbors[vertex].size() == 2, "Broken derived band boundary"): return {}
		if seen.has(vertex): continue
		var pending: Array = [vertex]
		var count := 0
		while not pending.is_empty():
			var current: int = pending.pop_back()
			if seen.has(current): continue
			seen[current] = true
			count += 1
			pending.append_array(neighbors[current])
		loops.append(count)
	_check(loops.size() == 2, "Derived ribbon must have two open boundary loops")
	return {"boundary_loop_sizes": loops, "exact_canonical_positions": true, "cap_faces": 0}


func _canonicalize(points: PackedVector3Array) -> Dictionary:
	# Clip arithmetic can differ across a shared edge; canonicalize only sub-micron twins.
	const EPSILON := .000001
	var result := points.duplicate()
	var cells := {}
	var count := 0
	var maximum := 0.0
	for i in result.size():
		var p := result[i]
		var cell := Vector3i((p / EPSILON).floor())
		var match_id := -1
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					for id: int in cells.get(cell + Vector3i(x, y, z), []):
						if p.distance_to(result[id]) <= EPSILON: match_id = id
		if match_id >= 0:
			maximum = maxf(maximum, p.distance_to(result[match_id]))
			result[i] = result[match_id]
			count += 1
		else:
			if not cells.has(cell): cells[cell] = []
			cells[cell].append(i)
	return {"points": result, "duplicates": count, "maximum_distance": maximum, "tolerance": EPSILON}


func _derive_ribbon(part: MeshInstance3D, skirt: MeshInstance3D) -> void:
	var old_mesh := part.mesh
	var original := old_mesh.surface_get_arrays(0)
	var old: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
	var old_indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
	var side_indices := PackedInt32Array()
	var used := {}
	var cap_faces := 0
	for face in range(0, old_indices.size(), 3):
		var a := old[old_indices[face]]
		var b := old[old_indices[face + 1]]
		var c := old[old_indices[face + 2]]
		# Discard horizontal disks before any radial sampling of the original band.
		if maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)) < .000001:
			cap_faces += 1
			continue
		for corner in 3:
			var id := old_indices[face + corner]
			side_indices.append(id)
			used[id] = true
	var low := INF
	var high := -INF
	var rings := {}
	for id: int in used:
		var p := old[id]
		if not _check(p.is_finite() and Vector2(p.x, p.z).length() > .05, "Invalid original ribbon wrap"): return
		low = minf(low, p.y)
		high = maxf(high, p.y)
		var key := roundi(p.y * 100000.0)
		if not rings.has(key): rings[key] = []
		rings[key].append(fposmod(atan2(p.z, p.x), TAU))
	if not _check(is_finite(low) and high > low and rings.size() >= 2, "Missing original band sides"): return
	for angles: Array in rings.values():
		angles.sort()
		if not _check(angles.size() >= 12, "Incomplete ribbon ring"): return
		for i in angles.size():
			var gap: float = angles[i + 1] - angles[i] if i + 1 < angles.size() else angles[0] + TAU - angles[i]
			if not _check(gap <= PI / 4.0, "Inconsistent ribbon angular wrap"): return
	var surface := skirt.mesh.surface_get_arrays(0)
	var source: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var source_indices: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	var max_distance := 0.0
	for id: int in used:
		var p := old[id]
		var radial := Vector2(p.x, p.z)
		var hit := _radial_hit(source, source_indices, p.y, radial.normalized())
		if not _check(not hit.is_empty(), "No unique standing skirt intersection: " + str(part.name)): return
		max_distance = maxf(max_distance, absf(radial.length() - float(hit.radius)))
	var record := {"name": str(part.name), "rest_y_bounds": [low, high], "original_vertex_count": old.size(),
		"original_side_triangles": side_indices.size() / 3, "discarded_original_cap_faces": cap_faces,
		"max_geometry_distance": max_distance, "rejection_distance": MAX_BIND_DISTANCE,
		"offset_method": "Signed radial difference at matching rest Y/angle, projected onto source normal; radial application retains exact Y width, no added clearance"}
	derivations.append(record)
	if not _check(max_distance <= MAX_BIND_DISTANCE, "Ribbon/skirt distance exceeds guard: " + str(part.name)): return
	var design := {}
	for key in part.get_meta_list(): design[key] = part.get_meta(key)
	FittedPanel.build(part, [{"mesh": skirt}], [[Plane(Vector3.UP, low), Plane(Vector3.DOWN, -high)]], 0.0)
	var panel := part.mesh.surface_get_arrays(0)
	var panel_points: PackedVector3Array = panel[Mesh.ARRAY_VERTEX]
	var panel_normals: PackedVector3Array = panel[Mesh.ARRAY_NORMAL]
	var panel_indices: PackedInt32Array = panel[Mesh.ARRAY_INDEX]
	var triangles: PackedInt32Array = part.get_meta("skin_layer_triangles")
	var bary: PackedVector3Array = part.get_meta("skin_layer_barycentric")
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var bindings := PackedInt32Array()
	var blends := PackedVector3Array()
	var bone_ids := PackedInt32Array()
	var weights := PackedFloat32Array()
	var source_faces := {}
	for face in range(0, source_indices.size(), 3): source_faces[Vector3i(source_indices[face], source_indices[face + 1], source_indices[face + 2])] = true
	var inherited := {}
	var minimum_offset := INF
	var maximum_offset := -INF
	var radial_minimum := INF
	var radial_maximum := -INF
	var skipped := 0
	for face in range(0, panel_indices.size(), 3):
		var ia := panel_indices[face]
		var ib := panel_indices[face + 1]
		var ic := panel_indices[face + 2]
		if (panel_points[ib] - panel_points[ia]).cross(panel_points[ic] - panel_points[ia]).length_squared() < 1e-16:
			skipped += 1
			continue
		var parent_face := Vector3i(triangles[ia * 3], triangles[ia * 3 + 1], triangles[ia * 3 + 2])
		if not _check(source_faces.has(parent_face), "Unknown inherited source triangle"): return
		inherited[parent_face] = true
		for id: int in [ia, ib, ic]:
			var triangle := triangles.slice(id * 3, id * 3 + 3)
			if not _check(Vector3i(triangle[0], triangle[1], triangle[2]) == parent_face, "Panel triangle crosses a source edge"): return
			var blend := bary[id]
			if not _check(blend.is_finite() and minf(blend.x, minf(blend.y, blend.z)) >= -.00001 and absf(blend.x + blend.y + blend.z - 1.0) < .00001, "Invalid inherited barycentric"): return
			var p := source[triangle[0]] * blend.x + source[triangle[1]] * blend.y + source[triangle[2]] * blend.z
			if not _check(p.distance_to(panel_points[id]) < .000002 and p.y >= low - .000002 and p.y <= high + .000002, "Panel escaped its clipped source slab"): return
			var radial := Vector2(p.x, p.z)
			var direction := radial.normalized()
			var hit := _radial_hit(old, side_indices, p.y, direction)
			if not _check(not hit.is_empty(), "No unique authored band intersection: " + str(part.name)): return
			var distance := float(hit.radius) - radial.length()
			max_distance = maxf(max_distance, absf(distance))
			if not _check(absf(distance) <= MAX_BIND_DISTANCE, "Derived ribbon offset exceeds guard"): return
			var displacement := Vector3(direction.x, 0, direction.y) * distance
			var offset := displacement.dot(panel_normals[id])
			minimum_offset = minf(minimum_offset, offset)
			maximum_offset = maxf(maximum_offset, offset)
			radial_minimum = minf(radial_minimum, distance)
			radial_maximum = maxf(radial_maximum, distance)
			var point := p + displacement
			point.y = clampf(point.y, low, high)
			if not _check(point.is_finite() and panel_normals[id].is_finite(), "Nonfinite derived ribbon"): return
			positions.append(point)
			normals.append(panel_normals[id])
			bindings.append_array(triangle)
			blends.append(blend)
			var skin: Array = LayerBinding.interpolate_weights(surface, triangle, blend)
			bone_ids.append_array(skin[0])
			weights.append_array(skin[1])
	if not _check(not positions.is_empty(), "Empty source-derived band"): return
	var welded := _canonicalize(positions)
	positions = welded.points
	var derived_low := INF
	var derived_high := -INF
	for point in positions:
		derived_low = minf(derived_low, point.y)
		derived_high = maxf(derived_high, point.y)
	_check(absf(derived_low - low) < .000001 and absf(derived_high - high) < .000001, "Derived band changed its rest-height width")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(range(positions.size()))
	arrays[Mesh.ARRAY_BONES] = bone_ids
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	if surface[Mesh.ARRAY_TEX_UV2] != null:
		var uv2 := PackedVector2Array()
		for i in positions.size():
			var triangle := bindings.slice(i * 3, i * 3 + 3)
			var blend := blends[i]
			uv2.append(surface[Mesh.ARRAY_TEX_UV2][triangle[0]] * blend.x + surface[Mesh.ARRAY_TEX_UV2][triangle[1]] * blend.y + surface[Mesh.ARRAY_TEX_UV2][triangle[2]] * blend.z)
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var shapes := _derived_shapes(skirt.mesh, positions, normals, bindings, blends)
	if not failures.is_empty(): return
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for i in skirt.mesh.get_blend_shape_count(): mesh.add_blend_shape(skirt.mesh.get_blend_shape_name(i))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	mesh.surface_set_material(0, old_mesh.surface_get_material(0))
	part.mesh = mesh
	for i in shapes.size(): part.set_blend_shape_value(i, skirt.get_blend_shape_value(i))
	for key in part.get_meta_list():
		if not str(key).begins_with("skin_layer_") and not design.has(key): part.remove_meta(key)
	for key in design:
		if not str(key).begins_with("skin_layer_"): part.set_meta(key, design[key])
	part.set_meta("skin_layer_triangles", bindings)
	part.set_meta("skin_layer_barycentric", blends)
	var source_ids := PackedInt32Array()
	source_ids.resize(positions.size())
	part.set_meta("skin_layer_source_index", source_ids)
	part.set_meta("skin_layer_unmapped", 0)
	record.merge({"derived_vertices": positions.size(), "derived_triangles": positions.size() / 3,
		"derived_rest_y_bounds": [derived_low, derived_high],
		"canonicalized_duplicates": welded.duplicates, "maximum_weld_distance": welded.maximum_distance,
		"weld_tolerance": welded.tolerance,
		"inherited_source_triangles": inherited.size(), "skipped_zero_area_clip_triangles": skipped,
		"signed_normal_offset_range": [minimum_offset, maximum_offset], "radial_offset_range": [radial_minimum, radial_maximum],
		"max_geometry_distance": max_distance, "topology": _open_band(positions, arrays[Mesh.ARRAY_INDEX]),
		"cap_policy": "Only open source side triangles; original horizontal cap faces and cap-center vertices excluded"}, true)


func _derived_shapes(source_mesh: ArrayMesh, positions: PackedVector3Array, normals: PackedVector3Array,
		bindings: PackedInt32Array, blends: PackedVector3Array) -> Array:
	var rest: PackedVector3Array = source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var result: Array = []
	for target: Array in source_mesh.surface_get_blend_shape_arrays(0):
		var current: PackedVector3Array = target[Mesh.ARRAY_VERTEX]
		var vertices := PackedVector3Array()
		var target_normals := PackedVector3Array()
		for i in positions.size():
			var a := bindings[i * 3]
			var b := bindings[i * 3 + 1]
			var c := bindings[i * 3 + 2]
			var old_normal := (rest[c] - rest[a]).cross(rest[b] - rest[a])
			var new_normal := (current[c] - current[a]).cross(current[b] - current[a])
			if not _check(old_normal.length_squared() > 1e-16 and new_normal.length_squared() > 1e-16, "Degenerate source morph triangle"): return []
			var old_basis := Basis(rest[b] - rest[a], rest[c] - rest[a], old_normal.normalized())
			var new_basis := Basis(current[b] - current[a], current[c] - current[a], new_normal.normalized())
			var map := new_basis * old_basis.inverse()
			var blend := blends[i]
			var anchor := rest[a] * blend.x + rest[b] * blend.y + rest[c] * blend.z
			var posed := current[a] * blend.x + current[b] * blend.y + current[c] * blend.z
			vertices.append(posed + map * (positions[i] - anchor))
			target_normals.append((map.inverse().transposed() * normals[i]).normalized())
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = vertices
		shape[Mesh.ARRAY_NORMAL] = target_normals
		result.append(shape)
	return result


func derive_ribbons(doll: Node3D, skirt: MeshInstance3D) -> void:
	for label in RIBBONS:
		var matches: Array[MeshInstance3D] = []
		for part: MeshInstance3D in doll.rig.meshes:
			if str(part.name) == label: matches.append(part)
		if not _check(matches.size() == 1 and not matches[0].get_meta("is_underbody", false), "Missing/ambiguous ribbon: " + label): return
		_derive_ribbon(matches[0], skirt)
		if not failures.is_empty(): return


func _check(ok: bool, message: String) -> bool:
	if not ok and message not in failures: failures.append(message)
	return ok


func _visit(part: MeshInstance3D, skirt: MeshInstance3D) -> bool:
	if part == skirt: return true
	if depends.has(part): return depends[part]
	if not _check(not visiting.has(part), "Cyclic layer graph: " + str(part.name)): return false
	visiting[part] = true
	var linked: Array[MeshInstance3D] = []
	var affected := false
	for path in part.get_meta("skin_layer_sources", PackedStringArray()):
		var source := part.get_node_or_null(NodePath(path)) as MeshInstance3D
		if not _check(source != null, "Missing layer source: %s -> %s" % [part.name, path]): continue
		linked.append(source)
		affected = _visit(source, skirt) or affected
	sources[part] = linked
	depends[part] = affected
	visiting.erase(part)
	if affected: order.append(part)
	return affected


func _skins(doll: Node3D, part: MeshInstance3D) -> Array[Transform3D]:
	var arrays := part.mesh.surface_get_arrays(0)
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var result: Array[Transform3D] = []
	if not _check(ids.size() == count * 4 and weights.size() == ids.size(), "Invalid layer skin arrays"): return result
	var bones: Array[Transform3D] = []
	var skeleton: Skeleton3D = doll.rig.skeleton
	for bone in skeleton.get_bone_count():
		bones.append(doll.rig.global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse())
	for i in count:
		var skin := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
		for slot in 4:
			var id := ids[i * 4 + slot]
			var weight := weights[i * 4 + slot]
			if not _check(id >= 0 and id < bones.size() and is_finite(weight), "Invalid layer skin influence"): return []
			skin.basis.x += bones[id].basis.x * weight
			skin.basis.y += bones[id].basis.y * weight
			skin.basis.z += bones[id].basis.z * weight
			skin.origin += bones[id].origin * weight
		if not _check(skin.is_finite() and absf(skin.basis.determinant()) > 0.00000001, "Singular layer skin transform"): return []
		result.append(skin)
	return result


func _surface_offsets(anchors: PackedVector3Array, directions: PackedVector3Array, gaps: PackedFloat32Array,
		rest_anchors: PackedVector3Array, posed: PackedVector3Array, normals: PackedVector3Array,
		skins: Array[Transform3D], label: String) -> void:
	var groups := {}
	for i in anchors.size():
		if gaps[i] < 0: continue
		var key := Vector3i((rest_anchors[i] * 1000000.0).round())
		if not groups.has(key): groups[key] = []
		groups[key].append(i)
	var max_distance := 0.0
	var max_residual := 0.0
	for group: Array in groups.values():
		var anchor := Vector3.ZERO
		var displacement := Vector3.ZERO
		for i: int in group:
			anchor += anchors[i]
			displacement += directions[i] * gaps[i]
		anchor /= group.size()
		displacement /= group.size()
		# A seam has one position, constrained by all incident source face planes.
		for iteration in 48:
			var residual := 0.0
			for i: int in group:
				var deficit: float = gaps[i] - (anchor + displacement - anchors[i]).dot(directions[i])
				residual = maxf(residual, deficit)
				if deficit > 0: displacement += directions[i] * deficit
			if residual < .0000001: break
		for i: int in group:
			max_residual = maxf(max_residual, gaps[i] - (anchor + displacement - anchors[i]).dot(directions[i]))
		max_distance = maxf(max_distance, displacement.length())
		if not _check(displacement.length() <= MAX_BIND_DISTANCE and displacement.is_finite(), "Surface seam offset exceeded guard: " + label): return
		for i: int in group:
			posed[i] = anchor + displacement
			normals[i] = (skins[i].basis.inverse() * displacement.normalized()).normalized()
	_check(max_residual < .000002, "Surface seam planes did not converge: " + label)
	surface_records.append({"name": label, "groups": groups.size(), "minimum_clearance": surface_clearance,
		"max_offset": max_distance, "max_plane_residual": max_residual})


func _transfer(doll: Node3D, part: MeshInstance3D, affected_sources: Array[MeshInstance3D]) -> void:
	if not _check(not part.get_meta("is_underbody", false), "Refusing body layer transfer"): return
	var arrays := part.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rest_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var triangles: PackedInt32Array = part.get_meta("skin_layer_triangles", PackedInt32Array())
	var bary: PackedVector3Array = part.get_meta("skin_layer_barycentric", PackedVector3Array())
	var ids: PackedInt32Array = part.get_meta("skin_layer_source_index", PackedInt32Array())
	if not _check(triangles.size() == rest.size() * 3 and bary.size() == rest.size() and ids.size() == rest.size(),
		"Incomplete binding arrays: " + str(part.name)): return
	if not _check(int(part.get_meta("skin_layer_unmapped", 0)) == 0, "Unmapped layer vertices: " + str(part.name)): return
	var skins := _skins(doll, part)
	if skins.size() != rest.size(): return
	var linked: Array = sources[part]
	var source_rest: Array[PackedVector3Array] = []
	var source_posed: Array[PackedVector3Array] = []
	for source: MeshInstance3D in linked:
		source_rest.append(source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		source_posed.append(doll.rig.deformed_vertices(source))
	var posed: PackedVector3Array = doll.rig.deformed_vertices(part)
	var normals := rest_normals.duplicate()
	var shape_id := part.find_blend_shape_by_name("RestNap")
	if not _check(shape_id >= 0 and part.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED,
		"Expected normalized RestNap target: " + str(part.name)): return
	var shapes: Array = part.mesh.surface_get_blend_shape_arrays(0).duplicate(true)
	# Preserve current normals on vertices attached to an unrelated source.
	for shape in shapes.size():
		var amount := part.get_blend_shape_value(shape)
		var target: PackedVector3Array = shapes[shape][Mesh.ARRAY_NORMAL]
		for i in normals.size(): normals[i] += (target[i] - rest_normals[i]) * amount
	var updated := 0
	var anchors := PackedVector3Array()
	var rest_anchors := PackedVector3Array()
	var directions := PackedVector3Array()
	var gaps := PackedFloat32Array()
	anchors.resize(rest.size())
	rest_anchors.resize(rest.size())
	directions.resize(rest.size())
	gaps.resize(rest.size())
	gaps.fill(-1.0)
	for i in rest.size():
		var id := ids[i]
		if not _check(id >= 0 and id < linked.size() and bary[i].is_finite() and absf(bary[i].x + bary[i].y + bary[i].z - 1.0) < .0001,
			"Invalid binding source/barycentric: " + str(part.name)): return
		if linked[id] not in affected_sources: continue
		var old: PackedVector3Array = source_rest[id]
		var current: PackedVector3Array = source_posed[id]
		var a := triangles[i * 3]
		var b := triangles[i * 3 + 1]
		var c := triangles[i * 3 + 2]
		if not _check(mini(a, mini(b, c)) >= 0 and maxi(a, maxi(b, c)) < old.size() and current.size() == old.size(), "Invalid binding triangle"): return
		var old_normal := (old[c] - old[a]).cross(old[b] - old[a])
		var new_normal := (current[c] - current[a]).cross(current[b] - current[a])
		if not _check(old_normal.length_squared() > 1e-16 and new_normal.length_squared() > 1e-16, "Degenerate source triangle: " + str(part.name)): return
		var old_basis := Basis(old[b] - old[a], old[c] - old[a], old_normal.normalized())
		var new_basis := Basis(current[b] - current[a], current[c] - current[a], new_normal.normalized())
		var map := new_basis * old_basis.inverse()
		var anchor := old[a] * bary[i].x + old[b] * bary[i].y + old[c] * bary[i].z
		var contact := current[a] * bary[i].x + current[b] * bary[i].y + current[c] * bary[i].z
		# Transfer the signed authored offset, with no minimum gap or inflation.
		posed[i] = contact + map * (rest[i] - anchor)
		var posed_normal := (map.inverse().transposed() * rest_normals[i]).normalized()
		normals[i] = (skins[i].basis.inverse() * posed_normal).normalized()
		if surface_follow:
			var orientation := 1.0 if old_normal.dot(rest_normals[i]) >= 0 else -1.0
			anchors[i] = contact
			rest_anchors[i] = anchor
			directions[i] = new_normal.normalized() * orientation
			gaps[i] = maxf(surface_clearance, (rest[i] - anchor).dot(old_normal.normalized() * orientation))
		updated += 1
	if surface_follow:
		_surface_offsets(anchors, directions, gaps, rest_anchors, posed, normals, skins, str(part.name))
		if not failures.is_empty(): return
	# Weld duplicate positions without merging deliberately split shading normals.
	var groups := {}
	for i in rest.size():
		var key := Vector3i((rest[i] * 100000.0).round())
		if not groups.has(key): groups[key] = []
		groups[key].append(i)
	for group: Array in groups.values():
		var center := Vector3.ZERO
		for i: int in group: center += posed[i]
		center /= group.size()
		for i: int in group: posed[i] = center
	var unskinned := PackedVector3Array()
	for i in rest.size():
		var point := skins[i].affine_inverse() * posed[i]
		if not _check(point.is_finite() and normals[i].is_finite() and normals[i].length_squared() > .5, "Nonfinite layer geometry/normal"): return
		max_roundtrip_error = maxf(max_roundtrip_error, (skins[i] * point).distance_to(posed[i]))
		unskinned.append(point)
	shapes[shape_id][Mesh.ARRAY_VERTEX] = unskinned
	shapes[shape_id][Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = part.mesh.blend_shape_mode
	for shape in part.mesh.get_blend_shape_count(): mesh.add_blend_shape(part.mesh.get_blend_shape_name(shape))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	mesh.surface_set_material(0, part.mesh.surface_get_material(0))
	part.mesh = mesh
	for shape in shapes.size(): part.set_blend_shape_value(shape, 1.0 if shape == shape_id else 0.0)
	changed.append(part)
	var source_names: Array = []
	for source: MeshInstance3D in linked: source_names.append(str(doll.body_rig.get_path_to(source)))
	records.append({"path": str(doll.body_rig.get_path_to(part)), "vertices": rest.size(), "transferred_vertices": updated, "sources": source_names})


func run(doll: Node3D, skirt: MeshInstance3D) -> Dictionary:
	if surface_follow:
		# Two fabric mid-surfaces need their combined half-thickness as separation.
		surface_clearance = maxf(doll.body_contact.profile.rendering_thickness, doll.skirt_fabric.collision_margin())
	for part: MeshInstance3D in doll.rig.meshes: _visit(part, skirt)
	var unbound: Array = []
	var unrelated: Array = []
	for part: MeshInstance3D in doll.rig.meshes:
		if part == skirt or part.get_meta("is_underbody", false) or not part.is_visible_in_tree(): continue
		var path := str(doll.body_rig.get_path_to(part))
		if part.has_meta("skin_layer_sources") and not depends.get(part, false): unrelated.append(path)
		var label := str(part.name)
		if not part.has_meta("skin_layer_sources") and (part.get_meta("semantic", "") in ["skirt", "apron"] or "Ribbon" in label or "Seam" in label or "Border" in label):
			unbound.append({"path": path, "reason": "No source binding; retained visible and unchanged"})
	var affected: Array[MeshInstance3D] = [skirt]
	for part in order:
		if not failures.is_empty(): break
		_transfer(doll, part, affected)
		if part in changed: affected.append(part)
	_check(max_roundtrip_error < .00002, "Layer inverse-skin roundtrip exceeded tolerance")
	return {"method": "Topological barycentric triangle frames and actual weighted inverse skin; seam-coherent incident-plane thickness constraints" if surface_follow else
		"Topological barycentric triangle frames, signed standing offsets, actual weighted inverse skin; no RestCloth.point or collision solve",
		"surface_follow": surface_follow, "surface_constraints": surface_records,
		"ribbon_derivations": derivations,
		"dependent_count": order.size(), "transferred_count": changed.size(), "transferred": records,
		"unbound_count": unbound.size(), "unbound": unbound, "unrelated_bound": unrelated,
		"transfer_complete": failures.is_empty() and unbound.is_empty(), "max_roundtrip_error": max_roundtrip_error,
		"failures": failures}
