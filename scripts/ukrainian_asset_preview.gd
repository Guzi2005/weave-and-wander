extends Node3D

const Doll = preload("res://scripts/ukrainian_doll.gd")
const Motion = preload("res://scripts/wiki_preview_motion.gd")

var doll: Node3D
var motion := Motion.new()
var camera: Camera3D
var status: Label

var camera_target := Vector3(0, 1.35, 0)
var camera_target_pos := Vector3(0, 1.45, 7.0)
var camera_target_size := 3.4
var target_angle := 0.0
var manual_turntable := false

func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1440, 900)
	get_viewport().msaa_3d = Viewport.MSAA_4X

	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#e9eff0")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#e5eff2")
	world.environment.ambient_light_energy = 0.38
	add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 0.45
	light.light_color = Color("#fff2df")
	light.shadow_enabled = true
	add_child(light)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#cbdce0")
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material_override = mat
	floor_mesh.position = Vector3(0, -0.002, 0)
	add_child(floor_mesh)

	_spawn_doll()

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_target_size
	camera.position = camera_target_pos
	camera.near = 0.02
	camera.far = 40.0
	add_child(camera)
	camera.look_at(camera_target)
	camera.current = true

	_setup_ui()
	if "--capture" in OS.get_cmdline_user_args():
		_do_capture.call_deferred()


func _do_capture() -> void:
	for tick in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute("res://captures/ukrainian_preview")
		img.save_png("res://captures/ukrainian_preview/workbench_ui.png")
	get_tree().quit(0)


func _spawn_doll() -> void:
	if doll != null:
		doll.free()
		doll = null
	doll = Doll.new()
	add_child(doll)
	doll.configure({"outfit": 0, "hair": 3, "palette": 0, "shoe_style": 1})
	doll.set_process(false)
	motion.apply(doll)


