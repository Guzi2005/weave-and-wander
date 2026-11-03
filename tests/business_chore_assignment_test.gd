extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var chore = game._business_chore
	assert(not game._navigation.route(game.staff[1].global_position,game._rooms.archive.to_global(Vector3(-6.3,0,2.7))).is_empty())
	chore.destination = Vector3(0,0,2.9)
	for worker in game.staff:
		game._set_staff_idle(worker, 10000)
		worker.energy = 1.0
	# Each staff member, including the hired clerk, can be selected.
	for candidate in game.staff:
		for worker in game.staff:
			worker.visible = worker == candidate
		assert(chore.choose_worker() == candidate)
		candidate.set_meta("shift_departing", true)
		assert(chore.choose_worker() == null)
		candidate.set_meta("shift_departing", false)
	print("BUSINESS_CHORE_ASSIGNMENT_TEST passed: all three staff eligible")
	game.free()
	quit()
