extends SceneTree

const CHARACTER = preload("res://shaders/doll_volume.gdshader")
const ROOM = preload("res://shaders/room_paper.gdshader")
const PAPER = preload("res://shaders/paper.gdshader")
const LINING = preload("res://shaders/doll_lining.gdshader")
var game: Node
var failures: Array[String] = []
var character_parts := 0
var scene_parts := 0
var capture_tag := "character_print"


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-tag="):
			capture_tag = argument.get_slice("=", 1).validate_filename()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	for i in 3:
		await process_frame
	game._fit_stage()
	game._update_ui()
	root.size_changed.disconnect(game._fit_stage)
	for control in game.find_children("*", "Control", true, false):
		control.tooltip_text = ""
	var people: Array = game.staff + game.customers + game._street_life.pedestrians + [game._street_life.postman]
	for person in people:
		for part in person.rig.meshes:
			var material := part.material_override as ShaderMaterial
			_check(material != null and material.shader in [CHARACTER, LINING], "Character part escaped print material: " + str(part.name))
			if material != null and material.shader == CHARACTER and DisplayServer.get_name() != "headless":
				_check(is_equal_approx(_parameter(material, "tone_steps"), 2.0), "Character reverted to multi-band shading")
				_check(is_equal_approx(_parameter(material, "tooth"), 0.075), "Character print grain was overridden")
			character_parts += 1
	for scene in game._rooms.values() + [game._street, game._street_life.bicycle]:
		for part in scene.find_children("*", "GeometryInstance3D", true, false):
			var material := part.material_override as ShaderMaterial
			var allowed := [ROOM, PAPER]
			if part.is_in_group("shop_glass_panels"):
				allowed.append(preload("res://shaders/miniature_glass.gdshader"))
			if part.name == "ReflectiveGlass":
				allowed.append(preload("res://shaders/mirror_surface.gdshader"))
			_check(material != null and material.shader in allowed, "Scene object lost its lit paper material: " + str(part.get_path()))
			scene_parts += 1
	_check(character_parts > 100 and scene_parts > 100, "Material checks did not cover the scene")
	await _snapshot("room")
	# A character-free pass makes unintended environment changes pixel-comparable.
	var visible_people: Array[Node3D] = []
	for person in people:
		if person.visible:
			visible_people.append(person)
			person.hide()
	await _snapshot("environment")
	for person in visible_people:
		person.show()
	for frame in 900:
		game._street_life.simulate(1.0 / 60.0, 1, 9 * 60 + 15)
		if game._street_life.postal_stage == "to_door":
			break
	_check(game._street_life.postal_stage == "to_door", "Postman did not reach preview position")
	game.camera.position = Vector3(1.5, 4.1, 14)
	game.camera.look_at(Vector3(1.5, 1.4, 3.5))
	game.camera.size = 7.5
	game.camera.h_offset = 0
	game.camera.v_offset = 0
	game.get_node("GameInterface").hide()
	await _snapshot("detail")
	print("CHARACTER_PRINT_CHECK character_parts=", character_parts, " scene_parts=", scene_parts, " failures=", failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func _parameter(material: ShaderMaterial, key: String) -> float:
	var value: Variant = material.get_shader_parameter(key)
	if value == null:
		value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), key)
	_check(value != null, "Missing shader parameter: " + key)
	return float(value) if value != null else -1.0


func _snapshot(label: String) -> void:
	if not "--capture-style" in OS.get_cmdline_user_args():
		return
	game._toast_label.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://captures/%s_%s_%dx%d.png" % [capture_tag, label, root.size.x, root.size.y])
	_check(root.get_texture().get_image().save_png(path) == OK, "Style preview could not be saved")
