extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for person in game.staff:
		game._set_staff_idle(person, 100000)
	if game._inventory.in_location("storage").size() >= game._inventory.STORAGE_LIMIT:
		game._inventory.in_location("storage")[0].collect()
	var worker = game.staff[2]
	game._set_staff_idle(worker, 100000)
	worker.energy = 1.0
	game._assign_staff(worker, game._facility_index("sewing"), true)
	assert(game._production.actor == worker)
	var count: int = game._production.finished_count
	game._day_minutes = game.CLOSING_MINUTE
	game._process(.01)
	worker.energy = .24
	for step in 16000:
		game._process(.05)
		if game._production.finished_count == count:
			assert(worker.visible)
			assert(not worker.get_meta("shift_departing", false))
		if not worker.visible:
			break
	assert(game._production.finished_count > count)
	assert(not worker.visible)
	print("CLOSING_PRODUCTION_TEST passed: tired worker finished the accepted order before leaving")
	game.free()
	quit()
