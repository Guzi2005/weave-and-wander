extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if not value and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var routes := 0
	for id in game.ROOM_ORDER:
		var room: Node3D = game._rooms[id]
		_check(room.visible,"Adjacent room was hidden")
		_check(room.find_children("*","Label3D",true,false).is_empty(),"Scene lettering remains")
		_check(not room.has_node("ShopIdentity") and not room.has_node("RoomIdentity"),"Scene plaque remains")
		var destinations := [Vector3(-7.2,0,1.75),Vector3(7.2,0,1.75)]
		for facility in game.facilities:
			if facility["room"] == id:
				destinations.append(room.to_local(facility["use_position"]))
		for from in destinations:
			for to in destinations:
				var path: PackedVector3Array = room.route(from,to)
				_check(not path.is_empty(),"Blocked route in %s: %s -> %s" % [id,from,to])
				var previous: Vector3 = from
				for point in path:
					for sample in 30:
						var p := previous.lerp(point,sample/29.0)
						_check(room.is_walkable(Vector2(p.x,p.z)),"Route clips furniture in "+id)
					previous = point
				routes += 1
		for lamp in room.get_children():
			if not lamp.has_meta("roof_anchor_height"):
				continue
			var cord: MeshInstance3D = lamp.get_node("Cord")
			var top: float = lamp.position.y+cord.position.y+cord.mesh.get_aabb().end.y
			_check(absf(top-float(lamp.get_meta("roof_anchor_height"))) < .002,"Pendant cord detached from roof")
			_check(lamp.position.y-.13 > 3.5,"Pendant too low for character clearance")
	var actor: PaperDoll = game.staff[1]
	var id := actor.get_instance_id()
	game._set_speed(1.0)
	var completed := 0
	for facility in [5,9,2,6,10]:
		game._assign_staff(actor,facility,true)
		var reached := false
		for tick in 1800:
			var before: Vector3 = actor.position
			game._process(1.0/30.0)
			_check(actor.position.distance_to(before) < .12,"Room crossing teleported staff")
			if tick%90 == 0:
				await process_frame
			if game._staff_jobs[id]["phase"] == "work" and game._staff_jobs[id]["facility"] == facility:
				reached = true
				break
		_check(reached,"Staff failed to cross rooms to facility "+str(facility))
		_check(actor.get_meta("room") == game.facilities[facility]["room"],"Wrong actor room after travel")
		completed += int(reached)
	# Real pointer input through both room arrows, then the off-room portrait.
	game._switch_room("shop",false)
	await process_frame
	_click(game._room_right.get_global_rect().get_center())
	await game._camera_tween.finished
	_check(game._active_room == "archive","Right arrow did not open archive")
	_click(game._room_left.get_global_rect().get_center())
	await game._camera_tween.finished
	_check(game._active_room == "shop","Left arrow did not return to shop")
	var card: Control = game._cards[id]
	_click(card.get_global_rect().position+Vector2(43,38))
	await game._camera_tween.finished
	_check(game._active_room == actor.get_meta("room"),"Portrait did not locate staff in another room")
	_check(card.size.y > card.size.x,"Staff control must be a portrait card")
	game._switch_room("workshop",false)
	game._set_speed(2)
	await process_frame
	var start := card.get_global_rect().get_center()
	var destination: Vector2 = game.camera.unproject_position(game.facilities[5]["label_position"])
	_pointer(start,false)
	_button(start,true)
	await process_frame
	_pointer(destination,true)
	await process_frame
	_check(game.dragging_doll == actor and game._speed == 0,"Cross-room drag did not pause")
	_check(game._active_room == "workshop","Dragging off-room staff unexpectedly changed rooms")
	_button(destination,false)
	await process_frame
	_check(game._staff_jobs[id]["facility"] == 5 and actor.destination_anchor.get_ref() == game.facilities[5]["anchor"],"Cross-room card drop did not route staff")
	_check(game._speed == 2,"Drop did not restore speed")
	game._set_speed(1)
	var sales: int = game._sales_count
	game._switch_room("workshop",false)
	for tick in 2400:
		game._process(1.0/30.0)
		if tick%120 == 0:
			await process_frame
	_check(game._sales_count > sales,"Hidden shop stopped running")
	for customer in game.customers:
		_check(customer.visible,"Connected-house customer was hidden")
	game._set_speed(0)
	var positions := {}
	for staff in game.staff:
		positions[staff] = staff.position
	game._switch_room("archive",false)
	game._process(3)
	for staff in game.staff:
		_check(staff.position == positions[staff],"Room switching discarded pause")
	print("ADJACENT_ROOMS routes=",routes," completed_transfers=",completed," background_sales=",game._sales_count-sales," failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func _click(at: Vector2) -> void:
	_pointer(at,false)
	_button(at,true)
	_button(at,false)


func _pointer(at: Vector2, pressed: bool) -> void:
	var move := InputEventMouseMotion.new()
	move.position=at
	move.global_position=at
	move.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(move,true)


func _button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=at
	event.global_position=at
	event.button_index=MOUSE_BUTTON_LEFT
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed=pressed
	root.push_input(event,true)
