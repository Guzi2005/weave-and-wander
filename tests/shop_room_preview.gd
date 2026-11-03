extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._toast_label.hide()
	game._set_speed(1.0)
	for step in 900:
		game._process(1.0/30.0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--room-id="):
			game._switch_room(argument.get_slice("=",1),false)
	await process_frame
	game._fit_stage()
	_verify_frame(game)
	var record := "--record-room" in OS.get_cmdline_user_args()
	var folder := "res://captures/room_motion"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var capture_name := "single_room"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--room-name="):
			capture_name = argument.get_slice("=",1).validate_filename()
	for index in (90 if record else 1):
		for step in 10:
			game._process(1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/frame_%03d.png" % [folder,index] if record else "res://captures/%s.png" % capture_name
		var error := image.save_png(ProjectSettings.globalize_path(path))
		assert(error == OK)
	print("ROOM_PREVIEW frames=",90 if record else 1," viewport=",root.size)
	game.queue_free()
	await process_frame
	quit()


func _verify_frame(game: Node) -> void:
	assert(game._room.has_node("HingedRoof/LeftSlope/RoofBoard"),"Roof failed to build")
	assert(game._room.has_node("RoomShell"),"Room failed to build")
	var visible := root.get_visible_rect()
	var usable := visible.grow(-18)
	for instance in game._room.find_children("*","MeshInstance3D",true,false):
		for corner in 8:
			var point: Vector3 = instance.global_transform * instance.mesh.get_aabb().get_endpoint(corner)
			assert(usable.has_point(game.camera.unproject_position(point)), "Architecture clipped: " + str(instance.name))
	for facility in game.facilities:
		if facility["room"] != game._active_room:
			continue
		var screen: Vector2 = game.camera.unproject_position(facility["label_position"])
		assert(usable.has_point(screen), "Facility drop target outside room viewport")
		for group in ["ShopTools","TimeControls","StaffCards","RoomNavigation"]:
			var control: Control = game.get_node("GameInterface/FloatingHUD/"+group)
			assert(not control.get_global_rect().grow(8).has_point(screen),"Facility target covered by "+group)
	for id in game.ROOM_ORDER:
		var room: Node3D = game._rooms[id]
		assert(room.visible,"Connected neighbor was hidden")
		assert(room.find_children("*","Label3D",true,false).is_empty(),"Scene text remains")
		if abs(game.ROOM_ORDER.find(id)-game.ROOM_ORDER.find(game._active_room)) != 1:
			continue
		var side := -1 if room.position.x > game._room.position.x else 1
		for point in [Vector3(side*5.3,1.2,0),Vector3(side*5.3,5.3,0)]:
			assert(visible.has_point(game.camera.unproject_position(room.to_global(point))),"Neighbor interior or roof isn't visible")
	print("ROOM_FRAMING viewport=",visible.size," roof_and_room_visible=true targets_clear=true")
