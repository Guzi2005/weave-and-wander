extends SceneTree

const Package := preload("res://components/material_package.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var render := "--render" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if render:
		root.size = Vector2i(640, 480)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(1.4, 1.1, 1.6)
		camera.look_at(Vector3(0, 0.4, 0))
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.5
		camera.current = true
		var light := DirectionalLight3D.new()
		root.add_child(light)
		light.rotation_degrees = Vector3(-45, -35, 0)
	for form in Package.FORMS:
		var source := {"id": "sample", "meters": 8.0, "capacity_m": 10.0, "pigment": Color("ad5f6b"), "pattern_code": 2, "material": "linen"}
		var package := Package.new()
		root.add_child(package)
		package.configure(source, form)
		if render:
			await process_frame
			await RenderingServer.frame_post_draw
		var core_geometry := _geometry(package.core)
		var node_count: int = package.find_children("*", "", true, false).size()
		var triangle_count := _triangle_count(package)
		check(triangle_count < 4000, "%s exceeds modest geometry budget: %d" % [form, triangle_count])
		check(package.cloth_material.get_shader_parameter("pigment") == source.pigment, "%s lost pigment" % form)
		check(is_equal_approx(float(package.cloth_material.get_shader_parameter("pattern")), 2.0), "%s lost pattern" % form)
		check(is_equal_approx(float(package.cloth_material.get_shader_parameter("weave_scale")), 125.0) if form in ["book", "roll"] else true, "%s lost material fiber setting" % form)
		var previous := INF
		for amount in [10.0, 7.5, 5.0, 2.5, 0.1, 0.0]:
			package.set_quantity(amount)
			var size: Vector3 = package.shell.mesh.get_aabb().size
			var volume := size.x * size.y * size.z
			check(volume <= previous + 0.000001, "%s shape grew while consuming" % form)
			previous = volume
			check(_geometry(package.core) == core_geometry, "%s changed core while consuming" % form)
			check(package.find_children("*", "", true, false).size() == node_count, "%s accumulated nodes" % form)
			check(source.meters == 8.0, "%s presentation changed ledger quantity" % form)
			check(package.shell.visible == (amount > 0), "%s empty-state visibility wrong" % form)
			check(package.display_bounds().size.is_finite(), "%s invalid bounds" % form)
			check(package.grip_points().size() == 2, "%s missing grip points" % form)
		if form in ["roll", "spool", "ribbon"]:
			package.set_quantity(10.0)
			var full_radius: float = package.shell.mesh.top_radius
			package.set_quantity(0.0)
			var core_radius: float = package.shell.mesh.top_radius
			package.set_quantity(5.0)
			var half_radius: float = package.shell.mesh.top_radius
			check(is_equal_approx(half_radius * half_radius - core_radius * core_radius, 0.5 * (full_radius * full_radius - core_radius * core_radius)), "%s radius fails area conservation" % form)
		elif form == "book":
			package.set_quantity(10.0)
			var full: float = package.shell.mesh.get_aabb().size.x
			package.set_quantity(0.0)
			var bare: float = package.shell.mesh.get_aabb().size.x
			package.set_quantity(5.0)
			check(is_equal_approx(package.shell.mesh.get_aabb().size.x - bare, (full - bare) * 0.5), "Book thickness should be linear")
		elif form == "yarn":
			package.set_quantity(10.0)
			var full: float = package.shell.mesh.radius
			package.set_quantity(1.25)
			check(is_equal_approx(package.shell.mesh.radius, full * 0.5), "Yarn radius should follow volume")
		package.set_quantity(NAN)
		check(package.quantity == 0.0 and not package.shell.visible, "%s NaN handling" % form)
		package.set_quantity(INF)
		check(package.quantity == 0.0, "%s infinity handling" % form)
		package.set_quantity(-100)
		check(package.quantity == 0.0, "%s negative quantity" % form)
		package.set_quantity(100)
		check(package.quantity == 10.0, "%s over-capacity quantity" % form)
		for iteration in 100:
			package.set_quantity(float(iteration % 11))
		check(package.find_children("*", "", true, false).size() == node_count, "%s repeated updates leak nodes" % form)
		package.set_quantity(5)
		var local_grips: Array[Vector3] = package.grip_points()
		var local_bounds: AABB = package.display_bounds()
		package.position = Vector3(3, 1, -2)
		package.rotation.y = 0.7
		var transformed_grips: Array[Vector3] = package.grip_points()
		check(transformed_grips[0].distance_to(package.global_transform * local_grips[0]) < 0.00001, "%s grip transform" % form)
		check(package.display_bounds().size.distance_to(local_bounds.size) < 0.00001, "%s local bounds changed on movement" % form)
		source.meters = 2.0
		check(package.data.meters == 2.0, "%s dictionary is not shared" % form)
		package.configure(source, form)
		check(package.find_children("*", "", true, false).size() == node_count, "%s reconfigure duplicated geometry" % form)
		package.free()
	print("MATERIAL_PACKAGE_TEST checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _geometry(node: Node3D) -> Array:
	var result: Array = []
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		result.append([mesh.transform, mesh.mesh.get_aabb()])
	return result


func _triangle_count(node: Node3D) -> int:
	var count := 0
	for part in node.find_children("*", "MeshInstance3D", true, false):
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			count += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count
