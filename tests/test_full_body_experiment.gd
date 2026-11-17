extends SceneTree

const OrigDoll = preload("res://scripts/volume_doll.gd")
const FullDoll = preload("res://scripts/experimental_full_body_doll.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(0)
		return

	root.size = Vector2i(1800, 900)
	root.content_scale_size = root.size

	var stage := Node3D.new()
	root.add_child(stage)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#edf1f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#f4f7f8")
	env.environment.ambient_light_energy = 0.42
	stage.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.5
	light.shadow_enabled = true
	stage.add_child(light)

	var floor_m := PlaneMesh.new()
	floor_m.size = Vector2(30, 20)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#cfdbe0")
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_m
	floor_inst.material_override = floor_mat
	stage.add_child(floor_inst)

	# 1. Doll 1: Original VolumeDoll (Bare)
	var doll1 := OrigDoll.new()
	stage.add_child(doll1)
	doll1.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll1.position.x = -2.4

	# 2. Doll 2: Experimental FullBodyDoll (Bare continuous mannequin)
	var doll2 := FullDoll.new()
	stage.add_child(doll2)
	doll2.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll2.position.x = -0.8

	# 3. Doll 3: Original VolumeDoll (Wearing standard clothes)
	var doll3 := OrigDoll.new()
	stage.add_child(doll3)
	doll3.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll3.position.x = 0.8

	# 4. Doll 4: Experimental FullBodyDoll (Wearing Ukrainian costume with body underneath)
	var doll4 := FullDoll.new()
	stage.add_child(doll4)
	doll4.configure({"outfit": 0, "hair": 3, "palette": 0, "shoe_style": 1})
	doll4.wear_ukrainian_set()
	doll4.position.x = 2.4

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(0, 1.45, 7.0)
	stage.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.35, 0))
	camera.current = true

	# Wait for deferred build and rig binding
	for frame in 8:
		await process_frame

	# Strip clothes on doll1 and doll2
	var d1_skinned = doll1.body_rig.get_node_or_null("SkinnedMeshes")
	if d1_skinned != null:
		var g = d1_skinned.get_node_or_null("garment")
		if g != null: g.visible = false
		var s = d1_skinned.get_node_or_null("skirt")
		if s != null: s.visible = false
		var t = d1_skinned.get_node_or_null("torso")
		if t != null:
			for ch in t.get_children():
				if ch.name != "Neck": ch.visible = false
		for suffix in ["L", "R"]:
			var a = d1_skinned.get_node_or_null("arm" + suffix)
			if a != null:
				for cn in ["CuffBinding", "CuffThickness", "SleeveLining"]:
					var c = a.get_node_or_null(cn)
					if c != null: c.visible = false

	doll2.set_underbody_mode(true)

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute("res://captures/anatomy_inspection")
		img.save_png("res://captures/anatomy_inspection/full_body_experiment_front.png")
		print("FRONT_CAPTURE_SUCCESS")

	# Rotate to 3/4 view
	for d in [doll1, doll2, doll3, doll4]:
		d.body_rig.rotation.y = PI * 0.25

	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var img_quarter := root.get_texture().get_image()
	if img_quarter != null:
		img_quarter.save_png("res://captures/anatomy_inspection/full_body_experiment_quarter.png")
		print("QUARTER_CAPTURE_SUCCESS")

	# Rotate to pure side profile (PI * 0.5)
	for d in [doll1, doll2, doll3, doll4]:
		d.body_rig.rotation.y = PI * 0.50

	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var img_side := root.get_texture().get_image()
	if img_side != null:
		img_side.save_png("res://captures/anatomy_inspection/full_body_experiment_side.png")
		print("SIDE_CAPTURE_SUCCESS")

	quit(0)
