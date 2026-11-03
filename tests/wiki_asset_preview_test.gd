extends SceneTree
const Motion = preload("res://scripts/wiki_preview_motion.gd")
const Doll = preload("res://scripts/mosuo_doll.gd")
var failed := false
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value:
		failed = true
		push_error(label)
func run() -> void:
	var motion = Motion.new()
	motion.mode = "walk"
	motion.pace = .5
	motion.step(1.0)
	check(is_equal_approx(motion.walk_phase, PI),"Slow pace must advance half cycle")
	motion.pace = 1.5
	motion.step(1.0)
	check(is_equal_approx(motion.walk_phase, TAU*2),"Pace changes must preserve phase")
	motion.mode = "spin"
	motion.nonuniformity = .9
	var max_speed := 0.0
	var min_speed := 1000.0
	for frame in 480:
		motion.step(1.0/120.0)
		max_speed = maxf(max_speed,motion.angular_velocity)
		min_speed = minf(min_speed,motion.angular_velocity)
	check(min_speed > 0 and max_speed > min_speed*2,"Variable spin must vary smoothly without reversing")
	motion.nonuniformity = 0.0
	motion.step(.1)
	check(is_equal_approx(motion.angular_velocity,motion.spin_speed),"Zero irregularity must be uniform")
	motion.paused = true
	var frozen := Vector3(motion.elapsed,motion.walk_phase,motion.angle)
	motion.step(2.0)
	check(frozen == Vector3(motion.elapsed,motion.walk_phase,motion.angle),"Pause freezes all motion")
	var doll := Doll.new()
	root.add_child(doll)
	doll.configure({"outfit":0})
	doll.rig.animate(0,0,"idle",0)
	var spine: int = doll.rig.bones.Spine
	var foot: int = doll.rig.bones.FootL
	var first: Transform3D = doll.rig.skeleton.get_bone_pose(spine)
	var foot_first: Vector3 = doll.rig.global_pose(foot).origin
	doll.rig.animate(0,0,"idle",1)
	check(not doll.rig.skeleton.get_bone_pose(spine).is_equal_approx(first),"Idle breathing must move torso")
	check(doll.rig.global_pose(foot).origin.distance_to(foot_first) < .001,"Breathing keeps foot planted")
	doll.rig.animate(0,0,"idle",4)
	check(doll.rig.skeleton.get_bone_pose(spine).is_equal_approx(first),"Breathing cycle loops")
	for socket_name in ["CrownFlowerSocket","OccipitalTasselSocket","InsoleGripSocket"]:
		var sockets := doll.find_children(socket_name,"Marker3D",true,false)
		check(sockets.size() == 1,"Missing unique accessory mount: " + socket_name)
		if sockets.size() == 1:
			check(sockets[0].get_parent() is BoneAttachment3D,"Mount must follow a live bone")
			check(sockets[0].get_parent().bone_name == ("HandR" if socket_name == "InsoleGripSocket" else "Head"),"Wrong mount bone")
	motion.mode = "handwork"
	motion.apply(doll)
	var hand: Transform3D = doll.rig.global_pose(doll.rig.bones.HandR)
	check(hand.origin.distance_to(Vector3(.075,1.43,.36)) < .03,"Insole grip must reach the chest")
	check(hand.basis.y.dot(Vector3.UP) > .99,"Held insole must remain upright")
	var insole_parts := doll.find_children("MosuoInsole*","MeshInstance3D",true,false)
	insole_parts.append_array(doll.find_children("MosuoMagentaEdgedInsole","MeshInstance3D",true,false))
	check(insole_parts.size() == 2,"Insole must retain felt and magenta binding")
	for part in insole_parts:
		var center: Vector3 = part.mesh.get_aabb().get_center()
		check(center.y > 1.2 and center.y < 1.5,"Bound insole must start beside the wrist, not at world origin")
		var arrays: Array = part.mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			if indices[vertex*4] != doll.rig.bones.HandR or not is_equal_approx(weights[vertex*4],1.0):
				check(false,"Insole must be rigidly bound to the hand")
				break
	doll.free()
	print("WIKI_PREVIEW_MOTION_PASS" if not failed else "WIKI_PREVIEW_MOTION_FAILED")
	quit(1 if failed else 0)

