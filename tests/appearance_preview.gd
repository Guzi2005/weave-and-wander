extends Node3D

const Doll = preload("res://scripts/volume_doll.gd")
const Art = preload("res://scripts/paper_art.gd")
var dolls: Array[VolumeDoll] = []
var camera: Camera3D
var rotating := false
var walking := false
var recording := false
var rotation_angle := 0.0
var elapsed := 0.0


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	recording = "--capture" in arguments or "--record-motion" in arguments
	if recording:
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1600, 900)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("e9eff0")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("e5eff2")
	settings.ambient_light_energy = 0.38
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 0.45
	light.light_color = Color("fff2df")
	light.shadow_enabled = true
	add_child(light)
	var floor_mesh := Art.box("Stage", Vector3(30, 0.16, 16), Color("cbdce0"), Vector3(0, -0.09, 0))
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("cbdce0")
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.9
	camera.position = Vector3(0, 3.25, 12)
	add_child(camera)
	camera.look_at(Vector3(0, 1.43, 0))
	camera.current = true
	for index in 4:
		var doll := Doll.new()
		add_child(doll)
		doll.configure({"hair": [2, 0, 1, 1][index], "outfit": [1, 0, 2, 0][index],
			"palette": [2, 0, 3, 3][index], "skin": [1, 0, 2, 0][index], "hair_color": [2, 1, 0, 1][index],
			"reference": index == 3})
		doll.position.x = (index - 1.5) * 1.65
		doll.body_rig.rotation.y = [-0.3, 0.0, 0.48, 0.8][index]
		dolls.append(doll)
	if recording:
		_record.call_deferred()
	else:
		_setup_controls()
		get_viewport().size_changed.connect(_fit)
		_fit()


func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	camera.size = maxf(3.9, 7.5 * size.y / size.x)


func _setup_controls() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var row := HBoxContainer.new()
	row.position = Vector2(24, 20)
	row.add_theme_constant_override("separation", 12)
	canvas.add_child(row)
	_button(row, "返回店铺", func() -> void: get_tree().change_scene_to_file("res://main.tscn"))
	_button(row, "摩梭套装研究台", func() -> void: get_tree().change_scene_to_file("res://scenes/wiki_asset_preview.tscn"))
	_button(row, "乌克兰套装研究台", func() -> void: get_tree().change_scene_to_file("res://scenes/ukrainian_asset_preview.tscn"))
	_button(row, "转台", func() -> void: rotating = not rotating)
	_button(row, "走动", func() -> void: walking = not walking)
	_button(row, "换发型", func() -> void:
		for doll in dolls: doll.set_hair_style(doll.hair_style + 1))
	_button(row, "换衣服", func() -> void:
		for doll in dolls: doll.set_outfit_style(doll.outfit_style + 1))
	_button(row, "换配色", func() -> void:
		for doll in dolls: doll.set_palette(doll.palette_index + 1))


func _button(parent: Control, label: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(92, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(action)
	parent.add_child(button)


func _process(delta: float) -> void:
	if recording:
		return
	elapsed += delta
	if rotating:
		rotation_angle += delta * 0.55
	for index in dolls.size():
		var doll := dolls[index]
		if walking:
			doll._moving = true
			doll._heading = Vector3(sin(rotation_angle), 0, cos(rotation_angle))
			doll._travel_distance += delta * 0.9
		else:
			doll._moving = false
		doll._update_puppet_motion(delta)
		doll.body_rig.rotation.y = rotation_angle + [-0.3, 0.0, 0.48, 0.8][index]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		rotation_angle += event.relative.x * 0.012
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://main.tscn")


func _record() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_dir := ProjectSettings.globalize_path("res://captures")
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("dolls_3d.png"))
	for doll in dolls:
		doll.body_rig.rotation.y = PI * 0.5
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("dolls_3d_side.png"))
	for doll in dolls:
		doll.body_rig.rotation.y = PI
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("dolls_3d_back.png"))
	for i in 4:
		dolls[i].body_rig.rotation.y = [-0.3, 0.0, 0.48, 0.8][i]
		dolls[i].rig.animate(0, 0, "sewing", 0.25)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("dolls_3d_work.png"))
	for doll in dolls:
		doll.rig.animate(0, 0, "idle", 0)
	for i in 3:
		dolls[i].hide()
	dolls[3].position.x = 0
	dolls[3].body_rig.rotation.y = PI * 0.5
	camera.size = 3.2
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("reference_profile.png"))
	dolls[3].hide()
	dolls[1].show()
	dolls[1].position.x = 0
	dolls[1].body_rig.rotation.y = 0.15
	camera.size = 1.65
	camera.position = Vector3(0, 2.2, 12)
	camera.look_at(Vector3(0, 1.64, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("shoulder_detail.png"))
	camera.position = Vector3(0, 3.25, 12)
	camera.look_at(Vector3(0, 1.43, 0))
	camera.size = 3.9
	for i in 4:
		dolls[i].show()
		dolls[i].position.x = (i - 1.5) * 1.65
	if "--record-motion" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(output_dir.path_join("motion"))
		for frame in 96:
			for index in dolls.size():
				var doll := dolls[index]
				doll._moving = true
				doll._heading = Vector3.RIGHT
				doll._travel_distance += 0.9 / 24.0
				doll._update_puppet_motion(1.0 / 24.0)
				doll.body_rig.rotation.y = TAU * frame / 96.0 + [-0.3, 0.0, 0.48, 0.8][index]
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output_dir.path_join("motion/frame_%03d.png" % frame))
			await get_tree().process_frame
	print("VOLUME_PREVIEW_PASS ", get_viewport().get_texture().get_image().get_size())
	get_tree().quit()
