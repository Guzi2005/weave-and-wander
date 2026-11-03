extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	_check(not game.has_node("GameInterface/TopBar"),"Framed top bar still exists")
	var hud: Control = game.get_node("GameInterface/FloatingHUD")
	_check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE,"HUD swallows scene input")
	var clock_row: Control = hud.get_node("TimeControls")
	for pair in [["pause",0.0],["play",1.0],["fast_forward",2.0],["skip_forward",4.0]]:
		var button: Button = clock_row.get_node(pair[0])
		_check(button.size.x >= 44 and button.size.y >= 44,"Small touch target")
		_check(button.icon != null and not button.tooltip_text.is_empty(),"Missing icon or tooltip")
		_click(button.get_global_rect().get_center())
		await process_frame
		game._update_ui()
		_check(is_equal_approx(game._speed,pair[1]),"Time button did not change speed")
		_check(button.button_pressed,"Active speed not highlighted")
	_click(hud.get_node("ShopTools/Wardrobe").get_global_rect().get_center())
	await process_frame
	game._update_ui()
	_check(game._wardrobe.visible and game._speed == 0,"Wardrobe button failed to open and pause")
	_click(hud.get_node("ShopTools/Wardrobe").get_global_rect().get_center())
	await process_frame
	_check(not game._wardrobe.visible and game._speed == 4,"Wardrobe did not restore speed")
	var card: Control = game._cards[game.staff[0].get_instance_id()]
	_click(card.get_global_rect().position+Vector2(41,36))
	await process_frame
	_check(game._selected_doll == game.staff[0],"Floating portrait click did not locate character")
	_click(card.get_global_rect().position+Vector2(41,98))
	await process_frame
	_check(game._wardrobe.visible,"Energy strip did not open character details")
	game._close_wardrobe()
	var facility_point: Vector2 = game.camera.unproject_position(game.facilities[1]["label_position"])
	_click(facility_point)
	await process_frame
	_check(game._staff_jobs[game.staff[0].get_instance_id()]["facility"] == 1,"Empty HUD area blocks scene facility selection")
	var roof: Node3D = game._room.get_node("HingedRoof")
	_check(roof.has_node("LeftSlope") and roof.has_node("RightSlope/Chimney"),"Roof structure missing")
	_check(roof.find_children("SlateTiles*","MeshInstance3D",true,false).size() == 8,"Roof tiles not batched into eight meshes")
	var roof_min := INF
	var roof_max := -INF
	for name in ["LeftSlope/RoofBoard","RightSlope/RoofBoard"]:
		var board: MeshInstance3D = roof.get_node(name)
		var vertices: PackedVector3Array = board.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := board.global_transform*vertex
			roof_min = minf(roof_min,point.z)
			roof_max = maxf(roof_max,point.z)
		_check(is_equal_approx(board.mesh.get_aabb().size.z,roof.FRONT-roof.BACK),"Roof panel must have full depth")
	var floor: MeshInstance3D = game._room.get_node("RoomShell/CardboardFoundation")
	var floor_bounds := floor.mesh.get_aabb()
	var floor_min: float = floor.position.z + floor_bounds.position.z
	var floor_max: float = floor.position.z + floor_bounds.end.z
	_check(absf(roof_min-floor_min) < .25 and absf(roof_max-floor_max) < .25,"Roof depth does not match the floor footprint")
	var normal_style: StyleBoxFlat = hud.get_node("ShopTools/Wardrobe").get_theme_stylebox("normal")
	_check(normal_style.border_width_left == 0,"Floating buttons regained decorative outlines")
	print("FLOATING_HUD_CHECK pointer_clicks=9 roof_batches=8 failures=",failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event,true)
