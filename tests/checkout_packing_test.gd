extends SceneTree

const BT = preload("res://scripts/behavior_tree.gd")
var game: Node
var errors: Array[String] = []
var record_motion := false
var frame_serial := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value and message not in errors:
		errors.append(message)
		push_error(message)


func _run() -> void:
	record_motion = "--capture-actions" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for control in [game._view_controls,game._roof_controls,game._pop_up]: control.set_process(false)
	game._set_speed(0)
	game.get_node("GameInterface").hide()
	for actor in game.staff:
		game._set_staff_idle(actor,100000)
		actor.hide()
	for actor in game.customers: actor.hide()
	var stock: Node3D = game._inventory
	var exchange: Node3D = game._shop.checkout_exchange
	var cashier: Node3D = game.staff[1]
	cashier.show()
	staff_at_counter(cashier)
	var customer: Node3D = game.customers[0]
	customer.show()
	var behavior: RefCounted = game._customer_behaviors[customer.get_instance_id()]
	var queue: Node3D = game._shop.checkout_queue
	queue.join(customer)
	var anchor: Node3D = game._shop.interaction_anchor("customer_checkout")
	customer.global_position = anchor.global_position
	customer.move_to_anchor(anchor,"checkout")
	customer.resting_facing = PI
	for tick in 60: customer.simulate(1.0/30.0,1)
	var shirt: Node3D = stock.slots[1][0]
	var hat: Node3D = stock.slots[6][0]
	var trousers: Node3D = stock.slots[3][0]
	var ids := [shirt.get_instance_id(),hat.get_instance_id(),trousers.get_instance_id()]
	for item in [shirt,hat,trousers]:
		item.reserve(customer)
		stock.pick_up(item,customer)
	check_stack(customer,[shirt,trousers,hat])
	behavior.accepted.assign([shirt,hat,trousers])
	var money: int = game._money
	# Interrupt an order after one physical item has already entered the bag.
	for tick in 135:
		behavior._checkout(customer,1.0/30.0,tick == 0)
		customer.simulate(1.0/30.0,1)
		cashier.simulate(1.0/30.0,1)
	check(shirt.location == "packed", "Interruption fixture did not reach partially packed order")
	game._set_staff_idle(cashier,100000)
	for item in [shirt,hat,trousers]:
		check(item.location == "carried" and not item.paid,"Interrupted packing lost an item")
	check(game._money == money,"Interrupted order changed funds")
	check(customer.shopping_bag == null,"Interrupted order left an orphan carrier")
	check(behavior._checkout(customer,3,false) == BT.Status.RUNNING,"Missing cashier handed over the order")
	staff_at_counter(cashier)
	game.camera.position = Vector3(4.4,3.9,4.8)
	game.camera.look_at(Vector3(1.6,1.35,-.40))
	game.camera.fov = 38
	var phases := {}
	var captured := {}
	var instances: Array = []
	for item in [shirt,hat,trousers]: instances.append(item.parts.map(func(part: MeshInstance3D) -> int: return part.get_instance_id()))
	for tick in 400:
		var result: int = behavior._checkout(customer,1.0/30.0,false)
		customer.simulate(1.0/30.0,1)
		cashier.simulate(1.0/30.0,1)
		stock.advance()
		if is_instance_valid(exchange.packing):
			var wrapping: Node3D = exchange.packing
			if is_instance_valid(wrapping.bag):
				for packed in wrapping.bag.contents:
					check(wrapping.bag.contains_item(packed),"Packed item intersects tapered bag")
				if wrapping.phase == "handoff":
					var bottom: Vector3 = wrapping.bag.position
					check(bottom.y >= 1.18 or bottom.z-wrapping.bag.dimensions.z*.5 > .64,"Handoff crosses counter edge")
			if wrapping.phase == "insert" and wrapping.index == 2 and not captured.has("hat"):
				captured.hat = true
				await capture("checkout_hat_last")
		phases[exchange.phase] = true
		if exchange.active:
			check(game._money == money,"Order committed before packing was complete")
		if record_motion and tick%2 == 0: await motion_frame()
		if result == BT.Status.SUCCESS: break
	for phase in ["offer","receive","deposit","place","fold","insert","handoff"]:
		check(phases.has(phase),"Missing checkout phase "+phase)
	var bag: Node3D = customer.shopping_bag
	check(is_instance_valid(bag) and bag.contents == [shirt,trousers,hat],"Hat is not packed last above all folded garments")
	for item in bag.contents:
		check(bag.contains_item(item),"Carried bag wall intersects goods")
	var price := 0
	for index in 3:
		var item: Node3D = [shirt,hat,trousers][index]
		price += item.definition.price
		check(item.get_instance_id() == ids[index] and item.location == "packed" and item.paid,"Stock identity changed during packing")
		check(instances[index] == item.parts.map(func(part: MeshInstance3D) -> int: return part.get_instance_id()),"Packing replaced the clothing meshes")
		check(item.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE),"Packing rescaled clothes instead of folding")
		check(item.owner_id == customer.customer_id,"Purchased goods lost owner")
		check(stock.checkout(item,customer) == 0,"Repeated checkout charged a paid item")
	check(game._money == money+price and stock.transactions.size() == 3,"Multi-piece order settlement incorrect")
	customer.set_destination(customer.global_position+Vector3(2,0,1.8),"leaving")
	for tick in 90:
		customer.simulate(1.0/30.0,1)
		stock.advance()
		for item in bag.contents: check(bag.contains_item(item),"Walking carrier intersects goods")
		if record_motion and tick%2 == 0: await motion_frame()
	check(shirt.global_transform.origin.distance_to(bag.item_transform(shirt).origin) < .002,"Goods did not follow the carrier during departure")
	await capture("checkout_bag_departure")
	game._complete_customer(customer)
	await process_frame
	stock.advance()
	for item in [shirt,hat,trousers]: check(is_instance_valid(item) and item.location == "collected","Departure freed purchased inventory")
	# Worn purchases skip wrapping completely, including mixed worn/carried orders.
	if game.customers.is_empty(): game._spawn_customer()
	var next: Node3D = game.customers[0]
	queue.join(next)
	next.global_position = anchor.global_position
	next.move_to_anchor(anchor,"checkout")
	next.simulate(.1,1)
	var next_behavior: RefCounted = game._customer_behaviors[next.get_instance_id()]
	var worn: Node3D = stock.on_rack()[0]
	worn.reserve(next)
	stock.pick_up(worn,next)
	next.put_on(worn)
	next_behavior.accepted.assign([worn])
	for tick in 70:
		if next_behavior._checkout(next,1.0/30.0,tick == 0) == BT.Status.SUCCESS: break
	check(worn.paid and worn.location == "worn" and not is_instance_valid(next.shopping_bag),"Wear-out purchase was needlessly bagged")
	# Removed shoppers cannot delete or strand partially packed shop stock.
	queue.join(next)
	var returned: Node3D = stock.on_rack()[0]
	returned.reserve(next)
	stock.pick_up(returned,next)
	next_behavior.accepted.assign([returned])
	for tick in 105: next_behavior._checkout(next,1.0/30.0,tick == 0)
	game.customers.erase(next)
	next.queue_free()
	await process_frame
	await process_frame
	stock.advance()
	check(is_instance_valid(returned) and returned.location in ["rack","storage","basket"],"Deleted shopper lost counter stock")
	print("CHECKOUT_PACKING_TEST identity=true multi_item=true interruption=true wear_out=true frames=",frame_serial," failures=",errors.size())
	game.free()
	quit(0 if errors.is_empty() else 1)


func check_stack(customer: Node3D, ordered: Array) -> void:
	var top := -INF
	for item in ordered:
		var transform: Transform3D = customer.body_rig.global_transform.affine_inverse()*customer.carry_transform(item)
		var bounds: AABB = transform*item.presentation_bounds()
		check(bounds.position.y > top,"Handheld stack overlaps or puts hat under clothing")
		top = bounds.end.y


func staff_at_counter(actor: Node3D) -> void:
	game._assign_staff(actor,2,true)
	actor.global_position = game.facilities[2].anchor.global_position
	actor.move_to_anchor(game.facilities[2].anchor,"checkout")
	actor.simulate(.1,1)
	check(game._cashier_present(),"Cashier anchor unreachable")


func motion_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://captures/checkout_motion")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/frame_%04d.png"%frame_serial)
	frame_serial += 1


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for tick in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/%s_%dx%d.png"%[label,root.size.x,root.size.y]))
