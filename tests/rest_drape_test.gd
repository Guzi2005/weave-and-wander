extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")
var failures: Array[String] = []
var poses := 0
var minimum_width_ratio := INF
var minimum_hem_length := INF

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)

func _run() -> void:
	for recipe in [{"outfit":0},{"outfit":1},{"outfit":0,"reference":true}]:
		var doll := Doll.new()
		root.add_child(doll)
		doll.configure(recipe)
		var skirt: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/skirt/LongSkirt")
		var arrays: Array = skirt.mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_VERTEX].size() == 8*41,"Skirt opening was capped or topology changed")
		check(arrays[Mesh.ARRAY_INDEX].size() == 7*40*6,"Skirt must be one continuous open tube")
		for label in ["HemRibbon","FineHemRibbon"]:
			var trim: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/skirt/"+label)
			check(trim.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 40*6,"Hem trim seals the skirt cavity")
		var calves := doll.body_rig.find_children("Calf*","MeshInstance3D",true,false)
		check(calves.size()==2,"An open skirt needs two actual calves, not floating shoes")
		for start in 4:
			for target in 4:
				for blend in [0.0,.5,1.0]:
					var weights := Vector4.ZERO
					weights[start] = 1.0-blend
					weights[target] += blend
					doll.rig.animate(0,0,"idle",0)
					doll.rig.pose_rest("nap",1.0,0.0,weights)
					var vertices: PackedVector3Array = doll.rig.deformed_vertices(skirt)
					var inverse: Transform3D = doll.rig.global_pose(doll.rig.bones.Root).affine_inverse()
					var low := Vector3(INF,INF,INF)
					var high := Vector3(-INF,-INF,-INF)
					for index in 41:
						var p: Vector3 = inverse*vertices[index]
						check(p.is_finite(),"Nonfinite draped hem")
						low = low.min(p)
						high = high.max(p)
					var ratio := (high.x-low.x)/.874
					minimum_width_ratio = minf(minimum_width_ratio,ratio)
					# Height shrinks as cloth settles. Check fabric allowance along
					# the open hem as well, rather than requiring an inflated tube.
					var hem_length := 0.0
					for index in 40:
						hem_length += vertices[index].distance_to(vertices[index+1])
					minimum_hem_length = minf(minimum_hem_length,hem_length)
					check(hem_length >= 1.65,"Draped hem lost its fabric allowance around both legs")
					check(ratio >= .60,"Side-lying hem collapsed onto one leg")
					check(high.z-low.z > .24,"Front/back fabric collapsed onto the calves")
					for calf in calves:
						var points: PackedVector3Array = doll.rig.deformed_vertices(calf)
						var ankle := Vector3.ZERO
						for index in 16: ankle += points[index]/16.0
						var side: String = str(calf.get_meta("semantic")).right(1)
						var foot: Vector3 = doll.rig.global_pose(doll.rig.bones["Foot"+side]).origin
						check(ankle.distance_to(foot)<.12,"Calf detached from the shoe during nap")
					poses += 1
		doll.free()
	print("REST_DRAPE_CHECK poses=",poses," open_hem=true calves=true min_width_ratio=",minimum_width_ratio," min_hem_length=",minimum_hem_length," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
