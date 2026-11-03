extends SceneTree

## GPU capture of the modern everyday catalog garments on raw catalog dolls.
## Run without --headless:
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       --script tests/basic_garment_capture.gd --log-file captures/basic_garment_capture.log

const Doll = preload("res://scripts/catalog_doll.gd")

var stage: Node3D = null
var camera: Camera3D = null
var dolls: Array = []
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("BASIC_GARMENT_CAPTURE skipped=headless")
		quit(0)
		return
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	stage = Node3D.new()
	stage.name = "BasicGarmentCapture"
	root.add_child(stage)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#e9eff0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#e5eff2")
	environment.environment.ambient_light_energy = 0.38
	stage.add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_energy = 0.45
	key.light_color = Color("#fff2df")
	key.shadow_enabled = true
	stage.add_child(key)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 20.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#cbdce0")
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material = floor_material
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(0, -0.002, 0)
	stage.add_child(floor_instance)

	var styles := [10, 11, 12, 13, 1]
	var outfits := [2, 2, 2, 2, 1]
	var labels := ["CUBAN SHIRT", "BABYDOLL BLOUSE", "MODERN SKIRT", "SWEATER VEST", "APRON (REF)"]
	for index in styles.size():
		var doll := Doll.new()
		doll.catalog_style = styles[index]
		stage.add_child(doll)
		doll.configure({"outfit": outfits[index], "palette": index % 4, "hair": index % 3})
		doll.position.x = (index - 2.0) * 1.55
		dolls.append(doll)
		var label := Label3D.new()
		label.text = labels[index]
		label.font_size = 36
		label.pixel_size = 0.0018
		label.outline_size = 3
		label.modulate = Color("#eee8da")
		label.outline_modulate = Color("#293c35")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(doll.position.x, 2.62, 0)
		stage.add_child(label)

	camera = Camera3D.new()
	camera.name = "CaptureCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.3
	camera.near = 0.02
	camera.far = 30.0
	camera.position = Vector3(0, 1.6, 8.0)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.35, 0))
	camera.current = true

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	_save("res://captures/basic_garment_front.png")
	# The back view shows the apron straps crossing into the waist tie.
	for doll in dolls:
		doll.body_rig.rotation.y = PI
	await RenderingServer.frame_post_draw
	_save("res://captures/basic_garment_back.png")
	print("BASIC_GARMENT_CAPTURE dolls=", dolls.size(), " failures=", failures)
	stage.free()
	quit(0 if failures == 0 else 1)


func _save(output_path: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		failures += 1
		push_error("Capture viewport returned no image.")
		return
	var save_error := image.save_png(output_path)
	if save_error != OK:
		failures += 1
		push_error("Could not save capture: " + error_string(save_error))
	else:
		print("BASIC_GARMENT_CAPTURE saved=", output_path, " ", image.get_width(), "x", image.get_height())
