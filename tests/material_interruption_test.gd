extends SceneTree
var game: Node
var errors: Array[String] = []

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
	game._production.auto_restock = false
	for worker in game.staff: game._set_staff_idle(worker,100000)
	var flow: Node3D = game._production
	var worker: Node3D = game.staff[2]
	worker.global_position = flow.cabinet.to_global(Vector3(-1.1,0,1.35))
	# Make room by selling one existing stored item, keeping the capacity rule.
	if game._inventory.in_location("storage").size() >= game._inventory.STORAGE_LIMIT:
		game._inventory.in_location("storage")[0].collect()
	game._assign_staff(worker,game._facility_index("sewing"),true)
	var order: Dictionary = flow.order
	var interruptions := {}
	var targets := ["take_fabric","take_thread","to_cut","place_fabric","unfold","cut","rewind","take_pieces","carry_pieces","place_pieces","mount_thread","sew","finish","take_output","store_output","unmount","load_remnant","return_fabric","store_thread"]
	var waiting := false
	var previous_meters: float = flow.ledger.fabric(order.fabric_id).meters
	var previous_progress := 0.0
	for frame in 24000:
		worker.simulate(1.0/30.0,1)
		flow.advance(1.0/30.0)
		if not waiting and flow.phase in targets and not interruptions.has(flow.phase) and (flow.elapsed > .35 or worker.is_moving()):
			interruptions[flow.phase] = true
			print("INTERRUPT ",flow.phase)
			# A pause freezes both material accounting and operation time.
			var elapsed: float = flow.elapsed
			var quantity: float = flow.ledger.thread(order.thread_id).meters
			flow.advance(0.0)
			check(flow.elapsed == elapsed and flow.ledger.thread(order.thread_id).meters == quantity,"Paused production advanced")
			game._set_staff_idle(worker,100000)
			waiting = true
		elif waiting and flow.actor == null:
			check(worker.hand_targets.is_empty(),"Interrupted worker retains reach targets")
			var next: Node3D = game.staff[0] if worker == game.staff[2] else game.staff[2]
			next.global_position = game._rooms.workshop.to_global(Vector3(6.7,0,3.25))
			worker = next
			game._assign_staff(worker,game._facility_index("sewing"),true)
			waiting = false
		check(float(order.sew_progress) >= previous_progress,"Resume reduced sewing progress")
		previous_progress = float(order.sew_progress)
		check(flow.ledger.fabric(order.fabric_id).meters <= previous_meters,"Resume restored consumed fabric")
		previous_meters = flow.ledger.fabric(order.fabric_id).meters
		if flow.finished_count == 1: break
		if frame % 300 == 0: await process_frame
	check(flow.finished_count == 1,"Interrupted production stuck at %s, nav=%s" % [flow.phase,worker.navigation_status])
	# Deferred take/place actions may finish before the next stop, so separately
	# exercise adjacent pickups on a second order.
	for target in targets:
		if target not in ["take_thread","take_output"]: check(interruptions.has(target),"Interruption stage not exercised: "+target)
	check(game._inventory.produced_orders.size() == 1,"Resume duplicated output")
	check(flow.ledger.remnants.size() == 1,"Resume duplicated remnants")
	check(is_equal_approx(order.consumed_fabric_m,order.estimate.cut_m),"Resume double-debited fabric")
	check(is_equal_approx(order.consumed_thread_m,order.estimate.thread_m),"Resume double-debited thread")
	if game._inventory.in_location("storage").size() >= game._inventory.STORAGE_LIMIT:
		game._inventory.in_location("storage")[0].collect()
	game._assign_staff(worker,game._facility_index("sewing"),true)
	waiting = false
	for frame in 12000:
		worker.simulate(1.0/30.0,1)
		flow.advance(1.0/30.0)
		if not waiting and flow.phase in ["take_thread","take_output"] and not interruptions.has(flow.phase) and flow.elapsed > .35:
			interruptions[flow.phase] = true
			game._set_staff_idle(worker,100000)
			waiting = true
		elif waiting and flow.actor == null:
			game._assign_staff(worker,game._facility_index("sewing"),true)
			waiting = false
		if flow.finished_count == 2: break
		if frame % 300 == 0: await process_frame
	check(flow.finished_count == 2,"Second interrupted order failed at "+flow.phase)
	check(interruptions.has("take_thread") and interruptions.has("take_output"),"Adjacent pickups were not interrupted")
	print("MATERIAL_INTERRUPTION_TEST failures=",errors.size()," interruptions=",interruptions.size())
	game.free()
	quit(0 if errors.is_empty() else 1)
