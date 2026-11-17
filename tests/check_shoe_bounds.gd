extends SceneTree

func _init():
	var doll = preload("res://scripts/volume_doll.gd").new()
	root.add_child(doll)
	doll.configure({"outfit": 2, "shoe_style": 0})
	for child in doll.body_rig.find_children("*", "MeshInstance3D", true, false):
		if "Sole" in child.name or "Shoe" in child.name or "Trouser" in child.name or "Calf" in child.name:
			print(child.name, " parent=", child.get_parent().name, " global_pos=", child.global_position, " aabb=", child.get_aabb())
	quit(0)
