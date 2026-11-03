extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var dev = game.get_node("DeveloperPanel")
	dev._toggle()
	assert(dev.panel.visible)
	dev.speed_buttons[4].pressed.emit()
	assert(game._speed == 4.0)
	dev.speed_buttons[8].pressed.emit()
	assert(game._speed == 8.0)
	var before: int = game._money
	dev.money_button.pressed.emit()
	assert(game._money == before + 1000)
	dev.speed_buttons[1].pressed.emit()
	assert(game._speed == 1.0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/developer_panel.png")
	print("DEVELOPER_PANEL_CHECK passed")
	game.free()
	quit()
