extends SceneTree
## Visual check for the lossless workbench reduction (schemes A/B/C):
## procedural cutting-mat ruling, steel-ruler ticks and 2-triangle garden leaves.
func _initialize() -> void:
	_run.call_deferred()

func _shot(game: Node, desk: Node3D, from: Vector3, to: Vector3, fov: float, file: String) -> void:
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.camera.fov = fov
	game.camera.global_position = desk.to_global(from)
	game.camera.look_at(desk.to_global(to))
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/" + file))

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	root.size = Vector2i(1600, 1000)
	for frame in 8: await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	var desk: Node3D = game._pop_up.desk
	desk.set_time(10 * 60, game)
	game._pop_up.apply_depth(3.0)
	game.get_node("GameInterface").hide()
	# Desk-local coordinates: the GLB sits at z = -STUDIO_SETBACK inside the desk node.
	await _shot(game, desk, Vector3(14, 9, 14), Vector3(10, -1.1, 6), 40, "workbench_abc_ruler_mat.png")
	await _shot(game, desk, Vector3(0, 20, 42), Vector3(0, 8, -40), 55, "workbench_abc_overview.png")
	await _shot(game, desk, Vector3(-14, 2, -6), Vector3(-18, 2, -16), 45, "workbench_abc_mat_corner.png")
	print("WORKBENCH_ABC_CAPTURE saved")
	game.free()
	quit()
