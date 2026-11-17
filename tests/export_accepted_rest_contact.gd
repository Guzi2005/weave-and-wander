extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const RestCloth = preload("res://scripts/rest_cloth.gd")
const OUTPUT := "res://captures/accepted_rest_contact_raw.json"
const BODY_NAMES := ["MannequinTorso", "LegMannequin"]
const ROUNDTRIP_TOLERANCE := 0.00002

var failures: Array[String] = []
var max_roundtrip_error := 0.0
var max_forward_error := 0.0
var minimum_determinant := INF


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	if not ok and message not in failures:
		failures.append(message)
		if failures.size() <= 8: push_error("ACCEPTED_REST_RAW: " + message)
	return ok


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _vector(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func _vectors(points: PackedVector3Array) -> Array:
	var result: Array = []
	for point in points: result.append(_vector(point))
	return result


func _transform(transform: Transform3D) -> Dictionary:
	# Godot stores basis columns; JSON uses rows for Blender Matrix(rows).
	var b := transform.basis
	return {"basis": [[b.x.x, b.y.x, b.z.x], [b.x.y, b.y.y, b.z.y], [b.x.z, b.y.z, b.z.z]],
		"origin": _vector(transform.origin)}


func _geometry_signature(doll: Node3D) -> String:
	var data: Array = [doll.arm_shortening, doll.body_rig.transform]
	for part: MeshInstance3D in doll.rig.meshes:
		data.append([str(doll.body_rig.get_path_to(part)), part.transform, part.visible,
			part.mesh.surface_get_arrays(0), part.mesh.surface_get_blend_shape_arrays(0)])
		for bind in part.skin.get_bind_count():
			data.append([part.skin.get_bind_bone(bind), part.skin.get_bind_pose(bind)])
	for bone in doll.rig.skeleton.get_bone_count():
		data.append(doll.rig.skeleton.get_bone_rest(bone))
	return _sha256(var_to_bytes(data))


func _valid_mesh(part: MeshInstance3D) -> bool:
	if not _check(part.mesh != null and part.mesh.get_surface_count() == 1, "Expected one surface: " + str(part.name)): return false
	if not _check(part.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "Expected triangles"): return false
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if not _check(not vertices.is_empty() and arrays[Mesh.ARRAY_NORMAL].size() == vertices.size(), "Invalid vertex/normal counts"): return false
	if not _check(arrays[Mesh.ARRAY_BONES].size() == vertices.size() * 4 \
		and arrays[Mesh.ARRAY_WEIGHTS].size() == vertices.size() * 4, "Expected four skin influences"): return false
	if not _check(arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() % 3 == 0, "Missing triangle indices"): return false
	for index in arrays[Mesh.ARRAY_INDEX]:
		if not _check(index >= 0 and index < vertices.size(), "Index out of range"): return false
	return true


func _open_topology(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	# Weld only for the boundary diagnostic; exported vertices/indices stay exact.
	var weld := {}
	var ids: Array[int] = []
	for point in vertices:
		var key := Vector3i((point * 100000.0).round())
		if not weld.has(key): weld[key] = weld.size()
		ids.append(weld[key])
	var edges := {}
	for triangle in range(0, indices.size(), 3):
		for corner in 3:
			var a := ids[indices[triangle + corner]]
			var b := ids[indices[triangle + (corner + 1) % 3]]
			_check(a != b, "Degenerate welded skirt edge")
			var edge := Vector2i(mini(a, b), maxi(a, b))
			edges[edge] = edges.get(edge, 0) + 1
	var adjacency := {}
	var boundary_edges := 0
	var nonmanifold_edges := 0
	for edge: Vector2i in edges:
		if edges[edge] > 2: nonmanifold_edges += 1
		if edges[edge] != 1: continue
		boundary_edges += 1
		for pair in [[edge.x, edge.y], [edge.y, edge.x]]:
			if not adjacency.has(pair[0]): adjacency[pair[0]] = []
			adjacency[pair[0]].append(pair[1])
	var visited := {}
	var loops: Array[int] = []
	for vertex in adjacency:
		_check(adjacency[vertex].size() == 2, "Skirt boundary is not a loop")
		if visited.has(vertex): continue
		var pending: Array = [vertex]
		var count := 0
		while not pending.is_empty():
			var current: int = pending.pop_back()
			if visited.has(current): continue
			visited[current] = true
			count += 1
			pending.append_array(adjacency[current])
		loops.append(count)
	loops.sort()
	_check(loops.size() == 2 and nonmanifold_edges == 0, "LongSkirt must have two open, uncapped boundary loops")
	return {"weld_tolerance": 0.00001, "boundary_edges": boundary_edges,
		"boundary_loop_sizes": loops, "nonmanifold_edges": nonmanifold_edges}


func _export_mesh(doll: Node3D, part: MeshInstance3D, transforms: Array[Transform3D]) -> Dictionary:
	var arrays := part.mesh.surface_get_arrays(0)
	var base_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var base_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var unskinned := base_vertices.duplicate()
	var normals := base_normals.duplicate()
	var shapes: Array = part.mesh.surface_get_blend_shape_arrays(0)
	if not shapes.is_empty():
		_check(part.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED, "Expected absolute normalized morphs")
	for shape in shapes.size():
		var amount := part.get_blend_shape_value(shape)
		if is_zero_approx(amount): continue
		var target: PackedVector3Array = shapes[shape][Mesh.ARRAY_VERTEX]
		var target_normals: PackedVector3Array = shapes[shape][Mesh.ARRAY_NORMAL]
		if not _check(target.size() == base_vertices.size() and target_normals.size() == base_normals.size(), "Invalid morph arrays"): return {}
		for vertex in unskinned.size():
			unskinned[vertex] += (target[vertex] - base_vertices[vertex]) * amount
			normals[vertex] += (target_normals[vertex] - base_normals[vertex]) * amount
	# This is deliberately raw rig output: no body_contact/evaluate/project call.
	var posed: PackedVector3Array = doll.rig.deformed_vertices(part)
	var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var posed_normals := PackedVector3Array()
	var inverse_skin: Array = []
	for vertex in unskinned.size():
		var weighted := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
		for slot in 4:
			var id := bone_ids[vertex * 4 + slot]
			if not _check(id >= 0 and id < transforms.size(), "Invalid skin bone"): return {}
			var skin := transforms[id]
			var weight := weights[vertex * 4 + slot]
			weighted.basis.x += skin.basis.x * weight
			weighted.basis.y += skin.basis.y * weight
			weighted.basis.z += skin.basis.z * weight
			weighted.origin += skin.origin * weight
		var determinant := absf(weighted.basis.determinant())
		if not _check(weighted.is_finite() and determinant > 0.00000001, "Nonfinite/singular weighted skin transform"): return {}
		minimum_determinant = minf(minimum_determinant, determinant)
		var inverse := weighted.affine_inverse()
		var normal := (weighted.basis * normals[vertex]).normalized()
		if not _check(inverse.is_finite() and posed[vertex].is_finite() and normal.is_finite() \
			and normal.length_squared() > 0.99, "Nonfinite posed data or zero normal"): return {}
		max_forward_error = maxf(max_forward_error, (weighted * unskinned[vertex]).distance_to(posed[vertex]))
		max_roundtrip_error = maxf(max_roundtrip_error, (inverse * posed[vertex]).distance_to(unskinned[vertex]))
		posed_normals.append(normal)
		inverse_skin.append(_transform(inverse))
	return {"name": str(part.name), "path": str(doll.body_rig.get_path_to(part)),
		"semantic": part.get_meta("semantic", ""), "vertex_count": posed.size(),
		"vertices": _vectors(posed), "normals": _vectors(posed_normals), "indices": Array(arrays[Mesh.ARRAY_INDEX]),
		"unskinned_vertices": _vectors(unskinned), "unskinned_normals": _vectors(normals),
		"inverse_skin_transforms": inverse_skin}


func _run() -> void:
	var source_paths := ["res://scripts/game_body_doll.gd", "res://scripts/doll_rig.gd",
		"res://scripts/rest_cloth.gd", "res://scripts/accepted_body_v20.gd", "res://scripts/shorter_arm_body.gd"]
	var source_hashes := {}
	for path in source_paths: source_hashes[path] = _sha256(FileAccess.get_file_as_bytes(path))
	var doll := Doll.new()
	root.add_child(doll)
	doll.process_mode = Node.PROCESS_MODE_DISABLED
	doll.configure({"outfit": 0, "hair": 0, "skin": 0, "palette": 0})
	var skirt: MeshInstance3D
	var body: Array[MeshInstance3D] = []
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.is_visible_in_tree(): continue
		if str(part.name) == "LongSkirt":
			_check(skirt == null, "More than one LongSkirt")
			skirt = part
		if part.get_meta("is_underbody", false) and str(part.name) in BODY_NAMES: body.append(part)
	_check(skirt != null and body.size() == 3, "Expected LongSkirt and visible torso + two legs")
	if skirt == null:
		_finish(doll)
		return
	_valid_mesh(skirt)
	for part in body: _valid_mesh(part)
	_check(skirt.mesh.get_blend_shape_count() == RestCloth.SHAPES.size() and RestCloth.SHAPES.size() == 5, "Expected five rest shapes")
	if not failures.is_empty():
		_finish(doll)
		return
	for mode in RestCloth.SHAPES.size():
		_check(str(skirt.mesh.get_blend_shape_name(mode)) == RestCloth.SHAPES[mode], "Rest shape order differs")
	var arrays := skirt.mesh.surface_get_arrays(0)
	var base_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var vertex_bytes := base_vertices.to_byte_array()
	_check(vertex_bytes.size() == base_vertices.size() * 12, "Expected float32 XYZ vertex bytes")
	var signature := _geometry_signature(doll)
	var data := {"schema_version": 1, "style": 0, "engine": Engine.get_version_info().string,
		"accepted_body_version": doll.body_rig.get_meta("accepted_body_version", ""),
		"source_sha256": source_hashes, "geometry_rest_sha256": signature,
		"coordinate_space": "raw rig/skeleton model space; includes posed Root bone, excludes node/world/bench transforms",
		"contact": "RAW rig.deformed_vertices; no runtime contact, shader lift, or surface proxy projection",
		"normal_method": "normalize(weighted_skin_basis * (base_normal + sum(amount * (shape_normal - base_normal))))",
		"inverse_convention": "basis is 3x3 ROW-MAJOR; unskinned_corrected = basis * posed_corrected + origin; inverse of the weighted transform, not weighted inverses",
		"morph_convention": "absolute normalized morph positions; write unskinned_corrected directly, not a base-relative delta",
		"base_skirt": {"name": "LongSkirt", "vertex_count": base_vertices.size(),
			"triangle_count": arrays[Mesh.ARRAY_INDEX].size() / 3,
			"vertex_sha256": _sha256(vertex_bytes), "vertex_byte_count": vertex_bytes.size(),
			"vertex_hash_encoding": "PackedVector3Array.to_byte_array(): little-endian IEEE754 float32 XYZ, no header",
			"vertices": _vectors(base_vertices), "normals": _vectors(arrays[Mesh.ARRAY_NORMAL]),
			"indices": Array(arrays[Mesh.ARRAY_INDEX]), "bones": Array(arrays[Mesh.ARRAY_BONES]),
			"weights": Array(arrays[Mesh.ARRAY_WEIGHTS]),
			"open_topology": _open_topology(base_vertices, arrays[Mesh.ARRAY_INDEX])}, "modes": []}
	for mode in RestCloth.SHAPES.size():
		if not failures.is_empty(): break
		var nap_weights := Vector4.ZERO
		if mode > 0: nap_weights[mode - 1] = 1.0
		doll.rig.animate(0.0, 0.0, "idle", 0.0)
		doll.rig.pose_rest("sit" if mode == 0 else "nap", 1.0, 0.0, nap_weights)
		var transforms: Array[Transform3D] = []
		for bone in doll.rig.skeleton.get_bone_count():
			transforms.append(doll.rig.global_pose(bone) * doll.rig.skeleton.get_bone_global_rest(bone).affine_inverse())
		var active_weights: Array = []
		for shape in RestCloth.SHAPES.size():
			var weight := skirt.get_blend_shape_value(shape)
			_check(is_equal_approx(weight, 1.0 if mode == shape else 0.0), "Rest morph is not one-hot")
			active_weights.append(weight)
		var skirt_data := _export_mesh(doll, skirt, transforms)
		var shape_arrays: Array = skirt.mesh.surface_get_blend_shape_arrays(0)[mode]
		skirt_data["active_shape_vertices"] = _vectors(shape_arrays[Mesh.ARRAY_VERTEX])
		skirt_data["active_shape_normals"] = _vectors(shape_arrays[Mesh.ARRAY_NORMAL])
		var body_data: Array = []
		for part in body: body_data.append(_export_mesh(doll, part, transforms))
		data.modes.append({"mode": mode, "shape": RestCloth.SHAPES[mode], "rest_mode": "sit" if mode == 0 else "nap",
			"nap_weights": [nap_weights.x, nap_weights.y, nap_weights.z, nap_weights.w],
			"active_shape_weights": active_weights, "skirt": skirt_data, "body": body_data})
		_check(_geometry_signature(doll) == signature, "Mesh arrays, body, skin binds, or skeleton rest changed")
	_check(data.modes.size() == 5, "Incomplete pose matrix")
	_check(max_forward_error < ROUNDTRIP_TOLERANCE and max_roundtrip_error < ROUNDTRIP_TOLERANCE, "Skin transform round-trip exceeded tolerance")
	for path in source_paths:
		_check(source_hashes[path] == _sha256(FileAccess.get_file_as_bytes(path)), "Source changed while exporting: " + path)
	data["checks"] = {"max_forward_skin_error": max_forward_error, "max_inverse_roundtrip_error": max_roundtrip_error,
		"minimum_absolute_skin_determinant": minimum_determinant, "roundtrip_tolerance": ROUNDTRIP_TOLERANCE,
		"geometry_and_rest_unchanged": failures.is_empty(), "failures": failures}
	if failures.is_empty():
		_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir())) == OK, "Cannot create output directory")
	if failures.is_empty():
		var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
		if _check(file != null, "Cannot open output JSON"):
			file.store_string(JSON.stringify(data, "", false, true))
			file.flush()
			_check(file.get_error() == OK, "JSON write failed")
			print("ACCEPTED_REST_RAW_OUTPUT modes=%d skirt_vertices=%d skirt_triangles=%d body_parts=%d bytes=%d" % [
				data.modes.size(), base_vertices.size(), arrays[Mesh.ARRAY_INDEX].size() / 3, body.size(), file.get_length()])
			file.close()
	_finish(doll)


func _finish(doll: Node3D) -> void:
	doll.free()
	print("ACCEPTED_REST_CONTACT_RAW %s forward_error=%.9f inverse_error=%.9f" % [
		"PASS" if failures.is_empty() else "FAIL", max_forward_error, max_roundtrip_error])
	quit(0 if failures.is_empty() else 1)
