extends SceneTree

class PaperPreviewHost extends Node:
	var _speed := 0.0

func _initialize() -> void: run.call_deferred()

func capture(label: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/mechanics_" + label + ".png")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600,1000)
	# Fast art review of the real book UI, without rebuilding the 3D town.
	if "--paper-only" in OS.get_cmdline_user_args():
		var host := PaperPreviewHost.new()
		root.add_child(host)
		var state = load("res://scripts/progression_state.gd").new()
		host.add_child(state)
		var panel = load("res://scripts/progression_panel.gd").new()
		host.add_child(panel)
		panel.setup(host,state)
		panel.open_page("magazine")
		await capture("magazine")
		print("MANUSCRIPT CAPTURE complete")
		quit()
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._speed = 0.0
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._vendor.tick(20,1,600)
	game._view_controls.set_page(3)
	game._view_controls.depth = 3.0
	game._view_controls.apply_view()
	game._update_ui()
	await capture("backstreet")
	game._vendor.open_shop()
	await capture("vendor_shop")
	game._vendor._panel.close_panel()
	game._desktop.enter_desktop()
	game._view_controls.step(2.0)
	await capture("desktop")
	for page in ["magazine","skills","strategy","ledger","save"]:
		game._progression_panel.open_page(page)
		await capture(page)
	game._progression_panel.close_page()
	game._desktop.leave_desktop()
	game._furnishings.open()
	game._view_controls.step(2.0)
	await capture("furnishing")
	game._furnishings.close()
	print("MECHANICS CAPTURE complete")
	quit()
