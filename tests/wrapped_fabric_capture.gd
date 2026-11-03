extends SceneTree
const Package = preload("res://components/material_package.gd")
const SAMPLES := [
	{"label":"thin 8 m", "meters":8.0, "capacity_m":8.0, "thickness_m":0.0005, "width_m":1.4},
	{"label":"thick 8 m", "meters":8.0, "capacity_m":8.0, "thickness_m":0.0025, "width_m":1.4},
	{"label":"partly used 3 m", "meters":3.0, "capacity_m":8.0, "thickness_m":0.001, "width_m":1.4},
]
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1600,1000)
	var studio := Node3D.new()
	root.add_child(studio)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("e7e0cf")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e6eadf")
	world.environment.ambient_light_energy = .65
	studio.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42,-45,0)
	light.light_energy = .40
	light.shadow_enabled = true
	studio.add_child(light)
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8,.05,6)
	base.mesh = box
	base.position.y = -.04
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/room_paper.gdshader")
	mat.set_shader_parameter("pigment",Color("d4cbb5"))
	base.material_override = mat
	studio.add_child(base)
	for i in SAMPLES.size():
		var sample: Dictionary = SAMPLES[i]
		var data := sample.duplicate(true)
		data["id"] = "inspection_%d" % i
		data["pigment"] = Color("779ab1")
		data["pattern_code"] = 0
		data["material"] = "cotton"
		var package := Package.new()
		studio.add_child(package)
		package.configure(data,"book")
		package.position = Vector3(-.78+i*.78,0,0)
		package.rotation.y = -.38
		var label := Label3D.new()
		label.text = "%s  %.2f mm" % [str(sample["label"]), float(sample["thickness_m"])*1000.0]
		label.font_size = 48
		label.pixel_size = .0018
		label.outline_size = 8
		label.modulate = Color("4a4032")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(package.position.x,1.04,0)
		studio.add_child(label)
	var camera := Camera3D.new()
	studio.add_child(camera)
	camera.position = Vector3(2.6,2.8,3.3)
	camera.look_at(Vector3(0,.44,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.95
	camera.current = true
	for tick in 16: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/material_wrapped_detail.png"))
	print("WRAPPED_FABRIC_CAPTURE saved")
	studio.free()
	quit()
