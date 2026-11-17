extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const Split = preload("res://tests/experiments/garment_seam_split.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and message not in failures: failures.append(message)


func _area(arrays: Array) -> float:
	var result := 0.0
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for face in range(0, ids.size(), 3):
		result += (points[ids[face + 1]] - points[ids[face]]).cross(points[ids[face + 2]] - points[ids[face]]).length() * .5
	return result


func _run() -> void:
	var doll := Doll.new()
	doll.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(doll)
	doll.configure({"outfit": 0, "hair": 0, "skin": 0, "palette": 0})
	var skirt: MeshInstance3D = doll.body_rig.find_child("LongSkirt", true, false)
	var band: MeshInstance3D = doll.body_rig.find_child("WaistRibbon", true, false)
	var height := INF
	for point: Vector3 in band.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: height = minf(height, point.y)
	var before := skirt.mesh.surface_get_arrays(0)
	var original_hash := hash(var_to_bytes([before, skirt.mesh.surface_get_blend_shape_arrays(0)]))
	var result := Split.split(skirt.mesh, height)
	_check(result.error.is_empty(), str(result.error))
	if result.error.is_empty():
		var after: Array = result.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = after[Mesh.ARRAY_VERTEX]
		var original: PackedVector3Array = before[Mesh.ARRAY_VERTEX]
		_check(result.added_vertices > 0 and result.cut_faces > 0, "Expected seam refinement")
		_check(points.slice(0, original.size()) == original, "Original standing points changed")
		_check(absf(_area(before) - _area(after)) < .00001, "Standing surface area changed")
		_check(hash(var_to_bytes([skirt.mesh.surface_get_arrays(0), skirt.mesh.surface_get_blend_shape_arrays(0)])) == original_hash, "Source mesh mutated")
		_check(result.mesh.get_blend_shape_count() == skirt.mesh.get_blend_shape_count(), "Morphs lost")
		_check(result.mesh.surface_get_material(0) == skirt.mesh.surface_get_material(0), "Material changed")
		for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			_check(after[slot].slice(0, before[slot].size()) == before[slot], "Original stream changed: " + str(slot))
		var normal_error := 0.0
		var tangent_error := 0.0
		for id in original.size():
			normal_error = maxf(normal_error, before[Mesh.ARRAY_NORMAL][id].distance_to(after[Mesh.ARRAY_NORMAL][id]))
			for channel in 4:
				tangent_error = maxf(tangent_error, absf(before[Mesh.ARRAY_TANGENT][id * 4 + channel] - after[Mesh.ARRAY_TANGENT][id * 4 + channel]))
		print("SEAM_REENCODING normal_error=", normal_error, " tangent_error=", tangent_error)
		_check(normal_error < .0002 and tangent_error < .0002, "Normal/tangent reencoding exceeded quantization tolerance")
		var old_shapes := skirt.mesh.surface_get_blend_shape_arrays(0)
		var new_shapes: Array = result.mesh.surface_get_blend_shape_arrays(0)
		for shape in old_shapes.size():
			_check(result.mesh.get_blend_shape_name(shape) == skirt.mesh.get_blend_shape_name(shape), "Morph name changed")
			_check(new_shapes[shape][Mesh.ARRAY_VERTEX].size() == points.size(), "Incomplete morph refinement")
		for binding: Dictionary in result.edge_bindings:
			var a: int = binding.edge[0]
			var b: int = binding.edge[1]
			var id: int = binding.index
			_check(points[id].distance_to(original[a].lerp(original[b], binding.weight)) < .000001, "New point left original edge")
			_check(absf(points[id].y - height) < .000001, "New point missed real waistband boundary")
			_check(after[Mesh.ARRAY_TEX_UV2][id].distance_to(before[Mesh.ARRAY_TEX_UV2][a].lerp(before[Mesh.ARRAY_TEX_UV2][b], binding.weight)) < .000001, "Inertia UV2 not interpolated")
			var weight_sum := 0.0
			for slot in 4: weight_sum += after[Mesh.ARRAY_WEIGHTS][id * 4 + slot]
			_check(absf(weight_sum - 1.0) < .0001, "Refined skin weights are not normalized")
			for shape in old_shapes.size():
				var expected: Vector3 = old_shapes[shape][Mesh.ARRAY_VERTEX][a].lerp(old_shapes[shape][Mesh.ARRAY_VERTEX][b], binding.weight)
				_check(expected.distance_to(new_shapes[shape][Mesh.ARRAY_VERTEX][id]) < .000001, "Morph was not interpolated on the original edge")
		var indices: PackedInt32Array = after[Mesh.ARRAY_INDEX]
		for face in range(0, indices.size(), 3):
			var low := INF
			var high := -INF
			for corner in 3:
				low = minf(low, points[indices[face + corner]].y)
				high = maxf(high, points[indices[face + corner]].y)
			_check(not (low < height - .000001 and high > height + .000001), "Triangle still spans fixed and free sides")
		var again := Split.split(result.mesh, height)
		_check(again.error.is_empty() and again.added_vertices == 0, "Seam split is not idempotent")
		var original_mesh := skirt.mesh
		for pose in ["stand", "walk", "sit", "nap"]:
			doll.rig.animate(.6, 1.0 if pose == "walk" else 0.0, "idle", 0.0)
			doll.rig.pose_rest("nap" if pose == "nap" else "sit", 1.0 if pose in ["sit", "nap"] else 0.0, 0.0, Vector4(1, 0, 0, 0))
			var old_pose: PackedVector3Array = doll.rig.deformed_vertices(skirt)
			skirt.mesh = result.mesh
			var new_pose: PackedVector3Array = doll.rig.deformed_vertices(skirt)
			_check(old_pose == new_pose.slice(0, old_pose.size()), "Original posed points changed: " + pose)
			skirt.mesh = original_mesh
	doll.free()
	print("GARMENT_SEAM_SPLIT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
