extends Node3D
const Doll = preload("res://scripts/mosuo_doll.gd")
const Motion = preload("res://scripts/wiki_preview_motion.gd")
const BeadBundle = preload("res://components/seed_bead_bundle.gd")
const Braid = preload("res://components/path_braid.gd")
const Flower = preload("res://components/parametric_flower.gd")
var doll: Node3D
var motion = Motion.new()
var camera: Camera3D
var status: Label
var pause_button: Button
var recording := false
var beads: BeadBundle
var braid: Braid
var flower: Flower
var _flower_color_button: ColorPickerButton
var flower_angles := Vector3.ZERO
var flower_height := .74
var headwear_position := Vector3(0,.055,-.025)
var headwear_angles := Vector3(-8,0,-4)
var _param_sliders: Array[Dictionary] = []
var _bead_color_button: ColorPickerButton
var _braid_color_button: ColorPickerButton
var _material_option: OptionButton
var _repeat_option: OptionButton

func _ready() -> void:
	recording = "--capture" in OS.get_cmdline_user_args() or "--record-motion" in OS.get_cmdline_user_args()
	beads = BeadBundle.photo_001()
	braid = Braid.photo_001()
	flower = load("res://assets/collections/mosuo_flower.tres").duplicate()
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1440, 900)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("eeeadf")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("fff5e6")
	world.environment.ambient_light_energy = .22
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	# Broad studio reflection panels give silk and the silver-thread mask distinct
	# moving highlights; a uniform sky cannot make a metallic weave readable.
	var sky_material := PanoramaSkyMaterial.new()
	var panorama := Image.create(256,128,false,Image.FORMAT_RGBF)
	for y in 128:
		for x in 256:
			var uv := Vector2(x/256.0,y/128.0)
			var key_panel := (1.0-smoothstep(.055,.10,absf(uv.x-.22)))*(1.0-smoothstep(.12,.19,absf(uv.y-.40)))
			var rim_panel := (1.0-smoothstep(.025,.065,absf(uv.x-.72)))*(1.0-smoothstep(.10,.21,absf(uv.y-.39)))
			panorama.set_pixel(x,y,Color(.045,.05,.065)+Color(2.8,2.65,2.45)*key_panel+Color(1.8,2.0,2.3)*rim_panel)
	sky_material.panorama = ImageTexture.create_from_image(panorama)
	sky.sky_material = sky_material
	world.environment.sky = sky
	world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = .65
	light.shadow_enabled = true
	add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("e1dbca")
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	_spawn_doll()
	camera = Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.65
	camera.position = Vector3(0, 2.55, 7)
	camera.look_at(Vector3(0, 1.45, 0))
	camera.current = true
	_setup_ui()
	if recording:
		_capture.call_deferred()

