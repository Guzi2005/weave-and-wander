extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string('res://tools/ww-wiki/public/assets/catalog.json'))
	for key in catalog.assets:
		if not str(key).begins_with("WW-BASIC-"): continue
		var entry = catalog.assets[key]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(600,760)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color('f0f1ee')
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.65
		viewport.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -25, 0)
		light.light_energy = 0.9
		viewport.add_child(light)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file('res://tools/ww-wiki/public/assets/models/'+entry.model+'.glb',state) != OK:
			quit(1)
			return
		var model := doc.generate_scene(state)
		viewport.add_child(model)
		var bounds := AABB()
		var first := true
		for part in model.find_children('*','MeshInstance3D',true,false):
			var box: AABB = part.global_transform * part.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(bounds.size.y,bounds.size.x*760.0/600.0)*1.15
		camera.position = bounds.get_center()+Vector3(2,4,6) if entry.model == "fabric_headband" else bounds.get_center()+Vector3(1.5,1.0,6)
		camera.look_at(bounds.get_center())
		camera.current = true
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var filename='res://tools/ww-wiki/public/assets/'+entry.model+'-cover.png'
		viewport.get_texture().get_image().save_png(filename)
		print(filename)
		viewport.queue_free()
		await process_frame
	quit()

