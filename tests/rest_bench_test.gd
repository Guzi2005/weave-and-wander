extends SceneTree

var game: Node
var bench: Node3D
var failures: Array[String] = []
var bench_index := -1


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)


func reset() -> void:
	for index in game.staff.size():
		var actor: Node3D = game.staff[index]
		game._set_staff_idle(actor,100000)
		if game._staff_behaviors.has(actor.get_instance_id()):
			game._staff_behaviors[actor.get_instance_id()].cancel_break()
		actor.energy = .3
		actor.personality = {}
		actor.global_position = bench.to_global(Vector3(-1.22+index*1.22,0,1.65))
		actor._rest_blend = 0.0
		actor._update_puppet_motion(.1)


func step(delta := 1.0/30.0) -> void:
	for actor in game.staff:
		actor.simulate(delta,1.0)
	game._process_staff_jobs(delta)


func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280,800)
	root.content_scale_size = root.size
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._set_speed(0)
	game.get_node("GameInterface").hide()
	for person in game.customers: person.hide()
	bench = game._rooms.archive.get_node("RestBench")
	for index in game.facilities.size():
		if game.facilities[index].id == "bench": bench_index = index
	check(bench_index >= 0,"Bench is not a deployable starting facility")
	for energy in [.2501,.25,.1501,.15]:
		reset()
		var actor: Node3D = game.staff[0]
		actor.energy = energy
		var needs: RefCounted = preload("res://scripts/staff_behavior.gd").new(actor,game)
		check(needs._needs_break(actor,0) == (energy <= .25),"Automatic rest threshold changed")
		game._assign_staff(actor,bench_index,true)
		check(bench.mode_for(actor) == ("nap" if energy <= .15 else "sit"),"Nap eligibility threshold changed")
	reset()
	for actor in game.staff: game._assign_staff(actor,bench_index,true)
	for tick in 120: step()
	check(bench.reservations.size() == 3,"Three staff cannot share the bench")
	var used: Array = []
	for actor in game.staff:
		check(actor.has_arrived(),"Bench approach is unreachable")
		var reservation: Dictionary = bench.reservations[actor.get_instance_id()]
		check(reservation.mode == "sit" and reservation.seats.size() == 1,"Seated rest consumes wrong capacity")
		for seat in reservation.seats:
			check(seat not in used,"Rest seats overlap")
			used.append(seat)
		check(actor._rest_blend > .99,"Staff did not transition to sitting")
	check(bench.available_span(true).is_empty(),"Full bench accepted a sleeper")
	await capture("rest_bench_three")
	for actor in game.staff: contact_check(actor)
	reset()
	var sleeper: Node3D = game.staff[0]
	var sitter: Node3D = game.staff[1]
	sleeper.energy = .10
	game._assign_staff(sleeper,bench_index,true)
	game._assign_staff(sitter,bench_index,true)
	game._assign_staff(game.staff[2],bench_index,true)
	check(bench.reservations.size() == 2,"A sleeper did not reserve two seats atomically")
	check(game._staff_jobs[game.staff[2].get_instance_id()].facility == -1,"Full bench displaced a resting person")
	game.staff[2].global_position = bench.to_global(Vector3(3.3,0,1.8))
	game.staff[2].hide()
	for tick in 100: step()
	var sleep_claim: Dictionary = bench.reservations[sleeper.get_instance_id()]
	check(sleep_claim.mode == "nap" and sleep_claim.seats.size() == 2 and sleep_claim.seats[1] == sleep_claim.seats[0]+1,"Nap must occupy two adjacent seats")
	check(sleeper.activity == "napping" and sitter.activity == "resting","Rest pose/status mismatch")
	var energy: float = sleeper.energy
	step(.5)
	check(absf(sleeper.energy-energy-.045*.5) < .0001,"Nap recovery rate is incorrect")
	await capture("rest_bench_nap")
	contact_check(sleeper)
	contact_check(sitter)
	for pose in 4:
		sleeper.nap_pose = pose
		var previous: Vector3 = sleeper.rig.global_pose(sleeper.rig.bones.HandL).origin
		var previous_foot: Vector3 = sleeper.rig.global_pose(sleeper.rig.bones.FootR).origin
		for frame in 65:
			sleeper.simulate(1.0/30.0,1.0)
			if frame%12 == 0: contact_check(sleeper)
			var current: Vector3 = sleeper.rig.global_pose(sleeper.rig.bones.HandL).origin
			check(current.distance_to(previous) < .055,"Nap pose switch snapped the hand")
			previous = current
			var foot: Vector3 = sleeper.rig.global_pose(sleeper.rig.bones.FootR).origin
			check(foot.distance_to(previous_foot) < .055,"Nap pose switch snapped the ankle")
			previous_foot = foot
		check(sleeper._nap_pose_weights[pose] > .99,"Nap pose transition did not finish")
		contact_check(sleeper)
		await capture("rest_pose_%d"%pose)
	sleeper.nap_pose = 0
	for frame in 65: sleeper.simulate(1.0/30.0,1.0)
	var hip_before: Vector3 = sleeper.body_rig.to_global(sleeper.rig.skeleton.get_bone_global_pose(sleeper.rig.bones.Hips).origin)
	bench.position.x += .1
	game._navigation.refresh()
	for tick in 90: step()
	var hip_after: Vector3 = sleeper.body_rig.to_global(sleeper.rig.skeleton.get_bone_global_pose(sleeper.rig.bones.Hips).origin)
	check(hip_after.distance_to(hip_before+Vector3(.1,0,0)) < .025,"Moving bench broke seated attachment")
	bench.position.x -= .1
	game._navigation.refresh()
	# Fragmented free seats cannot be combined into a two-seat nap.
	reset()
	for actor in game.staff: bench.reserve(actor,false)
	bench.release(game.staff[0])
	bench.release(game.staff[2])
	var candidate: Node3D = game.staff[0]
	bench.reserve(candidate,true)
	check(bench.mode_for(candidate) == "sit","Nonadjacent empty seats allowed a nap")
	reset()
	# A deleted staff object must not permanently occupy the bench.
	var temporary: Node3D = load("res://scripts/volume_doll.gd").new()
	game.add_child(temporary)
	bench.reserve(temporary,true)
	temporary.free()
	check(bench.available_span(true).size() == 2 and bench.reservations.is_empty(),"Deleted actor left a ghost reservation")
	# Exhaustion autonomously chooses nearby bench, without manual deployment.
	sleeper.energy = .1
	step()
	check(game._staff_jobs[sleeper.get_instance_id()].facility == bench_index,"Tired staff did not choose nearby bench")
	for tick in 1200:
		step()
		if game._staff_behaviors[sleeper.get_instance_id()].breaks_completed > 0: break
	check(not bench.reservations.has(sleeper.get_instance_id()),"Recovered sleeper kept both seats")
	print("REST_BENCH_TEST three_seats=true nap=true thresholds=true hand_ankle_continuity=true reservations=true moving=true recovery=true failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func contact_check(actor: Node3D) -> void:
	var side_minimum := INF
	for part in actor.rig.meshes:
		if not part.visible: continue
		var minimum := INF
		for p in actor.rig.deformed_vertices(part):
			var local: Vector3 = bench.to_local(actor.body_rig.to_global(p))
			if absf(local.x) < 1.80 and local.z > -.47 and local.z < .47:
				minimum = minf(minimum,local.y)
		check(minimum >= .70,"Seat penetration: "+actor.doll_name+"/"+str(part.name)+" y="+str(minimum))
		if part.get_meta("semantic","") in ["torso","garment","skirt"]:
			side_minimum = minf(side_minimum,minimum)
	if actor.rest_mode == "nap" and actor._rest_blend > .99:
		check(side_minimum <= .78,"Sleeping flank floats above the cushion")
		for suffix in ["L","R"]:
			var shoulder: Transform3D = actor.rig.skeleton.get_bone_pose(actor.rig.bones["UpperArm"+suffix])
			check(absf(shoulder.origin.x) < .14 and shoulder.origin.z > .04,"Sleeping shoulders did not fold inward/forward")


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.camera.position = bench.to_global(Vector3(2.8,3.2,7.4))
	game.camera.look_at(bench.to_global(Vector3(0,1.1,0)))
	game.camera.fov = 39
	for tick in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://captures/%s_%dx%d.png"%[label,root.size.x,root.size.y]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("REST_CAPTURE ",path)
