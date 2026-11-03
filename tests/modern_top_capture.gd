extends SceneTree

## GPU capture of the revised modern tops (styles 10 Cuban shirt and 11
## babydoll blouse): front / side / back views plus a three-length comparison
## proving garment_length moves the hem only.
## Run without --headless:
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       --script tests/modern_top_capture.gd --log-file captures/modern_top_capture.log

const Doll = preload("res://scripts/catalog_doll.gd")
const OUTPUT_DIR := "res://captures/modern_top_revision/"

var stage: Node3D = null
var camera: Camera3D = null
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("MODERN_TOP_CAPTURE skipped=headless")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	stage = Node3D.new()
	stage.name = "ModernTopCapture"
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

	camera = Camera3D.new()
	camera.name = "CaptureCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.02
	camera.far = 30.0
	stage.add_child(camera)
	camera.current = true

	# Front / side / back of both revised tops at the default length.
	var views := [
		["front", 0.0], ["side", PI * .5], ["back", PI]]
	for view in views:
		var dolls := []
		for index in 2:
			var doll := _make_doll(10 + index, .80, index, (index - 0.5) * 1.6, str(view[1]))
			dolls.append(doll)
		_aim(Vector3(0, 1.35, 0), Vector3(0, 1.6, 8.0), 3.1)
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		_save(OUTPUT_DIR + "tops_" + str(view[0]) + ".png")
		for doll in dolls:
			doll.free()

	# Three-length comparison: hem moves, shoulders/neck/sleeves stay put.
	var lengths := [.55, .80, 1.05]
	var length_dolls := []
	for index in lengths.size() * 2:
		var style := 10 + index / 3
		var length: float = lengths[index % 3]
		var doll := _make_doll(style, length, index, (index - 2.5) * 1.25, "0.0")
		var tag := Label3D.new()
		tag.text = "%s %.2f" % ["CUBAN" if style == 10 else "BABYDOLL", length]
		tag.font_size = 30
		tag.pixel_size = 0.0016
		tag.outline_size = 3
		tag.modulate = Color("#eee8da")
		tag.outline_modulate = Color("#293c35")
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = Vector3(doll.position.x, 2.55, 0)
		stage.add_child(tag)
		length_dolls.append(doll)
	_aim(Vector3(0, 1.3, 0), Vector3(0, 1.55, 8.0), 4.1)
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(OUTPUT_DIR + "tops_lengths.png")
	for doll in length_dolls:
		doll.free()

	print("MODERN_TOP_CAPTURE failures=", failures)
	stage.free()
	quit(0 if failures == 0 else 1)


func _make_doll(style: int, length: float, seed_index: int, x: float, yaw: String) -> VolumeDoll:
	var doll := Doll.new()
	doll.catalog_style = style
	doll.catalog_garment_length = length
	stage.add_child(doll)
	doll.configure({"outfit": 2, "palette": seed_index % 4, "hair": seed_index % 3})
	doll.position.x = x
	doll.body_rig.rotation.y = float(yaw)
	return doll


func _aim(target: Vector3, position: Vector3, size: float) -> void:
	camera.size = size
	camera.position = position
	camera.look_at(target)


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
		print("MODERN_TOP_CAPTURE saved=", output_path, " ", image.get_width(), "x", image.get_height())
