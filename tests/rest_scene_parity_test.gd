extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var early := Doll.new()
	early.configure({"outfit":1,"hair":2,"palette":2,"skin":1})
	root.add_child(early)
	var late := Doll.new()
	root.add_child(late)
	late.configure({"outfit":1,"hair":2,"palette":2,"skin":1})
	await process_frame
	for doll in [early,late]:
		doll.rig.animate(0,0,"idle",0)
		doll.rig.pose_rest("nap",1.0)
	for path in ["SkinnedMeshes/skirt/LongSkirt","SkinnedMeshes/legR/Calf","SkinnedMeshes/shoeR/ShoeUpper"]:
		var a: MeshInstance3D = early.body_rig.get_node_or_null(path)
		var b: MeshInstance3D = late.body_rig.get_node_or_null(path)
		if a == null or b == null:
			failures.append("Missing parity mesh: "+path)
			continue
		var av: PackedVector3Array = early.rig.deformed_vertices(a)
		var bv: PackedVector3Array = late.rig.deformed_vertices(b)
		var maximum := 0.0
		for index in av.size(): maximum=maxf(maximum,av[index].distance_to(bv[index]))
		if maximum > .0001: failures.append(path)
		for index in a.skin.get_bind_count():
			if not a.skin.get_bind_pose(index).is_equal_approx(b.skin.get_bind_pose(index)):
				failures.append("Skin bind mismatch "+path+"/"+str(index))
		for index in a.mesh.get_blend_shape_count():
			if not is_equal_approx(a.get_blend_shape_value(index),b.get_blend_shape_value(index)):
				failures.append("Blend weight mismatch "+path+"/"+str(index))
	early.free()
	late.free()
	print("REST_SCENE_PARITY failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
