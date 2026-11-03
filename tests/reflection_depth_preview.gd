extends SceneTree

var game: Node
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/%s_%dx%d.png" % [label, root.size.x, root.size.y]))

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	game._toast_label.hide()
	var book: Node = game._pop_up
	var view: Node = game._view_controls
	var mirror: Node3D = get_nodes_in_group("shop_mirrors")[0]
	check(book.rear_rooms.position.z == -6.5, "Rear rooms must physically adjoin front rooms")
	check(book.back_street.position.z < book.rear_rooms.position.z - 6, "Back street must lie beyond rear rooms")
	view.zoom = .1
	for depth in [0.0, 1.0, 1.5, 2.0, 2.5, 3.0]:
		view.depth = depth
		view.target_depth = depth
		view.apply_view()
		game._update_ui()
		if depth == 2:
			check(not game._street.get_node("BluestoneStreet").visible, "Front street must not persist at the rear rooms")
			check(game._rooms.shop.visible and book.front_room_amount() > 0, "Front rooms must remain as the rear view foreground")
			check(mirror.reflection_enabled, "Standing foreground mirror must retain a live reflection")
		await capture("depth_connected_%02d" % roundi(depth * 10))
	view.depth = 1
	view.target_depth = 1
	view.apply_view()
	game.get_node("GameInterface").hide()
	game.camera.position = Vector3(-1.3, 3.8, 5.5)
	game.camera.look_at(Vector3(-1.3, 2.85, -3.3))
	game.camera.fov = 35
	book.rear_rooms.animate_samples(0)
	await capture("window_rear_live_a")
	var cloth: Node3D = book.rear_rooms._hanging_samples[1]
	var old_pose: Transform3D = cloth.global_transform
	book.rear_rooms.animate_samples(1.8)
	check(not cloth.global_transform.is_equal_approx(old_pose), "The window must reveal actual animated rear-room geometry")
	await capture("window_rear_live_b")
	# Exercise the real browse -> carry -> booth -> wear -> mirror behavior tree.
	var behavior: RefCounted
	game._set_speed(1)
	for tick in 5400:
		game._process(1.0 / 30.0)
		for candidate in game._customer_behaviors.values():
			if candidate.stage == "mirror_wait":
				behavior = candidate
				break
		if behavior != null:
			break
		if tick % 300 == 0:
			await process_frame
	# The actor eases from walking direction to the mirror-facing anchor.
	for i in 24:
		game._process(1.0 / 30.0)
	game._set_speed(0)
	check(behavior != null, "Customer must autonomously reach the mirror with a real garment")
	if behavior == null:
		game.free()
		quit(1)
		return
	check(behavior.item.location == "worn", "Mirror customer must be wearing the same inventory item")
	game.get_node("GameInterface").hide()
	game.camera.position = Vector3(1.6, 3.0, 8.5)
	game.camera.look_at(Vector3(3.7, 1.5, -.5))
	game.camera.fov = 32
	var customer: Node3D = behavior.actor
	book.apply_depth(1)
	mirror.update_reflection()
	for corner in [Vector3(-.4, -1.25, 0), Vector3(.4, 1.25, 0)]:
		var projected: Vector2 = mirror._camera.unproject_position(mirror.to_global(corner)) / Vector2(mirror._viewport.size)
		var expected := Vector2(1, 1) if corner.x < 0 else Vector2.ZERO
		check(projected.distance_to(expected) < .01, "Mirror frustum must align with physical aperture: " + str(projected))
	await capture("mirror_customer")
	var before: Image
	if DisplayServer.get_name() != "headless":
		before = mirror._viewport.get_texture().get_image()
	customer.position.x += .65
	customer.rotation.y -= .7
	book.apply_depth(1)
	await capture("mirror_customer_moved")
	check(behavior.item.global_transform.is_equal_approx(customer.body_rig.global_transform), "Paused runtime must keep the reflected garment on its customer without a test-only sync")
	if before != null:
		var after: Image = mirror._viewport.get_texture().get_image()
		check(before.get_data() != after.get_data(), "Moving a real customer must change their reflection")
		before.save_png(ProjectSettings.globalize_path("res://captures/mirror_reflection_buffer.png"))
	print("REFLECTION_DEPTH_TEST failures=", failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
