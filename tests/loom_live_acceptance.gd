extends SceneTree
func _initialize(): launch.call_deferred()
func launch():
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._switch_room("workshop")
	game._assign_staff(game.staff[1],game._facility_index("loom"),true)
	print("LIVE_LOOM_ACCEPTANCE worker=",game.staff[1].doll_name)