## Root integration contract: bead_parameters / braid_parameters are set on the doll
## before configure(); the motion rig survives because the Motion object is kept and
## re-applied to the freshly built doll.
func _spawn_doll() -> void:
	if doll != null:
		doll.free()
		doll = null
	doll = Doll.new()
	add_child(doll)
	doll.set("bead_parameters", beads)
	doll.set("headwear_position",headwear_position)
	doll.set("headwear_rotation_degrees",headwear_angles)
	doll.set("flower_parameters",flower)
	doll.set("flower_mount_position",Vector3(.27,flower_height,.12))
	doll.set("flower_mount_rotation",Vector3(0,0,-12)+flower_angles)
	if "braid_parameters" in doll:
		doll.set("braid_parameters", braid)
	doll.configure({"outfit":0, "hair":0, "palette":0})
	doll.set_process(false)
	if not recording:
		motion.apply(doll)

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var full := Control.new()
	full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(full)
	var theme := Theme.new()
	theme.default_font_size = 12
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("f4f1e9")
	panel.border_color = Color("c9c5b9")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(0)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	for type in ["PanelContainer", "Button", "OptionButton"]:
		theme.set_stylebox("panel" if type == "PanelContainer" else "normal", type, panel)
	theme.set_color("font_color", "Label", Color("293c40"))
	theme.set_color("font_color", "Button", Color("293c40"))
	theme.set_color("font_color", "OptionButton", Color("293c40"))
	full.theme = theme
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 90
	full.add_child(header)
	var heading := VBoxContainer.new()
	header.add_child(heading)
	var title := Label.new()
	title.text = "W&W Wiki   /   游戏资产研究台"
	title.add_theme_font_size_override("font_size", 18)
	heading.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "摩梭人照片参考套装 · mosuo_photo_001    /    头饰（含紫色米珠串与假发辫冠） · 红底花纹上衣 · 浅蓝长褶裙"
	heading.add_child(subtitle)
	var left := PanelContainer.new()
	left.position = Vector2(20,110)
	left.custom_minimum_size = Vector2(240,0)
	full.add_child(left)
	var refs := VBoxContainer.new()
	refs.add_theme_constant_override("separation",10)
	left.add_child(refs)
	var ref_label := Label.new()
	ref_label.text = "参考与出处  /  WW-MOS-001"
	refs.add_child(ref_label)
	var photo := TextureRect.new()
	photo.texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://Docs/wiki-concept-2026-10-28/mosuo-example/source-user-upload.png")))
	photo.custom_minimum_size = Vector2(215,430)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	refs.add_child(photo)
	var source := Label.new()
	source.text = "用户提供照片与归属\n米珠材质：用户补充说明\n年代 / 地点 / 原始出处：待补\n鞋履：通用基础版型，无文化属性"
	source.add_theme_font_size_override("font_size",12)
	refs.add_child(source)
	var controls := PanelContainer.new()
	controls.anchor_left = 1.0
	controls.anchor_right = 1.0
	controls.anchor_bottom = 1.0
	controls.offset_left = -310
	controls.offset_right = -20
	controls.offset_top = 110
	controls.offset_bottom = -50
	full.add_child(controls)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var label := Label.new()
	label.text = "动画与视角"
	column.add_child(label)
	var mode := OptionButton.new()
	mode.fit_to_longest_item = false
	mode.clip_text = true
	for entry in ["待机站立 · 呼吸", "原地行走", "转圈", "手持鞋垫 · 姿态研究", "坐下 · 衣料检查", "坐下 → 躺卧"]:
		mode.add_item(entry)
	mode.item_selected.connect(func(index: int): motion.reset(); motion.mode = ["idle","walk","spin","handwork","sit","lie"][index])
	column.add_child(mode)
	_slider(column, "步频倍率", .25, 2.0, .05, 1.0, func(value: float): motion.pace = value)
	var presets := HBoxContainer.new()
	column.add_child(presets)
	for entry in [["慢走",.55],["常速",1.0],["快走",1.65]]:
		_button(presets,entry[0],func(): motion.mode = "walk"; motion.pace = entry[1]; mode.select(1); _pace_slider.value = entry[1])
	_slider(column, "转圈速度 °/s", 0, 120, 1, 35, func(value: float): motion.spin_speed = value)
	_slider(column, "不匀速程度", 0, .9, .05, 0, func(value: float): motion.nonuniformity = value)
	pause_button = _button(column,"暂停",func(): motion.paused = not motion.paused; pause_button.text = "继续" if motion.paused else "暂停")
	_button(column,"重置视角与时间",func(): motion.reset())
	var views := HBoxContainer.new()
	column.add_child(views)
	for entry in [["正面",0.0],["侧面",PI/2],["背面",PI]]:
		_button(views,entry[0],func(): motion.angle = entry[1])
	status = Label.new()
	status.add_theme_font_size_override("font_size",12)
	column.add_child(status)
	_setup_adornment_panel(column)
	_button(column,"本地 Wiki",func(): OS.shell_open("http://127.0.0.1:4318/#/workshop"))
	_button(column,"返回店铺",func(): get_tree().change_scene_to_file("res://main.tscn"))
	var footer := Label.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -40
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.text = "实际游戏模型 · 基于照片的数字改编    |    背面、固定方式含推演    |    拖动模型区域旋转"
	full.add_child(footer)

