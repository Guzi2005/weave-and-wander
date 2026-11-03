extends SceneTree

var game: Node
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)


func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._set_speed(0)
	game.get_node("GameInterface").hide()
	for person in game.staff:
		game._set_staff_idle(person,100000)
		person.hide()
	for person in game.customers: person.hide()
	var cashier: Node3D = game.staff[1]
	cashier.show()
	game._assign_staff(cashier,2,true)
	cashier.global_position = game.facilities[2].anchor.global_position
	cashier.move_to_anchor(game.facilities[2].anchor,"checkout")
	cashier.simulate(.1,1)
	check(game._cashier_present(),"Cashier was not at the actual counter")
	var customer: Node3D = game.customers[0]
	customer.show()
	var counter: Node3D = game._shop.interaction_anchor("customer_checkout")
	customer.global_position = counter.global_position
	customer.move_to_anchor(counter,"checkout")
	customer.simulate(.1,1)
	game._shop.checkout_queue.join(customer)
	var item: Node3D = game._inventory.on_rack()[0]
	item.reserve(customer)
	game._inventory.pick_up(item,customer)
	var behavior: RefCounted = game._customer_behaviors[customer.get_instance_id()]
	behavior.accepted.assign([item])
	var money: int = game._money
	var exchange: Node3D = game._shop.checkout_exchange
	for frame in 240:
		behavior._checkout(customer,1.0/30.0,frame == 0)
		cashier.simulate(1.0/30.0,1)
		customer.simulate(1.0/30.0,1)
		if frame < 49: check(game._money == money,"Payment booked before the handover finished")
		if frame == 13:
			check(exchange.phase == "offer" and exchange.cash.visible,"No money offering action")
			await capture("checkout_payment_offer",Vector3(5.5,3.5,4.9),Vector3(1.65,1.3,-.3),42)
		if frame == 29:
			check(exchange.phase == "receive","Cashier skipped receiving money")
			await capture("checkout_payment_receive",Vector3(5.5,3.5,4.9),Vector3(1.65,1.3,-.3),42)
		if frame == 88:
			await capture("checkout_folding",Vector3(3.9,3.5,4.0),Vector3(1.4,1.3,-.3),39)
		if frame == 116:
			await capture("checkout_bagging",Vector3(3.9,3.5,4.0),Vector3(1.4,1.3,-.3),39)
		if item.paid: break
	check(item.paid and exchange.completed_count == 1 and game._money == money+item.definition.price,"Payment did not settle exactly once")
	check(customer.hand_targets.is_empty() and cashier.hand_targets.is_empty(),"Payment left a stuck hand pose")
	check(item.location == "packed" and customer.shopping_bag.contents == [item],"Checkout did not deliver the actual stock object")
	await capture("checkout_delivered",Vector3(3.9,3.5,4.0),Vector3(1.4,1.3,-.3),39)
	# Gaze and eye bones move without detaching headwear or the whole body.
	var target := Node3D.new()
	game.add_child(target)
	target.global_position = customer.body_rig.to_global(Vector3(.8,2.5,1.0))
	customer.attend(target,8)
	for tick in 40: customer.simulate(.033,1)
	var head: Quaternion = customer.rig.skeleton.get_bone_pose_rotation(customer.rig.bones.Head)
	var eye: Vector3 = customer.rig.skeleton.get_bone_pose_position(customer.rig.bones.EyeL)
	check(absf(head.get_euler().y) > .10,"NPC head does not track its focus")
	check(eye.distance_to(customer.rig.skeleton.get_bone_rest(customer.rig.bones.EyeL).origin) > .001,"Eyes did not change gaze")
	customer.simulate(2,0)
	check(head.is_equal_approx(customer.rig.skeleton.get_bone_pose_rotation(customer.rig.bones.Head)),"Paused gaze advanced")
	target.free()
	customer.simulate(.1,1)
	customer.hide()
	cashier.hide()
	game._set_staff_idle(cashier,100000)
	var worker: Node3D = game.staff[2]
	worker.show()
	var loom: Node3D = game._rooms.workshop.get_node("WeavingLoom")
	var loom_index: int = game._facility_index("loom")
	game._assign_staff(worker,loom_index,true)
	for tick in 1800:
		worker.simulate(1.0/30.0,1)
		if worker.has_arrived(): break
	check(worker.has_arrived(),"Loom is not reachable through navigation")
	var before: float = game._inventory.fabric_meters()
	var moved := {}
	for frame in 400:
		loom.advance(worker,1.0/30.0)
		worker.simulate(1.0/30.0,1)
		moved[loom.phase] = true
		if frame == 32:
			await capture("loom_working",loom.to_global(Vector3(3.8,3.4,4.8)),loom.to_global(Vector3(0,1.25,.12)),43)
		if frame == 385:
			await capture("loom_finished_bolt",loom.to_global(Vector3(3.8,3.4,4.8)),loom.to_global(Vector3(0,1.25,.12)),43)
	check(moved.size() == 4,"Missing loom cycle phases")
	check(loom.produced == 1 and loom.yarn_remaining == 88,"Loom consumed/produced wrong quantities")
	check(is_equal_approx(game._inventory.fabric_meters(),before+2.0),"Woven cloth was not stored as usable inventory")
	var output_id: String = loom.output_nodes[0].get_meta("fabric_id")
	check(game._inventory.fabric_batches.any(func(batch: Dictionary) -> bool: return batch.id == output_id),"Physical bolt and stock identity differ")
	var progress: float = loom.elapsed
	loom.advance(worker,0)
	check(loom.elapsed == progress,"Paused loom advanced")
	game._set_staff_idle(worker,100000)
	check(loom.phase == "idle" and worker.hand_targets.is_empty(),"Unstaffed loom kept operating")
	# The woven object feeds sewing and is not conjured again by repeated receipts.
	var batch: Dictionary = game._inventory.fabric_batches.back().duplicate(true)
	game._inventory.fabric_batches.clear()
	game._inventory.receive_fabric(batch)
	game._inventory.receive_fabric(batch)
	check(game._inventory.fabric_batches.size() == 1,"Duplicate fabric receipt")
	var rng := RandomNumberGenerator.new()
	var sewn: Node3D = game._inventory.sew_new(rng)
	check(sewn != null and sewn.get_meta("fabric_sources")[0].fabric_id == output_id,"Sewing lost fabric provenance")
	game._inventory.fabric_batches.clear()
	check(game._inventory.sew_new(rng) == null,"Sewing created clothes without cloth")
	print("LIVE_CRAFT_TEST gaze=true payment=true loom=true fabric=true failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func capture(label: String, eye: Vector3, target: Vector3, fov: float) -> void:
	if DisplayServer.get_name() == "headless": return
	game.camera.position = eye
	game.camera.look_at(target)
	game.camera.fov = fov
	for tick in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/%s_%dx%d.png"%[label,root.size.x,root.size.y]))
