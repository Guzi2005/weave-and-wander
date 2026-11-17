extends SceneTree

const OrigDoll = preload("res://scripts/volume_doll.gd")
const FullDoll = preload("res://scripts/experimental_full_body_doll.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(0)
		return

	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size

	var stage := Node3D.new()
	root.add_child(stage)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#edf1f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#f4f7f8")
	env.environment.ambient_light_energy = 0.45
	stage.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.55
	light.shadow_enabled = true
	stage.add_child(light)

	var floor_m := PlaneMesh.new()
	floor_m.size = Vector2(40, 20)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#cfdbe0")
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_m
	floor_inst.material_override = floor_mat
	stage.add_child(floor_inst)

	# Showcase lineup: 5 dolls with diverse skin tones, hair colors, and eye colors
	var configs = [
		{
			"name": "Porcelain_Blonde_Blue",
			"skin": "porcelain",      # Skin index 0 / Fair Porcelain
			"hair": 3,                # Wavy lob
			"hair_color": "blonde",   # Hair index 5 / Golden Blonde
			"eye": "sapphire",        # Eye index 3 / Sapphire Blue
			"pos": Vector3(-3.2, 0, 0),
			"underbody": false,
		},
		{
			"name": "Ivory_Silver_Aqua",
			"skin": "fair",           # Skin index 4 / Ivory Fair
			"hair": 0,                # Low buns
			"hair_color": "silver",   # Hair index 8 / Silver Frost
			"eye": "aqua",            # Eye index 4 / Aqua Lake
			"pos": Vector3(-1.6, 0, 0),
			"underbody": true,        # Bare mannequin to inspect skin & eyes clearly
		},
		{
			"name": "Tan_Auburn_Amber",
			"skin": "tan",            # Skin index 1 / Warm Tan
			"hair": 3,                # Wavy lob
			"hair_color": "auburn",   # Hair index 3 / Auburn Copper
			"eye": "amber",           # Eye index 1 / Warm Amber
			"pos": Vector3(0.0, 0, 0),
			"underbody": false,
			"ukrainian": true,        # Full Ukrainian set
		},
		{
			"name": "Bronze_Emerald_Black",
			"skin": "bronze",         # Skin index 2 / Bronze Chestnut
			"hair": 2,                # Braids
			"hair_color": "jet_black",# Hair index 4 / Jet Black
			"eye": "emerald",         # Eye index 5 / Emerald Forest
			"pos": Vector3(1.6, 0, 0),
			"underbody": true,        # Bare mannequin
		},
		{
			"name": "Espresso_Mauve_Amethyst",
			"skin": "espresso",       # Skin index 3 / Deep Espresso
			"hair": 3,                # Wavy lob
			"hair_color": "mauve",    # Hair index 10 / Pastel Mauve
			"eye": "amethyst",        # Eye index 7 / Amethyst Violet
			"pos": Vector3(3.2, 0, 0),
			"underbody": false,
		},
	]

	var dolls: Array[Node3D] = []
	for cfg in configs:
		var d = FullDoll.new()
		stage.add_child(d)
		d.position = cfg["pos"]
		var conf_dict := {
			"outfit": 0,
			"hair": cfg["hair"],
			"skin": cfg["skin"],
			"hair_color": cfg["hair_color"],
			"eye": cfg["eye"],
			"palette": 0,
		}
		if cfg.get("ukrainian", false):
			conf_dict["shoe_style"] = 1
			d.configure(conf_dict)
			d.wear_ukrainian_set()
			# Re-apply custom hair color to ukrainian set
			d.set_hair_color(cfg["hair_color"])
			d.set_eye_color(cfg["eye"])
		else:
			d.configure(conf_dict)

		if cfg.get("underbody", false):
			d.set_underbody_mode(true)
		dolls.append(d)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(0, 1.45, 7.0)
	stage.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.35, 0))
	camera.current = true

	# Wait for build & skinning
	for frame in 8:
		await process_frame

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute("res://captures/appearance_showcase")
	var full_img := root.get_texture().get_image()
	if full_img != null:
		full_img.save_png("res://captures/appearance_showcase/lineup_full.png")
		print("LINEUP_FULL_SUCCESS")

	# Close up on faces for eyes, hair and skin tones
	camera.size = 1.35
	camera.position = Vector3(0, 2.02, 3.5)
	camera.look_at_from_position(camera.position, Vector3(0, 2.02, 0))

	# Shift dolls closer for face lineup
	dolls[0].position.x = -1.2
	dolls[1].position.x = -0.6
	dolls[2].position.x = 0.0
	dolls[3].position.x = 0.6
	dolls[4].position.x = 1.2

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw

	var face_img := root.get_texture().get_image()
	if face_img != null:
		face_img.save_png("res://captures/appearance_showcase/faces_close_up.png")
		print("FACES_CLOSEUP_SUCCESS")

	quit(0)
