extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("HEADLESS_SKIPPED")
		quit(0)
		return

	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size

	var stage := Node3D.new()
	root.add_child(stage)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#edf1f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#f4f7f8")
	env.environment.ambient_light_energy = 0.4
	stage.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.5
	light.shadow_enabled = true
	stage.add_child(light)

	var floor_m := PlaneMesh.new()
	floor_m.size = Vector2(20, 20)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#cfdbe0")
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_m
	floor_inst.material_override = floor_mat
	stage.add_child(floor_inst)

	# 1. Doll 1: Standard Outfit 0 (as seen in game)
	var doll1 := Doll.new()
	stage.add_child(doll1)
	doll1.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll1.position.x = -1.8

	# 2. Doll 2: Bare structure (clothes hidden)
	var doll2 := Doll.new()
	stage.add_child(doll2)
	doll2.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll2.position.x = 0.0

	# 3. Doll 3: Side view of bare structure
	var doll3 := Doll.new()
	stage.add_child(doll3)
	doll3.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll3.position.x = 1.8

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(0, 1.45, 7.0)
	stage.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.35, 0))
	camera.current = true

	# Wait for deferred build and rig binding to finish
	for frame in 6:
		await process_frame

	# Now hide the clothing meshes in SkinnedMeshes on doll2 and doll3
	for d in [doll2, doll3]:
		var skinned = d.body_rig.get_node_or_null("SkinnedMeshes")
		if skinned != null:
			var garment_node = skinned.get_node_or_null("garment")
			if garment_node != null: garment_node.visible = false
			var skirt_node = skinned.get_node_or_null("skirt")
			if skirt_node != null: skirt_node.visible = false
			var torso_node = skinned.get_node_or_null("torso")
			if torso_node != null:
				for child in torso_node.get_children():
					if child.name != "Neck":
						child.visible = false

	doll3.body_rig.rotation.y = PI * 0.5

	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute("res://captures/anatomy_inspection")
		img.save_png("res://captures/anatomy_inspection/volumedoll_anatomy_comparison.png")
		print("ANATOMY_CAPTURED_SUCCESS")

	quit(0)
