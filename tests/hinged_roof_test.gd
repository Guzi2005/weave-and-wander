extends SceneTree

var failures: Array[String] = []
var game: Node
var controls: Node
var capture := false
var tag := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)


func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event,true)


func _step(frames: int) -> void:
	for i in frames:
		controls.step(1.0/60.0)


func _roof_point(roof: Node3D, side: int) -> Vector2:
	var center := Vector3.ZERO
	for point in roof.corners(side):
		center += point
	return game.camera.unproject_position(center*.25)


func _snapshot(state: String) -> void:
	if not capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://captures/hinged_roof_%s_%s.png" % [state,tag])
	_check(root.get_texture().get_image().save_png(output) == OK,"Could not save roof preview")


func _run() -> void:
	capture = "--capture-roof" in OS.get_cmdline_user_args()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	controls = game._roof_controls
	controls.set_process(false)
	game._toast_label.hide()
	game._fit_stage()
	tag = "%dx%d" % [root.size.x,root.size.y]
	for frame in 900:
		game._process(1.0/30.0)
	game._set_speed(0)
	game._update_ui()
	var camera_start: Transform3D = game.camera.transform
	var camera_size: float = game.camera.size
	var offset := Vector2(game.camera.h_offset,game.camera.v_offset)
	var lamps := {}
	for room in game._rooms.values():
		_check(room.find_children("*","Label3D",true,false).is_empty(),"Scene lettering returned")
		var roof: Node3D = room.get_node("HingedRoof")
		_check(roof.find_children("SlateTiles*","MeshInstance3D",true,false).size() == 8,"Roof tile batching regressed")
		_check(roof.has_node("RightSlope/Chimney"),"Chimney must move with its roof leaf")
		for lamp in room.get_children():
			if lamp.has_meta("roof_anchor_height"):
				lamps[lamp] = lamp.global_transform
		for side in [-1,1]:
			var board: MeshInstance3D = roof.get_node(("LeftSlope" if side < 0 else "RightSlope")+"/RoofBoard")
			var arrays := board.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var area := 0.0
			for i in range(0,vertices.size(),3):
				if normals[i].y > .99:
					area += (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length()*.5
			var expected: float = Vector2(roof.HALF_WIDTH,roof.RIDGE-roof.EAVE).length()*(roof.FRONT-roof.BACK)
			_check(absf(area-expected) < .002,"Roof panel has a hole or missing front portion")
			_check(is_zero_approx(roof.open_amount(side)),"Roof should start closed")
	var roof: Node3D = game._room.get_node("HingedRoof")
	var hinges := [roof.corners(-1)[0],roof.corners(-1)[3],roof.corners(1)[0],roof.corners(1)[3]]
	await _snapshot("closed")
	game._world_press_position = Vector2(-1,-1)
	_click(_roof_point(roof,-1))
	_check(game._world_press_position == Vector2(-1,-1),"Opaque roof click reached the room")
	_move(_roof_point(roof,-1))
	_step(240)
	_check(roof.open_amount(-1) > .99 and roof.open_amount(1) < .01,"Left hover did not open just the left half")
	_check(controls.hovered_roof == roof,"Stationary hover lost its moving roof")
	_check(roof.corners(-1)[0].distance_to(hinges[0]) < .0001 and roof.corners(-1)[3].distance_to(hinges[1]) < .0001,"Left ridge hinge drifted")
	_verify_open_frame(roof)
	await _snapshot("left_open")
	# Rendering can deliver OS focus/exit events; restore synthetic hover before the next input sequence.
	_move(_roof_point(roof,-1))
	_step(1)
	_move(game.camera.unproject_position(Vector3(-3.7,1.0,1.2)))
	_step(90)
	_check(roof.open_amount(-1) > .99,"Entering the room made its roof shut")
	var interior: Vector2 = game.camera.unproject_position(Vector3(-3.7,1.0,1.2))
	_click(interior)
	_check(game._world_press_position.is_equal_approx(interior),"Open roof blocked an interior click")
	_move(_roof_point(roof,1))
	_step(180)
	_check(roof.open_amount(1) > .99 and roof.open_amount(-1) < .01,"Right hover did not swap open half")
	_check(roof.corners(1)[0].distance_to(hinges[2]) < .0001 and roof.corners(1)[3].distance_to(hinges[3]) < .0001,"Right ridge hinge drifted")
	_verify_open_frame(roof)
	await _snapshot("right_open")
	for lamp in lamps:
		_check(lamp.global_transform.is_equal_approx(lamps[lamp]),"Lamp moved with the roof")
	game._fit_stage()
	_check(game.camera.transform.is_equal_approx(camera_start) and is_equal_approx(game.camera.size,camera_size),"Hover changed camera zoom or position")
	_check(Vector2(game.camera.h_offset,game.camera.v_offset).is_equal_approx(offset),"Hover changed camera framing")
	_move(Vector2(30,30))
	_step(8)
	_check(roof.open_amount(1) > .99,"Lid closed before its grace period")
	_step(90)
	_check(roof.open_amount(1) < .01,"Roof did not close after pointer exit")
	# Tap opens a leaf, releases keep it open, and another tap on the raised leaf closes it.
	for side in [-1,1]:
		_touch(_roof_point(roof,side),true)
		game._world_press_position = Vector2(-1,-1)
		_click(_roof_point(roof,side),-1)
		_check(game._world_press_position == Vector2(-1,-1),"Touch roof tap leaked an emulated mouse click")
		_touch(_roof_point(roof,side),false)
		_step(90)
		_check(roof.open_amount(side) > .99,"Touch did not keep the lid open")
		_touch(_roof_point(roof,side),true)
		_step(90)
		_check(roof.open_amount(side) < .01,"Touch could not close raised lid")
	_move(Vector2(30,30))
	_step(90)
	_move(_roof_point(roof,-1))
	_step(90)
	controls._leave_window()
	_step(90)
	_check(roof.open_amount(-1) < .01,"Window exit left a hovered roof open")
	_move(_roof_point(roof,-1))
	_step(90)
	var ui: Control = game.get_node("GameInterface/FloatingHUD/TimeControls")
	_move(ui.get_global_rect().get_center())
	_step(90)
	_check(roof.open_amount(-1) < .01,"HUD hover kept a roof open")
	# Verify adjacent roofs use the same pointer picking after a camera switch.
	for room_id in ["workshop","archive"]:
		game._switch_room(room_id,false)
		var neighbor: Node3D = game._room.get_node("HingedRoof")
		_move(_roof_point(neighbor,-1))
		_step(90)
		_check(neighbor.open_amount(-1) > .99,"Neighbor roof is not interactive")
		_move(Vector2(30,30))
		_step(90)
	game._switch_room("shop",false)
	if "--record-roof" in OS.get_cmdline_user_args():
		await _record(roof)
	print("HINGED_ROOF_CHECK full_panels=6 mouse_touch=true paused_hover=true fixed_hinges=true failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func _verify_open_frame(roof: Node3D) -> void:
	for point in roof.framing_points():
		_check(root.get_visible_rect().grow(-12).has_point(game.camera.unproject_position(point)),"Raised roof clips viewport")


func _touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = 0
	event.pressed = pressed
	root.push_input(event,true)


func _click(point: Vector2, device: int = 0) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.device = device
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)


func _record(roof: Node3D) -> void:
	var folder := ProjectSettings.globalize_path("res://captures/roof_motion")
	DirAccess.make_dir_recursive_absolute(folder)
	_move(Vector2(30,30))
	_step(90)
	var pointer := Vector2(30,30)
	for frame in 84:
		if frame == 7:
			pointer = _roof_point(roof,-1)
		elif frame == 32:
			pointer = _roof_point(roof,1)
		elif frame == 62:
			pointer = Vector2(30,30)
		_move(pointer)
		_step(4)
		await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png"%frame))
		_check(result == OK,"Roof animation frame export failed")
