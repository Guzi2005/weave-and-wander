extends SceneTree

func _init() -> void:
	var scn: Control = load("res://scenes/garment_lab.tscn").instantiate()
	root.add_child(scn)
	
	for i in 5:
		await process_frame
		
	var layout: HBoxContainer = scn.get_node("HBoxContainer") if scn.has_node("HBoxContainer") else null
	for c in scn.get_children():
		print("Child of GarmentLab: ", c.name, " class=", c.get_class(), " size=", c.size if c is Control else "", " pos=", c.position if c is Control else "")
		if c is HBoxContainer:
			for sub in c.get_children():
				print("   - sub: ", sub.name, " class=", sub.get_class(), " size=", sub.size, " pos=", sub.position, " min_size=", sub.custom_minimum_size)
				if sub is ScrollContainer:
					for sc_child in sub.get_children():
						print("       * ScrollChild: ", sc_child.name, " size=", sc_child.size, " pos=", sc_child.position, " min_size=", sc_child.custom_minimum_size)
	quit()