func _setup_adornment_panel(column: VBoxContainer) -> void:
	var divider := HSeparator.new()
	column.add_child(divider)
	var head := Label.new()
	head.text = "头饰参数 / Adornments"
	head.add_theme_font_size_override("font_size", 13)
	column.add_child(head)
	var note := Label.new()
	note.text = "预览参数仅本次会话有效、不写盘。持久化与路径控制点：在 Inspector 中编辑 assets/collections/mosuo_seed_beads.tres 与 mosuo_braid.tres（Curve3D 控制点可直接拖动）。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color("6a6f66"))
	column.add_child(note)
	var mount_label := Label.new()
	mount_label.text = "整组头饰佩戴 / 位置与角度"
	column.add_child(mount_label)
	_param_slider(column,"佩戴高度",-.10,.20,.005,headwear_position.y,func(v: float): headwear_position.y = v)
	_param_slider(column,"前后位置",-.15,.15,.005,headwear_position.z,func(v: float): headwear_position.z = v)
	_param_slider(column,"左右位置",-.15,.15,.005,headwear_position.x,func(v: float): headwear_position.x = v)
	_param_slider(column,"前后倾角",-30,30,1,headwear_angles.x,func(v: float): headwear_angles.x = v)
	_param_slider(column,"左右倾角",-25,25,1,headwear_angles.z,func(v: float): headwear_angles.z = v)
	_param_slider(column,"水平转角",-45,45,1,headwear_angles.y,func(v: float): headwear_angles.y = v)
	_button(column,"应用佩戴位置",_spawn_doll)
	var bead_label := Label.new()
	bead_label.text = "米珠 · Seed beads"
	column.add_child(bead_label)
	_bead_color_button = _color_row(column, "珠色", beads.bead_color, func(c: Color): beads.bead_color = c)
	_param_slider(column, "珠径", .002, .012, .0005, beads.bead_diameter, func(v: float): beads.bead_diameter = v)
	_param_slider(column, "串数", 4, 72, 1, beads.strand_count, func(v: float): beads.strand_count = int(v))
	_param_slider(column, "紧密度", .6, 1.5, .05, beads.tightness, func(v: float): beads.tightness = v)
	_material_option = OptionButton.new()
	_material_option.fit_to_longest_item = false
	_material_option.clip_text = true
	for entry in ["材质 · glass 玻璃", "材质 · pearl 珍珠", "材质 · metal 金属", "材质 · matte 哑光"]:
		_material_option.add_item(entry)
	_material_option.item_selected.connect(func(index: int): beads.bead_preset = ["glass","pearl","metal","matte"][index])
	column.add_child(_material_option)
	_repeat_option = OptionButton.new()
	_repeat_option.fit_to_longest_item = false
	_repeat_option.clip_text = true
	_repeat_option.add_item("重复单元 · 单色米珠")
	_repeat_option.add_item("重复单元 · 3小珍珠+1大珍珠")
	_repeat_option.item_selected.connect(func(index: int): beads.repeat_unit = [] if index == 0 else _pearl_repeat_unit())
	column.add_child(_repeat_option)
	var braid_label := Label.new()
	braid_label.text = "辫冠 · False braid"
	column.add_child(braid_label)
	_braid_color_button = _color_row(column, "辫色", braid.hair_color, func(c: Color): braid.hair_color = c)
	_param_slider(column, "辫宽", .03, .14, .001, braid.width, func(v: float): braid.width = v)
	_param_slider(column, "辫厚", .02, .10, .001, braid.depth, func(v: float): braid.depth = v)
	_param_slider(column, "交叉节距", .07, .32, .005, braid.pitch, func(v: float): braid.pitch = v)
	var flower_label := Label.new()
	flower_label.text = "头花 / 朝上花冠 · 独立挂点"
	column.add_child(flower_label)
	_flower_color_button = _color_row(column,"花色",flower.petal_color,func(c: Color): flower.petal_color = c)
	_param_slider(column,"花冠半径",.04,.16,.005,flower.radius,func(v: float): flower.radius = v)
	_param_slider(column,"花瓣层数",1,8,1,flower.layers,func(v: float): flower.layers = int(v))
	_param_slider(column,"每层瓣数",3,16,1,flower.petals_per_layer,func(v: float): flower.petals_per_layer = int(v))
	_param_slider(column,"花瓣杯深",.01,.10,.005,flower.cup_depth,func(v: float): flower.cup_depth = v)
	_param_slider(column,"挂点高度",.60,.84,.01,flower_height,func(v: float): flower_height = v)
	_param_slider(column,"花冠前后倾角",-60,60,1,0,func(v: float): flower_angles.x = v)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "应用并重筑", _spawn_doll)
	_button(actions, "重置参数", _reset_adornments)

