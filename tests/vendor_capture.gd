extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1440,960)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("d7c9ac")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff2d8")
	env.ambient_light_energy = .45
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-25,0)
	light.light_energy = .65
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.7
	camera.position = Vector3(7,5.0,11)
	camera.look_at(Vector3(0,1.8,0))
	var shop: Node3D = load("res://assets/street_vendor/paper_textile_shop.glb").instantiate()
	world.add_child(shop)
	shop.position = Vector3(-.8,0,-1.8)
	var floor_node := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(12,.1,10)
	floor_node.mesh = plane
	floor_node.position.y = -.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c5c2ae")
	floor_node.material_override = mat
	world.add_child(floor_node)
	var vendor := preload("res://scripts/street_vendor.gd").new()
	world.add_child(vendor)
	vendor._build_visuals()
	vendor.tick(20,1,540)
	vendor.position = Vector3(-1,0,.6)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/vendor_diorama.png")
	camera.size = 3.3
	camera.position = Vector3(1.15,1.7,5.5)
	camera.look_at(vendor._grandmother.global_position+Vector3(0,1.25,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/vendor_grandmother.png")
	print("VENDOR CAPTURE saved")
	quit()
