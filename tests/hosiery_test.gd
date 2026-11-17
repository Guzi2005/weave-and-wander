extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var doll = preload("res://scripts/volume_doll.gd").new()
	root.add_child(doll)
	for length in [0.0, .22, .55, .85, 1.0]:
		doll.set_hosiery({"enabled": true, "length": length, "pattern": 2})
		var found := 0
		for part: MeshInstance3D in doll.rig.meshes:
			if str(part.name) == "Calf":
				found += 1
				assert(part.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2].size() > 0)
				assert(is_equal_approx(part.material_override.get_shader_parameter("sock_top"), .15 + length*1.19))
		assert(found == 2)
		assert(doll.body_rig.find_children("HosieryWaist", "MeshInstance3D", true, false).size() == (1 if length == 1.0 else 0))
		for phase in [0.0, PI*.5, PI, PI*1.5]:
			doll.rig.animate(phase, 1.0, "idle", phase)
			for part: MeshInstance3D in doll.rig.meshes:
				for point in doll.rig.deformed_vertices(part):
					assert(point.is_finite())
	# An authored zero sleeve weight must remain attached to the body.
	var weights: Array = doll.rig._weights("garment", "UkrShirt", Vector3(.25,1.6,.1), 0.0)
	assert(weights[1][2] == 0.0 and weights[1][3] == 0.0)
	doll.set_hosiery({"enabled": false})
	assert(doll.body_rig.find_children("HosieryWaist", "MeshInstance3D", true, false).is_empty())
	doll.free()
	print("HOSIERY_PASS lengths=5 walk_phases=4 torso_weights=preserved")
	quit()
