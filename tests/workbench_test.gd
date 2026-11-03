extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	var desk: Node3D = game._pop_up.desk
	var model: Node3D = desk.get_node("PBRWorktable")
	var count := 0
	var textured := 0
	var metal := 0
	var triangles := 0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		check(mesh.layers == 2, "Workbench must use its own render layer")
		for surface in mesh.mesh.get_surface_count():
			triangles += mesh.mesh.surface_get_array_index_len(surface) / 3
			var mat: Material = mesh.get_active_material(surface)
			check(mat is ShaderMaterial and mat.shader == desk.COLOR_BLOCKS, "Outer world needs its own textured color-block shader")
			if mat is ShaderMaterial:
				count += 1
				if mat.get_shader_parameter("has_normal") and mat.get_shader_parameter("normal_map") != null:
					textured += 1
				if mat.get_shader_parameter("metalness") > .5:
					metal += 1
	check(count > 12 and textured > 5 and metal >= 2, "PBR surfaces, normal maps and metals must import")
	check(triangles < 300000, "Lossless-reduced studio must stay under 300k triangles (schemes A/B/C), got %d" % triangles)
	check(model.find_child("CuttingGrid*", true, false) == null and model.find_child("RulerTick*", true, false) == null and model.find_child("Studio_MatInk*", true, false) == null, "Grid and ruler ticks must be procedural shader lines, not box meshes")
	var ruled_mat := false
	var ruled_ruler := false
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var surface_mat: Material = mesh.get_active_material(surface)
			if surface_mat is ShaderMaterial:
				ruled_mat = ruled_mat or surface_mat.get_shader_parameter("cutting_mat_grid") == true
				ruled_ruler = ruled_ruler or surface_mat.get_shader_parameter("ruler_ticks") == true
	check(ruled_mat and ruled_ruler, "Cutting mat grid and steel ruler ticks must be enabled in the studio shader")
	check(model.find_child("SolidOakWorktop", true, false) == null, "Legacy workbench must not survive the rebuild")
	var mat: MeshInstance3D = model.find_child("CuttingMat_90x60cm", true, false)
	check(mat != null, "Standard size cutting mat is missing")
	if mat != null:
		var size: Vector3 = mat.mesh.get_aabb().size * mat.global_basis.get_scale()
		check(absf(size.x / size.z - 1.5) < .02, "Cutting mat must have the 90:60 aspect ratio")
		check(absf(size.x - 45) < .1, "Outer-world scale must be 2 cm per game unit")
	check(desk.glass_panes.size() == 2, "Window needs two actual transparent glass panes")
	check(desk.get_node_or_null("DaylightOutsideWindow") == null, "Opaque fake window backdrop must be removed")
	for name in ["GardenTreeNear", "GardenTreeMiddle", "GardenTreeFar", "GardenFern0", "FabricBasketLeft", "ReferenceBooksLeft"]:
		check(model.find_child(name, true, false) != null, "Missing imported model: " + name)
	for plant in model.find_children("Garden*", "Node3D", true, false):
		if not ("Tree" in plant.name or "Fern" in plant.name):
			continue
		for part in plant.find_children("*", "MeshInstance3D", true, false):
			var front := -INF
			for surface in part.mesh.get_surface_count():
				var points: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for point in points:
					front = maxf(front,part.to_global(point).z)
			check(front < -21.5, "Outdoor foliage must stay behind the window wall: %s z=%.2f" % [plant.name,front])
	check(game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Camera must have real perspective")
	var near_width: float = game.camera.unproject_position(Vector3(1,3,6)).distance_to(game.camera.unproject_position(Vector3(-1,3,6)))
	var far_width: float = game.camera.unproject_position(Vector3(1,3,-6)).distance_to(game.camera.unproject_position(Vector3(-1,3,-6)))
	check(near_width > far_width * 1.1, "Equal objects closer to camera must appear larger")
	desk.set_time(9*60, game)
	var day: float = desk.window_light.light_energy
	var lamp_day: float = desk.lamp.light_energy
	check(desk.window_light.light_cull_mask == 2, "Window sun must be isolated")
	check(game.get_node("SoftWindowLight").light_cull_mask == 9, "Miniature and mirror-only wall lighting must be retained")
	desk.set_time(22*60, game)
	check(desk.window_light.light_energy < day and desk.lamp.light_energy > lamp_day, "Night must dim window light and brighten the task lamp")
	check(desk.lamp is SpotLight3D and desk.lamp.shadow_enabled, "Desk lamp must cast a directed beam with shadows")
	check(desk.lamp.light_cull_mask == 11, "Desk lamp must illuminate the workbench, miniature and reflected room shell")
	check(not desk._bulb_materials.is_empty(), "The desk-lamp bulb needs an emissive material")
	var emitter: Node3D = model.find_child("TaskLampEmitter", true, false)
	check(emitter != null and desk.lamp.global_position.distance_to(emitter.global_position) < .01, "Lamp beam must originate at its actual bulb")
	check(get_nodes_in_group("shop_lamps").size() >= 4, "Rooms need actual pendant lights")
	var lit_rooms := 0
	for indoor in get_nodes_in_group("shop_lamps"):
		var room_id: String = game._navigation.room_at(indoor.global_position)
		var enabled: bool = game._room_lights.get(room_id, false)
		if not enabled:
			continue
		lit_rooms += 1
		# The workshop pendant is intentionally dimmed (.20) so the task lamp leads.
		var minimum := .15 if room_id == "workshop" else 1.0
		check(indoor.light_energy >= minimum and indoor.shadow_enabled, "Shop lights must turn on at night: " + room_id)
	check(lit_rooms > 0, "At least one room light must be switched on at night")
	var glass_shaders := [preload("res://shaders/miniature_glass.gdshader"), preload("res://shaders/street_glass.gdshader")]
	for pane in get_nodes_in_group("shop_glass_panels"):
		check(pane.material_override.shader in glass_shaders, "Shop windows need transparent physical panes, not opaque pictures")
	check(desk._customer_lights.size() == 3, "Customer areas need invisible lighting support")
	var dawn: Dictionary = desk.DayCycle.sample(6*60)
	var sunset: Dictionary = desk.DayCycle.sample(18*60)
	var blue: Dictionary = desk.DayCycle.sample(19.5*60)
	check(dawn.sun.r > dawn.sun.b and sunset.sun.r > sunset.sun.b, "Golden-hour sun must be warm")
	check(blue.ambient.b > blue.ambient.r and blue.sun_energy < sunset.sun_energy, "Blue hour needs a cool sky after sunset")
	check(desk.DayCycle.sample(0).sky.is_equal_approx(desk.DayCycle.sample(1440).sky), "Day cycle must wrap without a color jump")
	desk.set_time(1439.9, game)
	var midnight_rotation: Vector3 = desk.window_light.rotation_degrees
	desk.set_time(.1, game)
	check(midnight_rotation.distance_to(desk.window_light.rotation_degrees) < .1, "Midnight must not make the light direction jump")
	var stone: ArrayMesh = game._street._stone_mesh()
	var normals: PackedVector3Array = stone.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var beveled := false
	for normal in normals:
		if normal.y > .1 and normal.y < .95:
			beveled = true
	check(beveled and stone.get_aabb().size.y >= .085, "Street stones need shallow thickness and beveled seam normals")
	var original: Transform3D = model.global_transform
	for depth in [0.0,.5,1.0,1.5,2.0,2.5,3.0]:
		game._pop_up.apply_depth(depth)
		check(model.global_transform.is_equal_approx(original), "Workbench must not fold or translate with scene pages")
	for depth in [0.0, .2, .4, .6, 1.0]:
		game._pop_up.apply_depth(depth)
		for group in game._pop_up._static_groups:
			if group.get("role", "") == "front_room_fixed":
				check(is_equal_approx(group.last, 1.0), "Only the outer wall should fold between street and front rooms")
		for actor in game.staff:
			check(is_equal_approx(game._pop_up._actor_amount(actor), 1.0), "Staff must remain unfolded behind the outer wall")
	print("WORKBENCH_TEST: %d stylized surfaces, %d normal-mapped, %d metallic, %d triangles; %d failures" % [count,textured,metal,triangles,failures.size()])
	game.free()
	quit(0 if failures.is_empty() else 1)
