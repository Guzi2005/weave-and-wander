extends SceneTree
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func capture(game, target: Node3D, offset: Vector3, focus: Vector3, label: String):
	if DisplayServer.get_name() == "headless": return
	game._view_controls.set_process(false)
	game.get_node("GameInterface").hide()
	game.get_node("RenderAB").hide()
	game.camera.global_position = target.to_global(offset)
	game.camera.look_at(target.to_global(focus))
	game.camera.fov = 48
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/production_consistency_"+label+".png")
func run():
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for worker in game.staff: game._set_staff_idle(worker,100000)
	var loom = game._rooms.workshop.get_node("WeavingLoom")
	check(loom.required_picks()*loom.seconds_per_pick >= 600,"Insufficient weaving workload")
	var ledger = game._inventory.materials
	var before := 0.0
	for yarn in ledger.yarn_batches: before += float(yarn.meters)
	var weaver = game.staff[1]
	var station = game.facilities[game._facility_index("loom")].anchor
	weaver.global_position = station.global_position
	weaver.move_to_anchor(station,"weaving")
	for frame in 90: weaver.simulate(1.0/30,1)
	check(loom.advance(weaver,.1) == "working","Opening yarn cannot produce a batch")
	check(loom.advance(game.staff[0],1) == "busy","Concurrent worker took over loom")
	var after := 0.0
	for yarn in ledger.yarn_batches: after += float(yarn.meters)
	check(is_equal_approx(before-after,loom.yarn_requirement()),"Incorrect yarn debit")
	var color: Color = loom.active_descriptor.pigment
	var bobbin = loom.shuttle.find_child("ShuttleBobbin",true,false)
	check(bobbin != null,"Shuttle bobbin missing")
	if bobbin != null:
		check(bobbin.material_override.get_shader_parameter("pigment") == color,"Shuttle yarn differs from cloth")
	for source in loom.active_yarn:
		check(ledger.yarn(source.id).pigment == color,"Different yarn colours silently consumed")
	loom.batch_length_m = 8
	loom.picks_per_meter = 1
	check(loom.required_picks() == 80,"Active batch lost density snapshot")
	loom.advance(weaver,320)
	loom.stop()
	check(loom.picks_done == 40,"Pause lost progress")
	loom.advance(weaver,320)
	loom.stop()
	var batch: Dictionary = game._inventory.fabric_batches.back()
	check(batch.meters == 2.0 and batch.picks == 80,"Output changed when tuning edited mid-batch")
	check(batch.pigment == color,"Output colour mismatched")
	var flow = game._production
	check(flow.packages.has(batch.id),"Output has no retrievable physical package")
	check(batch.form == "book" and flow.packages[batch.id].form == "book","Woven cloth is not a fabric book")
	check(loom.has_node("FabricBookShelf0"),"Output has no supporting shelf")
	check(is_equal_approx(flow.mounts[batch.id].position.y,.72),"Book does not rest on shelf")
	check(flow.mounts[batch.id].get_parent() == loom,"Output teleported to cabinet")
	check(flow.mounts[batch.id].has_meta("material_access"),"Output lacks pickup position")
	flow.sync_stock()
	check(flow.packages[batch.id].get_parent() == flow.mounts[batch.id],"Stock sync replaced physical output")
	await capture(game,loom,Vector3(3.8,2.8,4.2),Vector3(.65,.95,.4),"loom")
	game._inventory.in_location("storage")[0].collect()
	flow.selected_fabric = batch.id
	flow.selected_style = 1
	var worker = game.staff[2]
	game._assign_staff(worker,game._facility_index("sewing"),true)
	var picked := false
	var checked_sewing := false
	for frame in 15000:
		worker.simulate(1.0/30,1)
		flow.advance(1.0/30)
		if flow.phase == "sew" and flow.elapsed > .3:
			if not checked_sewing:
				await capture(game,flow.machine,Vector3(1.6,1.8,2.4),Vector3(-.1,.4,0),"sewing")
			checked_sewing = true
			var machine = flow.machine
			check(machine.loaded_fabric_id == flow.order.material_snapshot.id,"Sewing fabric snapshot was skipped")
			check(machine.get_node("FabricUnderFoot").material_override.get_shader_parameter("pigment") == flow.order.material_snapshot.pigment,"Sewing fabric pigment mismatch")
			check(machine.find_children("ThreadPath*","MeshInstance3D",false,false).size() == 4,"Not all four thread segments are tracked")
			for part in machine.get_children():
				if str(part.name).begins_with("ThreadPath"):
					check(part.visible and part.material_override.get_shader_parameter("pigment") == flow.order.thread_snapshot.pigment,"Sewing thread mismatch")
		picked = picked or flow.carried == flow.packages[batch.id]
		if flow.finished_count > 0: break
		if frame%300 == 0: await process_frame
	check(picked and flow.finished_count == 1,"Woven bolt did not reach finished garment: "+flow.phase)
	check(checked_sewing,"Sewing material assertion never executed")
	check(flow.packages[batch.id].get_parent() == flow.mounts[batch.id],"Remaining bolt did not return to loom")
	print("LOOM_PRODUCTION_TEST failures=",failures)
	game.free()
	quit(0 if failures == 0 else 1)
