extends SceneTree

var game: Node
var failures: Array[String] = []
var capture := false


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _tick(delta: float) -> void:
	game._process(delta)


func _run() -> void:
	capture = "--record-postal-stop" in OS.get_cmdline_user_args()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._day_minutes = 9*60+15
	game._set_speed(1)
	var life: Node3D = game._street_life
	game._view_controls.target_zoom = 1
	game._view_controls.step(1)
	for frame in 1200:
		_tick(1.0/60.0)
		if life.bicycle.position.x >= 1.5:
			break
	_check(life.postal_stage == "arriving","Missed arrival preview")
	# Focused asset camera only; the playable room framing is untouched.
	if capture:
		root.size_changed.disconnect(game._fit_stage)
		game.get_node("GameInterface").hide()
		for person in game.staff+game.customers+life.pedestrians:
			person.hide()
		game.camera.position = Vector3(6.2,3.6,13)
		game.camera.look_at(Vector3(2.6,1.35,5.7))
		game.camera.size = 5.1
		game.camera.h_offset = 0
		game.camera.v_offset = 0
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/postal_stop_motion"))
	for sample in 66:
		_tick(.05)
		await _snapshot(sample)
	_check(life.bicycle.parking_amount > .99,"Kickstand did not deploy")
	var checked_pause := false
	for frame in 1800:
		_tick(1.0/60.0)
		if life.postal_stage == "mounting":
			game._set_speed(0)
			var position: Vector3 = life.postman.position
			var progress: float = life._mount_clock
			var foot: Transform3D = life.postman.rig.skeleton.get_bone_global_pose(life.postman.rig.bones["FootL"])
			for i in 30:
				_tick(1.0/60.0)
			_check(position == life.postman.position and progress == life._mount_clock,"Mount animation ignores pause")
			_check(foot.is_equal_approx(life.postman.rig.skeleton.get_bone_global_pose(life.postman.rig.bones["FootL"])),"Paused mounting still changes bones")
			game._set_speed(1)
			checked_pause = true
			break
	_check(checked_pause,"Postman never returned to mount bicycle")
	for sample in 66:
		_tick(.05)
		await _snapshot(sample+66)
	_check(life.postal_stage == "departing" and life._bike_speed > 4,"Postman did not accelerate away")
	_check(life.bicycle.parking_amount == 0,"Kickstand stayed down while cycling")
	_check(life.deliveries.size() == 1,"Visit did not deliver once")
	print("POSTAL_VISIT_CHECK smooth_mount=true pause=true kickstand=true deliveries=",life.deliveries.size()," failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func _snapshot(frame: int) -> void:
	if not capture:
		return
	for customer in game.customers:
		customer.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://captures/postal_stop_motion/frame_%03d.png"%frame)
	_check(root.get_texture().get_image().save_png(path) == OK,"Postal stop frame export failed")
