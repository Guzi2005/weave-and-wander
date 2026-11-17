extends Node

func _ready() -> void:
	var lab_scene = load("res://scenes/garment_lab.tscn").instantiate()
	add_child(lab_scene)
	lab_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# wait 10 frames
	for i in 10:
		await get_tree().process_frame
	var img = get_viewport().get_texture().get_image()
	img.save_png("D:/workspace/weave-and-wander/captures/actual_lab_capture.png")
	print("Saved actual capture: ", img.get_width(), "x", img.get_height())
	get_tree().quit()
