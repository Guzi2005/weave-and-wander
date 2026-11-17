extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const SeamSplit = preload("res://tests/experiments/garment_seam_split.gd")
const SOURCE_PATHS := ["res://scripts/accepted_body_v20.gd", "res://scripts/shorter_arm_body.gd",
	"res://scripts/doll_rig.gd", "res://scripts/game_body_doll.gd", "res://scripts/rest_cloth.gd",
	"res://scripts/volume_doll.gd"]
const BODY_ORDER := ["torso", "legL", "legR"]
const TOLERANCE := 0.00002
var failures: Array[String] = []
var checks := 0
var max_forward_error := 0.0
var max_inverse_error := 0.0
var minimum_determinant := INF


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok and message not in failures:
		failures.append(message)
		if failures.size() <= 8: push_error("WEARING_SIMULATION: " + message)
	return ok


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _vectors(points: PackedVector3Array) -> Array:
	var result: Array = []
	for point in points:
		_check(point.is_finite(), "Nonfinite vertex or normal")
		result.append([point.x, point.y, point.z])
	return result


func _transform(transform: Transform3D) -> Dictionary:
	# Godot stores basis columns; Blender Matrix(rows) needs rows.
	var b := transform.basis
	return {"basis_rows": [[b.x.x, b.y.x, b.z.x], [b.x.y, b.y.y, b.z.y], [b.x.z, b.y.z, b.z.z]],
		"origin": [transform.origin.x, transform.origin.y, transform.origin.z]}


func _geometry_signature(doll: Node3D) -> String:
	# Exclude animated poses and morph weights, but retain every immutable array.
	var data: Array = [doll.arm_shortening, doll.body_rig.transform]
	for part: MeshInstance3D in doll.rig.meshes:
		data.append([str(doll.body_rig.get_path_to(part)), part.transform, part.visible,
			part.mesh.surface_get_arrays(0), part.mesh.surface_get_blend_shape_arrays(0),
			part.mesh.blend_shape_mode])
		for shape in part.mesh.get_blend_shape_count():
			data.append(part.mesh.get_blend_shape_name(shape))
		for bind in part.skin.get_bind_count():
			data.append([part.skin.get_bind_bone(bind), part.skin.get_bind_pose(bind)])
	var skeleton: Skeleton3D = doll.rig.skeleton
	for bone in skeleton.get_bone_count():
		data.append([skeleton.get_bone_name(bone), skeleton.get_bone_parent(bone),
			skeleton.get_bone_rest(bone), skeleton.get_bone_global_rest(bone)])
	return _sha256(var_to_bytes(data))


func _valid_mesh(part: MeshInstance3D, bone_count: int) -> bool:
	var label := str(part.name)
	if not _check(part.mesh != null and part.mesh.get_surface_count() == 1, "Expected one surface: " + label): return false
	if not _check(part.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "Expected triangles: " + label): return false
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if not _check(not vertices.is_empty() and arrays[Mesh.ARRAY_NORMAL] != null, "Missing geometry: " + label): return false
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if not _check(normals.size() == vertices.size(), "Normal count mismatch: " + label): return false
	if not _check(arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null, "Missing skin arrays: " + label): return false
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if not _check(ids.size() == vertices.size() * 4 and weights.size() == ids.size(), "Expected four skin influences: " + label): return false
	if not _check(arrays[Mesh.ARRAY_INDEX] != null, "Missing indices: " + label): return false
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(not indices.is_empty() and indices.size() % 3 == 0, "Invalid triangle count: " + label)
	for index in indices:
		_check(index >= 0 and index < vertices.size(), "Index out of range: " + label)
	for vertex in vertices.size():
		_check(vertices[vertex].is_finite() and normals[vertex].is_finite(), "Nonfinite rest data: " + label)
		var total := 0.0
		for slot in 4:
			var influence := vertex * 4 + slot
			_check(ids[influence] >= 0 and ids[influence] < bone_count, "Invalid skin bone: " + label)
			_check(is_finite(weights[influence]) and weights[influence] >= 0.0, "Invalid skin weight: " + label)
			total += weights[influence]
		_check(absf(total - 1.0) <= 4.0 / 65535.0, "Skin weights do not sum to one: " + label)
	return failures.is_empty()


