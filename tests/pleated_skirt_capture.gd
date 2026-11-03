extends SceneTree

## GPU capture of the four contract templates. Run without --headless:
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       --script tests/pleated_skirt_capture.gd --log-file captures/pleated_skirt_capture.log

const Design = preload("res://scripts/pleated_skirt_design.gd")
const Skirt = preload("res://components/pleated_skirt.gd")

var stage: Node3D = null
var camera: Camera3D = null
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PLEATED_SKIRT_CAPTURE skipped=headless")
		quit(0)
		return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	stage = Node3D.new()
	stage.name = "PleatedSkirtTemplateCapture"
	root.add_child(stage)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#596B64")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#FFF6E8")
	environment.environment.ambient_light_energy = 0.28
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(environment)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 20.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#596B64")
	floor_material.roughness = 0.95
	floor_mesh.material = floor_material
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(0, -0.002, 0)
	stage.add_child(floor_instance)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -30, 0)
	key.light_color = Color("#FFF1DA")
	key.light_energy = 0.7
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 145, 0)
	fill.light_color = Color("#C9D8EE")
	fill.light_energy = 0.12
	stage.add_child(fill)

	var painted := OS.get_cmdline_user_args().has("--painted")
	var x_positions := [0.0] if painted else [-1.8, -0.6, 0.6, 1.8]
	var labels := ["2D PAINT + PATCH + STROKE"] if painted else ["PLAIN", "MOSUO STUDY", "YI STUDY", "WAX STUDY"]
	for index in x_positions.size():
		var template_id: String = Design.TEMPLATE_IDS[index]
		var skirt := Skirt.new()
		skirt.name = "Skirt_" + template_id
		skirt.position = Vector3(x_positions[index], 0, 0)
		stage.add_child(skirt)
		var fixture_name: String = "painted" if painted else template_id
		var error = skirt.load_design("res://assets/designs/pleated_skirt/%s/skirt.json" % fixture_name)
		if error != OK:
			failures += 1
			push_error("Could not configure capture template: " + template_id)
			continue
		var label := Label3D.new()
		label.text = labels[index]
		label.font_size = 36
		label.pixel_size = 0.0018
		label.outline_size = 3
		label.modulate = Color("#eee8da")
		label.outline_modulate = Color("#293c35")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(x_positions[index], float(skirt.design["parameters"]["length_cm"]) / 100.0 + 0.13, 0)
		stage.add_child(label)

	camera = Camera3D.new()
	camera.name = "CaptureCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.45 if painted else 3.15
	camera.near = 0.02
	camera.far = 30.0
	camera.position = Vector3(0, 1.8, 4.2)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.48, 0))
	camera.current = true

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		failures += 1
		push_error("Capture viewport returned no image.")
	else:
		var output_path := "res://captures/pleated_skirt_painted.png" if painted else "res://captures/pleated_skirt_four_templates.png"
		var save_error := image.save_png(output_path)
		if save_error != OK:
			failures += 1
			push_error("Could not save capture: " + error_string(save_error))
		else:
			print("PLEATED_SKIRT_CAPTURE templates=", x_positions.size(),
				" size=", image.get_width(), "x", image.get_height(),
				" path=", output_path, " failures=", failures)
	stage.free()
	quit(0 if failures == 0 else 1)
