extends SceneTree

var game: Node
var failures: Array[String] = []
var capture := false
var tag := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _tick(frames: int, delta: float = 1.0/30.0) -> void:
	for i in frames:
		game._process(delta)
		game._view_controls.step(delta)
		game._roof_controls.step(delta)


func _wheel(direction: int, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN if direction > 0 else MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	root.push_input(event,true)


func _snapshot(name: String) -> void:
	if not capture:
		return
	game._toast_label.hide()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(20,150)
	motion.global_position = motion.position
	root.push_input(motion,true)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://captures/street_%s_%s.png"%[name,tag])
	_check(root.get_texture().get_image().save_png(path) == OK,"Failed to save street preview")


func _run() -> void:
	capture = "--capture-street" in OS.get_cmdline_user_args()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if capture:
		for control in game.find_children("*","Control",true,false):
			control.tooltip_text = ""
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._fit_stage()
	tag = "%dx%d"%[root.size.x,root.size.y]
	var controls: Node = game._view_controls
	var life: Node3D = game._street_life
	var street: Node3D = game._street
	_check(not street.facades.visible,"Interior started behind an opaque facade")
	_check(street.has_node("ShopEntranceMat"),"Missing shop mat")
	_check(street.get_node("BluestoneStreet").find_children("WornStoneBatch*","MultiMeshInstance3D",true,false).size() == 5,"Stone paving is not batched")
	_check(game._shop.ENTRY == street.INSIDE,"Customer entry is not the front door")
	_check(life.pedestrians.size() == 6,"Missing street pedestrians")
	_check(life.postman.rig.skeleton.get_bone_count() == 20,"Postal uniform is not skinned")
	for part in ["PeakedCapCrown","BroadVisor","PostalSatchel","PostalCoatSkirt"]:
		_check(not life.postman.find_children(part,"MeshInstance3D",true,false).is_empty(),"Missing postal clothing: "+part)
	_check_pedals(life.postman)
	var center := root.get_visible_rect().size*.5
	game._set_speed(0)
	var initial_size: float = game.camera.size
	var initial_position: Transform3D = game.camera.transform
	var initial_offset := Vector2(game.camera.h_offset,game.camera.v_offset)
	var pedestrian_start: Vector3 = life.pedestrians[0].position
	for i in 4:
		_wheel(1,center)
	_tick(45)
	_check(controls.zoom > .3 and controls.exterior,"Wheel did not reveal street")
	_check(street.facades.visible and street.exterior_amount > .99,"Street lacks complete facade")
	_check(game.camera.size > initial_size*1.25,"Zoom did not widen street view")
	_check(life.pedestrians[0].position == pedestrian_start,"Zoom unpaused simulation")
	_check(game._facility_near_screen(center,10000) == -1,"Street view can assign hidden facilities")
	_check(game._rooms.values().all(func(room: Node3D) -> bool: return room.visible),"Zoom hid adjacent rooms")
	var ui_point: Vector2 = game.get_node("GameInterface/FloatingHUD/ShopTools").get_global_rect().get_center()
	var previous_zoom: float = controls.target_zoom
	_wheel(-1,ui_point)
	_check(controls.target_zoom == previous_zoom,"HUD wheel changed world zoom")
	await _snapshot("exterior")
	for i in 4:
		_wheel(-1,center)
	_tick(45)
	_check(is_zero_approx(controls.zoom) and not street.facades.visible,"Zoom in did not restore cutaway")
	_check(game.camera.transform.is_equal_approx(initial_position) and is_equal_approx(game.camera.size,initial_size),"Zoom changed fixed room camera")
	_check(Vector2(game.camera.h_offset,game.camera.v_offset).is_equal_approx(initial_offset),"Zoom changed room framing")
	_check(controls.interior_interaction(),"Interior input remained disabled")
	for i in 4:
		_wheel(-1,center)
	_tick(45)
	_check(is_equal_approx(controls.depth,2.0),"Wheel did not advance into rear rooms")
	_check(not street.get_node("BluestoneStreet").visible,"Front street persists in rear-room view")
	for i in 4:
		_wheel(1,center)
	_tick(45)
	_check(controls.interior_interaction() and street.get_node("BluestoneStreet").visible,"Reverse scroll did not restore the live front rooms and street")
	# Pinch uses viewport-relative distances and must not also activate a roof.
	var span := root.get_visible_rect().size.y*.2
	_touch(0,center-Vector2(span,0),true)
	_touch(1,center+Vector2(span,0),true)
	_drag(0,center-Vector2(span*.2,0))
	_drag(1,center+Vector2(span*.2,0))
	_touch(0,center-Vector2(span*.2,0),false)
	_touch(1,center+Vector2(span*.2,0),false)
	_check(controls.target_zoom > .4,"Two-finger pinch did not zoom out")
	controls.target_zoom = 0
	_tick(45)
	game._set_speed(1)
	var states := {}
	var crossings := 0
	var seen := {}
	var recorded_post := false
	for frame in 4200:
		var postal_position: Vector3 = life.postman.position
		var postal_visible: bool = life.postman.visible
		var postal_before: String = life.postal_stage
		var bicycle_position: Vector3 = life.bicycle.position
		var previous := {}
		for customer in game.customers:
			previous[customer] = customer.position
		_tick(1)
		if postal_visible and life.postman.visible:
			_check(life.postman.position.distance_to(postal_position) < .16,"Postal rider teleports during mount/dismount")
		if postal_before in ["dismounting","mounting","delivering","to_door","to_bike"]:
			_check(life.bicycle.position.is_equal_approx(bicycle_position),"Parked bicycle moves before mounting ends")
		if life.postal_stage in ["to_door","delivering","to_bike"]:
			_check(life.bicycle.parking_amount > .99,"Parked bicycle has no support")
		states[life.postal_stage] = true
		for person in game.customers:
			if previous.has(person):
				_check(person.position.distance_to(previous[person]) < .09,"Customer teleported between street and shop")
				if (person.position.z-street.DOOR_Z)*(previous[person].z-street.DOOR_Z) < 0:
					_check(absf(person.position.x) < .1,"Customer crossed facade outside shop door")
					_check(street._door_open > .85,"Customer walked through closed door")
					crossings += 1
			if person.position.z <= 3.4:
				_check(person.position.x >= -7.2,"Customer entered through workshop")
		if capture and not recorded_post and life.postal_stage == "arriving" and life.bicycle.position.x > -3:
			controls.target_zoom = 1
			controls.step(1)
			await _snapshot("postman_arrives")
			await _postal_closeup()
			recorded_post = true
		if capture and life.postal_stage == "delivering" and not seen.has("delivery"):
			seen["delivery"] = true
			controls.target_zoom = 0
			controls.step(1)
			await _snapshot("interior_delivery")
		if frame%180 == 0:
			await process_frame
	for state in ["arriving","dismounting","to_door","delivering","to_bike","mounting","departing","waiting"]:
		_check(states.has(state),"Missing postal stage: "+state)
	_check(life.deliveries.size() == 1,"Daily delivery repeated or failed")
	_check(crossings >= 4 and game._sales_count >= 2,"Street customer round trip did not complete")
	_check(life._delivery_stack.visible,"Delivered papers did not appear")
	_check(life.pedestrians[0].position != pedestrian_start,"Pedestrians do not walk")
	life.subscribed_publications.clear()
	game._day_index = 2
	game._day_minutes = 9*60+15
	_tick(1)
	_check(life.postal_stage == "passing","Unsubscribed postman should only pass by")
	_tick(720)
	_check(life.deliveries.size() == 1 and life.postal_stage == "waiting","Unsubscribed postman delivered or failed to leave")
	game._day_index = 3
	game._day_minutes = 9*60+15
	life.subscribed_publications.append("服饰研究")
	_tick(1500)
	_check(life.deliveries.size() == 2,"Next day did not deliver again")
	_check(life.deliveries.back()["publications"] == ["服饰研究"],"Delivered the wrong subscription")
	game._set_speed(0)
	var bike_position: Vector3 = life.bicycle.position
	_tick(20)
	_check(life.bicycle.position == bike_position,"Postal bicycle ignores pause")
	if "--record-street" in OS.get_cmdline_user_args():
		await _record()
	print("STREET_POST_CHECK crossings=",crossings," sales=",game._sales_count," deliveries=",life.deliveries.size()," wheel_pinch=true failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func _postal_closeup() -> void:
	var camera: Camera3D = game.camera
	var saved := camera.transform
	var size := camera.size
	var offset := Vector2(camera.h_offset,camera.v_offset)
	game.get_node("GameInterface").hide()
	var visible_people: Array[Node3D] = []
	for person in game.staff+game.customers+game._street_life.pedestrians:
		if person.visible:
			visible_people.append(person)
			person.hide()
	var at: Vector3 = game._street_life.bicycle.position
	camera.position = at+Vector3(3,2.9,7)
	camera.look_at(at+Vector3(0,1.3,0))
	camera.size = 4.6
	camera.h_offset = 0
	camera.v_offset = 0
	await _snapshot("postman_close")
	var doll: Node3D = game._street_life.postman
	var bicycle: Node3D = game._street_life.bicycle
	var phase: float = doll.pedal_phase
	camera.position = at+Vector3(-4,2.9,6)
	camera.look_at(at+Vector3(0,1.3,0))
	await _snapshot("postman_rear")
	camera.position = at+Vector3(3,2.9,7)
	camera.look_at(at+Vector3(0,1.3,0))
	if "--record-street" in OS.get_cmdline_user_args():
		var directory := ProjectSettings.globalize_path("res://captures/postal_motion")
		DirAccess.make_dir_recursive_absolute(directory)
		for frame in 48:
			bicycle.crank.rotation.z = phase-TAU*frame/48.0
			bicycle.roll(0)
			doll.pedal_phase = bicycle.crank.rotation.z
			doll._update_puppet_motion(1.0/60.0)
			await process_frame
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(directory.path_join("frame_%03d.png"%frame)) == OK,"Postal close-up recording failed")
		bicycle.crank.rotation.z = phase
		bicycle.roll(0)
	var doll_position := doll.position
	doll.position.y = 0
	doll.riding = false
	doll.rig.animate(PI*.5,1.0,"idle",0)
	doll.body_rig.rotation.y = .15
	bicycle.hide()
	await _snapshot("postman_walk")
	bicycle.show()
	doll.position = doll_position
	doll.riding = true
	doll.pedal_phase = phase
	doll._update_puppet_motion(0)
	camera.transform = saved
	camera.size = size
	camera.h_offset = offset.x
	camera.v_offset = offset.y
	game.get_node("GameInterface").show()
	for person in visible_people:
		person.show()


func _touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	root.push_input(event,true)


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event,true)


