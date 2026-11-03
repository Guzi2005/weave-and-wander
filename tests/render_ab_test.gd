extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._set_speed(0)
	var experiment = game.get_node("RenderAB")
	var debug_before := root.debug_draw
	var eye: Vector3 = game.camera.position
	var original_code: String = load("res://shaders/doll_costume.gdshader").code
	for mode in [false,true,false]:
		experiment.set_flat(mode)
		for i in 5: await process_frame
		assert(game.camera.projection == (Camera3D.PROJECTION_ORTHOGONAL if mode else Camera3D.PROJECTION_PERSPECTIVE))
		assert(root.debug_draw == (Viewport.DEBUG_DRAW_DISABLED if mode else debug_before))
		assert(game.camera.position.is_equal_approx(eye))
		var start := Time.get_ticks_usec()
		for i in 30: await process_frame
		print("AB ",mode," ms/frame=",snappedf((Time.get_ticks_usec()-start)/30000.0,.1))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/game_ab_%s.png" % ("flat" if mode else "original"))
	assert(load("res://shaders/doll_costume.gdshader").code == original_code)
	experiment.set_flat(true)
	for strength in [0.0,.25,.5,1.0,0.0]:
		experiment.perspective_strength = strength
		game._view_controls.apply_view()
		var position: Vector3 = game.camera.position
		for i in 5: await process_frame
		assert(game.camera.position.is_equal_approx(position),"Camera accumulates perspective offset")
		assert(game.camera.far > game.camera.near)
		assert(game.camera.projection == (Camera3D.PROJECTION_ORTHOGONAL if strength == 0 else Camera3D.PROJECTION_PERSPECTIVE))
	for hour in [9,19,22]:
		game._day_minutes = hour*60
		game._pop_up.desk.set_time(game._day_minutes,game)
		for i in 5: await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/game_ab_lit_%d.png" % hour)
	experiment.set_flat(false)
	assert(load("res://shaders/doll_costume.gdshader").code == original_code)
	print("RENDER_AB_TEST pass: perspective range, stable framing, lit cycle, shader rollback")
	game.free()
	quit()
