extends SceneTree

## GPU capture of the redesigned style-13 academic V-neck sweater vest:
## front/side/back of the vest layered over its shirt, a three-length row
## (.55/.80/1.05) and a shirt-only vs shirt+vest layering comparison.
## Run without --headless:
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       --script tests/vest_capture.gd --log-file captures/vest_capture.log

const Doll = preload("res://scripts/catalog_doll.gd")
const OUT := "res://captures/vest_redesign_20261028/"

var stage: Node3D = null
var camera: Camera3D = null
var labels: Array = []
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("VEST_CAPTURE skipped=headless")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	stage = Node3D.new()
	stage.name = "VestCapture"
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
	camera.position = Vector3(0, 1.5, 8.0)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.3, 0))
	camera.current = true

	# 1. Vest layered over its shirt: front, side, back.
	var vest_doll := _doll(13, .80, 0.0, 0)
	_label("SHIRT + SWEATER VEST", 0.0)
	camera.size = 2.7
	for view in [["front", 0.0], ["side", PI * .5], ["back", PI]]:
		vest_doll.body_rig.rotation.y = view[1]
		await _settle()
		_save(OUT + "vest_%s.png" % view[0])
	vest_doll.hide()
	_clear_labels()

	# 2. Three garment lengths: the hem moves, neckline and shoulders stay.
	camera.size = 3.4
	var row: Array = []
	var lengths := [.55, .80, 1.05]
	for i in 3:
		row.append(_doll(13, lengths[i], (i - 1) * 1.4, i + 1))
		_label("LENGTH %.2f" % lengths[i], (i - 1) * 1.4)
	await _settle()
	_save(OUT + "vest_lengths.png")
	for doll in row:
		doll.hide()
	_clear_labels()

	# 3. Layering comparison: the modern shirt alone vs with the vest on top.
	camera.size = 3.0
	_doll(10, .80, -.85, 3)
	_doll(13, .80, .85, 0)
	_label("CUBAN SHIRT", -.85)
	_label("SHIRT + VEST", .85)
	await _settle()
	_save(OUT + "vest_layered.png")

	print("VEST_CAPTURE failures=", failures)
	stage.free()
	quit(0 if failures == 0 else 1)


func _doll(style: int, length: float, x: float, seed: int) -> VolumeDoll:
	var doll := Doll.new()
	doll.catalog_style = style
	doll.catalog_garment_length = length
	stage.add_child(doll)
	doll.configure({"outfit": 2, "palette": seed % 4, "hair": seed % 3})
	doll.position.x = x
	return doll


func _label(text: String, x: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.pixel_size = 0.0018
	label.outline_size = 3
	label.modulate = Color("#eee8da")
	label.outline_modulate = Color("#293c35")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(x, 2.62, 0)
	stage.add_child(label)
	labels.append(label)


func _clear_labels() -> void:
	for label in labels:
		label.free()
	labels.clear()


func _settle() -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw


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
		print("VEST_CAPTURE saved=", output_path, " ", image.get_width(), "x", image.get_height())
