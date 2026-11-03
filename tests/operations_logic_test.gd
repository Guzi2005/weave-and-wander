extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var shop: Node3D = game._shop
	var inventory: Node3D = game._inventory
	var counter: int = game._facility_index("counter", "shop")
	var counter_local := shop.to_local(game.facilities[counter].anchor.global_position)
	_check(shop.is_walkable(Vector2(counter_local.x, counter_local.z)), "Cashier post is not a walkable spot")
	var hat: Node3D
	var garment: Node3D
	for item in inventory.items:
		if hat == null and item.definition.is_hat() and item.location == "rack":
			hat = item
		elif garment == null and not item.definition.is_hat() and item.location == "rack":
			garment = item
	hat.tried_on = true
	inventory.slots[hat.slot].erase(hat)
	hat.location = "carried"
	inventory.return_item(hat)
	var low := INF
	for part in hat.parts:
		for vertex in part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			low = minf(low, (hat.global_transform * vertex).y)
	_check(low >= .64 and low <= .75, "Returned hat is not sitting on the basket rim, low y=%s" % low)
	var plan: Dictionary = inventory.restock_plan()
	var mount: Vector3 = inventory.slot_transform(plan.slot).origin
	_check(plan.place.z > mount.z and absf(plan.place.x - mount.x) < .5 and plan.place.distance_to(Vector3(mount.x, 0, mount.z)) < 1.35, "Restock stand is far from the hat: %s vs %s" % [plan.place, mount])
	garment.tried_on = true
	inventory.slots[garment.slot].erase(garment)
	garment.location = "carried"
	inventory.return_item(garment)
	plan = inventory.restock_plan()
	_check(plan.fetch.distance_to(shop.interaction_anchor("return_basket").global_position) < .05, "Basket returns are not collected at the basket")
	for doll in game.staff:
		game._set_staff_idle(doll, 30.0)
		doll.global_position = Vector3(-12.0, 0, 1.2)
	game.customers[0].global_position = Vector3(0, 0, 1.0)
	game.customers[0].set_meta("room", "shop")
	game._process_staff_jobs(.05)
	_check(game.facilities[counter].staff != null, "Nobody covered the unmanned counter")
	_check(game._staff_jobs[game.facilities[counter].staff.get_instance_id()].facility == counter, "Counter cover went to another facility")
	var followed: Node3D = game.staff[0]
	followed.global_position = Vector3(0, 0, 1.2)
	game.staff[1].global_position = Vector3(30, 0, 8)
	game.staff[2].global_position = Vector3(32, 0, 8)
	game.customers[0].global_position = Vector3(34, 0, 8)
	game._begin_follow(followed)
	game._view_controls.step(.2)
	_check(game._pop_up.enclosed and game._street.exterior_amount > .98, "Follow view left the shop cut away")
	_check(not game._street.get_node("ReflectionInteriorShell").visible, "Enclosed follow still draws the mirror-only shell")
	_check(is_zero_approx(game._shop.get_node("HingedRoof").open_amount(1)), "Follow view left a roof lid open")
	var third_distance: float = game.camera.position.distance_to(followed.global_position)
	_check(third_distance > 1.5 and third_distance < 4.2, "Third-person follow is not beside the character")
	var blocker: Node3D = game.staff[1]
	blocker.global_position = game.camera.position - Vector3(0, 1.72, 0)
	blocker.visible = true
	game._view_controls.apply_view()
	_check(game.camera.position.distance_to(followed.global_position) < third_distance - .4, "Third-person camera stayed inside another person")
	game._set_follow_perspective(true)
	game._view_controls.step(.1)
	var body: GeometryInstance3D = followed.body_rig.find_children("*", "GeometryInstance3D", true, false)[0]
	_check(followed.visible and body.layers == 8, "First person hid the body from the mirror")
	_check(game.camera.position.distance_to(followed.global_position + Vector3(0, 1.92, 0)) < .45, "First-person camera is not at eye height")
	game._end_follow()
	_check(followed.visible and body.layers == 1 and game._view_controls.follow_target == null, "Leaving follow did not restore the character")
	_check(not game._pop_up.enclosed and game._street.get_node("ReflectionInteriorShell").visible, "Leaving follow kept the enclosed shop")
	print("OPERATIONS_CHECK failures=", failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
