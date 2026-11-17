extends SceneTree

func _init() -> void:
	print("Initial root.size: ", root.size)
	var scn: Control = load("res://scenes/garment_lab.tscn").instantiate()
	root.add_child(scn)
	print("scn.size right after add: ", scn.size)
	for i in 5:
		await process_frame
	print("scn.size after 5 frames: ", scn.size)
	for c in scn.get_children():
		print("  scn child: ", c.name, " size: ", c.size if c is Control else "")
		if c is HBoxContainer:
			for sub in c.get_children():
				print("    layout sub: ", sub.name, " size: ", sub.size, " min_size: ", sub.custom_minimum_size)
	quit()
