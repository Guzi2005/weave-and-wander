extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 950)
	root.content_scale_size = root.size
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("edf1f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("f4f7f8")
	env.environment.ambient_light_energy = 0.42
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.5
	stage.add_child(light)
	var dolls: Array[Node3D] = []
	for style in 3:
		var doll := Doll.new()
		stage.add_child(doll)
		doll.configure({"outfit": style, "hair": 0, "palette": style})
		doll.position.x = (style - 1) * 1.40
		doll.set_process(false)
		dolls.append(doll)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.15
	camera.position = Vector3(0, 1.45, 7)
	camera.look_at(Vector3(0, 1.35, 0))
	camera.current = true
	var exported: Array = []
	for pose in ["idle", "work", "walk"]:
		for doll in dolls:
			doll.rig.animate(0.8, 1.0 if pose == "walk" else 0.0, "sewing" if pose == "work" else "idle", 0.5)
			doll.body_contact.update()
			doll.body_rig.rotation.y = 0.4 if pose == "work" else 0.0
			if "--export-contact" in OS.get_cmdline_user_args(): exported.append(export_pose(doll, pose))
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/game_body_" + pose + ".png")
	if not exported.is_empty():
		var file := FileAccess.open("res://captures/game_body_contact_input.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(exported))
		file.close()
	stage.free()
	print("GAME_BODY_CAPTURE 3 styles x 3 poses; body untouched")
	quit()


func export_pose(doll: Node3D, pose: String) -> Dictionary:
	var data := {"style": doll.outfit_style, "pose": pose, "body": [], "cloth": [], "contact": "post-skin capsule projection, normal lift excluded (conservative diagnostic)"}
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.visible: continue
		var body: bool = part.get_meta("is_underbody", false)
		if not body and str(part.name) not in ["TailoredShell", "LongSkirt", "Apron", "OpenWaistcoat", "Trouser"]: continue
		var points: PackedVector3Array = doll.rig.deformed_vertices(part)
		var material := part.material_override as ShaderMaterial
		if not body and material != null and material.get_shader_parameter("cloth_contact_enabled") == true:
			for i in points.size():
				points[i] = doll.body_contact.project(points[i], material.get_shader_parameter("cloth_layer_clearance"), material.get_shader_parameter("cloth_contact_arms"))
		var vertices: Array = []
		for p in points: vertices.append([p.x, p.y, p.z])
		var arrays := part.mesh.surface_get_arrays(0)
		var indices: Array = range(vertices.size()) if arrays[Mesh.ARRAY_INDEX] == null else Array(arrays[Mesh.ARRAY_INDEX])
		var item := {"name": str(part.name), "vertices": vertices, "indices": indices}
		if body: data.body.append(item)
		else: data.cloth.append(item)
	return data
