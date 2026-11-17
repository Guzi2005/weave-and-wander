extends Node3D

const GrandmaDoll := preload("res://scripts/characters/grandma_doll.gd")
const GranddaughterDoll := preload("res://scripts/characters/granddaughter_doll.gd")
const CrafterAuntieDoll := preload("res://scripts/characters/crafter_auntie_doll.gd")
const PostmanDoll := preload("res://scripts/characters/postman_doll.gd")

const SHOP_SCENE_PATH := "res://scenes/shop_room.tscn"
const STAGE_SKY_COLOR := Color("e9eff0")
const STAGE_FLOOR_COLOR := Color("cbdce0")
const AMBIENT_COLOR := Color("e5eff2")
const SUN_COLOR := Color("fff2df")
const LINEUP_POSITIONS := [-2.28, -0.76, 0.76, 2.28]

var _dolls: Array = []
var _doll_configs := [
	{"name": "奶奶", "cls": GrandmaDoll, "angle": 0.0},
	{"name": "孙女", "cls": GranddaughterDoll, "angle": 0.0},
	{"name": "摊主", "cls": CrafterAuntieDoll, "angle": 0.0},
	{"name": "邮差", "cls": PostmanDoll, "angle": 0.0},
]

var _camera: Camera3D
var _turntable := false
var _walking := false
var _pose_phase := 0.0
var _yaw := 0.0
var _view_index := 0
var _expr_index := 0
var _dragging := false
var _capture_mode := false


func _ready() -> void:
	_capture_mode = "--capture" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_args()
	if not DisplayServer.get_name().begins_with("headless"):
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1600, 900)
		get_window().title = "四角色中体型展示（p2 游戏样式）"

	_setup_stage()
	_setup_camera()
	_spawn_dolls()
	_setup_ui()

	if _capture_mode:
		call_deferred("_run_captures")


func _setup_stage() -> void:
	var env := WorldEnvironment.new()
	env.name = "StageEnvironment"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = STAGE_SKY_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = AMBIENT_COLOR
	settings.ambient_light_energy = 0.38
	env.environment = settings
	add_child(env)

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 0.45
	light.light_color = SUN_COLOR
	light.shadow_enabled = true
	add_child(light)

	var stage := MeshInstance3D.new()
	stage.name = "Stage"
	var box := BoxMesh.new()
	box.size = Vector3(32.0, 0.16, 18.0)
	stage.mesh = box
	stage.position = Vector3(0.0, -0.09, 0.0)
	var stage_mat := StandardMaterial3D.new()
	stage_mat.albedo_color = STAGE_FLOOR_COLOR
	stage_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stage_mat.roughness = 1.0
	stage.material_override = stage_mat
	add_child(stage)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "StudioCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.05
	_camera.position = Vector3(0.0, 3.25, 12.0)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 1.42, 0.0), Vector3.UP)


func _spawn_dolls() -> void:
	for i in _doll_configs.size():
		var cfg: Dictionary = _doll_configs[i]
		var doll_script = cfg["cls"]
		var doll = doll_script.new()
		doll.position = Vector3(float(LINEUP_POSITIONS[i]), 0.0, 0.0)
		add_child(doll)
		doll.configure({"name": cfg["name"]})
		if doll.body_rig != null:
			doll.body_rig.rotation.y = float(cfg["angle"])
		if doll.rig != null and doll.rig.has_method("animate"):
			doll.rig.animate(0.0, 0.0, "idle", 0.0)
		_add_ground_shadow_if_missing(doll, i)
		_dolls.append(doll)


func _add_ground_shadow_if_missing(doll: Node3D, index: int) -> void:
	if doll.find_child("*Shadow*", true, false) != null:
		return
	var shadow := MeshInstance3D.new()
	shadow.name = "GroundShadow_%d" % index
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.45
	cyl.height = 0.004
	cyl.radial_segments = 32
	shadow.mesh = cyl
	shadow.position = Vector3(doll.position.x, -0.007, doll.position.z + 0.02)
	shadow.scale = Vector3(1.15, 1.0, 0.52)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.72, 0.75, 0.48)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = mat
	add_child(shadow)


