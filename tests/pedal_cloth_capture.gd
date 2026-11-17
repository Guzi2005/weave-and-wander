extends SceneTree

## GPU capture of the Ukrainian set on the shared doll rig.
## Run without --headless from prototypes/dollhouse-3d:
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       --script tests/ukrainian_capture.gd --log-file captures/ukrainian_capture.log

const Doll = preload("res://scripts/experimental_full_body_doll.gd")

var stage: Node3D = null
var camera: Camera3D = null
var doll: Node3D = null
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("UKRAINIAN_CAPTURE skipped=headless")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute("res://captures/pedal_contact")
	root.size = Vector2i(1200, 1400)
	root.content_scale_size = root.size
	stage = Node3D.new()
	stage.name = "UkrainianCapture"
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

	doll = Doll.new()
	stage.add_child(doll)
	doll.configure({"outfit": 0, "palette": 0, "hair": 3, "shoe_style": 1})
	doll.set_process(false)
	doll.face_for_wardrobe()
	doll.rig.pose_rest("sit",1.0)
	doll.rig.place_foot("L",Vector3(-.15,.45,.42))
	doll.rig.place_foot("R",Vector3(.15,.42,.62))
	doll._pedal_contact.update(doll.rig)

	camera = Camera3D.new()
	camera.name = "CaptureCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.85
	camera.near = 0.02
	camera.far = 30.0
	stage.add_child(camera)
	_aim(Vector3(0, 1.45, 7.0), Vector3(0, 1.32, 0))

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	_save("res://captures/pedal_contact/front.png")

	doll.body_rig.rotation.y = PI * 0.25
	await RenderingServer.frame_post_draw
	_save("res://captures/pedal_contact/quarter.png")

	doll.body_rig.rotation.y = PI * 0.5
	await RenderingServer.frame_post_draw
	_save("res://captures/pedal_contact/side.png")

	doll.body_rig.rotation.y = PI
	await RenderingServer.frame_post_draw
	_save("res://captures/pedal_contact/back.png")

	# Waist close-up: documents the high sash line and layered skirts.
	doll.body_rig.rotation.y = 0.0
	camera.size = 1.25
	_aim(Vector3(0.6, 1.75, 6.0), Vector3(0, 1.22, 0))
	await RenderingServer.frame_post_draw
	_save("res://captures/pedal_contact/waist.png")

	# Neck close-up: red ribbon bow over the center-front opening.
	camera.size = 0.55
	_aim(Vector3(0, 1.95, 4.0), Vector3(0, 1.83, 0))
	await RenderingServer.frame_post_draw
	_save("res://captures/pedal_contact/neck.png")
	print("UKRAINIAN_CAPTURE failures=", failures)
	stage.free()
	quit(0 if failures == 0 else 1)


func _aim(from: Vector3, target: Vector3) -> void:
	camera.position = from
	camera.look_at(target)
	camera.current = true


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
		print("UKRAINIAN_CAPTURE saved=", output_path, " ", image.get_width(), "x", image.get_height())
