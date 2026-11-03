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
	game._spawn_clock = 100000
	var room: Node3D = game._shop
	var inventory: Node3D = game._inventory
	_check(not room._segment_clear(Vector2(3.50,.58),Vector2(3.54,.50)), "Short corner crossing escaped collision checks")
	var rack: Node3D = room.get_node("GarmentDisplay")
	var actor: PaperDoll = game.staff[0]
	for person in game.staff:
		game._set_staff_idle(person, 100000)
	# A reserved item still occupies its rack slot until physically picked up.
	var customer: Node3D = game.customers[0]
	var item: Node3D = inventory.items[0]
	_check(item.reserve(customer), "Cannot reserve opening garment")
	_check(item in inventory.slots[item.slot], "Reservation creates a premature gap")
	var old_transform := rack.transform
	var moved := old_transform
	moved.origin.z += .15
	var placed: Dictionary = game.try_place_fixture(rack, moved)
	_check(placed.ok, "Valid rack move rejected: " + placed.reason)
	_check(item.global_position.distance_to(inventory.slot_transform(item.slot).origin) < .001, "Rack move left the reserved garment behind")
	_check(room.interaction_anchor("pickup_0").global_position.z > .5, "Pickup marker did not move with rack")
	inventory.return_item(item, customer)
	# Invalid placement must roll back atomically, without moving stock or changing routes.
	var valid_transform := rack.transform
	var invalid := valid_transform
	invalid.origin = room.get_node("CheckoutCounter").position
	var rejected: Dictionary = game.try_place_fixture(rack, invalid)
	_check(not rejected.ok, "Overlapping furniture accepted")
	_check(rack.transform.is_equal_approx(valid_transform), "Rejected placement moved furniture")
	_check(item.global_position.distance_to(inventory.slot_transform(item.slot).origin) < .001, "Rejected placement moved inventory")
	# Rotated furniture has a rotated footprint, not its previous axis-aligned box.
	var mirror: Node3D = room.get_node("StandingMirror")
	var mirror_before := mirror.transform
	mirror.position = Vector3(4.0, 0, 1.5)
	mirror.rotation.y += PI * .5
	game._navigation.refresh()
	var local_marker: Vector3 = mirror.to_local(room.interaction_anchor("customer_mirror").global_position)
	_check(not room.is_walkable(Vector2(4, 1.5)), "Rotated mirror has no obstruction")
	_check(room.is_walkable(Vector2(3.74, -.87)), "Old mirror position remains blocked")
	_check(local_marker.length() > 1.0, "Mirror interaction point lost its local offset")
	mirror.transform = mirror_before
	game._navigation.refresh()
	# Reassign while already crossing a boundary; no old per-room provider survives.
	game._assign_staff(actor, 9, true)
	for tick in 90:
		game._process(1.0 / 30.0)
	game._assign_staff(actor, 5, true)
	var arrived := false
	for tick in 1800:
		var before := actor.global_position
		game._process(1.0 / 30.0)
		_check(actor.global_position.distance_to(before) < .12, "Cross-room movement teleported")
		if game._staff_jobs[actor.get_instance_id()].phase == "work":
			arrived = true
			break
	_check(arrived and actor.get_meta("room") == "workshop", "Reassigned employee cannot cross rooms")
	# Move an interaction target while a staff member is on the way.
	game._assign_staff(actor, 0, true)
	for tick in 30:
		game._process(1.0 / 30.0)
	rack.position.z += .1
	game._navigation.refresh()
	game._refresh_facilities()
	arrived = false
	for tick in 1800:
		game._process(1.0 / 30.0)
		if game._staff_jobs[actor.get_instance_id()].phase == "work":
			arrived = true
			break
	_check(arrived and actor.global_position.distance_to(room.interaction_anchor("rack").global_position) < .04, "Staff went to the old furniture location")
	# Unreachable destinations are blocked, never a false arrival or remote task.
	actor.stop_navigation()
	var count := [0]
	actor.arrived.connect(func(_actor: PaperDoll) -> void: count[0] += 1)
	var result := actor.set_destination(room.get_node("CheckoutCounter").global_position, "checkout")
	for tick in 30:
		actor.simulate(1.0 / 30.0, 1)
	_check(not result and actor.navigation_status == "blocked" and not actor.has_arrived() and count[0] == 0, "Blocked route was counted as an arrival")
	# A blocked live target resumes after the obstruction is removed.
	var marker := Marker3D.new()
	room.add_child(marker)
	marker.position = Vector3(.0, 0, 2.5)
	var bench: Node3D = room.get_node("ParcelBench")
	var bench_before := bench.transform
	bench.position = marker.position
	game._navigation.refresh()
	actor.move_to_anchor(marker, "stocking")
	_check(actor.navigation_status == "blocked", "Obstacle did not block destination")
	bench.transform = bench_before
	game._navigation.refresh()
	for tick in 1200:
		actor.simulate(1.0 / 30.0, 1)
		if actor.has_arrived():
			break
	_check(actor.has_arrived(), "Blocked actor failed to resume after layout changed")
	# Changed aisle geometry triggers replanning before the next movement step.
	actor.set_destination(Vector3(5.2, 0, 2), "stocking")
	bench.position = Vector3(3.0, 0, 2)
	game._navigation.refresh()
	for tick in 1200:
		actor.simulate(1.0 / 30.0, 1)
		var point := room.to_local(actor.global_position)
		_check(room.is_walkable(Vector2(point.x, point.z)), "Replanned route crossed moved furniture")
		if actor.has_arrived():
			break
	_check(actor.has_arrived(), "Actor did not detour around moved furniture")
	bench.transform = bench_before
	game._navigation.refresh()
	# Curtain folds are rigid leaves; adjacent edges stay joined at all poses.
	var curtain: Node3D = room.fitting_room.curtain
	for amount in [0.0, .25, .5, .75, 1.0]:
		curtain.amount = amount
		curtain._pose()
		for i in curtain.panels.size() - 1:
			var a: Node3D = curtain.panels[i]
			var b: Node3D = curtain.panels[i + 1]
			var right := a.to_global(Vector3(curtain.PANEL_WIDTH * .5, 0, 0))
			var left := b.to_global(Vector3(-curtain.PANEL_WIDTH * .5, 0, 0))
			_check(right.distance_to(left) < .001, "Accordion leaves separated")
			_check(a.scale.is_equal_approx(Vector3.ONE), "Curtain panel was scaled instead of hinged")
	print("DYNAMIC_NAVIGATION failures=", failures.size(), " revisions=", game._navigation.revision)
	game.free()
	quit(0 if failures.is_empty() else 1)