func _inverse_skin(doll: Node3D, skirt: MeshInstance3D, posed: PackedVector3Array) -> Array:
	var arrays := skirt.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var transforms: Array[Transform3D] = []
	var skeleton: Skeleton3D = doll.rig.skeleton
	for bone in skeleton.get_bone_count():
		transforms.append(doll.rig.global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse())
	var result: Array = []
	for vertex in vertices.size():
		var weighted := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
		for slot in 4:
			var influence := vertex * 4 + slot
			var skin := transforms[ids[influence]]
			var weight := weights[influence]
			weighted.basis.x += skin.basis.x * weight
			weighted.basis.y += skin.basis.y * weight
			weighted.basis.z += skin.basis.z * weight
			weighted.origin += skin.origin * weight
		var determinant := absf(weighted.basis.determinant())
		if not _check(weighted.is_finite() and determinant > 0.00000001, "Nonfinite or singular skin transform"): return []
		minimum_determinant = minf(minimum_determinant, determinant)
		var inverse := weighted.affine_inverse()
		if not _check(inverse.is_finite(), "Nonfinite inverse skin transform"): return []
		max_forward_error = maxf(max_forward_error, (weighted * vertices[vertex]).distance_to(posed[vertex]))
		max_inverse_error = maxf(max_inverse_error, (inverse * posed[vertex]).distance_to(vertices[vertex]))
		result.append(_transform(inverse))
	return result


func _bone_targets(doll: Node3D, vertices: PackedVector3Array, preserve_sections := false, waist_bottom := 1.30) -> PackedVector3Array:
	var skeleton: Skeleton3D = doll.rig.skeleton
	var skins: Array[Transform3D] = []
	for label in ["Hips", "ThighL", "ThighR", "ShinL", "ShinR"]:
		var bone := skeleton.find_bone(label)
		if not _check(bone >= 0, "Missing shape target bone: " + label): return PackedVector3Array()
		var skin: Transform3D = doll.rig.global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()
		if not _check(skin.is_finite(), "Nonfinite shape target skin transform"): return PackedVector3Array()
		skins.append(skin)
	var result := PackedVector3Array()
	for point in vertices:
		var hip_point := skins[0] * point
		# Both legs share one skirt envelope; never choose a side from point.x.
		var thigh_point := ((skins[1] * point) + (skins[2] * point)) * 0.5
		var shin_point := ((skins[3] * point) + (skins[4] * point)) * 0.5
		var thigh_blend := 1.0 - smoothstep(1.04, waist_bottom, point.y)
		var shin_blend := 1.0 - smoothstep(0.45, 0.78, point.y)
		var target := hip_point.lerp(thigh_point.lerp(shin_point, shin_blend), thigh_blend)
		if preserve_sections:
			var center := Vector3(0.0, point.y, 0.0)
			var hip_center := skins[0] * center
			var thigh_center := ((skins[1] * center) + (skins[2] * center)) * 0.5
			var shin_center := ((skins[3] * center) + (skins[4] * center)) * 0.5
			var posed_center := hip_center.lerp(thigh_center.lerp(shin_center, shin_blend), thigh_blend)
			var hip_rotation := skins[0].basis.get_rotation_quaternion()
			var thigh_rotation := skins[1].basis.get_rotation_quaternion().slerp(skins[2].basis.get_rotation_quaternion(), 0.5)
			var shin_rotation := skins[3].basis.get_rotation_quaternion().slerp(skins[4].basis.get_rotation_quaternion(), 0.5)
			var rotation := hip_rotation.slerp(thigh_rotation.slerp(shin_rotation, shin_blend), thigh_blend)
			target = posed_center + rotation * (point - center)
			_check(absf(target.distance_to(posed_center) - point.distance_to(center)) <= TOLERANCE,
				"Section rotation changed the standing radial clearance")
		_check(target.is_finite(), "Nonfinite shared-bone shape target")
		if point.y >= waist_bottom:
			_check(target.distance_to(hip_point) <= TOLERANCE, "Shared-bone root differs from hip skin")
		result.append(target)
	return result