func _setup_ui() -> void:
	var hud := CanvasLayer.new()
	hud.name = "PreviewHUD"
	add_child(hud)

	var bar := HBoxContainer.new()
	bar.position = Vector2(28, 22)
	bar.add_theme_constant_override("separation", 12)
	hud.add_child(bar)

	var back_btn := _make_button("返回店铺")
	back_btn.pressed.connect(func() -> void:
		if ResourceLoader.exists(SHOP_SCENE_PATH):
			get_tree().change_scene_to_file(SHOP_SCENE_PATH)
	)
	bar.add_child(back_btn)

	var turn_btn := _make_button("转台")
	turn_btn.pressed.connect(func() -> void:
		_turntable = not _turntable
	)
	bar.add_child(turn_btn)

	var walk_btn := _make_button("走动")
	walk_btn.pressed.connect(func() -> void:
		_walking = not _walking
		if not _walking:
			_apply_pose(0.0, 0.0, 0.0)
	)
	bar.add_child(walk_btn)

	var view_btn := _make_button("换视角")
	view_btn.pressed.connect(func() -> void:
		var angles := [0.0, -0.48, PI * 0.5, PI, PI * 1.5]
		_view_index = (_view_index + 1) % angles.size()
		_yaw = angles[_view_index]
		_set_all_yaw(_yaw)
	)
	bar.add_child(view_btn)

	var expr_btn := _make_button("换表情")
	expr_btn.pressed.connect(func() -> void:
		var exprs := ["content", "happy", "thinking"]
		_expr_index = (_expr_index + 1) % exprs.size()
		for doll in _dolls:
			if doll.has_method("set_expression"):
				doll.set_expression(exprs[_expr_index])
	)
	bar.add_child(expr_btn)


func _make_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(92, 44)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", Color("f7f9fa"))
	btn.add_theme_color_override("font_hover_color", Color("ffffff"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("707376")
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate()
	hover.bg_color = Color("82868a")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("5e6164")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	return btn


func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.01
		_set_all_yaw(_yaw)


func _process(delta: float) -> void:
	if _capture_mode:
		return
	if _turntable:
		_yaw += delta * 0.65
		_set_all_yaw(_yaw)
	if _walking:
		_pose_phase += delta * 4.2
		_apply_pose(_pose_phase, 1.0, _pose_phase)


func _set_all_yaw(yaw: float) -> void:
	for doll in _dolls:
		if doll.body_rig != null:
			doll.body_rig.rotation.y = yaw


func _apply_pose(wave: float, walk_blend: float, phase: float) -> void:
	for doll in _dolls:
		if doll.rig != null and doll.rig.has_method("animate"):
			doll.rig.animate(wave, walk_blend, "idle", phase)


func _run_captures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	await _wait_frames(3)

	# 1. Straight front p2 studio lineup
	_set_camera_view(Vector3(0.0, 3.25, 12.0), Vector3(0.0, 1.42, 0.0), 4.05)
	_set_all_yaw(0.0)
	_apply_pose(0.0, 0.0, 0.0)
	await _save_capture("res://captures/four_characters_3d_front.png")

	# 2. Slight three-quarter turn (matches p2 preview turn ~26 deg)
	_set_all_yaw(-0.46)
	await _save_capture("res://captures/four_characters_3d_three_quarter.png")

	# 3. Profile side view (+90 deg)
	_set_all_yaw(PI * 0.5)
	await _save_capture("res://captures/four_characters_3d_side.png")

	# 4. Back view (180 deg)
	_set_all_yaw(PI)
	await _save_capture("res://captures/four_characters_3d_back.png")

	# 5. Mid-stride walk pose at three-quarter turn
	_set_all_yaw(-0.42)
	_apply_pose(1.35, 1.0, 1.35)
	await _save_capture("res://captures/four_characters_3d_walk.png")

	# 6. Close-up pair 1 front (Grandma & Granddaughter)
	_apply_pose(0.0, 0.0, 0.0)
	_set_all_yaw(0.0)
	_set_camera_view(Vector3(-1.52, 2.75, 12.0), Vector3(-1.52, 1.38, 0.0), 3.05)
	await _save_capture("res://captures/closeup_front_grandma_granddaughter.png")

	# 7. Close-up pair 2 front (Crafter Auntie & Postman)
	_set_camera_view(Vector3(1.52, 2.75, 12.0), Vector3(1.52, 1.38, 0.0), 3.05)
	await _save_capture("res://captures/closeup_front_auntie_postman.png")

	# 8. Close-up pair 1 back
	_set_all_yaw(PI)
	_set_camera_view(Vector3(-1.52, 2.75, 12.0), Vector3(-1.52, 1.38, 0.0), 3.05)
	await _save_capture("res://captures/closeup_back_grandma_granddaughter.png")

	# 9. Close-up pair 2 back
	_set_camera_view(Vector3(1.52, 2.75, 12.0), Vector3(1.52, 1.38, 0.0), 3.05)
	await _save_capture("res://captures/closeup_back_auntie_postman.png")

	get_tree().quit(0)


func _set_camera_view(cam_pos: Vector3, target: Vector3, ortho_size: float) -> void:
	_camera.size = ortho_size
	_camera.position = cam_pos
	_camera.look_at(target, Vector3.UP)


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save_capture(res_path: String) -> void:
	await _wait_frames(2)
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(res_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("Failed to save capture: %s (err=%d)" % [abs_path, err])
	else:
		print("CAPTURED: ", abs_path)
