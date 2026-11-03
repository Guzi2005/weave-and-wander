extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1500, 660)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("e9eff0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("f5f7f5")
	environment.environment.ambient_light_energy = .8
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-35,0)
	light.light_energy = .30
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.15
	camera.position = Vector3(0,2.33,10)
	stage.add_child(camera)
	camera.current = true
	for i in 3:
		var doll := preload("res://scripts/volume_doll.gd").new()
		stage.add_child(doll)
		doll.configure({"hair":0,"outfit":0,"palette":0,"skin":0,"hair_color":1})
		doll.position.x = (i-1)*.90
		doll.body_rig.rotation.y = [0.0,PI*.25,PI*.5][i]
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/rounded_head_profiles.png"))
	print("HEAD_PREVIEW result=",result)
	stage.free()
	quit(result)
