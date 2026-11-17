extends SceneTree

func _init() -> void:
	var scn: Control = load("res://scenes/garment_lab.tscn").instantiate()
	root.add_child(scn)
	scn.size = Vector2(1420, 920)
	
	# Switch to granddaughter preset
	scn.current_hair_color = Color("3d2c25")
	scn.current_garment_palette["main"] = Color(0.92, 0.89, 0.83)
	scn.current_garment_palette["bottom_main"] = Color(0.14, 0.28, 0.22)
	scn._set_active_slots("23", "24", "none", "25", "none", "19", "none")

	for i in 15:
		await process_frame
		
	var vp: SubViewport = scn.viewport
	if vp != null:
		var img_3d := vp.get_texture().get_image()
		img_3d.save_png("D:/workspace/weave-and-wander/captures/granddaughter_viewport.png")
		print("3D viewport captured: ", img_3d.get_width(), "x", img_3d.get_height())

	quit()
