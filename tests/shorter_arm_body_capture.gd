extends SceneTree

const Baseline = preload("res://scripts/accepted_body_v20.gd")
const Shorter = preload("res://scripts/shorter_arm_body.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1200, 1000)
	root.content_scale_size = root.size
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("edf1f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("f4f7f8")
	env.environment.ambient_light_energy = 0.42
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.5
	stage.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 20)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("cfdbe0")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = material
	stage.add_child(ground)
	var dolls: Array[Node3D] = []
	for type in [Baseline, Shorter]:
		var doll := type.new() as Node3D
		stage.add_child(doll)
		doll.configure({"outfit": 0, "hair": 0, "palette": 0})
		doll.set_process(false)
		doll.rig.animate(0.0, 0.0, "idle", 0.0)
		doll.body_rig.rotation.y = 0.0
		doll.position.x = -0.80 if dolls.is_empty() else 0.80
		doll.set_underbody_mode(true)
		dolls.append(doll)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.05
	camera.position = Vector3(0, 1.45, 7)
	camera.look_at(Vector3(0, 1.35, 0))
	camera.current = true
	for view in ["front", "quarter"]:
		for doll in dolls:
			doll.body_rig.rotation.y = 0.0 if view == "front" else 0.6
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://captures/accepted_body_shorter_arm_" + view + ".png"
		root.get_texture().get_image().save_png(path)
		print("CAPTURE ", path)
	stage.free()
	quit()
