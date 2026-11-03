extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene := load("res://scenes/mosuo_adornment_authoring.tscn").instantiate() as Node3D
	root.add_child(scene)
	var flower := scene.get_node("HeadRig/CrownFlowerSocket/ParametricFlower")
	var beads := scene.get_node("HeadRig/OccipitalTasselSocket/ParametricBeadBundle")
	var braid := scene.get_node("HeadRig/ParametricBraid")
	for node in [flower,beads,braid]: assert(node.mesh != null and node.mesh.get_surface_count() > 0)
	var width: float = flower.mesh.get_aabb().size.x
	flower.recipe.radius *= .7
	flower.rebuild()
	assert(flower.mesh.get_aabb().size.x < width*.8)
	var route: Path3D = scene.get_node("HeadRig/TasselRoute")
	var before: AABB = beads.mesh.get_aabb()
	var last := route.curve.get_point_count()-1
	route.curve.set_point_position(last,route.curve.get_point_position(last)+Vector3(.25,0,0))
	beads.rebuild()
	assert(beads.mesh.get_aabb().size.x > before.size.x+.1)
	assert(beads.recipe.path == route.curve)
	print("ADORNMENT_AUTHORING_PASS parameter and draggable-path geometry updates")
	scene.free()
	quit()
