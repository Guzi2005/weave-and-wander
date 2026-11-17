extends SceneTree

func _init() -> void:
	var Doll = load("res://scripts/game_body_doll.gd")
	var doll: Node3D = Doll.new()
	root.add_child(doll)
	doll._build_appearance()
	await process_frame
	var br: Node3D = doll.body_rig
	print("body_rig: ", br.global_position, " clothes_root: ", doll.clothes_root.get_path() if doll.clothes_root else "null")
	for n in ["ArmLeft", "ArmRight", "LegLeft", "LegRight", "HeadRig"]:
		var node := br.get_node_or_null(n) as Node3D
		if node:
			print(n, " pos=", node.global_position, " rot=", node.rotation, " parent=", node.get_parent().name)
			for c in node.get_children():
				print("   - ", c.name, " vis=", c.visible if c is Node3D else "")
	print("doll.hair_root=", doll.hair_root.get_path() if doll.hair_root else "null")
	print("body_rig children:")
	for c in br.get_children():
		print("  ", c.name, " ", c.get_class())
	quit()
