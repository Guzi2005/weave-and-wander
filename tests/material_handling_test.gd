extends SceneTree
## Focused checks for the optimized material handling: combined fabric+thread
## pickup, spool staged on the cutting table, tray carrying the spool to the
## sewing machine in one trip, and a single combined return of leftovers.

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
	for person in game.staff: game._set_staff_idle(person,100000)
	var flow: Node3D = game._production
	var worker: Node3D = game.staff[2]
	worker.global_position = flow.cabinet.to_global(Vector3(-1.1,0,1.35))
	# Make room by selling one existing stored item, keeping the capacity rule.
	if game._inventory.in_location("storage").size() >= game._inventory.STORAGE_LIMIT:
		game._inventory.in_location("storage")[0].collect()
	game._assign_staff(worker,game._facility_index("sewing"),true)
	var plan: Dictionary = flow.order
	check(not plan.is_empty(),"No production order started")
	if plan.is_empty():
		game.free()
		quit(1)
		return
	var bolt: Node3D = flow.packages[plan.fabric_id]
	var spool: Node3D = flow.packages[plan.thread_id]
	var start_fabric: float = flow.ledger.fabric(plan.fabric_id).meters
	var start_thread: float = flow.ledger.thread(plan.thread_id).meters
	var package_count: int = flow.packages.size()
	var combined_pickup := false
	var staged_on_table := false
	var book_opened := false
	var tray_carries_spool := false
	var combined_return := false
	var spool_above_load := false
	var maximum_carry_gap := 0.0
	var maximum_ride_gap := 0.0
	var history: Array[String] = []
	for frame in 12000:
		worker.simulate(1.0/30.0,1)
		flow.advance(1.0/30.0)
		if flow.phase != (history[-1] if not history.is_empty() else ""):
			history.append(flow.phase)
			print("HANDLING_PHASE ",flow.phase," nav=",worker.navigation_status)
		match flow.phase:
			"to_cut":
				var both_carried: bool = flow.ledger.fabric(plan.fabric_id).location == "carried" and flow.ledger.thread(plan.thread_id).location == "carried"
				combined_pickup = combined_pickup or (both_carried and spool.get_parent() == flow)
				maximum_ride_gap = maxf(maximum_ride_gap,spool.global_position.distance_to(bolt.global_position))
				spool_above_load = spool_above_load or spool.global_position.y > bolt.to_global(bolt.display_bounds().get_center()).y
			"unfold","cut","rewind":
				book_opened = book_opened or bolt.open_amount > .9
				staged_on_table = staged_on_table or (spool.get_parent() == flow.pieces and flow.ledger.thread(plan.thread_id).location == "cutting")
			"carry_pieces","place_pieces":
				tray_carries_spool = tray_carries_spool or (flow.carried == flow.pieces and spool.get_parent() == flow.pieces)
			"to_return":
				combined_return = combined_return or (flow.carried == bolt and flow.ledger.thread(plan.thread_id).location == "carried" and spool.global_position.distance_to(bolt.global_position) < .9)
		if flow.carried != null and flow.phase in ["to_cut","carry_pieces","to_remnant","to_return","return_thread","to_unmount"]:
			for side in worker.hand_targets:
				var actual: Vector3 = worker.body_rig.to_global(worker.rig.global_pose(worker.rig.bones["Hand"+side]).origin)
				maximum_carry_gap = maxf(maximum_carry_gap,actual.distance_to(worker.hand_targets[side]))
		if frame % 600 == 0:
			check(flow.packages.size() == package_count,"Package registry changed size")
			check(root.find_children(str(plan.thread_id),"",true,false).size() == 1,"Phantom or duplicate spool node")
			check(root.find_children(str(plan.fabric_id),"",true,false).size() == 1,"Phantom or duplicate fabric node")
		if flow.finished_count == 1: break
		if frame % 300 == 0: await process_frame
	check(flow.finished_count == 1,"Order did not finish at phase "+flow.phase)
	check(combined_pickup,"Fabric and thread were not carried together to the cutting table")
	check(maximum_ride_gap < .9,"Spool teleported away from the carried fabric: gap=%s" % maximum_ride_gap)
	check(spool_above_load or bolt.form == "roll","Spool is not stably stacked atop the book package")
	check(staged_on_table,"Thread was not staged on the cutting table tray")
	check(book_opened and is_zero_approx(bolt.open_amount),"Fabric book did not open and close")
	check(tray_carries_spool,"Tray did not carry the spool to the sewing machine in one trip")
	check(combined_return,"Leftover bolt and spool were not returned together")
	check(not history.has("to_machine"),"Separate thread trip to the machine still happens")
	check(not history.has("to_pieces"),"Worker walked back to the table for pieces it already stood at")
	check(not history.has("lift_remaining"),"Early remnant return trip still happens")
	check(history.count("to_return") == 1,"Remnant returned more than once")
	var travels := 0
	for entry in history:
		if entry in flow.TRAVEL_PHASES: travels += 1
	check(travels <= 10,"Trip sequence got longer: %d travel phases" % travels)
	var order_of := {}
	for index in history.size(): order_of[history[index]] = index
	var sequence := ["take_fabric","take_thread","to_cut","unfold","cut","carry_pieces","mount_thread","sew","unmount","load_remnant","to_return","return_fabric","store_thread"]
	for index in range(1,sequence.size()):
		check(order_of.get(sequence[index-1],-1) >= 0 and order_of.get(sequence[index],-1) > order_of.get(sequence[index-1],-1),"Phase order broken: %s -> %s" % [sequence[index-1],sequence[index]])
	check(is_equal_approx(flow.ledger.fabric(plan.fabric_id).meters,start_fabric-float(plan.estimate.cut_m)),"Fabric debit differs from plan")
	check(is_equal_approx(flow.ledger.thread(plan.thread_id).meters,start_thread-float(plan.estimate.thread_m)),"Thread debit differs from plan")
	check(flow.ledger.remnants.size() == 1,"Reusable remnant missing or duplicated")
	check(game._inventory.produced_orders.size() == 1,"Wrong number of produced items")
	check(bolt.get_parent() == flow.mounts[plan.fabric_id],"Remaining fabric did not return to its slot")
	check(spool.get_parent() == flow.mounts[plan.thread_id],"Thread did not return to its peg")
	check(flow.packages.size() == package_count,"Package registry changed size")
	check(maximum_carry_gap < .12,"Hands cannot reach carried material: gap=%s" % maximum_carry_gap)
	check(worker.hand_targets.is_empty(),"Completed worker has stuck hand targets")
	flow.selected_fabric = "missing_fabric_for_test"
	game._assign_staff(worker,game._facility_index("sewing"),false)
	check(game._staff_jobs[worker.get_instance_id()].phase == "idle","Failed sewing request became a fake work timer")
	check(not str(worker.get_meta("idle_reason","")).is_empty(),"Failed production has no waiting reason")
	print("MATERIAL_HANDLING_TEST failures=",errors.size()," travels=",travels," ride_gap=",maximum_ride_gap," carry_gap=",maximum_carry_gap)
	game.free()
	quit(0 if errors.is_empty() else 1)
