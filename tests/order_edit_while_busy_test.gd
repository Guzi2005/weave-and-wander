extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var flow = game._production
	var catalog = game._supply_catalog
	catalog.entries.clear()
	catalog.queue.clear()
	# Opening inventory fills the stockroom; free one output slot for this test.
	var stored: Array = game._inventory.in_location("storage")
	if stored.size() >= game._inventory.STORAGE_LIMIT:
		var removed = stored[0]
		game._inventory.items.erase(removed)
		removed.free()
	for worker in game.staff:
		game._set_staff_idle(worker, 100000)
	if not flow.order.is_empty():
		flow.ledger.cancel(str(flow.order.id))
		flow.order = {}
	var original: Dictionary = flow.begin_order(flow.selected_fabric, flow.selected_thread, flow.size_factor, 1, .7, .8)
	assert(not original.is_empty())
	var frozen := original.duplicate(true)
	var panel = game._production_panel
	flow.selected_style = 10
	flow.selected_garment_length = .65
	panel.refresh()
	assert(not panel.style_choice.disabled and not panel.fabric_choice.disabled and not panel.thread_choice.disabled)
	assert(panel.top_length.editable and not panel.make_button.disabled)
	panel._start()
	assert(catalog.queue.size() == 1)
	assert(catalog.queue[0].snapshot.style == 10)
	assert(is_equal_approx(catalog.queue[0].snapshot.garment_length, .65))
	assert(original == frozen)
	flow.selected_style = 13
	assert(catalog.queue[0].snapshot.style == 10)
	assert(catalog.cancel_job(catalog.queue[0].id))
	flow.ledger.cancel(str(original.id))
	flow.order = {}
	var dispatched: Dictionary = flow.begin_order(flow.selected_fabric, flow.selected_thread, flow.size_factor, 10, .7, .65)
	assert(not dispatched.is_empty())
	assert(flow.selected_style == 13)
	print("ORDER_EDIT_WHILE_BUSY_TEST passed")
	game.free()
	quit()
