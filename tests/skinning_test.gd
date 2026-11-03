extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")
var failures: Array[String] = []
var tested_poses := 0
var clearance_samples := 0
var maximum_sole_tilt := 0.0
var shoulder_samples := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var doll := Doll.new()
	root.add_child(doll)
	for recipe in [{"outfit": 0}, {"outfit": 1}, {"outfit": 2}, {"outfit": 0, "reference": true}]:
		doll.configure(recipe)
		var rig = doll.rig
		_check(rig.skeleton.get_bone_count() == 22 and rig.bones.has("EyeL") and rig.bones.has("EyeR"), "Expected body, garment and independent eye bones.")
		var shell := doll.body_rig.get_node("SkinnedMeshes/garment/TailoredShell")
		_check(shell.get_meta("garment_component") == "simple_shell", "Default doll must use the approved simple-parts construction.")
		_check_shoulders(doll)
		var nose: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/head/RoundNose")
		var nose_size := nose.mesh.get_aabb().size
		_check(absf(nose_size.x - nose_size.y) < 0.002 and absf(nose_size.y - nose_size.z) < 0.002, "Nose must be a simple sphere.")
		var skirt: MeshInstance3D = doll.body_rig.get_node_or_null("SkinnedMeshes/skirt/LongSkirt")
		if skirt != null:
			_check(doll.body_rig.find_children("Trouser*", "", true, false).is_empty(), "Covered trouser mesh should be masked under long garments.")
		for sample in 24:
			var wave := TAU * sample / 24.0
			rig.animate(wave, 1.0, "idle", 0)
			tested_poses += 1
			if sample % 6 == 0:
				_check_shoulders(doll)
			var skirt_vertices := PackedVector3Array()
			var skirt_indices := PackedInt32Array()
			if skirt != null:
				skirt_vertices = rig.deformed_vertices(skirt)
				skirt_indices = skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			for instance in rig.meshes:
				if not str(instance.name).begins_with("FlatSole") and not str(instance.name).begins_with("ShoeUpper"):
					continue
				var rest: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var deformed: PackedVector3Array = rig.deformed_vertices(instance)
				var min_y := INF
				var max_y := -INF
				for i in rest.size():
					var point := deformed[i]
					_check(point.is_finite(), "Non-finite skinned vertex.")
					_check(point.y > -0.002, "Shoe penetrated the floor.")
					if rest[i].y < 0.010:
						min_y = minf(min_y, point.y)
						max_y = maxf(max_y, point.y)
					if skirt != null and point.y > 0.213:
						clearance_samples += 1
						var inside := _inside_skirt(point, skirt_vertices, skirt_indices)
						if not inside and failures.is_empty():
							print("CLEARANCE_SAMPLE wave=", wave, " point=", point, " outfit=", doll.outfit_style)
						_check(inside, "Shoe upper protrudes through the long garment above its hem.")
				if min_y != INF:
					maximum_sole_tilt = maxf(maximum_sole_tilt, max_y - min_y)
					_check(max_y - min_y < 0.001, "Shoe sole rolls instead of remaining flat.")
		for activity in ["sewing", "stocking", "checkout"]:
			rig.animate(0, 0, activity, 0.25)
			_check_shoulders(doll)
			_check(rig.skeleton.get_bone_pose_rotation(rig.bones["ForearmL"]).angle_to(Quaternion.IDENTITY) > 0.1, "Work pose did not bend the elbow.")
	print("SKINNING_CHECK poses=", tested_poses, " clearance_vertices=", clearance_samples,
		" shoulder_pivots=", shoulder_samples, " sole_tilt=", maximum_sole_tilt, " failures=", failures.size())
	doll.free()
	quit(0 if failures.is_empty() else 1)


func _inside_skirt(point: Vector3, vertices: PackedVector3Array, indices: PackedInt32Array) -> bool:
	var hits: Array[float] = []
	for index in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		if point.y < minf(a.y, minf(b.y, c.y)) or point.y > maxf(a.y, maxf(b.y, c.y)):
			continue
		if point.x < minf(a.x, minf(b.x, c.x)) or point.x > maxf(a.x, maxf(b.x, c.x)):
			continue
		var hit = Geometry3D.segment_intersects_triangle(point, point + Vector3(0, 0, 3), a, b, c)
		if hit == null:
			continue
		var duplicate := false
		for distance in hits:
			if absf(distance - hit.z) < 0.0001:
				duplicate = true
		if not duplicate:
			hits.append(hit.z)
	return hits.size() % 2 == 1


func _check_shoulders(doll: VolumeDoll) -> void:
	var rig = doll.rig
	var bodice: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/garment/TailoredShell")
	var body_vertices: PackedVector3Array = rig.deformed_vertices(bodice)
	var body_indices: PackedInt32Array = bodice.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	# Overlapping sleeve roots are intentional; test containment against the torso alone.
	body_indices = body_indices.slice(0, bodice.get_meta("torso_index_count", body_indices.size()))
	for suffix in ["L", "R"]:
		var pivot: Vector3 = rig.skeleton.get_bone_global_pose(rig.bones["UpperArm" + suffix]).origin
		shoulder_samples += 1
		_check(_inside_skirt(pivot, body_vertices, body_indices), "Shoulder pivot is outside the torso.")