func _run() -> void:
	var nap := 0
	var seen_nap := false
	var include_shape_targets := false
	var include_bone_targets := false
	var preserve_sections := false
	var attach_waist := false
	var split_waist := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--split-waist":
			if not _check(not split_waist, "--split-waist cannot repeat"): break
			split_waist = true
			continue
		if arg == "--attach-waist":
			if not _check(not attach_waist, "--attach-waist cannot repeat"): break
			attach_waist = true
			continue
		if arg == "--preserve-sections":
			if not _check(not preserve_sections, "--preserve-sections cannot repeat"): break
			preserve_sections = true
			continue
		if arg in ["--shape-targets", "--bone-targets"]:
			if not _check(not include_shape_targets and not include_bone_targets,
				"--shape-targets and --bone-targets are mutually exclusive and cannot repeat"): break
			include_shape_targets = arg == "--shape-targets"
			include_bone_targets = arg == "--bone-targets"
			continue
		if not _check(arg.begins_with("--nap=") and not seen_nap, "Expected --nap=N (0..3), --shape-targets or --bone-targets, each at most once"): break
		var value := arg.trim_prefix("--nap=")
		if not _check(value in ["0", "1", "2", "3"], "Nap variant must be 0..3"): break
		nap = int(value)
		seen_nap = true
	_check(not preserve_sections or include_bone_targets, "--preserve-sections requires --bone-targets")
	_check(not attach_waist or (include_bone_targets and not preserve_sections), "--attach-waist requires --bone-targets without --preserve-sections")
	_check(not split_waist or attach_waist, "--split-waist requires --attach-waist")
	if not failures.is_empty():
		_finish()
		return
	var source_hashes := {}
	for path in SOURCE_PATHS:
		_check(FileAccess.file_exists(path), "Missing source: " + path)
		source_hashes[path] = FileAccess.get_sha256(path)
	var doll := Doll.new()
	doll.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(doll)
	doll.configure({"outfit": 0, "hair": 0, "skin": 0, "palette": 0})
	if not _check(doll.rig != null and is_instance_valid(doll.rig.skeleton), "Missing configured rig"):
		_finish(doll)
		return
	var skeleton: Skeleton3D = doll.rig.skeleton
	_check(skeleton.get_bone_count() == 22, "Expected 22 accepted bones")
	_check(doll.arm_shortening == 0.045, "Expected accepted 0.045 arm shortening")
	var skirt: MeshInstance3D
	var body_by_semantic := {}
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.is_visible_in_tree(): continue
		if str(part.name) == "LongSkirt":
			_check(skirt == null, "Duplicate LongSkirt")
			skirt = part
		if part.get_meta("is_underbody", false) and str(part.name) in ["MannequinTorso", "LegMannequin"]:
			var semantic: String = part.get_meta("semantic", "")
			_check(not body_by_semantic.has(semantic), "Duplicate body semantic: " + semantic)
			body_by_semantic[semantic] = part
	_check(skirt != null and body_by_semantic.size() == 3, "Expected LongSkirt, torso and two legs")
	var body: Array[MeshInstance3D] = []
	for semantic in BODY_ORDER:
		if _check(body_by_semantic.has(semantic), "Missing body part: " + semantic):
			body.append(body_by_semantic[semantic])
	if skirt != null: _valid_mesh(skirt, skeleton.get_bone_count())
	for part in body: _valid_mesh(part, skeleton.get_bone_count())
	if not failures.is_empty():
		_finish(doll)
		return
	var arrays := skirt.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var waist_attachment := {}
	var mesh_seam := {}
	if attach_waist:
		var band: MeshInstance3D = doll.body_rig.find_child("WaistRibbon", true, false)
		if not _check(band != null, "Missing actual waistband"): _finish(doll); return
		var low := INF
		var high := -INF
		for point: Vector3 in band.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			low = minf(low, point.y)
			high = maxf(high, point.y)
		var rows: Array[float] = []
		for point in vertices:
			if not rows.has(point.y): rows.append(point.y)
		rows.sort()
		var spacing := rows[-1] - rows[-2]
		if not _check(low > 1.04 and high <= rows[-1] + TOLERANCE and spacing > 0.0, "Waistband outside skirt root range"): _finish(doll); return
		waist_attachment = {"part": str(doll.body_rig.get_path_to(band)), "bone": "Hips",
			"lower_y": low, "upper_y": high, "release_y": low - spacing * 2.0,
			"release_rows": 2,
			"policy": "Waistband vertices follow hip skin; smooth compliant release over two existing rows below it"}
		if split_waist:
			var split := SeamSplit.split(skirt.mesh, low)
			if not _check(split.error.is_empty(), str(split.error)): _finish(doll); return
			_check(split.added_vertices > 0, "Waist boundary did not split the source surface")
			skirt.mesh = split.mesh
			mesh_seam = split.duplicate()
			mesh_seam.erase("mesh")
			arrays = skirt.mesh.surface_get_arrays(0)
			vertices = arrays[Mesh.ARRAY_VERTEX]
			_valid_mesh(skirt, skeleton.get_bone_count())
			waist_attachment.release_y = low - spacing
			waist_attachment.release_rows = 1
			waist_attachment.policy = "Exact waistband boundary split; fixed above seam, one original row of compliant release below"
			source_hashes["res://tests/experiments/garment_seam_split.gd"] = FileAccess.get_sha256("res://tests/experiments/garment_seam_split.gd")
	var signature := _geometry_signature(doll)
	var body_data: Array = []
	for index in body.size():
		var part := body[index]
		var source := part.mesh.surface_get_arrays(0)
		body_data.append({"index": index, "name": str(part.name), "semantic": BODY_ORDER[index],
			"path": str(doll.body_rig.get_path_to(part)), "vertex_count": source[Mesh.ARRAY_VERTEX].size(),
			"triangle_count": source[Mesh.ARRAY_INDEX].size() / 3,
			"rest_vertices": _vectors(source[Mesh.ARRAY_VERTEX]), "normals": _vectors(source[Mesh.ARRAY_NORMAL]),
			"indices": Array(source[Mesh.ARRAY_INDEX])})
	var data := {"schema_version": 1, "style": 0, "nap_variant": nap,
		"engine": Engine.get_version_info().string,
		"accepted_body_version": doll.body_rig.get_meta("accepted_body_version", ""),
		"source_sha256": source_hashes, "geometry_rest_sha256": signature, "bone_count": skeleton.get_bone_count(),
		"coordinate_space": "Godot rig/model space, +Y up; posed Root included; no world transform or axis conversion",
		"deformation": "Raw rig.deformed_vertices; all skirt morph weights zero; no runtime contact or pose binding",
		"inverse_convention": "Frame 180: unskinned_point = basis_rows * posed_point + origin; inverse of weighted skin transform, not weighted inverses",
		"morph_convention": "Unskinned corrected positions are absolute normalized morph positions, not base-relative deltas",
		"sampling": "animate(0,0,idle,0); pose_rest(nap,smoothstep(0,1,clamp((frame-30)/90,0,1)),0,onehot(nap_variant))",
		"base_skirt": {"name": "LongSkirt", "vertex_count": vertices.size(),
			"triangle_count": arrays[Mesh.ARRAY_INDEX].size() / 3,
			"vertex_sha256": _sha256(vertices.to_byte_array()),
			"vertex_hash_encoding": "PackedVector3Array.to_byte_array(): little-endian float32 XYZ without header",
			"vertices": _vectors(vertices), "normals": _vectors(arrays[Mesh.ARRAY_NORMAL]),
			"indices": Array(arrays[Mesh.ARRAY_INDEX])}, "body_parts": body_data, "frames": []}
	if split_waist: data["mesh_seam"] = mesh_seam
	if include_shape_targets:
		data["deformation"] = "Raw rig.deformed_vertices; cloth_shape_targets retain posed rest morphs; cloth_pin_targets have zero morph weights; no runtime contact or pose binding"
		data["shape_target_role"] = "ARTISTIC REST-SHAPE PREFERENCE for Blender dynamic-mesh cloth, NOT a hard collision corrective"
	elif include_bone_targets:
		data["deformation"] = "cloth_shape_targets use original standing vertices and actual Hips/Thigh/Shin skin transforms, not RestCloth morphs; body and zero-morph cloth_pin_targets remain raw rig.deformed_vertices"
		data["shape_target_role"] = "SHARED-BONE ARTISTIC SHAPE PREFERENCE for one skirt around BOTH legs, NOT collision corrected"
		data["shape_target_method"] = "lerp(hip_skin*p, lerp(mean(ThighL_skin*p,ThighR_skin*p), mean(ShinL_skin*p,ShinR_skin*p), 1-smoothstep(0.45,0.78,p.y)), 1-smoothstep(1.04,1.30,p.y)); skin=global_pose*inverse(global_rest)"
		if preserve_sections:
			data["shape_target_method"] += "; evaluate center at (0,p.y,0), rotate radial offset with slerped skin quaternions; no radius scaling"
		if attach_waist:
			data["waist_attachment"] = waist_attachment
			data["shape_target_method"] = data["shape_target_method"].replace("1.04,1.30", "1.04," + str(waist_attachment.lower_y))
	var frame_numbers: Array[int] = [1, 30]
	for frame in range(35, 121, 5): frame_numbers.append(frame)
	frame_numbers.append(180)
	var pose_weights := Vector4.ZERO
	pose_weights[nap] = 1.0
	for frame in frame_numbers:
		if not failures.is_empty(): break
		var amount := smoothstep(0.0, 1.0, clampf(float(frame - 30) / 90.0, 0.0, 1.0))
		doll.rig.animate(0.0, 0.0, "idle", 0.0)
		doll.rig.pose_rest("nap", amount, 0.0, pose_weights)
		var shaped := PackedVector3Array()
		if include_shape_targets:
			shaped = doll.rig.deformed_vertices(skirt)
		elif include_bone_targets:
			shaped = _bone_targets(doll, vertices, preserve_sections, float(waist_attachment.get("lower_y", 1.30)))
		if include_shape_targets or include_bone_targets:
			if not _check(shaped.size() == vertices.size(), "Skirt shape target count changed"): break
		# Pin motion is skeletal only; the cloth solver owns every unpinned vertex.
		for shape in skirt.mesh.get_blend_shape_count():
			skirt.set_blend_shape_value(shape, 0.0)
			_check(skirt.get_blend_shape_value(shape) == 0.0, "Skirt morph was not cleared")
		var posed_body: Array = []
		for index in body.size():
			var posed: PackedVector3Array = doll.rig.deformed_vertices(body[index])
			_check(posed.size() == body_data[index].vertex_count, "Body vertex count changed")
			posed_body.append({"index": index, "name": str(body[index].name), "semantic": BODY_ORDER[index],
				"vertices": _vectors(posed)})
		var pins: PackedVector3Array = doll.rig.deformed_vertices(skirt)
		if not _check(pins.size() == vertices.size(), "Skirt vertex count changed"): break
		var sample := {"frame": frame, "rest_amount": amount, "body_parts": posed_body,
			"cloth_pin_targets": _vectors(pins)}
		if include_shape_targets or include_bone_targets:
			sample["cloth_shape_targets"] = _vectors(shaped)
		if frame == 180:
			var inverses := _inverse_skin(doll, skirt, pins)
			_check(inverses.size() == vertices.size(), "Incomplete inverse skin transforms")
			sample["cloth_inverse_skin_transforms"] = inverses
		data.frames.append(sample)
		_check(_geometry_signature(doll) == signature, "Body/mesh arrays, skin binds or bone rests changed")
	_check(data.frames.size() == 21, "Incomplete frame sequence")
	_check(is_finite(minimum_determinant) and max_forward_error < TOLERANCE and max_inverse_error < TOLERANCE,
		"Invalid or inaccurate inverse skin mapping")
	for path in source_hashes:
		_check(source_hashes[path] == FileAccess.get_sha256(path), "Source changed during export: " + path)
	data["checks"] = {"count": checks, "failures": failures, "finite_and_counts_valid": failures.is_empty(),
		"geometry_and_22_bone_rests_unchanged": failures.is_empty(), "source_hashes_unchanged": failures.is_empty(),
		"max_forward_skin_error": max_forward_error, "max_inverse_roundtrip_error": max_inverse_error,
		"minimum_absolute_skin_determinant": minimum_determinant, "roundtrip_tolerance": TOLERANCE}
	var output := "res://captures/wearing_simulation_nap%d.json" % nap
	if include_shape_targets:
		output = "res://captures/wearing_shaped_simulation_nap%d.json" % nap
	elif include_bone_targets:
		output = "res://captures/wearing_bound_simulation_nap%d.json" % nap
		if preserve_sections:
			output = "res://captures/wearing_section_simulation_nap%d.json" % nap
		if attach_waist:
			output = "res://captures/wearing_attached_blend_simulation_nap%d.json" % nap
		if split_waist:
			output = "res://captures/wearing_seamed_simulation_nap%d.json" % nap
	if failures.is_empty():
		_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir())) == OK, "Cannot create output directory")
	if failures.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if _check(file != null, "Cannot open output JSON"):
			file.store_string(JSON.stringify(data, "", false, true))
			file.flush()
			_check(file.get_error() == OK, "JSON write failed")
			print("WEARING_SIMULATION_OUTPUT path=%s frames=%d skirt_vertices=%d body_vertices=%s bytes=%d" % [
				output, data.frames.size(), vertices.size(), str(body_data.map(func(part: Dictionary): return part.vertex_count)), file.get_length()])
			file.close()
	_finish(doll)


func _finish(doll: Node3D = null) -> void:
	if is_instance_valid(doll): doll.free()
	print("WEARING_SIMULATION %s checks=%d failures=%d forward_error=%.9f inverse_error=%.9f" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), max_forward_error, max_inverse_error])
	quit(0 if failures.is_empty() else 1)
