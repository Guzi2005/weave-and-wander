extends SceneTree

## Close-up GPU capture of the cuban camp collar and the crossed apron
## straps, for visual review of the collar/straps geometry fix.
## Run without --headless (window may be hidden):
##   godot.windows.opt.tools.64.exe --path . \
##       --script tests/collar_strap_capture.gd --log-file captures/collar_strap_capture.log

const Doll = preload("res://scripts/catalog_doll.gd")

var stage: Node3D = null
var camera: Camera3D = null
var cuban: VolumeDoll = null
var apron: VolumeDoll = null
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("COLLAR_STRAP_CAPTURE skipped=headless")
		quit(0)
		return
	root.size = Vector2i(1200, 900)
	root.content_scale_size = root.size
	stage = Node3D.new()
	stage.name = "CollarStrapCapture"
	root.add_child(stage)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#e9eff0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#e5eff2")
	environment.environment.ambient_light_energy = 0.4
	stage.add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.light_energy = 0.5
	key.light_color = Color("#fff2df")
	key.shadow_enabled = true
	stage.add_child(key)

	cuban = Doll.new()
	cuban.catalog_style = 10
	stage.add_child(cuban)
	cuban.configure({"outfit": 2, "palette": 0, "hair": 0})
	cuban.position.x = -0.62

	apron = Doll.new()
	apron.catalog_style = 1
	stage.add_child(apron)
	apron.configure({"outfit": 1, "palette": 1, "hair": 1})
	apron.position.x = 0.62

	camera = Camera3D.new()
	camera.name = "CaptureCamera"
	camera.near = 0.02
	camera.far = 30.0
	stage.add_child(camera)
	camera.current = true

	for frame in 6:
		await process_frame

	# Collar close-up: chest and neck of the camp shirt from the front.
	_frame(Vector3(-0.62, 1.95, 2.1), Vector3(-0.62, 1.72, 0.0), 1.15)
	await RenderingServer.frame_post_draw
	_save("res://captures/collar_cuban_front.png")

	# Apron straps close-up: shoulder line from the front, slightly above.
	_frame(Vector3(0.62, 2.25, 2.2), Vector3(0.62, 1.68, 0.0), 1.35)
	await RenderingServer.frame_post_draw
	_save("res://captures/strap_shoulder_front.png")

	# Crossed straps on the back, down to the waist tie.
	cuban.body_rig.rotation.y = PI
	apron.body_rig.rotation.y = PI
	_frame(Vector3(0.62, 2.05, 2.3), Vector3(0.62, 1.55, 0.0), 1.5)
	await RenderingServer.frame_post_draw
	_save("res://captures/strap_cross_back.png")

	print("COLLAR_STRAP_CAPTURE failures=", failures)
	stage.free()
	quit(0 if failures == 0 else 1)


func _frame(eye: Vector3, target: Vector3, ortho_size: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ortho_size
	camera.position = eye
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
		print("COLLAR_STRAP_CAPTURE saved=", output_path, " ", image.get_width(), "x", image.get_height())