func _process(delta: float) -> void:
	if motion.mode == "spin":
		motion.step(delta)
		motion.apply(doll)
	elif motion.mode in ["walk", "dance", "run", "reach"]:
		motion.step(delta)
		motion.apply(doll)
	else:
		if doll != null and doll.body_rig != null:
			motion.step(delta)
			doll.rig.animate(0, 0, "idle", motion.elapsed)
			doll.body_rig.rotation.y = lerp_angle(doll.body_rig.rotation.y, target_angle, clampf(delta * 8.0, 0.0, 1.0))

	# Smooth camera interpolation
	camera.size = lerpf(camera.size, camera_target_size, clampf(delta * 6.0, 0.0, 1.0))
	camera.position = camera.position.lerp(camera_target_pos, clampf(delta * 6.0, 0.0, 1.0))
	camera.look_at(camera_target)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var theme := Theme.new()
	theme.default_font_size = 13

	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color("#f6f4edee")
	panel_box.border_color = Color("#cbd2d6")
	panel_box.set_border_width_all(1)
	panel_box.set_corner_radius_all(4)
	panel_box.content_margin_left = 14
	panel_box.content_margin_right = 14
	panel_box.content_margin_top = 10
	panel_box.content_margin_bottom = 10

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color("#ffffff")
	btn_normal.border_color = Color("#b8c2c8")
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(3)
	btn_normal.content_margin_left = 10
	btn_normal.content_margin_right = 10
	btn_normal.content_margin_top = 5
	btn_normal.content_margin_bottom = 5

	theme.set_stylebox("panel", "PanelContainer", panel_box)
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_color("font_color", "Label", Color("#263238"))
	theme.set_color("font_color", "Button", Color("#263238"))
	theme.set_color("font_color", "CheckBox", Color("#263238"))
	theme.set_color("font_pressed_color", "CheckBox", Color("#1b2529"))
	theme.set_color("font_hover_color", "CheckBox", Color("#10181c"))

	# Top Navigation Bar
	var top_panel := PanelContainer.new()
	top_panel.theme = theme
	top_panel.position = Vector2(20, 18)
	layer.add_child(top_panel)

	var top_box := HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 10)
	top_panel.add_child(top_box)

	var title := Label.new()
	title.text = "乌克兰传统服饰 · 数字人文研究台 (WW-UKR-001)"
	title.add_theme_font_size_override("font_size", 15)
	top_box.add_child(title)

	var sep := VSeparator.new()
	top_box.add_child(sep)

	_btn(top_box, "返回换装台", func(): get_tree().change_scene_to_file("res://tests/appearance_preview.tscn"))
	_btn(top_box, "返回店铺", func(): get_tree().change_scene_to_file("res://main.tscn"))
	_btn(top_box, "摩梭研究台", func(): get_tree().change_scene_to_file("res://scenes/wiki_asset_preview.tscn"))

	# Left Sidebar: View & Camera Controls
	var left_panel := PanelContainer.new()
	left_panel.theme = theme
	left_panel.position = Vector2(20, 80)
	layer.add_child(left_panel)

	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_box)

	var lbl_cam := Label.new()
	lbl_cam.text = "镜头预设 (Camera Presets)"
	left_box.add_child(lbl_cam)

	var btn_full := _btn(left_box, "全身视角 (Full Figure)", func():
		camera_target_size = 3.4
		camera_target = Vector3(0, 1.35, 0)
		camera_target_pos = Vector3(0, 1.45, 7.0)
	)

	var btn_waist := _btn(left_box, "高腰腰带 (High Sash & Knot)", func():
		camera_target_size = 1.35
		camera_target = Vector3(0, 1.38, 0)
		camera_target_pos = Vector3(0, 1.48, 5.0)
	)

	var btn_neck := _btn(left_box, "领口与珍珠领圈 (Collar & Beads)", func():
		camera_target_size = 0.8
		camera_target = Vector3(0, 1.84, 0)
		camera_target_pos = Vector3(0, 1.86, 3.5)
	)

	var btn_skirt := _btn(left_box, "经向彩条罩裙 (Striped Skirt)", func():
		camera_target_size = 1.8
		camera_target = Vector3(0, 0.80, 0)
		camera_target_pos = Vector3(0, 0.85, 5.0)
	)

	left_box.add_child(HSeparator.new())

	var lbl_motion := Label.new()
	lbl_motion.text = "旋转与动作 (Motion)"
	left_box.add_child(lbl_motion)

	_btn(left_box, "旋转转台 (Turntable Spin)", func():
		motion.mode = "idle" if motion.mode == "spin" else "spin"
		motion.spin_speed = 35.0
	)

	_btn(left_box, "行走动画 (Walk Cycle)", func():
		motion.mode = "idle" if motion.mode == "walk" else "walk"
	)

	_btn(left_box, "欢庆跳跃舞 (Hopak Folk Dance)", func():
		motion.mode = "idle" if motion.mode == "dance" else "dance"
	)

	_btn(left_box, "大步奔跑 (Dynamic Sprint)", func():
		motion.mode = "idle" if motion.mode == "run" else "run"
	)

	_btn(left_box, "探身采摘 (High Reach)", func():
		motion.mode = "idle" if motion.mode == "reach" else "reach"
	)

	var angle_row := HBoxContainer.new()
	left_box.add_child(angle_row)
	_btn(angle_row, "正面", func():
		motion.mode = "idle"
		target_angle = 0.0
	)
	_btn(angle_row, "斜侧", func():
		motion.mode = "idle"
		target_angle = PI * 0.25
	)
	_btn(angle_row, "正侧面", func():
		motion.mode = "idle"
		target_angle = PI * 0.5
	)
	_btn(angle_row, "背面", func():
		motion.mode = "idle"
		target_angle = PI
	)

	# Right Sidebar: Component Visibility Toggles
	var right_panel := PanelContainer.new()
	right_panel.theme = theme
	right_panel.position = Vector2(1080, 80)
	right_panel.custom_minimum_size = Vector2(340, 0)
	layer.add_child(right_panel)

	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_box)

	var lbl_parts := Label.new()
	lbl_parts.text = "档案部件拆解 (Components)"
	right_box.add_child(lbl_parts)

	_toggle(right_box, "衬衫 (Linen Blouse)", ["UkrShirt", "UkrShirtCollar", "UkrCuffs"])
	_toggle(right_box, "颈饰 (Choker & Ribbon)", ["UkrNeckBow", "UkrBeads"])
	_toggle(right_box, "腰带与流苏 (Sash & Tassels)", ["UkrSashWrap", "UkrSashKnot", "UkrSashTailL", "UkrSashTailR", "UkrTasselL", "UkrTasselR"])
	_toggle(right_box, "前围裙 (Mauve Apron)", ["UkrApron"])
	_toggle(right_box, "彩条罩裙 (Overskirt)", ["UkrOverskirtWoven"])
	_toggle(right_box, "白衬裙 (Underskirt)", ["UkrUnderskirt"])
	_toggle(right_box, "鞋口白袜面 (Sock Instep)", ["WhiteSockInstep", "WhiteSockInstep2"])
	var sock_label := Label.new()
	sock_label.text = "袜长 · 船袜 → 长筒袜 → 连裤袜"
	right_box.add_child(sock_label)
	var sock_length := HSlider.new()
	sock_length.min_value = 0.0
	sock_length.max_value = 1.0
	sock_length.step = .01
	sock_length.value = doll.hosiery.length
	right_box.add_child(sock_length)
	var sock_pattern := OptionButton.new()
	for label in ["素色", "罗纹", "横条纹", "圆点"]:
		sock_pattern.add_item(label)
	sock_pattern.select(doll.hosiery.pattern)
	right_box.add_child(sock_pattern)
	var update_socks := func():
		doll.set_hosiery({"enabled": true, "length": sock_length.value, "pattern": sock_pattern.selected})
		motion.apply(doll)
	sock_length.drag_ended.connect(func(_changed: bool): update_socks.call())
	sock_pattern.item_selected.connect(func(_index: int): update_socks.call())


func _btn(parent: Control, text: String, on_click: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_click)
	parent.add_child(b)
	return b


func _toggle(parent: Control, label: String, part_names: Array[String]) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = true
	cb.toggled.connect(func(pressed: bool):
		if doll == null or doll.body_rig == null:
			return
		for child in doll.body_rig.find_children("*", "MeshInstance3D", true, false):
			if str(child.name) in part_names:
				child.visible = pressed
	)
	parent.add_child(cb)
	return cb
