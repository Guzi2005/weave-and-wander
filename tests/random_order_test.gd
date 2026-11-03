extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var catalog = game._supply_catalog
	catalog.save_path = "user://random_order_test.json"
	catalog.entries.clear()
	catalog.queue.clear()
	catalog.random_auto_enabled = false
	for person in game.staff:
		game._set_staff_idle(person, 100000)
	while game._inventory.in_location("storage").size() >= game._inventory.STORAGE_LIMIT:
		game._inventory.in_location("storage")[0].collect()
	catalog._auto_random_order()
	assert(catalog.queue.is_empty())
	catalog.set_random_auto_enabled(true)
	catalog.load_catalog()
	assert(catalog.random_auto_enabled)
	var styles := {}
	var fabrics := {}
	for iteration in 24:
		catalog.queue.clear()
		catalog._auto_random_order()
		assert(catalog.queue.size() == 1)
		var job: Dictionary = catalog.queue[0]
		assert(job.random_auto and job.entry_id == "random_combination")
		assert(catalog.feasibility(job.snapshot).is_empty())
		styles[job.snapshot.style] = true
		fabrics[job.snapshot.fabric_id] = true
		catalog._auto_random_order()
		assert(catalog.queue.size() == 1)
	assert(styles.size() > 1 and fabrics.size() > 1)
	if DisplayServer.get_name() != "headless":
		game._order_queue_panel.show()
		game._order_queue_panel.tabs.current_tab = 1
		game._order_queue_panel.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/random_order_panel.png")
	catalog.queue[0].state = "producing"
	catalog._auto_random_order()
	assert(catalog.queue.size() == 2)
	catalog._auto_random_order()
	assert(catalog.queue.size() == 2)
	catalog.queue.clear()
	for spool in catalog.ledger.thread_batches:
		spool.meters = 0.0
	catalog._auto_random_order()
	assert(catalog.queue.is_empty())
	print("RANDOM_ORDER_TEST passed: empty catalog, diverse combinations, one waiting order, material shortages, saved switch")
	game.free()
	quit()
