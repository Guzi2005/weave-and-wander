extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	var started := Time.get_ticks_msec()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	print("GAME_BODY_ROOM startup_ms=", Time.get_ticks_msec() - started)
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._pop_up.apply_depth(1.0)
	game._pop_up.desk.set_time(10 * 60, game)
	for index in game.staff.size():
		var doll: Node3D = game.staff[index]
		game._set_staff_idle(doll, 100000)
		doll.position = Vector3((index - 1) * 1.65, 0, 2.8)
		doll.set_meta("room", "shop")
		doll.rig.animate(0.4, 0.0, "idle", 0.0)
		doll.body_rig.rotation.y = .12
		doll.body_contact.update()
		assert(doll.body_rig.get_meta("accepted_body_version") == "v20-short-arm-0045")
	var camera: Camera3D = game.camera
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.h_offset = 0
	camera.v_offset = 0
	camera.fov = 42
	camera.global_position = Vector3(1.1, 4.8, 12.4)
	camera.look_at(Vector3(0, 1.35, 1.1))
	for tick in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/game_body_shop.png")
	print("GAME_BODY_ROOM_CAPTURE accepted body verified on all three live staff")
	game.free()
	quit()
