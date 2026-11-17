extends SceneTree

func _init() -> void:
	var scn: Control = load("res://scenes/garment_lab.tscn").instantiate()
	root.add_child(scn)
	scn.size = Vector2(1420, 920)
	
	for i in 15:
		await process_frame
		
	# 1. Capture SubViewport (3D model)
	var vp: SubViewport = scn.viewport
	if vp != null:
		var img_3d := vp.get_texture().get_image()
		img_3d.save_png("D:/workspace/weave-and-wander/captures/3d_viewport_capture.png")
		print("3D viewport captured: ", img_3d.get_width(), "x", img_3d.get_height())

	# 2. Capture root viewport
	var root_img := root.get_texture().get_image()
	root_img.save_png("D:/workspace/weave-and-wander/captures/full_window_capture.png")
	print("Root window captured: ", root_img.get_width(), "x", root_img.get_height())
	
	# 3. Print the doll's clothes_root children and hair_root children!
	var doll = scn.doll
	print("DOLL VISIBLE: ", doll.visible)
	print("DOLL HAIR CHILDREN:")
	if doll.hair_root != null:
		for c in doll.hair_root.get_children():
			print("  - Hair: ", c.name, " vis=", c.visible if c is Node3D else true)
	else:
		print("  - Hair root is NULL!")
	
	print("DOLL CLOTHES CHILDREN:")
	if doll.clothes_root != null:
		for c in doll.clothes_root.get_children():
			print("  - Cloth: ", c.name, " vis=", c.visible if c is Node3D else true)
			for sub in c.get_children():
				print("      * Sub: ", sub.name, " vis=", sub.visible if sub is Node3D else true)
	else:
		print("  - Clothes root is NULL!")

	quit()
