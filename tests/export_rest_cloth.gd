extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")
const Bench = preload("res://components/rest_bench.gd")

func _initialize() -> void:
	_run.call_deferred()

func vectors(points: PackedVector3Array) -> Array:
	var result := []
	for p in points: result.append([p.x,p.y,p.z])
	return result

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var bench := Bench.new()
	stage.add_child(bench)
	var doll := Doll.new()
	stage.add_child(doll)
	doll.configure({"outfit":1,"hair":2})
	bench.reserve(doll,true)
	bench.support_actor(doll)
	doll._moving = false
	var skirt: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/skirt/LongSkirt")
	# Re-bakes must start from the authored pose, not accumulate the last bake.
	preload("res://scripts/rest_cloth.gd").install(skirt,false)
	var data := {"variants":[],"seat_top":.705}
	for variant in 4:
		doll.nap_pose = variant
		for frame in 150: doll.simulate(1.0/60.0,1.0)
		var rest: PackedVector3Array = skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var posed: PackedVector3Array = doll.rig.deformed_vertices(skirt)
		var world := PackedVector3Array()
		for p in posed: world.append(doll.body_rig.to_global(p))
		var pose := {"variant":variant,"rest":vectors(rest),"posed":vectors(world),"bones":{},"colliders":[]}
		var transform: Transform3D = doll.body_rig.global_transform*doll.rig.global_pose(doll.rig.bones.Root)
		pose["root_inverse"] = vectors(PackedVector3Array([transform.affine_inverse().basis.x,transform.affine_inverse().basis.y,transform.affine_inverse().basis.z,transform.affine_inverse().origin]))
		for label in ["Hips","Spine","ThighL","ThighR","ShinL","ShinR","FootL","FootR"]:
			var p: Vector3 = doll.body_rig.to_global(doll.rig.global_pose(doll.rig.bones[label]).origin)
			pose.bones[label] = [p.x,p.y,p.z]
		for part in doll.rig.meshes:
			if part.get_meta("semantic","").begins_with("shoe") or str(part.name).begins_with("Calf"):
				var points := PackedVector3Array()
				for p in doll.rig.deformed_vertices(part): points.append(doll.body_rig.to_global(p))
				pose.colliders.append({"name":str(part.name),"vertices":vectors(points),"triangles":Array(part.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX])})
		data.variants.append(pose)
	var file := FileAccess.open("res://captures/rest_cloth_input.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	print("REST_CLOTH_EXPORT variants=4")
	stage.free()
	quit()
