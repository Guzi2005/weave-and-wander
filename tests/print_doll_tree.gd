extends SceneTree

func _init():
	var doll = preload("res://scripts/volume_doll.gd").new()
	root.add_child(doll)
	doll.configure({"outfit": 0})
	_dump(doll, 0)
	quit(0)

func _dump(node: Node, indent: int):
	var prefix = "  ".repeat(indent)
	print(prefix, node.name, " (", node.get_class(), ") visible=", node.get("visible") if "visible" in node else "N/A")
	for child in node.get_children():
		_dump(child, indent + 1)