func _pearl_repeat_unit() -> Array[Dictionary]:
	var unit: Array[Dictionary] = []
	for i in 3:
		unit.append({"diameter_scale":.72,"length_scale":.72,"color":Color("e8e2d4"),"material":"pearl"})
	unit.append({"diameter_scale":1.55,"length_scale":1.35,"color":Color("f2ecdd"),"material":"pearl"})
	return unit

func _reset_adornments() -> void:
	beads = BeadBundle.photo_001()
	braid = Braid.photo_001()
	flower = load("res://assets/collections/mosuo_flower.tres").duplicate()
	_flower_color_button.color = flower.petal_color
	_bead_color_button.color = beads.bead_color
	_braid_color_button.color = braid.hair_color
	_material_option.select(0)
	_repeat_option.select(0)
	for entry in _param_sliders:
		(entry.slider as HSlider).value = entry.default
	_spawn_doll()

func _color_row(parent: Control, text: String, value: Color, action: Callable) -> ColorPickerButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(52, 20)
	picker.edit_alpha = false
	picker.color = value
	picker.color_changed.connect(action)
	row.add_child(picker)
	return picker

var _pace_slider: HSlider
func _slider(parent: Control, text: String, minimum: float, maximum: float, step: float, value: float, action: Callable) -> void:
	var label := Label.new()
	label.text = "%s  %.2f" % [text,value]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 230
	slider.value_changed.connect(func(v: float): label.text = "%s  %.2f" % [text,v]; action.call(v))
	parent.add_child(slider)
	if text == "步频倍率": _pace_slider = slider

func _param_slider(parent: Control, text: String, minimum: float, maximum: float, step: float, value: float, action: Callable) -> void:
	var label := Label.new()
	label.text = "%s  %.3f" % [text,value]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 210
	slider.value_changed.connect(func(v: float): label.text = "%s  %.3f" % [text,v]; action.call(v))
	parent.add_child(slider)
	_param_sliders.append({"slider":slider, "default":value})

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _process(delta: float) -> void:
	if recording: return
	motion.step(delta)
	motion.apply(doll)
	status.text = "步频 ×%.2f\n当前转速 %.1f°/s" % [motion.pace,motion.angular_velocity]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		motion.angle += event.relative.x*.01
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://main.tscn")

func _capture() -> void:
	var output := ProjectSettings.globalize_path("res://captures/mosuo_preview")
	DirAccess.make_dir_recursive_absolute(output)
	for tick in 6: await get_tree().process_frame
	for entry in [["front",0.0],["quarter",.6],["back",PI]]:
		motion.angle = entry[1]
		motion.apply(doll)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(entry[0]+".png"))
	motion.mode = "handwork"
	motion.angle = 0.0
	motion.apply(doll)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("handwork.png"))
	camera.size = 1.25
	camera.position = Vector3(0,3.2,5)
	camera.look_at(Vector3(0,2.45,0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("head-detail.png"))
	motion.mode = "idle"
	motion.angle = .3
	motion.apply(doll)
	camera.size = 1.65
	camera.position = Vector3(0,1.25,5)
	camera.look_at(Vector3(0,1.02,0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("textile-detail.png"))
	camera.size = 3.65
	camera.position = Vector3(0,2.55,7)
	camera.look_at(Vector3(0,1.45,0))
	if "--record-motion" in OS.get_cmdline_user_args():
		for mode_name in ["idle","walk","spin"]:
			motion.reset()
			motion.mode = mode_name
			motion.nonuniformity = .65
			for frame in 48:
				motion.step(1.0/12.0)
				motion.apply(doll)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(output.path_join("%s_%03d.png" % [mode_name,frame]))
	print("MOSUO_PREVIEW_CAPTURE_PASS")
	get_tree().quit()
