extends SceneTree

const Baseline = preload("res://scripts/accepted_body_v20.gd")
const Shorter = preload("res://scripts/shorter_arm_body.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func build(type: GDScript) -> Node3D:
	var doll := type.new() as Node3D
	root.add_child(doll)
	doll.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll.set_process(false)
	doll.set_underbody_mode(true)
	doll.rig.animate(0.0, 0.0, "idle", 0.0)
	return doll


func compare_meshes(original: Node3D, changed: Node3D, amount: float) -> void:
	check(original.rig.meshes.size() == changed.rig.meshes.size(), "Mesh count changed")
	for i in original.rig.meshes.size():
		var before: MeshInstance3D = original.rig.meshes[i]
		var after: MeshInstance3D = changed.rig.meshes[i]
		var auto_named := str(before.name).begins_with("@") and str(after.name).begins_with("@")
		check(before.name == after.name or auto_named, "Mesh order changed: %s / %s" % [before.name, after.name])
		check(before.get_meta("semantic") == after.get_meta("semantic"), "Mesh group changed")
		var a := before.mesh.surface_get_arrays(0)
		var b := after.mesh.surface_get_arrays(0)
		check(a[Mesh.ARRAY_INDEX] == b[Mesh.ARRAY_INDEX], "Topology changed: " + str(before.name))
		var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bv: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
		check(av.size() == bv.size(), "Vertex count changed")
		for j in av.size():
			var expected := av[j]
			if str(before.name) == "ArmMannequin":
				expected.y += amount * (1.0 - smoothstep(1.17, 1.69, expected.y))
			elif str(before.name) == "ArmMannequinThumb":
				expected.y += amount
			check(expected.distance_to(bv[j]) < 0.00001, "Unexpected shape change: " + str(before.name))
		if str(before.name) not in ["ArmMannequin", "ArmMannequinThumb"] or amount == 0.0:
			check(a[Mesh.ARRAY_NORMAL] == b[Mesh.ARRAY_NORMAL], "Unrelated normals changed")
		check(after.visible == before.visible, "Visibility changed: " + str(before.name))


func run() -> void:
	var baseline := build(Baseline)
	var shorter := build(Shorter)
	compare_meshes(baseline, shorter, 0.045)
	for suffix in ["L", "R"]:
		for label in ["UpperArm", "Forearm", "Hand"]:
			var index: int = shorter.rig.bones[label + suffix]
			var a: Transform3D = baseline.rig.skeleton.get_bone_global_rest(index)
			var b: Transform3D = shorter.rig.skeleton.get_bone_global_rest(index)
			var expected := a.origin
			expected.y += shorter.arm_raise_at(a.origin.y)
			check(expected.distance_to(b.origin) < 0.00001, "Joint did not follow arm: " + label)
	for activity in ["idle", "browsing", "checkout", "sewing"]:
		for phase in [0.0, 0.5, 1.5]:
			shorter.rig.animate(phase, 0.35, activity, phase)
			for i in shorter.rig.skeleton.get_bone_count():
				check(shorter.rig.skeleton.get_bone_global_pose(i).is_finite(), "Non-finite pose")
	shorter.arm_shortening = 0.0
	compare_meshes(baseline, shorter, 0.0)
	for i in shorter.rig.skeleton.get_bone_count():
		check(shorter.rig.skeleton.get_bone_rest(i).is_equal_approx(baseline.rig.skeleton.get_bone_rest(i)), "Zero does not restore joint")
	shorter.arm_shortening = 0.045
	compare_meshes(baseline, shorter, 0.045)
	baseline.free()
	shorter.free()
	print("SHORTER_ARM_BODY checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
