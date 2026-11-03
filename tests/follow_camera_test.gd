extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	var view: Node = game._view_controls
	var doll: Node3D = game.staff[1]
	game._set_staff_idle(doll,100000)
	var cases := [Vector3(0,0,7),Vector3(0,0,2),Vector3(-6.4,0,-1.8),Vector3(5.5,0,-1),Vector3(-10,0,.6)]
	for at in cases:
		doll.global_position = at
		for mode in [1,2,3]:
			view.follow(doll,mode == 1)
			view.set_follow_mode(mode)
			for frame in 36:
				doll.resting_facing = frame*.025
				doll.simulate(1.0/60,1)
				view.step(1.0/60)
				check(game.camera.global_position.is_finite(),"nonfinite camera")
				check(view._camera_space.clear_point(game.camera.global_position),"camera intersects geometry at %s mode %d" % [at,mode])
			if mode == 1:
				var pose: Transform3D = view._eye_pose(doll)
				check((-game.camera.global_basis.z).dot(pose.basis.z) > .95,"first-person did not follow head gaze")
			if at == cases[0]: await capture(game,"follow_%d" % mode)
	# A shop-side gaze target rotates the head independently of the body.
	doll.global_position = Vector3(0,0,3.0)
	doll.resting_facing = PI
	var target := Marker3D.new()
	game.add_child(target)
	target.global_position = Vector3(2.0,1.5,-1.0)
	doll.attend(target,60)
	for mode in [1,2,3]:
		view.set_follow_mode(mode)
		for frame in 90:
			doll.simulate(1.0/60,1)
			view.step(1.0/60)
		check(view._camera_space.clear_point(game.camera.global_position),"indoor gaze camera intersects geometry")
		if mode == 1:
			check((-game.camera.global_basis.z).dot(view._eye_pose(doll).basis.z) > .98,"independent gaze did not drive camera")
		await capture(game,"follow_shop_%d" % mode)
	target.free()
	view.clear_follow()
	check(view._mirror_only_meshes.is_empty(),"camera did not restore body layers")
	view.depth = 1.0
	view.zoom = 0.0
	view.apply_view()
	var normal_size: float = game.camera.size
	view.zoom = view.MIN_ZOOM
	view.apply_view()
	check(is_equal_approx(game.camera.size,normal_size/8.0),"Close zoom did not reach eightfold magnification")
	check(view._pan_scale() > 0.0,"Close zoom reversed pan scale")
	check(game.camera.near <= .0251,"Close view clips nearby cloth")

	print("FOLLOW_CAMERA_TEST failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
func capture(game: Node, label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	game.get_node("GameInterface").hide()
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/"+label+".png"))
