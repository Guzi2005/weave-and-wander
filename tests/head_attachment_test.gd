extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if not value and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var doll := preload("res://scripts/volume_doll.gd").new()
	root.add_child(doll)
	var samples := 0
	for hair in 3:
		for hood in [false,true]:
			doll.configure({"hair":hair,"reference":hood})
			var head: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/head/Head")
			var nose: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/head/RoundNose")
			var bounds := head.mesh.get_aabb()
			_check(bounds.size.z/bounds.size.y >= .94,"Head profile must be round, not flattened front to back.")
			var head_ids: PackedInt32Array = head.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			for frame in 12:
				doll.rig.animate(frame*TAU/12.0,1.0,"sewing",.25)
				var head_vertices: PackedVector3Array = doll.rig.deformed_vertices(head)
				var nose_vertices: PackedVector3Array = doll.rig.deformed_vertices(nose)
				var center := Vector3.ZERO
				for point in nose_vertices:
					center += point
				center /= nose_vertices.size()
				var head_bone: Transform3D = doll.rig.skeleton.get_bone_global_pose(doll.rig.bones["Head"])
				var backward := -head_bone.basis.z.normalized()
				var nose_back := center+backward*.051
				var deepest := 0.0
				for i in range(0,head_ids.size(),3):
					var hit = Geometry3D.segment_intersects_triangle(nose_back,nose_back-backward*.12,
						head_vertices[head_ids[i]],head_vertices[head_ids[i+1]],head_vertices[head_ids[i+2]])
					if hit != null:
						deepest = maxf(deepest,nose_back.distance_to(hit))
				_check(deepest > .025 and deepest < .065,"Nose must intersect cheek mesh substantially during animation.")
				samples += 1
	print("HEAD_ATTACHMENT_CHECK poses=",samples," failures=",failures.size())
	doll.free()
	quit(0 if failures.is_empty() else 1)
