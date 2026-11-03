extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	game._toast_label.hide()
	var view: Node = game._view_controls
	for sample in [0.0, .18, .32, .48, .66, 1.0]:
		view.depth = sample
		view.target_depth = sample
		view.zoom = .35
		view.apply_view()
		game._update_ui()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/popup_wall_%02d_%dx%d.png" % [roundi(sample * 100.0), root.size.x, root.size.y]))
	for page in [0.0, .3, .5, .7, 1.0, 1.3, 1.5, 1.7, 2.0, 2.3, 2.5, 2.7, 3.0]:
		view.depth = page
		view.target_depth = page
		view.zoom = .35
		view.apply_view()
		game._update_ui()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.save_png(ProjectSettings.globalize_path("res://captures/popup_%02d_%dx%d.png" % [roundi(page * 10), root.size.x, root.size.y]))
	game._day_minutes = 22 * 60
	view.depth = 1
	view.apply_view()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/popup_night_%dx%d.png" % [root.size.x, root.size.y]))
	print("POPUP_PREVIEW complete")
	game.free()
	quit()
