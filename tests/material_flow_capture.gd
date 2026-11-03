extends SceneTree

var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Material screenshot requires a rendering display")
		quit(1)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._pop_up.desk.set_time(9.0*60.0,game)
	game.get_node("GameInterface").hide()
	for person in game.staff:
		game._set_staff_idle(person,100000)
		person.hide()
	for person in game.customers: person.hide()
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.camera.h_offset = 0
	game.camera.v_offset = 0
	game.camera.fov = 40
	var cabinet: Node3D = game._production.cabinet
	game.camera.global_position = cabinet.to_global(Vector3(1.4,2.4,6.8))
	game.camera.look_at(cabinet.to_global(Vector3(.3,1.25,0)))
	for tick in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/material_cabinet_dense.png"))
	game.get_node("GameInterface").show()
	game._production_panel.show()
	if "--garment-selection" in OS.get_cmdline_user_args():
		var flow: Node3D = game._production
		if is_instance_valid(flow.actor): flow.suspend(flow.actor)
		if not flow.order.is_empty(): flow.ledger.cancel(flow.order.id)
		flow.order = {}
		flow.selected_style = 0
		flow.selected_fabric = "rose_check"
		flow.selected_thread = "thread_rose"
	if "--flower-selection" in OS.get_cmdline_user_args():
		var flow: Node3D = game._production
		if is_instance_valid(flow.actor): flow.suspend(flow.actor)
		if not flow.order.is_empty(): flow.ledger.cancel(flow.order.id)
		flow.order = {}
		flow.selected_style = 9
		flow.selected_fabric = "cream_roll"
		flow.selected_thread = "thread_cream"
	game._production_panel.refresh()
	for tick in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/material_panel.png"))
	if "--garment-selection" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/garment_production_panel.png"))
	if "--flower-selection" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/flower_production_panel.png"))
	print("MATERIAL_CABINET_CAPTURE saved")
	game.free()
	quit()
