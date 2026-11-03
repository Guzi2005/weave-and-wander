extends SceneTree

const Needs = preload("res://scripts/staff_behavior.gd")
var game: Node
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)


func step(delta := 1.0/30.0) -> void:
	for doll in game.staff:
		doll.simulate(delta,1)
	game._process_staff_jobs(delta)


func reset_staff() -> void:
	for doll in game.staff:
		game._set_staff_idle(doll,100000)
		if game._staff_behaviors.has(doll.get_instance_id()):
			game._staff_behaviors[doll.get_instance_id()].cancel_break()
		doll.energy = 1.0


func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	reset_staff()
	var bench: int = game._facility_index("bench")
	var tea: int = game._facility_index("rest","shop")
	check(game.facilities.filter(func(f): return f.activity == "resting").size() == 1,"Extra rest facility")
	check(game._rooms.workshop.get_node_or_null("WorkshopStool") == null,"Workshop tea fixture remains")
	var worker: PaperDoll = game.staff[0]
	var mints = game._mints
	worker.energy = .5
	worker.global_position = game.facilities[tea].anchor.global_position
	game._finish_staff_work(worker, tea)
	check(is_equal_approx(worker.energy,.55) and mints.stock == 7,"Serving not consumed")
	game._finish_staff_work(worker, tea)
	check(is_equal_approx(worker.energy,.55) and mints.stock == 7,"Duplicate serving")
	for actor in game.staff:
		actor.global_position = game.facilities[tea].anchor.global_position + Vector3(-1,0,0)
	mints.stock = 3
	for i in 600:
		for actor in game.staff: actor.simulate(1.0/30,1)
		mints.tick(1.0/30)
		if mints.restocks_completed == 1 and mints._restock_phase == "idle": break
	check(mints.stock == 9 and mints.reserve == 6 and mints.restocks_completed == 1,"Staff failed to refill exactly one batch")
	check(not game.staff.any(func(d): return d.get_meta("chore_reserved",false)), "Refill worker remained reserved")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,800)
		game.get_node("GameInterface").hide()
		var target: Vector3 = mints.bowl_position()
		await capture("mint_tea_service",target+Vector3(1.15,1.25,3.2),target)
	reset_staff()
	worker.personality = {"persistence":0.95,"recovery":1.0}
	worker.energy = .16
	var needs = Needs.new(worker,game)
	game._staff_jobs[worker.get_instance_id()] = {"phase":"work","facility":tea,"manual":false}
	check(not needs._needs_break(worker,0),"Persistent worker interrupted a task")
	worker.personality.persistence = .05
	check(needs._needs_break(worker,0),"Easily fatigued worker ignored rest")
	needs.tick(.01)
	check(game._staff_jobs[worker.get_instance_id()].facility == bench,"Tired worker did not reserve bench")
	check(is_equal_approx(Needs.recovery_scale_for(worker),1.3),"Recovery trait ignored")
	print("STAFF_STAMINA_TEST failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)



func capture(label: String, eye: Vector3, target: Vector3) -> void:
	if DisplayServer.get_name() == "headless": return
	game.camera.position = eye
	game.camera.look_at(target)
	game.camera.fov = 36
	for tick in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/%s_%dx%d.png"%[label,root.size.x,root.size.y]))
