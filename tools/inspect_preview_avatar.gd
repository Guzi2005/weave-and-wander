extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var doll := Doll.new()
	root.add_child(doll)
	doll.configure({"outfit":0,"hair":0,"palette":0,"skin":0})
	doll.set_process(false)
	var total := 0
	for part in doll.rig.meshes:
		var semantic := str(part.get_meta("semantic", ""))
		var arrays: Array = part.mesh.surface_get_arrays(0)
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		var excluded := semantic in ["skirt", "apron"] or str(part.name) in ["WaistRibbon","ApronStrapL","ApronStrapR","ApronTie"]
		if not excluded: total += count
		print("PART ", part.name, " semantic=", semantic, " vertices=", count, " excluded=", excluded, " blends=", part.mesh.get_blend_shape_count())
	print("TOTAL_VISIBLE_VERTICES ",total)
	for bone in doll.rig.skeleton.get_bone_count():
		print("BONE ",bone," ",doll.rig.skeleton.get_bone_name(bone)," parent=",doll.rig.skeleton.get_bone_parent(bone)," global=",doll.rig.skeleton.get_bone_global_rest(bone).origin)
	for action in ["stand","walk","sit","nap"]:
		doll.rig.animate(PI*.5,1.0 if action=="walk" else 0.0,"idle",0.0)
		if action in ["sit","nap"]: doll.rig.pose_rest(action,1.0,0.0)
		var low := Vector3(INF,INF,INF)
		var high := Vector3(-INF,-INF,-INF)
		for part in doll.rig.meshes:
			if not part.is_visible_in_tree(): continue
			for p in doll.rig.deformed_vertices(part):
				low=low.min(p)
				high=high.max(p)
		print("POSE ",action," low=",low," high=",high," root=",doll.rig.global_pose(doll.rig.bones.Root)," hips=",doll.rig.global_pose(doll.rig.bones.Hips).origin)
	quit()
