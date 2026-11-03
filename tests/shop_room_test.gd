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
	var room: Node3D = game._room
	for fixture in ["GarmentDisplay", "CheckoutCounter", "FittingBooth", "StandingMirror", "LaundryBasket", "SmallGoodsCabinet"]:
		_check(room.has_node(fixture), "Missing room fixture: " + fixture)
	var destinations: Array[Vector3] = [room.ENTRY, room.CHECKOUT, room.FITTING, room.MIRROR]
	for facility in game.facilities:
		if facility["room"] == "shop":
			destinations.append(facility["use_position"])
	var route_count := 0
	for origin in destinations:
		for target in destinations:
			var route: PackedVector3Array = room.route(origin, target)
			_check(not route.is_empty(), "Unreachable fixture: %s -> %s" % [origin, target])
			var previous := origin
			for point in route:
				for step in 30:
					var sample := previous.lerp(point, float(step)/29.0)
					_check(room.is_walkable(Vector2(sample.x, sample.z)), "Route crosses furniture: %s -> %s" % [origin, target])
				previous = point
			route_count += 1
	var stages: Dictionary = {}
	var samples := 0
	game._set_speed(1.0)
	for tick in 5400:
		game._process(1.0/30.0)
		for doll in game.staff + game.customers:
			if doll.get_meta("room", "shop") == "street":
				_check(doll.position.z >= 3.4 and doll.position.z <= 9,"Street customer left the entrance/road route")
				continue
			var actor_room: Node3D = game._rooms[doll.get_meta("room", "shop")]
			var local := actor_room.to_local(doll.position)
			_check(actor_room.is_walkable(Vector2(local.x,local.z)), "Actor entered furniture: %s %s" % [doll.doll_name,doll.position])
			samples += 1
		for behavior in game._customer_behaviors.values():
			stages[behavior.stage] = true
		if tick % 120 == 0:
			await process_frame
	for stage in ["browse_wait", "fitting_wait", "mirror_wait", "checkout_wait", "to_exit"]:
		_check(stages.has(stage), "Customer flow missed " + stage)
	_check(game._sales_count >= 3, "Customers failed to complete purchases.")
	var position: Vector3 = game.staff[0].position
	game._set_speed(0)
	game._process(4.0)
	_check(game.staff[0].position == position, "Pause moved a character.")
	var curtain: Node3D = room.get_node("FittingBooth/PleatedCurtain")
	curtain.set_closed(true)
	curtain.advance(2.0)
	_check(curtain.is_closed(), "Fitting curtain failed to close.")
	curtain.set_closed(false)
	curtain.advance(2.0)
	_check(curtain.is_open(), "Fitting curtain failed to reopen.")
	print("ROOM_CHECK routes=",route_count," actor_samples=",samples," sales=",game._sales_count," stages=",stages.keys()," failures=",failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
