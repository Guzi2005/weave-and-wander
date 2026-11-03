extends SceneTree

const BT = preload("res://scripts/behavior_tree.gd")
var game: Node
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)


func capture(label: String, eye: Vector3, target: Vector3, fov := 35.0) -> void:
	game.camera.position = eye
	game.camera.look_at(target)
	game.camera.fov = fov
	for tick in 5: await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/%s_%dx%d.png" % [label,root.size.x,root.size.y]))


func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	game.get_node("GameInterface").hide()
	for person in game.staff + game.customers: person.hide()
	for person in game.staff: game._set_staff_idle(person,100000)
	var stock: Node3D = game._inventory
	var spools: Array = game._shop.find_children("*","Node3D",true,false).filter(func(node: Node) -> bool: return node.has_meta("thread_turns"))
	check(spools.size() >= 9, "Detailed spool components are missing")
	for spool in spools:
		check(spool.get_meta("thread_turns",0) >= 18 and spool.get_meta("hollow_core",false), "Spool lacks winding or hollow core")
		check(spool.has_node("ContinuousWoundThread"), "Thread detail is not real geometry")
	var shirt: Node3D = stock.slots[1][0]
	var vest: Node3D = stock.slots[2][0]
	var trousers: Node3D = stock.slots[3][0]
	check(stock.display_item(vest,1), "Compatible shirt and waistcoat cannot share a hanger")
	check(stock.slots[1].size() == 2 and stock.slots[2].is_empty(), "Layering copied stock instead of moving it")
	check(not stock.display_item(trousers,1), "Shoulder hanger accepted a third incompatible garment")
	var hat_a: Node3D = stock._create(6,1)
	stock._store(hat_a)
	var hat_b: Node3D = stock._create(6,3)
	stock._store(hat_b)
	var hat_c: Node3D = stock._create(6,2)
	stock._store(hat_c)
	check(stock.display_item(hat_a,6) and stock.display_item(hat_b,6), "Matching hats cannot stack")
	check(not stock.display_item(hat_c,6), "Hat stand exceeded its three-hat limit")
	check(not stock.display_item(stock.slots[7][0],6), "Different hat crowns were nested together")
	await capture("stacked_hangers",Vector3(-3.9,3.10,4.2),Vector3(-4.9,1.72,-.9))
	await capture("stacked_hat_stand",Vector3(-.1,3.0,3.0),Vector3(-1.6,1.8,-.98))
	await capture("wood_trouser_clamp",Vector3(-3.1,2.8,1.8),Vector3(-4.35,2.22,-1.1),27)
	await capture("wound_thread_spools",Vector3(1.2,3.2,.9),Vector3(1.22,2.68,-2.0),28)
	var shopper: Node3D = game.customers[0]
	var hat_ids: Array = stock.slots[6].map(func(piece: Node3D) -> String: return piece.item_id)
	hat_a.reserve(shopper)
	check(stock.pick_up(hat_a,shopper), "Cannot select one hat from a stack")
	check(stock.slots[6].size() == 2 and stock.slots[6][0].item_id == hat_ids[0] and stock.slots[6][1].item_id == hat_ids[2], "Picking one stacked hat changed other stock identities")
	shopper.release_item(stock,hat_a)
	shopper.profile.wanted_styles = [2]
	shopper.profile.favorite_palette = 1
	shopper.profile.max_pieces = 1
	shopper.profile.budget = 100
	var choice: Dictionary = stock.choose_for(shopper,shopper.profile)
	check(choice.items == [vest], "Customer cannot select only the outer layer")
	check(stock.pick_up(vest,shopper), "Cannot remove the outer layer")
	check(stock.slots[1] == [shirt] and shirt.location == "rack", "Removing vest also removed the shirt")
	shopper.release_item(stock,vest)
	stock.display_item(vest,1)
	# The same multi-piece selection may remove both layers, without copying meshes.
	for piece in [shirt,vest]:
		piece.reserve(shopper)
		stock.pick_up(piece,shopper)
		shopper.put_on(piece)
		check(piece.get_parent() == stock, "Disposable customer owns permanent stock")
	shirt.settle(shopper)
	var shirt_id: String = shirt.item_id
	var vest_id: String = vest.item_id
	game.customers.erase(shopper)
	shopper.queue_free()
	await process_frame
	await process_frame
	stock.advance()
	check(is_instance_valid(shirt) and is_instance_valid(vest), "Customer deletion freed its garments")
	check(shirt.item_id == shirt_id and shirt.location == "collected", "Paid garment was not retained as collected stock")
	check(vest.item_id == vest_id and vest.location == "basket", "Unpaid garment was not recovered after holder loss")
	# Restore shelf stock for the service tests.
	while not stock.in_location("basket").is_empty(): stock.restock_step()
	while game.customers.size() < 4: game._spawn_customer()
	var booth: Node3D = game._shop.fitting_room
	var owner: Node3D = game.customers[0]
	owner.global_position = game._shop.interaction_anchor("fitting").global_position
	owner.hide()
	check(booth.request(owner), "First customer could not reserve fitting booth")
	booth.close_for(owner,true)
	booth.advance(2)
	for index in range(1,4):
		var person: Node3D = game.customers[index]
		person.global_position = Vector3(-2+index,0,2.5)
		person.show()
		var behavior: RefCounted = game._customer_behaviors[person.get_instance_id()]
		behavior._move(person,0,true,"to_fitting","fitting_queue","fitting")
	for tick in 600:
		for index in range(1,4): game.customers[index].simulate(1.0/30.0,1)
	for index in range(1,4):
		var person: Node3D = game.customers[index]
		check(person.has_arrived(), "Waiting slot is unreachable")
		check(not booth.request(person), "Waiting customer stole occupied booth")
		for other in range(index+1,4):
			check(person.global_position.distance_to(game.customers[other].global_position) > 1.0, "Waiting customers overlap")
	await capture("fitting_queue_spaced",Vector3(7.7,4.1,7.4),Vector3(4.2,1.35,.45),48)
	var booth_transform: Transform3D = booth.get_parent().transform
	var marker: Marker3D = booth.join(game.customers[1])
	var marker_before := marker.global_position
	booth.get_parent().position.x -= .1
	check(marker.global_position.distance_to(marker_before+Vector3(-.1,0,0)) < .001, "Queue did not follow its furniture")
	booth.get_parent().transform = booth_transform
	booth.release(owner)
	owner.global_position = Vector3(-3,0,2)
	booth.advance(2)
	check(not booth.request(game.customers[2]), "Later customer jumped the fitting queue")
	check(booth.request(game.customers[1]), "First waiting customer did not receive the free booth")
	for person in game.customers: booth.release(person)
	# Queue service must pause, not count down to automatic payment without a cashier.
	var buyer: Node3D = game.customers[1]
	var behavior: RefCounted = game._customer_behaviors[buyer.get_instance_id()]
	var purchase: Node3D = stock.on_rack()[0]
	purchase.reserve(buyer)
	stock.pick_up(purchase,buyer)
	behavior.accepted.assign([purchase])
	game._shop.checkout_queue.join(buyer)
	var counter: Marker3D = game._shop.interaction_anchor("customer_checkout")
	buyer.global_position = counter.global_position
	buyer.move_to_anchor(counter,"checkout")
	buyer.simulate(.1,1)
	var money: int = game._money
	for tick in 200:
		check(behavior._checkout(buyer,.1,tick==0) == BT.Status.RUNNING, "Unstaffed counter completed a sale")
	check(not purchase.paid and game._money == money, "Money changed with nobody at the till")
	check(stock.checkout(purchase,buyer) == 0, "Inventory API allowed a transaction without a cashier")
	var cashier: Node3D = game.staff[1]
	game._assign_staff(cashier,2,true)
	for tick in 900:
		cashier.simulate(1.0/30.0,1)
		if cashier.has_arrived(): break
	check(game._cashier_present(), "Arrived cashier is not available for service")
	behavior._checkout(buyer,.8,false)
	game._set_staff_idle(cashier,100000)
	check(behavior._checkout(buyer,10,false) == BT.Status.RUNNING and not purchase.paid, "Interrupted service completed without cashier")
	game._assign_staff(cashier,2,true)
	cashier.simulate(.1,1)
	var result := BT.Status.RUNNING
	for tick in 240:
		result = behavior._checkout(buyer,1.0/30.0,false)
		cashier.simulate(1.0/30.0,1)
		buyer.simulate(1.0/30.0,1)
		if result == BT.Status.SUCCESS: break
	check(result == BT.Status.SUCCESS, "Customer cannot pay and receive the bag after cashier returns")
	check(purchase.paid and game._money == money+purchase.definition.price, "Staffed sale charged incorrectly")
	game._complete_customer(buyer)
	await process_frame
	stock.advance()
	check(is_instance_valid(purchase) and purchase.location == "collected", "Normal departure lost the purchased item")
	print("SHOP_SERVICE_TEST ownership=true layers=true hats=true queue=true cashier=true failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
