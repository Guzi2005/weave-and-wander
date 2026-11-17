extends SceneTree
const SAVE = preload("res://scripts/game_save.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var saved := SAVE.read_snapshot("user://progression_test.save.bak")
	assert(saved.ok,"Run progression_system_test first with the same isolated APPDATA")
	SAVE.pending_snapshot = saved.data
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	assert(SAVE.pending_snapshot.is_empty())
	assert(game._business_state == "workshop" and game.customers.is_empty())
	assert(game._money == saved.data.world._money)
	assert(game._inventory.items.size() == saved.data.items.size())
	assert(game._inventory.items[0].item_id == saved.data.items[0].id)
	assert(game._progression.quiz_answers == saved.data.progression.quiz)
	assert(game._vendor.stock == saved.data.extras.street_vendor.stock)
	for path in saved.data.layouts:
		assert(game.get_node(path).transform.is_equal_approx(saved.data.layouts[path]))
	assert(is_equal_approx(game._inventory.fabric_batches[0].meters,saved.data.fabrics[0].meters))
	print("SAVE RESTART: fresh-process identity, materials, quiz, vendor and layout restored")
	quit()
