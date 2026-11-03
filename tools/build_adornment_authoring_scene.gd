extends SceneTree
const Procedural = preload("res://components/parametric_adornment_node.gd")
const Beads = preload("res://components/seed_bead_bundle.gd")
const Braid = preload("res://components/path_braid.gd")
const Socket = preload("res://components/accessory_socket.gd")

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "MosuoAdornmentAuthoring"
	scene.set_meta("instructions","Select the recipe on a procedural mesh to edit parameters. Select a Path3D to drag control points. Save reusable recipes as .tres, then export the game assets.")
	var head := Node3D.new()
	head.name = "HeadRig"
	head.position = Vector3(0,2.02,.035)
	scene.add_child(head)
	var bead_recipe := Beads.photo_001()
	var braid_recipe := Braid.photo_001()
	for entry in [["TasselRoute",bead_recipe],["BraidRoute",braid_recipe]]:
		var path := Path3D.new()
		path.name = entry[0]
		path.curve = entry[1].path.duplicate(true)
		head.add_child(path)
	var flower_socket := Socket.new()
	flower_socket.name = "CrownFlowerSocket"
	flower_socket.socket_id = "CrownFlowerSocket"
	flower_socket.position = Vector3(.27,.74,.12)
	flower_socket.rotation_degrees = Vector3(0,0,-12)
	head.add_child(flower_socket)
	var flower := Procedural.new()
	flower.name = "ParametricFlower"
	flower.recipe = load("res://assets/collections/mosuo_flower.tres").duplicate(true)
	flower_socket.add_child(flower)
	var bead_socket := Socket.new()
	bead_socket.name = "OccipitalTasselSocket"
	bead_socket.socket_id = "OccipitalTasselSocket"
	bead_socket.position = bead_recipe.path.get_point_position(0)
	head.add_child(bead_socket)
	var beads := Procedural.new()
	beads.name = "ParametricBeadBundle"
	beads.recipe = bead_recipe
	beads.geometry_origin = bead_socket.position
	beads.path_node = NodePath("../../TasselRoute")
	bead_socket.add_child(beads)
	var braid := Procedural.new()
	braid.name = "ParametricBraid"
	braid.recipe = braid_recipe
	braid.path_node = NodePath("../BraidRoute")
	head.add_child(braid)
	var camera := Camera3D.new()
	camera.position = Vector3(0,2.7,4)
	camera.rotation_degrees.x = -12
	camera.current = true
	scene.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-25,0)
	scene.add_child(light)
	for node in scene.find_children("*","",true,false): node.owner = scene
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed,"res://scenes/mosuo_adornment_authoring.tscn") == OK)
	scene.free()
	print("ADORNMENT_AUTHORING_SCENE_SAVED")
	quit()
