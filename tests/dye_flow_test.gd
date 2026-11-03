extends SceneTree
var errors: Array[String] = []
var game: Node
var captured := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok and message not in errors:
		errors.append(message)
		push_error(message)

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._production.auto_restock = false
	for person in game.staff: game._set_staff_idle(person,100000)
	if not game._production.order.is_empty():
		game._production.ledger.cancel(game._production.order.id)
		game._production.order = {}
	var flow: Node3D = game._dye
	var ledger: RefCounted = flow.ledger
	var id := "stock_blue_check"
	var original: Dictionary = ledger.fabric(id).duplicate(true)
	var job: Dictionary = ledger.reserve(id,"thread_blue",1,2)
	check(not flow.can_start(id,0),"Dye accepted fabric reserved by sewing")
	ledger.cancel(job.id)
	check(not flow.start(id,-1),"Dye accepted invalid color")
	check(flow.start(id,1),"Dye order did not start")
	check(not flow.start(id,2),"Dye accepted duplicate order")
	check(not ledger.can_reserve(id,"thread_blue",1,2),"Sewing accepted fabric in dye vat")
	var worker: Node3D = game.staff[2]
	worker.global_position = flow.production.cabinet.to_global(Vector3(-1.1,0,1.35))
	game._assign_staff(worker,game._facility_index("dye"),true)
	var interrupted := false
	var last := ""
	for frame in 9000:
		worker.simulate(1.0/30.0,1.0)
		flow.advance(1.0/30.0)
		if flow.phase != last:
			print("DYE_PHASE ",flow.phase," nav=",worker.navigation_status)
			last = flow.phase
		if not interrupted and flow.phase == "rinse" and flow.elapsed > 1:
			game._set_staff_idle(worker,100000)
			check(flow.actor == null,"Interrupted dye worker still owns order")
			check(ledger.available_fabric(id) == 0,"Interrupted dye unlocked wet cloth")
			game._assign_staff(worker,game._facility_index("dye"),true)
			interrupted = true
		if flow.phase in ["dye","dry"] and flow.elapsed > 1 and not captured.has(flow.phase):
			captured[flow.phase] = true
			await capture(flow.phase)
		if flow.completed > 0: break
		if frame % 300 == 0: await process_frame
	check(flow.completed == 1,"Dye cycle did not finish: "+flow.phase+" "+str(worker.global_position)+" "+worker.navigation_status)
	check(interrupted,"Interruption branch not exercised")
	var result: Dictionary = ledger.fabric(id)
	check(is_equal_approx(result.meters,original.meters),"Dye changed material quantity")
	check(result.pigment != original.pigment,"Dye left original color")
	check(result.pattern_id == original.pattern_id and result.pattern_scale == original.pattern_scale,"Dye erased pattern")
	check(result.thickness_m == original.thickness_m,"Dye changed gauge")
	check(result.location == "storage" and not result.has("dye_job"),"Dry cloth not unlocked in storage")
	check(is_equal_approx(flow.dyes[1],20-float(original.meters)*.1),"Dye dose duplicated or missing")
	check(flow.package.get_parent() == flow.production.mounts[id] and flow.package.visible,"Dyed package not returned visibly")
	check(flow.package.cloth_material.get_shader_parameter("pigment") == result.pigment,"Returned package wrong color")
	var made: Dictionary = ledger.reserve(id,"thread_blue",1,2)
	check(not made.is_empty(),"Cannot make clothes from dyed fabric")
	if not made.is_empty():
		ledger.cut(made.id)
		ledger.advance_sewing(made.id,1)
		var item: Node3D = game._inventory.create_from_work_order(made)
		check(item.definition.material_data.pigment == result.pigment,"Dyed color lost in finished garment")
		check(item.definition.material_data.pattern_id == original.pattern_id,"Check pattern lost in finished garment")
	await capture("complete")
	print("DYE_FLOW_TEST failures=",errors.size()," phases=",flow.history)
	game.free()
	quit(0 if errors.is_empty() else 1)

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1600,1000)
	game._pop_up.desk.set_time(9*60,game)
	game.get_node("GameInterface").hide()
	var vat: Node3D = game._dye.vat
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.camera.fov = 40
	game.camera.global_position = vat.to_global(Vector3(4,3.8,6.8))
	game.camera.look_at(vat.to_global(Vector3(0,1.35,0)))
	if label == "complete":
		game.get_node("GameInterface").show()
		game._dye_panel.show()
		game._dye_panel.refresh()
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/dye_"+label+".png"))
