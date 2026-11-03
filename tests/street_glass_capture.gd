extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	root.size = Vector2i(1600,1000)
	for frame in 8: await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._pop_up.desk.set_time(9*60,game)
	game._pop_up.apply_depth(0.0)
	game.get_node("GameInterface").hide()
	var streets := root.find_children("*","Node3D",true,false).filter(func(n: Node) -> bool: return n.get_script() == load("res://scripts/street_scene.gd"))
	var street: Node3D = streets[0]
	street.set_exterior(1)
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.camera.fov = 45
	game.camera.global_position = street.to_global(Vector3(7,4.7,16))
	game.camera.look_at(street.to_global(Vector3(0,2.1,3.8)))
	for frame in 24: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/street_glass.png"))
	var count := 0
	for pane in get_nodes_in_group("shop_window_panels"):
		assert(pane.material_override.shader == load("res://shaders/street_glass.gdshader"))
		assert(pane.material_override.get_shader_parameter("reflection_texture") is ViewportTexture)
		count += 1
	print("STREET_GLASS_CAPTURE verified panes=",count)
	game.free()
	quit()
