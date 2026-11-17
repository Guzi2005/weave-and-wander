extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._speed = 0.0
	var view: Node = game._view_controls
	view.set_page(3)
	check(view.page_index() == 3,"Arrow selects rear street")
	view.step_page(1)
	check(view.page_index() == 3,"Page clamps at final scene")
	view.step_page(-1)
	check(view.page_index() == 2,"Previous arrow selects previous scene")
	view.set_page(1)
	view.depth = 1.0
	view.apply_view()
	var camera_x: float = game.camera.position.x
	var camera_z: float = game.camera.position.z
	var actor_position: Vector3 = game.staff[0].global_position
	view.set_page(3)
	view.depth = 3.0
	view.apply_view()
	check(game.staff[0].global_position.is_equal_approx(actor_position),"Page turn must not relocate actor")
	check(is_equal_approx(game.camera.position.x,camera_x),"Page turn camera X fixed")
	check(is_equal_approx(game.camera.position.z,camera_z),"Page turn camera Z fixed")
	check(game._pop_up.page_offset(3) == Vector3(0,0,16),"Backstreet presentation offset")
	var e := InputEventMouseButton.new()
	e.pressed = true
	e.button_index = MOUSE_BUTTON_WHEEL_UP
	e.position = Vector2(600,350)
	view._scroll_input(e)
	check(view.page_index() == 3,"Wheel must not change page")
	view.set_page(1)
	view.depth = 1.0
	var editor = game.get("_furnishings")
	if editor == null:
		editor = load("res://scripts/furnishing_mode.gd").new()
		game.add_child(editor)
		editor.setup(game)
	game._speed = 2.0
	editor.open()
	check(game._speed == 0.0 and editor.active,"Furnishing pauses")
	check(game._shop.get_node("HingedRoof").open_amount(-1) > .99,"Furnishing opens roofs for direct picking")
	var hit_found := false
	for part in editor.fixture.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var point: Vector3 = part.global_transform * part.get_aabb().get_center()
		if editor.pick_fixture(game.camera.unproject_position(point)) >= 0: hit_found = true; break
	check(hit_found,"Furniture can be selected directly on scene")
	# A direct drag must keep the camera and actual furniture still until commit.
	view.focus_x += .75
	view.apply_view()
	var pick_point := Vector2.ZERO
	var can_drag := false
	for part in editor.fixture.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var screen: Vector2 = game.camera.unproject_position(part.global_transform * part.get_aabb().get_center())
		if not editor._panel.get_global_rect().has_point(screen) and editor.pick_fixture(screen) == 0:
			pick_point = screen
			can_drag = true
			break
	check(can_drag,"Direct drag has an unobstructed pick point")
	if can_drag:
		var camera_before: Transform3D = game.camera.global_transform
		var furniture_before: Transform3D = editor.fixture.transform
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = pick_point
		editor._input(press)
		check(editor._dragging,"Pressing a visible fixture starts a drag")
		check(game.camera.global_transform.is_equal_approx(camera_before),"Direct selection cannot jump the camera")
		var motion := InputEventMouseMotion.new()
		motion.position = pick_point + Vector2(40,0)
		editor._input(motion)
		check(editor.fixture.transform.is_equal_approx(furniture_before),"Dragging leaves live furniture untouched")
		check(not editor.proposed.is_equal_approx(furniture_before),"Dragging moves the preview")
		var cancel := InputEventMouseButton.new()
		cancel.button_index = MOUSE_BUTTON_RIGHT
		cancel.pressed = true
		cancel.position = motion.position
		editor._input(cancel)
		check(not editor._dragging and editor.proposed.is_equal_approx(furniture_before),"Right click cancels the drag")
	var fixture: Node3D = editor.fixture
	var before := fixture.transform
	editor.move_preview(Vector2(30,0))
	check(fixture.transform.is_equal_approx(before),"Preview cannot move live fixture")
	var result: Dictionary = editor.commit()
	check(not result.ok,"Out-of-room placement rejected")
	check(fixture.transform.is_equal_approx(before),"Rejected commit preserves fixture")
	editor.close()
	check(game._speed == 2.0 and not view.interaction_locked,"Close restores speed and input")
	var desk = game.get("_desktop")
	if desk == null:
		desk = load("res://scripts/desktop_interaction.gd").new()
		game.add_child(desk)
		desk.setup(game)
	desk.enter_desktop()
	check(desk.active and game._speed == 0.0 and view.desktop_mode,"Desktop enters paused")
	view.step(1.0)
	check(desk.objects.size() == 6,"Six real desktop menu objects")
	for entry in desk.objects:
		var pos: Vector3 = entry.node.to_global(Vector3(0,entry.height,0))
		var screen: Vector2 = game.camera.unproject_position(pos)
		check(desk.pick(screen).get("key","") == entry.key,"3D book hit test: " + entry.key)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/desktop_navigation_20261111.png")
	desk.leave_desktop()
	check(not desk.active and game._speed == 2.0,"Desktop returns to prior speed")
	print("CHAPTER_NAVIGATION failures=",failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
