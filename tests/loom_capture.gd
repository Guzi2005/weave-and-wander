extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	for light in game.find_children("*","Light3D",true,false):
		light.light_energy *= .45
	game.get_node("GameInterface").hide()
	for person in game.staff: game._set_staff_idle(person,100000)
	var loom = game._rooms.workshop.get_node("WeavingLoom")
	var worker = game.staff[0]
	var index: int = game._facility_index("loom")
	worker.global_position = game.facilities[index].anchor.global_position
	game._assign_staff(worker,index,true)
	for frame in 90:
		worker.simulate(1.0/30,1)
		loom.advance(worker,1.0/30)
	loom.picks_done = 40
	for sample in [["shed",.12],["shuttle",.42],["beat",.76],["take_up",.95]]:
		loom.elapsed = loom.seconds_per_pick*sample[1]
		for frame in 30:
			loom.advance(worker,.00001)
			worker.simulate(1.0/30,1)
		game.camera.global_position = loom.to_global(Vector3(3.4,2.6,3.7))
		game.camera.look_at(loom.to_global(Vector3(0,1.1,.4)))
		game.camera.fov = 48
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/loom_seated_"+sample[0]+".png"))
		var gap := 0.0
		for side in worker.hand_targets:
			var actual: Vector3 = worker.body_rig.to_global(worker.rig.global_pose(worker.rig.bones["Hand"+side]).origin)
			gap = maxf(gap,actual.distance_to(worker.hand_targets[side]))
		var foot_gap := 0.0
		for side in worker.foot_targets:
			var actual: Vector3 = worker.body_rig.to_global(worker.rig.global_pose(worker.rig.bones["Foot"+side]).origin)
			foot_gap = maxf(foot_gap,actual.distance_to(worker.foot_targets[side]))
		print("LOOM_CAPTURE phase=",sample[0]," hand_gap=",gap," seated=",worker._rest_blend," foot_gap=",foot_gap)
	game.free()
	quit()
