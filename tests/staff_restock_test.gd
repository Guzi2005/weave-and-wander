extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for actor in game.staff: game._set_staff_idle(actor,100000)
	var stock = game._inventory
	var actor = game.staff[0]
	var plan: Dictionary = stock.restock_plan()
	check(plan.has("fetch"),"Storage has no physical pickup")
	var item = plan.item
	var identity: int = item.get_instance_id()
	check(item.visible,"Storage stock invisible")
	var job := {"facility":game._facility_index("rack","shop"),"phase":"moving","restock_id":item.item_id,"restock_phase":"fetch","manual":false}
	game._staff_jobs[actor.get_instance_id()] = job
	item.reserved_by = "staff:%d" % actor.get_instance_id()
	actor.global_position = plan.fetch
	var start: Vector3 = item.global_position
	game._restock.arrived(actor,job)
	game._restock.advance(actor,job,.4)
	check(item.global_position.distance_to(start) > .001 and item.location == "staff_carried","Pickup did not move existing item")
	game._restock.advance(actor,job,.7)
	check(job.restock_phase == "place","Pickup did not start carry route")
	var before: Vector3 = item.global_position
	actor.position.x += .3
	game._restock.advance(actor,job,.1)
	check(item.global_position.distance_to(before) > .2,"Garment does not follow worker")
	actor.stop_navigation()
	actor.global_position = plan.place
	game._restock.arrived(actor,job)
	game._restock.advance(actor,job,.5)
	check(item.location == "staff_carried","Garment became sellable before hang complete")
	game._restock.advance(actor,job,.6)
	check(item.location == "rack" and item.get_instance_id() == identity,"Transfer replaced or lost garment")
	check(item.reserved_by.is_empty(),"Claim not released")
	# Exercise the actual navigation signal -> pickup -> carry -> hang path.
	game._set_staff_idle(actor,100000)
	game._business_state = "workshop"
	var next: Dictionary = stock.restock_plan()
	check(not next.is_empty(),"No second restock candidate")
	if not next.is_empty():
		check(game._best_open_job() == game._facility_index("hats" if next.item.definition.is_hat() else "rack","shop"),"Workshop time excludes restocking")
		var transported = next.item
		game._assign_staff(actor,game._facility_index("hats" if transported.definition.is_hat() else "rack","shop"),true)
		var saw_carry := false
		for frame in 9000:
			actor.simulate(1.0/30.0,1)
			game._tick_staff_job(actor,1.0/30.0)
			stock.advance()
			saw_carry = saw_carry or transported.location == "staff_carried"
			if transported.location == "rack": break
			if frame % 300 == 0: await process_frame
		check(saw_carry and transported.location == "rack","Real navigation failed restock: %s / %s" % [transported.location,game._staff_jobs[actor.get_instance_id()]])
	# Reassignment returns the SAME carried item to a fetchable floor position.
	game._set_staff_idle(actor,100000)
	var pending: Dictionary = stock.restock_plan()
	if not pending.is_empty():
		var interrupted = pending.item
		var interrupted_job := {"facility":game._facility_index("rack","shop"),"phase":"moving","restock_id":interrupted.item_id,"restock_phase":"fetch","manual":true}
		game._staff_jobs[actor.get_instance_id()] = interrupted_job
		actor.global_position = pending.fetch
		game._restock.arrived(actor,interrupted_job)
		game._restock.advance(actor,interrupted_job,.5)
		game._set_staff_idle(actor,100000)
		check(interrupted.location == "stock_pending" and interrupted.reserved_by.is_empty(),"Interrupted transfer lost item or claim")
		check(not stock.restock_plan_for(interrupted.item_id).is_empty(),"Interrupted item cannot be picked up again")
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/doll_costume.gdshader")
	mat.set_shader_parameter("pigment",Color.RED)
	mat.set_shader_parameter("use_vertex_color",true)
	var copied: ShaderMaterial = game._pop_up._copy(mat)
	check(copied.get_shader_parameter("pigment") == Color.RED and copied.get_shader_parameter("use_vertex_color") == true,"Startup copy lost material")
	print("STAFF_RESTOCK_TEST failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
