extends SceneTree

## GPU capture of the supply catalog / order queue panel at 1280x720.
## Run without --headless:
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       --script tests/supply_catalog_capture.gd --log-file captures/supply_catalog_capture.log

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SUPPLY_CATALOG_CAPTURE skipped=headless")
		quit(0)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._speed = 0.0
	var catalog: Node = game._supply_catalog
	catalog.save_path = "user://supply_catalog_capture.json"
	catalog.entries.clear()
	catalog.queue.clear()
	var inventory: Node3D = game._inventory
	var ledger: RefCounted = inventory.materials
	while inventory.in_location("storage").size() >= inventory.STORAGE_LIMIT - 2:
		inventory.in_location("storage")[0].collect()
	if not game._production.order.is_empty():
		ledger.cancel(str(game._production.order.id))
		game._production.order = {}
		game._production.phase = "idle"

	var apron := _entry(catalog, ledger, "rose_check", "thread_rose", 1, {"auto_enabled": true, "target_stock": 2})
	var skirt := _entry(catalog, ledger, "sage_linen", "thread_sage", 12, {"skirt_length": .62})
	var dyed := _entry(catalog, ledger, "sage_linen", "thread_blue", 10, {"name": "鼠尾草定制染衬衫", "material": "cotton", "pattern_code": 0, "pigment": Color("8ba28a"), "width_m": 1.4, "allow_dye": true, "auto_enabled": true, "target_stock": 1})
	catalog.enqueue_manual(apron.id)
	catalog.enqueue_manual(skirt.id)
	catalog.tick(.5)
	game._switch_room("workshop", false)

	var panel: PanelContainer = game._order_queue_panel
	panel.show()
	panel.tabs.current_tab = 0
	panel.refresh()
	await _save("res://captures/supply_catalog_catalog.png")
	panel.tabs.current_tab = 1
	panel.refresh()
	await _save("res://captures/supply_catalog_queue.png")
	print("SUPPLY_CATALOG_CAPTURE entries=", catalog.entries.size(), " queue=", catalog.queue.size(), " failures=", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(catalog.save_path))
	game.free()
	quit(0 if failures == 0 else 1)


func _entry(catalog: Node, ledger: RefCounted, fabric_id: String, thread_id: String, style: int, extra: Dictionary) -> Dictionary:
	var fabric: Dictionary = ledger.fabric(fabric_id)
	var data := {
		"style": style,
		"fabric_id": fabric_id,
		"material": str(fabric.get("material", "cotton")),
		"pattern_code": int(fabric.get("pattern_code", 0)),
		"pigment": fabric.get("pigment", Color.WHITE),
		"width_m": float(fabric.get("width_m", 1.4)),
		"thickness_m": float(fabric.get("thickness_m", .001)),
		"thread_id": thread_id,
	}
	data.merge(extra, true)
	return catalog.add_entry(data)


func _save(output_path: String) -> void:
	for _frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		failures += 1
		push_error("Capture viewport returned no image.")
		return
	var save_error := image.save_png(output_path)
	if save_error != OK:
		failures += 1
		push_error("Could not save capture: " + error_string(save_error))
	else:
		print("SUPPLY_CATALOG_CAPTURE saved=", output_path, " ", image.get_width(), "x", image.get_height())
