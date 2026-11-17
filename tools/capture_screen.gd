extends SceneTree

func _init() -> void:
	var LabScript = load("res://scripts/garment_lab.gd")
	var lab: Control = LabScript.new()
	root.add_child(lab)
	
	for i in 5:
		await process_frame
	
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("D:/workspace/weave-and-wander/captures/current_screen_test.png")
	print("Saved screenshot to D:/workspace/weave-and-wander/captures/current_screen_test.png: ", img.get_width(), "x", img.get_height())
	quit()
