extends SceneTree

# GPU captures of the real-stock rack, an emptied slot with a filled basket, and customer thoughts.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._toast_label.hide()
	game._set_speed(1.0)
	await _save(game, "inventory_opening")
	var wanted := {"inventory_mirror": false, "inventory_basket": false, "inventory_wish": false}
	for tick in 27000:
		game._process(1.0 / 30.0)
		var inventory: Node3D = game._inventory
		var stages: Array = game._customer_behaviors.values().map(func(behavior: RefCounted) -> String: return behavior.stage)
		var thinking: bool = game.customers.any(func(doll: Node3D) -> bool: return doll.thought_time > 1.5 and doll.get_meta("room", "") == "shop")
		if not wanted["inventory_wish"] and "browse_wait" in stages and thinking:
			wanted["inventory_wish"] = true
			await _save(game, "inventory_wish")
		elif not wanted["inventory_mirror"] and "mirror_wait" in stages and thinking:
			wanted["inventory_mirror"] = true
			await _save(game, "inventory_mirror")
		elif not wanted["inventory_basket"] and inventory.in_location("basket").size() >= 1 and inventory.free_slot() >= 0:
			wanted["inventory_basket"] = true
			await _save(game, "inventory_basket")
		if not wanted.values().has(false):
			break
		if tick % 300 == 0:
			await process_frame
	print("INVENTORY_PREVIEW captured=", wanted)
	game.queue_free()
	await process_frame
	quit()


func _save(game: Node, title: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://captures/%s_%dx%d.png" % [title, image.get_width(), image.get_height()]))
