extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const OUTPUT := "res://captures/garment_contour_diagnostic.json"
const BIN_COUNT := 24
const DIRECTIONS := ["front", "back", "left", "right"]
const LABELS := ["LongSkirt", "TailoredShell"]
var failures: Array[String] = []
var checks := 0
var records: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		if failures.size() <= 8: push_error(message)
	return ok


func _xyz(p: Vector3) -> Array:
	return [p.x, p.y, p.z]


func _sector(p: Vector3) -> String:
	if absf(p.z) >= absf(p.x): return "front" if p.z >= 0 else "back"
	return "right" if p.x >= 0 else "left"


func _maximum(previous: Dictionary, value: float, index: int, original: Vector3, skinned: Vector3, contacted: Vector3) -> Dictionary:
	if not previous.is_empty() and value <= float(previous.value_m): return previous
	return {"value_m": value, "vertex_index": index, "original_rest": _xyz(original),
		"skinned": _xyz(skinned), "contacted": _xyz(contacted)}


func _body_signature(doll: Node3D) -> int:
	var data: Array = []
	for part: MeshInstance3D in doll.rig.meshes:
		if part.get_meta("is_underbody", false): data.append(part.mesh.surface_get_arrays(0))
	for bone in doll.rig.skeleton.get_bone_count(): data.append(doll.rig.skeleton.get_bone_rest(bone))
	return hash(var_to_bytes(data))


