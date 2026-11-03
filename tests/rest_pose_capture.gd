extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")
const Bench = preload("res://components/rest_bench.gd")
var stage: Node3D
var bench: Node3D
var sleeper: VolumeDoll
var sitter: VolumeDoll
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,800)
	root.content_scale_size = root.size
	stage = Node3D.new()
	root.add_child(stage)
	bench = Bench.new()
	stage.add_child(bench)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("dbe5e1")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .75
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = .8
	stage.add_child(light)
	for index in 2:
		var doll := Doll.new()
		stage.add_child(doll)
		doll.configure({"hair":2 if index==0 else 0,"hair_color":0 if index==0 else 1,"outfit":1 if index==0 else 0,"skin":0,"palette":0})
		bench.reserve(doll,index==0)
		bench.support_actor(doll)
		doll._moving = false
		doll.get_node("GroundContact").hide()
		if index==0: sleeper=doll
		else: sitter=doll
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 36
	for pose in 4:
		sleeper.nap_pose = pose
		for frame in 130:
			sleeper.simulate(1.0/60,1)
			sitter.simulate(1.0/60,1)
		camera.position = Vector3(2.5,2.8,7.7)
		camera.look_at(Vector3(0,1.12,.05))
		await capture("rest_refined_%d"%pose)
		if pose==0:
			await export_editor_scene()
			camera.position = Vector3(-.4,3.7,6.4)
			camera.look_at(Vector3(-.45,1,.15))
			await capture("rest_refined_top")
			camera.position = Vector3(3.8,1.65,6.3)
			camera.look_at(Vector3(-.55,1.05,.15))
			await capture("rest_refined_side")
			camera.position = Vector3(-1.6,2.25,3.1)
			camera.look_at(Vector3(-1.25,1.12,.32))
			await capture("rest_refined_expression")
	print("REST_POSE_CAPTURE views=7")
	stage.free()
	quit()

func capture(label: String) -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/%s.png"%label)

func export_editor_scene() -> void:
	# A pose snapshot for the editor MCP, baked from the same runtime skinning.
	var snapshot := Node3D.new()
	snapshot.name = "RestPoseSnapshot"
	stage.add_child(snapshot)
	for source in stage.find_children("*","MeshInstance3D",true,false):
		if not source.is_visible_in_tree(): continue
		var part := MeshInstance3D.new()
		var model: VolumeDoll = sleeper if source in sleeper.rig.meshes else (sitter if source in sitter.rig.meshes else null)
		if model != null:
			var arrays: Array = source.mesh.surface_get_arrays(0)
			arrays[Mesh.ARRAY_VERTEX] = model.rig.deformed_vertices(source)
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			part.mesh = mesh
		else:
			part.mesh = source.mesh
		part.material_override = source.material_override
		snapshot.add_child(part)
		part.global_transform = source.global_transform
		part.owner = snapshot
	for source in [camera,stage.get_child(1),stage.get_child(2)]:
		var copy: Node = source.duplicate()
		snapshot.add_child(copy)
		copy.owner = snapshot
	var packed := PackedScene.new()
	packed.pack(snapshot)
	ResourceSaver.save(packed,"res://captures/rest_pose_editor.tscn")
	snapshot.free()