func _record() -> void:
	var path := ProjectSettings.globalize_path("res://captures/street_motion")
	DirAccess.make_dir_recursive_absolute(path)
	game._day_index = 4
	game._day_minutes = 9*60+15
	game._set_speed(1)
	game._view_controls.target_zoom = 1
	game._view_controls.step(1)
	for frame in 132:
		if frame == 48:
			game._view_controls.target_zoom = 0
		if frame == 88:
			game._view_controls.target_zoom = 1
		_tick(9,1.0/30.0)
		game._toast_label.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(path.path_join("frame_%03d.png"%frame)) == OK,"Street frame export failed")


func _check_pedals(doll: PaperDoll) -> void:
	doll.riding = true
	for i in 32:
		doll.pedal_phase = TAU*i/32.0
		doll._update_puppet_motion(1.0/60.0)
		for side in [-1,1]:
			var suffix := "L" if side < 0 else "R"
			var foot: Transform3D = doll.rig.skeleton.get_bone_global_pose(doll.rig.bones["Foot"+suffix])
			var target := Vector3(side*.15,.51-side*.16*sin(doll.pedal_phase),.16-side*.16*cos(doll.pedal_phase))
			_check(foot.origin.distance_to(target) < .002,"Cycling ankle detached from pedal")
			_check(foot.basis.y.dot(Vector3.UP) > .999,"Cycling shoe is not flat on pedal")
	doll.riding = false