func _measure(doll: Node3D, part: MeshInstance3D, pose: String) -> Dictionary:
	var arrays := part.mesh.surface_get_arrays(0)
	var original: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw_skinned: PackedVector3Array = doll.rig.deformed_vertices(part)
	var raw_contacted: PackedVector3Array = doll.body_contact.evaluate_vertices(part)
	var context := "style%d/%s/%s" % [doll.outfit_style, pose, part.name]
	if not _check(original.size() > 0 and raw_skinned.size() == original.size() and raw_contacted.size() == original.size(), context + ": invalid vertex counts"):
		return {}
	var hip: int = doll.rig.bones.Hips
	var skin: Transform3D = doll.rig.global_pose(hip) * doll.rig.skeleton.get_bone_global_rest(hip).affine_inverse()
	if not _check(skin.is_finite() and absf(skin.basis.determinant()) > .000001, context + ": invalid Hips skin transform"):
		return {}
	var to_rest := skin.affine_inverse()
	var arm_ids: Array = [doll.rig.bones.UpperArmL, doll.rig.bones.ForearmL, doll.rig.bones.UpperArmR, doll.rig.bones.ForearmR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var eligible := PackedInt32Array()
	var minimum := INF
	var maximum := -INF
	var excluded := 0
	for i in original.size():
		if not _check(original[i].is_finite() and raw_skinned[i].is_finite() and raw_contacted[i].is_finite(), context + ": nonfinite source sample"):
			continue
		var sleeve := 0.0
		if str(part.name) == "TailoredShell":
			for j in 4:
				if bones[i * 4 + j] in arm_ids: sleeve += weights[i * 4 + j]
		if sleeve > .001:
			excluded += 1
			continue
		eligible.append(i)
		minimum = minf(minimum, original[i].y)
		maximum = maxf(maximum, original[i].y)
	if not _check(not eligible.is_empty() and maximum > minimum, context + ": empty eligible height range"):
		return {}
	var bins: Array = []
	for b in BIN_COUNT:
		var directions := {}
		for direction in DIRECTIONS:
			directions[direction] = {"count": 0, "rest": null, "skinned": null, "contacted": null}
		bins.append({"index": b, "rest_y_min": lerpf(minimum, maximum, float(b) / BIN_COUNT),
			"rest_y_max": lerpf(minimum, maximum, float(b + 1) / BIN_COUNT),
			"directions": directions, "max_runtime_displacement_m": 0.0})
	var runtime_max := {}
	var skin_max := {}
	var total_max := {}
	var radial_growth_max := {}
	var hip_max := {}
	var changed := 0
	for i in eligible:
		var p := original[i]
		var skinned: Vector3 = to_rest * raw_skinned[i]
		var contacted: Vector3 = to_rest * raw_contacted[i]
		if not _check(skinned.is_finite() and contacted.is_finite(), context + ": nonfinite Hips-rest sample"):
			continue
		var b := mini(BIN_COUNT - 1, int(floor((p.y - minimum) / (maximum - minimum) * BIN_COUNT)))
		var sector: Dictionary = bins[b].directions[_sector(p)]
		sector.count += 1
		var radii := [Vector2(p.x, p.z).length(), Vector2(skinned.x, skinned.z).length(), Vector2(contacted.x, contacted.z).length()]
		for stage in 3:
			var label: String = ["rest", "skinned", "contacted"][stage]
			sector[label] = radii[stage] if sector[label] == null else maxf(sector[label], radii[stage])
		var displacement := skinned.distance_to(contacted)
		if displacement > .000001: changed += 1
		bins[b].max_runtime_displacement_m = maxf(bins[b].max_runtime_displacement_m, displacement)
		runtime_max = _maximum(runtime_max, displacement, i, p, skinned, contacted)
		skin_max = _maximum(skin_max, p.distance_to(skinned), i, p, skinned, contacted)
		total_max = _maximum(total_max, p.distance_to(contacted), i, p, skinned, contacted)
		radial_growth_max = _maximum(radial_growth_max, radii[2] - radii[1], i, p, skinned, contacted)
		if p.y >= 1.0 and p.y <= 1.4:
			hip_max = _maximum(hip_max, displacement, i, p, skinned, contacted)
	return {"style": doll.outfit_style, "pose": pose, "part": str(part.name), "present": true,
		"vertex_count": original.size(), "eligible_vertices": eligible.size(), "excluded_sleeve_vertices": excluded,
		"changed_by_runtime_contact": changed, "rest_height_range": [minimum, maximum], "bins": bins,
		"max_runtime_displacement": runtime_max, "max_skinning_displacement": skin_max,
		"max_total_displacement": total_max, "max_runtime_radial_growth": radial_growth_max,
		"max_runtime_displacement_in_hip_band": hip_max}


func _sample_style(style: int) -> void:
	var doll := Doll.new()
	root.add_child(doll)
	doll.configure({"outfit": style, "hair": 0, "skin": 0, "palette": style})
	doll.process_mode = Node.PROCESS_MODE_DISABLED
	if not _check(doll.rig != null and doll.body_contact != null and doll.body_contact.has_method("evaluate_vertices"), "Missing contact evaluator for style %d" % style):
		doll.free()
		return
	var before := _body_signature(doll)
	for pose in ["idle", "hands_abdomen", "walk_pi_2"]:
		doll.clear_interaction()
		_check(doll.hand_targets.is_empty() and doll.foot_targets.is_empty(), "Reach cleanup failed")
		doll.body_contact.motion.clear()
		doll.body_contact.motion_amount = 0.0
		doll.rig.animate(PI / 2.0 if pose == "walk_pi_2" else 0.0, 1.0 if pose == "walk_pi_2" else 0.0, "idle", .5)
		if pose == "hands_abdomen":
			for side in [-1.0, 1.0]:
				var suffix := "L" if side < 0 else "R"
				doll.reach(suffix, doll.body_rig.to_global(Vector3(side * .08, 1.40, .30)))
			doll.apply_reaches()
			for suffix in ["L", "R"]:
				var hand: Vector3 = doll.body_rig.to_global(doll.rig.global_pose(doll.rig.bones["Hand" + suffix]).origin)
				_check(hand.is_finite() and hand.distance_to(doll.hand_targets[suffix]) < .025, "Abdomen reach target missed")
		else:
			doll.body_contact.update()
		for label in LABELS:
			var part: MeshInstance3D
			for candidate: MeshInstance3D in doll.rig.meshes:
				if str(candidate.name) == label: part = candidate
			if part == null:
				_check(style == 2 and label == "LongSkirt", "Unexpected missing garment: " + label)
				records.append({"style": style, "pose": pose, "part": label, "present": false,
					"reason": "Style 2 uses trousers, not LongSkirt"})
			else:
				records.append(_measure(doll, part, pose))
		doll.clear_interaction()
		_check(_body_signature(doll) == before, "Accepted body/rest skeleton changed")
	doll.free()


func _run() -> void:
	for style in 3: _sample_style(style)
	_check(records.size() == 18 and records.all(func(record: Dictionary) -> bool: return not record.is_empty()), "Incomplete diagnostic records")
	var report := {"schema": "garment-contour-diagnostic-v1", "generated_utc": Time.get_datetime_string_from_system(true),
		"units": "meters", "height_bins": BIN_COUNT, "hip_band_rest_y": [1.0, 1.4],
		"coordinate_space": "Original mesh rest coordinates; skinned/contacted multiplied by inverse(global_pose(Hips) * global_rest(Hips).affine_inverse())",
		"rest_stage": "Current mesh after static body fit and contour shaping, before animation; NOT an unfitted garment baseline",
		"direction_rule": "Fixed original-rest dominant-axis sectors: front +Z, back -Z, left -X, right +X; radial maximum is sqrt(x*x+z*z)",
		"bin_rule": "24 equal bins over each part's eligible original-rest Y range, last bin includes upper endpoint; null maxima mean empty sector",
		"shell_exclusion": "Sum of UpperArmL/ForearmL/UpperArmR/ForearmR weights greater than 0.001",
		"contact_stage": "CPU body_contact.evaluate_vertices, not GPU readback; secondary motion zeroed to isolate collision/lift",
		"runtime_displacement": "Distance between contacted and skinned positions, not total animation displacement",
		"pose_parameters": {"work_phase": .5, "hands_abdomen": {"L": [-.08, 1.40, .30], "R": [.08, 1.40, .30]}, "walk_wave": PI / 2.0},
		"checks": checks, "failures": failures, "records": records}
	var directory := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	if _check(directory == OK, "Cannot create diagnostic output directory"):
		var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
		if _check(file != null, "Cannot open diagnostic output"):
			file.store_string(JSON.stringify(report, "\t"))
			file.flush()
			_check(file.get_error() == OK, "Diagnostic write failed")
			file.close()
	print("GARMENT_CONTOUR_DIAGNOSTIC ", "PASS" if failures.is_empty() else "FAIL", " records=", records.size(), " checks=", checks, " failures=", failures.size(), " output=", OUTPUT)
	quit(0 if failures.is_empty() else 1)
