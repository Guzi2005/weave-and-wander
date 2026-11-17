extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const Bench = preload("res://components/rest_bench.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	var stage := Node3D.new()
	root.add_child(stage)
	var bench := Bench.new()
	stage.add_child(bench)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("dbe5e1")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .75
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = .8
	stage.add_child(light)
	var dolls: Array[Node3D] = []
	for index in 2:
		var doll := Doll.new()
		stage.add_child(doll)
		doll.configure({"hair": 2 if index == 0 else 0, "hair_color": 0 if index == 0 else 1, "outfit": 1 if index == 0 else 0, "skin": 0, "palette": 0})
		bench.reserve(doll, index == 0)
		bench.support_actor(doll)
		doll._moving = false
		doll.get_node("GroundContact").hide()
		dolls.append(doll)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 36
	for pose in 4:
		dolls[0].nap_pose = pose
		for frame in 130:
			for doll in dolls: doll.simulate(1.0 / 60.0, 1)
		camera.position = Vector3(-.4, 3.7, 6.4)
		camera.look_at(Vector3(-.45, 1, .15))
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/game_body_rest_%d.png" % pose)
	print("GAME_BODY_REST_CAPTURE four nap poses plus seated staff")
	stage.free()
	quit()
