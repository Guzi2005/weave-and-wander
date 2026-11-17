extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(0)
		return

	root.size = Vector2i(1200, 800)
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

	# Doll with shoes in side profile and 3/4 profile
	var doll1 := Doll.new()
	stage.add_child(doll1)
	doll1.configure({"outfit": 2, "shoe_style": 0}) # outfit 2 shows trousers/shoes clearly
	doll1.position.x = -0.8
	doll1.body_rig.rotation.y = PI * 0.5 # side view

	var doll2 := Doll.new()
	stage.add_child(doll2)
	doll2.configure({"outfit": 2, "shoe_style": 1}) # strapped shoes with white sock
	doll2.position.x = 0.8
	doll2.body_rig.rotation.y = PI * 0.5 # side view

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.4
	camera.position = Vector3(0, 0.45, 4.0)
	stage.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 0.35, 0))
	camera.current = true

	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute("res://captures/anatomy_inspection")
		img.save_png("res://captures/anatomy_inspection/shoe_heel_current.png")
		print("SHOE_CAPTURE_SUCCESS")

	quit(0)
