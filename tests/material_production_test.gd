extends SceneTree

var game: Node
var errors: Array[String] = []
var snapshots := {}
var capture_enabled := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value and message not in errors:
		errors.append(message)
		push_error(message)

func _run() -> void:
	capture_enabled = "--material-capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._production.auto_restock = false
	game.get_node("GameInterface").hide()
	for person in game.staff:
		game._set_staff_idle(person,100000)
		person.hide()
	for person in game.customers: person.hide()
	var flow: Node3D = game._production
	var requested_style := 1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--style="): requested_style = int(argument.trim_prefix("--style="))
	if requested_style != 1:
		if is_instance_valid(flow.actor): flow.suspend(flow.actor)
		if not flow.order.is_empty(): flow.ledger.cancel(flow.order.id)
		flow.order = {}
		flow.phase = "idle"
		flow.selected_style = requested_style
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fabric="):
			if not flow.order.is_empty(): flow.ledger.cancel(flow.order.id)
			flow.order = {}
			flow.phase = "idle"
			flow.selected_fabric = argument.trim_prefix("--fabric=")
	var worker: Node3D = game.staff[2]
	worker.show()
	worker.global_position = flow.cabinet.to_global(Vector3(-1.1,0,1.35))
	# Make room by selling one existing stored item, keeping the capacity rule.
	if game._inventory.in_location("storage").size() >= game._inventory.STORAGE_LIMIT:
		var old_stock: Node3D = game._inventory.in_location("storage")[0]
		old_stock.collect()
		check(old_stock.location == "collected","could not clear production storage capacity")
	game._assign_staff(worker,game._facility_index("sewing"),true)
	var plan: Dictionary = flow.order
	if plan.is_empty():
		push_error("Production assignment did not create an order for style %d" % requested_style)
		game.free()
		quit(1)
		return
	var start_fabric: float = flow.ledger.fabric(plan.fabric_id).meters
	var start_thread: float = flow.ledger.thread(plan.thread_id).meters
	var full_shell: Vector3 = flow.packages[plan.fabric_id].shell.mesh.get_aabb().size
	var seen := {}
	var last := ""
	var maximum_carry_gap := 0.0
	var move_stations := "--move-stations" in OS.get_cmdline_user_args()
	var stations_moved := false
	for frame in 9000:
		worker.simulate(1.0/30.0,1.0)
		flow.advance(1.0/30.0)
		if move_stations and not stations_moved and flow.phase == "unfold" and flow.elapsed > .5:
			var moved: Transform3D = flow.cutting.transform
			moved.origin.z -= .15
			var placed: Dictionary = game.try_place_fixture(flow.cutting,moved)
			if not placed.ok:
				var room: Node3D = game._rooms.workshop
				for key in room._anchors:
					if not str(key).ends_with("_label") and room.route(Vector3(0,0,3.25),room.to_local(room._anchors[key].global_position)).is_empty(): print("BLOCKED_ANCHOR ",key," ",room.to_local(room._anchors[key].global_position))
			check(placed.ok,"Moving cutting station rejected: "+str(placed.reason))
			moved = flow.cabinet.transform
			moved.origin.x += .10
			placed = game.try_place_fixture(flow.cabinet,moved)
			check(placed.ok,"Moving material cabinet rejected: "+str(placed.reason))
			stations_moved = true
		seen[flow.phase] = true
		if flow.carried != null and flow.phase in ["to_cut","carry_pieces","to_remnant","to_return","return_thread","to_unmount"]:
			for side in worker.hand_targets:
				var actual: Vector3 = worker.body_rig.to_global(worker.rig.global_pose(worker.rig.bones["Hand"+side]).origin)
				maximum_carry_gap = maxf(maximum_carry_gap,actual.distance_to(worker.hand_targets[side]))
		if flow.phase != last:
			print("MATERIAL_PHASE ",flow.phase," position=",worker.global_position," nav=",worker.navigation_status)
			last = flow.phase
		var ready_capture: bool = flow.elapsed > (1.8 if flow.phase == "unfold" else .7)
		if flow.phase == "to_cut": ready_capture = worker.global_position.distance_to(flow.cabinet.access.global_position) > .8
		if flow.phase in ["take_fabric","to_cut","unfold","cut","sew","store_thread"] and not snapshots.has(flow.phase) and ready_capture:
			snapshots[flow.phase] = true
			await capture(flow.phase,flow,worker)
		if flow.finished_count > 0: break
		if frame % 300 == 0: await process_frame
	check(flow.finished_count == 1,"Production did not finish: phase=%s nav=%s pos=%s destination=%s" % [flow.phase,worker.navigation_status,worker.global_position,worker.destination])
	check(not move_stations or stations_moved,"Furniture move not exercised")
	check(plan.status == "completed","Ledger order not completed")
	check(is_equal_approx(flow.ledger.fabric(plan.fabric_id).meters,start_fabric-float(plan.estimate.cut_m)),"Fabric debit differs from plan")
	check(is_equal_approx(flow.ledger.thread(plan.thread_id).meters,start_thread-float(plan.estimate.thread_m)),"Thread debit differs from plan")
	check(flow.ledger.remnants.size() == 1,"Reusable remnant missing or duplicated")
	check(flow.packages[plan.fabric_id].get_parent() == flow.mounts[plan.fabric_id],"Remaining fabric did not return to its slot")
	check(flow.packages[plan.thread_id].get_parent() == flow.mounts[plan.thread_id],"Thread did not return to peg")
	var remaining_shell: Vector3 = flow.packages[plan.fabric_id].shell.mesh.get_aabb().size
	check(remaining_shell.x*remaining_shell.y*remaining_shell.z < full_shell.x*full_shell.y*full_shell.z,"Fabric package did not thin")
	check(game._inventory.produced_orders.size() == 1,"Wrong number of produced items")
	if game._inventory.produced_orders.has(plan.id):
		var item: Node3D = game._inventory.produced_orders[plan.id]
		var flower := requested_style == 9
		check((item.definition.accessory_kind == "flower" if flower else item.definition.outfit_style == requested_style) and item.definition.material_data.pigment == plan.material_snapshot.pigment,"Finished garment lost selected style or source material")
		check(item.location == ("accessory" if flower else "storage") and item.visible,"Finished item is not visibly stored")
		check(game._inventory.create_from_work_order(plan) == item,"Repeated completion created a second garment")
	check(worker.hand_targets.is_empty(),"Completed worker has stuck hand targets")
	check(maximum_carry_gap < .12,"Hands cannot reach carried material: gap=%s" % maximum_carry_gap)
	for required in ["take_fabric","take_thread","unfold","cut","take_pieces","carry_pieces","mount_thread","sew","store_output","load_remnant","return_fabric","store_thread"]:
		check(seen.has(required),"Skipped phase "+required)
	await capture("complete",flow,worker)
	print("MATERIAL_PRODUCTION_TEST failures=",errors.size()," phases=",seen.size()," max_carry_gap=",maximum_carry_gap)
	game.free()
	quit(0 if errors.is_empty() else 1)

func capture(label: String, flow: Node3D, worker: Node3D) -> void:
	if not capture_enabled: return
	var target: Vector3 = worker.global_position+Vector3(0,1.3,0)
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.camera.h_offset = 0
	game.camera.v_offset = 0
	game.camera.fov = 42
	game.camera.global_position = target+Vector3(3.0,2.0,4.7)
	game.camera.look_at(target)
	if label in ["unfold","cut"]:
		game.camera.global_position = flow.cutting.to_global(Vector3(-3.0,3.7,2.8))
		game.camera.look_at(flow.cutting.to_global(Vector3(0,1.0,.1)))
	if label in ["complete","store_thread"]:
		worker.hide()
		game.camera.global_position = flow.cabinet.to_global(Vector3(1.4,3.2,4.0))
		game.camera.look_at(flow.cabinet.to_global(Vector3(0,1.7,0)))
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/material_%s.png" % label))
	worker.show()
