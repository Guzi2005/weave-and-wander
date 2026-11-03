extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	await process_frame
	# Closing is triggered at the published 18:00 boundary.
	scene._day_minutes = 18.0 * 60.0
	scene._process(0.01)
	assert(scene._business_state == "closing")
	assert(scene._street.sign_is_open) # Changes only after the character reaches the sign.
	var serial: int = scene._customer_serial
	scene._spawn_customer()
	assert(scene._customer_serial == serial)
	var captured: Dictionary = {}
	for step in 12000:
		scene._process(.05)
		var chore = scene._business_chore
		if DisplayServer.get_name() != "headless" and chore.phase == "finishing" and not captured.has(chore.kind):
			captured[chore.kind] = true
			scene._view_controls.set_process(false)
			scene.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			if chore.kind == "close_sign":
				# Exterior proof: keep the actor and the hanging OPEN/CLOSED board in frame.
				scene.camera.position = Vector3(0,5.8,15.5)
				scene.camera.look_at(Vector3(0,2.45,3.8))
			else:
				scene.camera.position = chore.actor.global_position + Vector3(3,3.2,5)
				scene.camera.look_at(chore.actor.global_position + Vector3(0,1.2,0))
			scene._pop_up.apply_depth(0.0 if chore.kind == "close_sign" else 1.0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/business_%s_action.png" % chore.kind)
		if scene._business_state == "workshop" and scene._business_chore.phase == "idle":
			break
	print("CLOSING_RESULT state=", scene._business_state, " customers=", scene.customers.size(), " worker=", scene.staff[2].position, " job=", scene._staff_jobs[scene.staff[2].get_instance_id()])
	print("CHORE phase=",scene._business_chore.phase," kind=",scene._business_chore.kind," actor=",scene._business_chore.actor," jobs=",scene._staff_jobs)
	assert(scene._business_state == "workshop")
	assert(scene._business_chore.completed.has("close_sign"))
	assert(scene._business_chore.completed.has("archive_off"))
	assert(not scene._street.sign_is_open)
	assert(not scene.staff[2].visible)
	assert(scene.staff[2].is_off_shift())
	scene._start_drag(scene.staff[2])
	assert(scene.dragging_doll == null)
	assert(scene.staff[0].visible and scene.staff[1].visible)
	assert(not scene._room_lights.shop and not scene._room_lights.archive)
	assert(scene._room_lights.workshop)
	# Measure lighting independently of machines: each lit room adds load.
	var production_actor = scene._production.actor
	var dye_actor = scene._dye.actor
	scene._production.actor = null
	scene._dye.actor = null
	var meter: float = scene._electricity_kwh
	scene._update_electricity(24.0)
	var one_room: float = scene._electricity_kwh - meter
	scene._room_lights.shop = true
	scene._room_lights.archive = true
	meter = scene._electricity_kwh
	scene._update_electricity(24.0)
	assert(is_equal_approx(scene._electricity_kwh - meter, one_room * 3.0))
	scene._room_lights.shop = false
	scene._room_lights.archive = false
	var production_phase: String = scene._production.phase
	var dye_phase: String = scene._dye.phase
	var probe = scene.staff[2] # Off-shift and stopped: does not alter an active worker.
	probe.destination = probe.global_position
	probe.navigation_status = "arrived"
	assert(probe.has_arrived())
	scene._production.actor = probe
	scene._production.phase = "sew"
	meter = scene._electricity_kwh
	scene._update_electricity(24.0)
	assert(is_equal_approx(scene._electricity_kwh - meter, one_room + .48))
	scene._production.actor = null
	scene._dye.actor = probe
	scene._dye.phase = "dye"
	meter = scene._electricity_kwh
	scene._update_electricity(24.0)
	assert(is_equal_approx(scene._electricity_kwh - meter, one_room + .62))
	scene._dye.phase = "dry"
	meter = scene._electricity_kwh
	scene._update_electricity(24.0)
	assert(is_equal_approx(scene._electricity_kwh - meter, one_room))
	scene._production.phase = production_phase
	scene._dye.phase = dye_phase
	scene._production.actor = production_actor
	scene._dye.actor = dye_actor
	probe.stop_navigation()
	if DisplayServer.get_name() != "headless":
		scene._pop_up.desk.set_time(scene._day_minutes, scene)
		scene._update_ui()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/business_workshop_time.png")
		# Closed exterior proof after the worker has reached the sign.
		scene._pop_up.apply_depth(0.0)
		scene.camera.position = Vector3(0,5.8,15.5)
		scene.camera.look_at(Vector3(0,2.45,3.8))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/business_closed_exterior.png")
	var before_money: int = scene._money
	scene._update_electricity(4000.0)
	assert(scene._money < before_money)
	var day: int = scene._day_index
	var minute: float = scene._day_minutes
	scene._process(1.0)
	assert(scene._day_index == day)
	assert(scene._day_minutes == minute)
	scene._start_next_day()
	assert(scene.staff[2].position.z > 7 and not scene.staff[2].is_off_shift())
	assert(scene._business_state == "opening")
	for step in 12000:
		scene._process(.05)
		if scene._business_state == "open" and scene._business_chore.phase == "idle":
			break
	assert(scene._business_state == "open")
	assert(scene._day_minutes >= 9.0 * 60.0)
	assert(scene._business_chore.completed.has("open_sign"))
	assert(scene._street.sign_is_open)
	assert(scene.staff[2].visible)
	assert(scene._room_lights.shop and scene._room_lights.archive)
	print("BUSINESS_DAY_CYCLE_TEST passed")
	scene.free()
	quit()
