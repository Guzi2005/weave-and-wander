extends SceneTree

const GameBodyDollScript = preload("res://scripts/game_body_doll.gd")
const Catalog = preload("res://captures/review_20261110/parametric_models_catalog.gd")
const ChineseFont = preload("res://assets/fonts/jiangcheng-500w.ttf")
const OUT_DIR := "res://captures/review_20261110"

func _initialize() -> void:
	call_deferred("_run_all_captures")

func _run_all_captures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("[ReviewCapture] Starting GPU renders on V20 short-arm mannequin (v20-short-arm-0045)...")

	await _render_sheet_01_hairstyles()
	await _render_sheet_02_remade_garments()
	await _render_sheet_03_basic_patterns()
	await _render_sheet_04_hats_scarf_tote()
	await _render_sheet_05_matryoshka_and_souvenirs()
	await _render_sheet_00_master_overview()

	print("[ReviewCapture] All sheets rendered successfully!")
	quit()

func _create_studio_world(parent: Node) -> Node3D:
	var studio := Node3D.new()
	studio.name = "Studio"
	parent.add_child(studio)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.95, 0.92, 0.87)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.97, 0.94, 0.90)
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.04

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 1.28
	key.rotation_degrees = Vector3(-34, -28, 0)
	key.shadow_enabled = true
	studio.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.90, 0.94, 1.0)
	fill.light_energy = 0.56
	fill.rotation_degrees = Vector3(-18, 142, 0)
	studio.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.95, 0.88)
	rim.light_energy = 0.42
	rim.rotation_degrees = Vector3(-48, -165, 0)
	studio.add_child(rim)

	# Warm paper backdrop & floor
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 16)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.91, 0.87, 0.81)
	floor_mat.roughness = 0.95
	floor_mesh.material_override = floor_mat
	studio.add_child(floor_mesh)

	return studio

class PreviewV20Doll extends "res://scripts/game_body_doll.gd":
	var _finalized := false

	func _ready() -> void:
		set_process(false)

	func init_unbaked_v20() -> void:
		outfit_style = 2
		hair_style = 0
		palette_index = 0
		set_process(false)
		# Build 2D base first via PaperDoll._build_appearance()
		super._build_appearance()
		# Wait: super._build_appearance() in GameBodyDoll already calls rig.bind()!
		# Instead, rebuild unbaked V20 hierarchy cleanly so custom nodes can be added before rig.bind():
		if is_instance_valid(body_rig):
			body_rig.free()
		arms.clear()
		legs.clear()
		_skirt = null
		skirt_root = null
		pleated_skirt = null
		body_rig = Node3D.new()
		body_rig.name = "VolumeDollRig"
		add_child(body_rig)
		clothes_root = Node3D.new()
		clothes_root.name = "OutfitSlot"
		body_rig.add_child(clothes_root)
		_build_volume_body()
		_build_volume_head()
		if hosiery != null:
			hosiery.build(self)
		_prepare_body_for_rig()
		_finalized = false

	func finalize_v20_rig() -> void:
		if _finalized or not is_instance_valid(body_rig):
			return
		_finalized = true
		rig = RigScript.new()
		rig.bind(body_rig, _covers_legs(), _keep_covered_legs())
		if hosiery != null:
			hosiery.apply(self)
		rig.animate(0, 0, "idle", 0)
		_setup_expressions()
		body_rig.rotation.y = _facing
		set_selected(selected)
		set_underbody_mode(false)

var _active_dolls: Array[PreviewV20Doll] = []

func _spawn_v20_doll(parent: Node3D) -> PreviewV20Doll:
	var doll := PreviewV20Doll.new()
	parent.add_child(doll)
	doll.init_unbaked_v20()
	_active_dolls.append(doll)
	return doll

func _make_card_viewport(grid: Control, width: int, height: int, badge_id: String,
		title_text: String, subtitle_text: String) -> SubViewport:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, height)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.94, 0.90)
	sb.border_color = Color(0.76, 0.69, 0.60)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	grid.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# Header bar with bold #ID badge + title + parameter note
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(width, 54)
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.20, 0.22, 0.26)
	hsb.corner_radius_top_left = 6
	hsb.corner_radius_top_right = 6
	hsb.content_margin_left = 10
	hsb.content_margin_right = 10
	hsb.content_margin_top = 5
	hsb.content_margin_bottom = 5
	header.add_theme_stylebox_override("panel", hsb)
	vbox.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	header.add_child(hbox)

	var badge := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.84, 0.34, 0.24)
	bsb.set_corner_radius_all(5)
	bsb.content_margin_left = 8
	bsb.content_margin_right = 8
	bsb.content_margin_top = 2
	bsb.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", bsb)
	hbox.add_child(badge)

	var badge_lbl := Label.new()
	badge_lbl.text = badge_id
	badge_lbl.add_theme_font_override("font", ChineseFont)
	badge_lbl.add_theme_font_size_override("font_size", 20)
	badge_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	badge.add_child(badge_lbl)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 1)
	hbox.add_child(title_box)

	var t_lbl := Label.new()
	t_lbl.text = title_text
	t_lbl.add_theme_font_override("font", ChineseFont)
	t_lbl.add_theme_font_size_override("font_size", 16)
	t_lbl.add_theme_color_override("font_color", Color(0.98, 0.96, 0.92))
	title_box.add_child(t_lbl)

	var s_lbl := Label.new()
	s_lbl.text = subtitle_text
	s_lbl.add_theme_font_override("font", ChineseFont)
	s_lbl.add_theme_font_size_override("font_size", 12)
	s_lbl.add_theme_color_override("font_color", Color(0.80, 0.84, 0.88))
	title_box.add_child(s_lbl)

	var vp_cont := SubViewportContainer.new()
	vp_cont.stretch = true
	vp_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vp_cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(vp_cont)

	var vp := SubViewport.new()
	vp.size = Vector2i(width - 4, height - 58)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp_cont.add_child(vp)

	return vp

func _create_sheet_root(sheet_w: int, sheet_h: int, header_title: String, header_sub: String, cols: int) -> Dictionary:
	var main_vp := SubViewport.new()
	main_vp.size = Vector2i(sheet_w, sheet_h)
	main_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(main_vp)

	var bg := ColorRect.new()
	bg.color = Color(0.90, 0.87, 0.82)
	bg.custom_minimum_size = Vector2(sheet_w, sheet_h)
	bg.size = Vector2(sheet_w, sheet_h)
	main_vp.add_child(bg)

	var margin := MarginContainer.new()
	margin.custom_minimum_size = Vector2(sheet_w, sheet_h)
	margin.size = Vector2(sheet_w, sheet_h)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	main_vp.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(outer_vbox)

	var top_bar := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.16, 0.18, 0.22)
	tsb.set_corner_radius_all(8)
	tsb.content_margin_left = 16
	tsb.content_margin_right = 16
	tsb.content_margin_top = 8
	tsb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", tsb)
	outer_vbox.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 18)
	top_bar.add_child(top_hbox)

	var h_lbl := Label.new()
	h_lbl.text = header_title
	h_lbl.add_theme_font_override("font", ChineseFont)
	h_lbl.add_theme_font_size_override("font_size", 22)
	h_lbl.add_theme_color_override("font_color", Color(0.99, 0.96, 0.90))
	top_hbox.add_child(h_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = header_sub
	sub_lbl.add_theme_font_override("font", ChineseFont)
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color(0.76, 0.84, 0.78))
	sub_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_hbox.add_child(sub_lbl)

	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	outer_vbox.add_child(grid)

	return {"viewport": main_vp, "grid": grid}

func _save_sheet_viewport(main_vp: SubViewport, filename: String) -> void:
	for doll in _active_dolls:
		if is_instance_valid(doll):
			doll.finalize_v20_rig()
	_active_dolls.clear()
	for _i in 6:
		await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var img := main_vp.get_texture().get_image()
	var full_path := ProjectSettings.globalize_path(OUT_DIR + "/" + filename)
	img.save_png(full_path)
	print("[ReviewCapture] Saved: ", full_path)
	main_vp.queue_free()
	await process_frame


# ============================================================================
# SHEET 01: MORE BASIC HAIRSTYLES (#01 - #06) ON V20 MANNEQUIN
# ============================================================================
func _render_sheet_01_hairstyles() -> void:
	var sheet := _create_sheet_root(1920, 1180,
		"【审核图 01】更多基础发型 (#01 - #06) · 基于最新 V20 短臂素体 (v20-short-arm-0045)",
		"每格含：左=正视图 | 中=3/4侧后视 | 右=参数调节变体（发长/卷度/刘海/发髻尺寸可调，不遮挡眼眉）", 3)
	var grid: GridContainer = sheet["grid"]

	var configs := [
		{
			"id": "#01",
			"title": "齐刘海内扣波波头 (Classic Chin Bob)",
			"sub": "可调: length(发长) / curl_in(内扣弧度) / bang_split(空气刘海分缝)",
			"builder": "build_hair_01_bob",
			"color1": Color(0.22, 0.16, 0.14),
			"params1": {"length": 0.25, "curl_in": 0.048, "bang_split": 0.12},
			"color2": Color(0.46, 0.28, 0.20),
			"params2": {"length": 0.34, "curl_in": 0.072, "bang_split": 0.45}
		},
		{
			"id": "#02",
			"title": "元气高马尾 (Bouncy High Ponytail)",
			"sub": "可调: tail_height(扎发高度) / tail_length(马尾长) / tail_flare(蓬松度)",
			"builder": "build_hair_02_high_ponytail",
			"color1": Color(0.28, 0.18, 0.14),
			"params1": {"tail_height": 0.46, "tail_length": 0.44, "tail_flare": 0.13},
			"color2": Color(0.15, 0.15, 0.18),
			"params2": {"tail_height": 0.52, "tail_length": 0.56, "tail_flare": 0.18, "scrunchie_color": Color(0.24, 0.48, 0.68)}
		},
		{
			"id": "#03",
			"title": "温柔披肩半扎长发 (Half-Up Long Straight)",
			"sub": "可调: length(披发长度) / back_spread(发尾扇形展开) / crown_bun_size(半扎丸子)",
			"builder": "build_hair_03_half_up_long",
			"color1": Color(0.32, 0.22, 0.17),
			"params1": {"length": 0.54, "back_spread": 0.10, "crown_bun_size": 0.064},
			"color2": Color(0.58, 0.38, 0.24),
			"params2": {"length": 0.68, "back_spread": 0.16, "crown_bun_size": 0.082}
		},
		{
			"id": "#04",
			"title": "芭蕾高丸子头/花苞头 (Topknot Ballet Bun)",
			"sub": "可调: bun_radius(花苞尺寸) / bun_height(花苞高度) / side_wisps(耳侧碎发长)",
			"builder": "build_hair_04_topknot_bun",
			"color1": Color(0.20, 0.15, 0.13),
			"params1": {"bun_radius": 0.125, "bun_height": 0.105, "side_wisps": 0.21},
			"color2": Color(0.48, 0.24, 0.22),
			"params2": {"bun_radius": 0.155, "bun_height": 0.130, "side_wisps": 0.30, "ribbon_color": Color(0.92, 0.82, 0.52)}
		},
		{
			"id": "#05",
			"title": "偏分大波浪锁骨发 (Side-Part Wavy Lob)",
			"sub": "可调: length(锁骨发长) / wave_amp(波浪振幅) / wave_freq(波浪频率)",
			"builder": "build_hair_05_wavy_lob",
			"color1": Color(0.38, 0.23, 0.17),
			"params1": {"length": 0.40, "wave_amp": 0.032, "wave_freq": 3.0},
			"color2": Color(0.74, 0.54, 0.34),
			"params2": {"length": 0.52, "wave_amp": 0.046, "wave_freq": 4.0}
		},
		{
			"id": "#06",
			"title": "活力双马尾 (Twin Pigtails)",
			"sub": "可调: tail_length(双马尾长) / mount_height(扎位高低) / bounce_flare(外翘弧度)",
			"builder": "build_hair_06_twin_pigtails",
			"color1": Color(0.25, 0.17, 0.15),
			"params1": {"tail_length": 0.44, "mount_height": 0.38, "bounce_flare": 0.15},
			"color2": Color(0.62, 0.34, 0.28),
			"params2": {"tail_length": 0.56, "mount_height": 0.43, "bounce_flare": 0.21, "accent": Color(0.28, 0.54, 0.48)}
		}
	]

	for cfg in configs:
		var vp := _make_card_viewport(grid, 620, 535, cfg["id"], cfg["title"], cfg["sub"])
		var studio := _create_studio_world(vp)

		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1.62
		studio.add_child(cam)
		cam.look_at_from_position(Vector3(0.0, 2.22, 6.0), Vector3(0.0, 2.18, 0.0), Vector3.UP)

		# Left: Front view
		var d1 := _spawn_v20_doll(studio)
		d1.position = Vector3(-0.70, 0, 0)
		d1.rotation_degrees = Vector3(0, 8, 0)
		var p1: Dictionary = cfg["params1"].duplicate()
		p1["color"] = cfg["color1"]
		Catalog.invoke(cfg["builder"], d1.head_rig, p1)

		# Center: Side-Profile 3/4 view to show ponytail/bun/back waves clearly with clean whitespace
		var d2 := _spawn_v20_doll(studio)
		d2.position = Vector3(0.0, 0, -0.06)
		d2.rotation_degrees = Vector3(0, 62, 0)
		Catalog.invoke(cfg["builder"], d2.head_rig, p1)

		# Right: Parameter & Color Variant (3/4 Front view)
		var d3 := _spawn_v20_doll(studio)
		d3.position = Vector3(0.70, 0, 0)
		d3.rotation_degrees = Vector3(0, -22, 0)
		var p2: Dictionary = cfg["params2"].duplicate()
		p2["color"] = cfg["color2"]
		Catalog.invoke(cfg["builder"], d3.head_rig, p2)

	await _save_sheet_viewport(sheet["viewport"], "01_hairstyles_01_to_06.png")


# ============================================================================
# SHEET 02: REMADE CORE GARMENTS (#07 - #09) ON V20 MANNEQUIN
# ============================================================================
func _render_sheet_02_remade_garments() -> void:
	var sheet := _create_sheet_root(1920, 1180,
		"【审核图 02】重制版核心服装 (#07 古巴领 / #08 娃娃衫 / #09 学院风V领背心) · 最新 V20 短臂素体",
		"每项含4组素体实装对比：左1=正视标准版 | 左2=3/4侧视 | 右2=短款参数变体 | 右1=长款/加宽参数变体（正交镜头无透视畸变）", 1)
	var grid: GridContainer = sheet["grid"]

	var rows := [
		{
			"id": "#07",
			"title": "古巴领重制版 (Cuban Collar Camp Shirt Remake) — 3D折页敞领V口露锁骨 + 平驳翻领三角缺口 + 门襟纽扣 + 左胸贴袋 + 翻边短袖",
			"sub": "可调参数: garment_length(衣长仅动下摆) / collar_spread(古巴领张角) / sleeve_length(袖长) / body_ease(箱型宽松度) / pocket_enabled(胸袋开关)",
			"builder": "build_garment_07_cuban_shirt_remake",
			"hair": "build_hair_01_bob",
			"variants": [
				{"pos_x": -1.15, "rot_y": 5.0, "params": {"color": Color(0.82, 0.88, 0.80), "garment_length": 0.50, "collar_spread": 1.05, "sleeve_length": 0.26}},
				{"pos_x": -0.38, "rot_y": -28.0, "params": {"color": Color(0.82, 0.88, 0.80), "garment_length": 0.50, "collar_spread": 1.05, "sleeve_length": 0.26}},
				{"pos_x": 0.38, "rot_y": 14.0, "params": {"color": Color(0.92, 0.80, 0.68), "garment_length": 0.12, "collar_spread": 0.85, "sleeve_length": 0.20, "pocket_enabled": false}},
				{"pos_x": 1.15, "rot_y": -16.0, "params": {"color": Color(0.32, 0.44, 0.54), "garment_length": 0.92, "collar_spread": 1.30, "sleeve_length": 0.34, "body_ease": 0.038}}
			]
		},
		{
			"id": "#08",
			"title": "娃娃衫重制版 (Babydoll Blouse Remake) — 彼得潘双瓣圆领 + 高腰线蝴蝶结分割 + 单调外扩A字木耳边下摆(消除水桶腰鼓包) + 灯笼泡泡袖",
			"sub": "可调参数: garment_length(下摆长短) / flare_amount(A字散摆张量) / gather_pleats(抽褶波浪数) / puff_volume(泡泡袖蓬度)",
			"builder": "build_garment_08_babydoll_remake",
			"hair": "build_hair_03_half_up_long",
			"variants": [
				{"pos_x": -1.15, "rot_y": 5.0, "params": {"color": Color(0.95, 0.88, 0.84), "garment_length": 0.52, "flare_amount": 0.105, "puff_volume": 0.038}},
				{"pos_x": -0.38, "rot_y": -30.0, "params": {"color": Color(0.95, 0.88, 0.84), "garment_length": 0.52, "flare_amount": 0.105, "puff_volume": 0.038}},
				{"pos_x": 0.38, "rot_y": 15.0, "params": {"color": Color(0.84, 0.90, 0.95), "ribbon_color": Color(0.28, 0.42, 0.62), "garment_length": 0.15, "flare_amount": 0.075, "puff_volume": 0.025}},
				{"pos_x": 1.15, "rot_y": -18.0, "params": {"color": Color(0.96, 0.92, 0.78), "ribbon_color": Color(0.68, 0.38, 0.24), "garment_length": 0.92, "flare_amount": 0.145, "puff_volume": 0.052, "gather_pleats": 18}}
			]
		},
		{
			"id": "#09",
			"title": "学院风V领背心重制版 (Preppy V-Neck Sweater Vest Remake) — 完整无裂缝针织躯干 + 学院双道撞色条纹V领/下摆罗纹 + 支持叠穿衬衫领带或单穿",
			"sub": "可调参数: garment_length(衣长) / v_depth(V领深度) / shoulder_width(肩带宽度) / layered_shirt(内搭衬衫开关) / rib_width(罗纹宽)",
			"builder": "build_garment_09_preppy_vest_remake",
			"hair": "build_hair_02_high_ponytail",
			"variants": [
				{"pos_x": -1.15, "rot_y": 5.0, "params": {"color": Color(0.18, 0.24, 0.36), "garment_length": 0.48, "v_depth": 0.27, "layered_shirt": true}},
				{"pos_x": -0.38, "rot_y": -28.0, "params": {"color": Color(0.18, 0.24, 0.36), "garment_length": 0.48, "v_depth": 0.27, "layered_shirt": true}},
				{"pos_x": 0.38, "rot_y": 15.0, "params": {"color": Color(0.90, 0.85, 0.76), "stripe_color": Color(0.20, 0.34, 0.28), "accent_stripe": Color(0.68, 0.24, 0.22), "garment_length": 0.14, "v_depth": 0.21, "layered_shirt": false}},
				{"pos_x": 1.15, "rot_y": -18.0, "params": {"color": Color(0.46, 0.18, 0.22), "stripe_color": Color(0.94, 0.88, 0.74), "accent_stripe": Color(0.20, 0.26, 0.38), "garment_length": 0.90, "v_depth": 0.33, "layered_shirt": true}}
			]
		}
	]

	for row_cfg in rows:
		var vp := _make_card_viewport(grid, 1884, 348, row_cfg["id"], row_cfg["title"], row_cfg["sub"])
		var studio := _create_studio_world(vp)

		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 1.65
		studio.add_child(cam)
		cam.look_at_from_position(Vector3(0.0, 1.80, 6.0), Vector3(0.0, 1.76, 0.0), Vector3.UP)

		for v in row_cfg["variants"]:
			var d := _spawn_v20_doll(studio)
			d.position = Vector3(float(v["pos_x"]), 0, 0)
			d.rotation_degrees = Vector3(0, v["rot_y"], 0)
			Catalog.invoke(row_cfg["hair"], d.head_rig, {"color": Color(0.24, 0.17, 0.14)})
			Catalog.invoke(row_cfg["builder"], d, v["params"])

	await _save_sheet_viewport(sheet["viewport"], "02_remade_garments_07_to_09.png")


# ============================================================================
# SHEET 03: MORE BASIC GARMENT PATTERNS (#10 - #15) ON V20 MANNEQUIN
# ============================================================================
func _render_sheet_03_basic_patterns() -> void:
	var sheet := _create_sheet_root(1920, 1180,
		"【审核图 03】更多基础版型 (#10 - #15) · 基于最新 V20 短臂素体 (含裸臂/裸腿素体衔接验证)",
		"每格含：左=正视图 | 中=3/4侧视图 | 右=参数调节变体（衣长/裙长/裤长/领深/袖长/廓形张量可调，正交镜头无透视畸变）", 3)
	var grid: GridContainer = sheet["grid"]

	var configs := [
		{
			"id": "#10",
			"title": "水手领基础衫 (Sailor Collar Blouse)",
			"sub": "可调: garment_length / collar_drop(方领深) / sleeve_length / tie_length(领巾)",
			"builder": "build_garment_10_sailor_blouse",
			"hair": "build_hair_01_bob",
			"cam_y": 1.76, "ortho_size": 1.68, "span_x": 0.64,
			"p1": {"color": Color(0.95, 0.94, 0.90), "collar_color": Color(0.16, 0.24, 0.38), "garment_length": 0.45, "sleeve_length": 0.25},
			"p2": {"color": Color(0.18, 0.24, 0.36), "collar_color": Color(0.94, 0.92, 0.86), "stripe_color": Color(0.18, 0.24, 0.36), "garment_length": 0.82, "sleeve_length": 0.42, "tie_length": 0.24}
		},
		{
			"id": "#11",
			"title": "经典V领针织开衫 (V-Neck Knit Cardigan)",
			"sub": "可调: garment_length / v_drop / sleeve_length / body_ease / pocket_scale",
			"builder": "build_garment_11_knit_cardigan",
			"hair": "build_hair_05_wavy_lob",
			"cam_y": 1.74, "ortho_size": 1.68, "span_x": 0.64,
			"p1": {"color": Color(0.76, 0.56, 0.44), "garment_length": 0.55, "sleeve_length": 0.44, "pocket_scale": 1.0},
			"p2": {"color": Color(0.42, 0.54, 0.46), "garment_length": 0.18, "v_drop": 0.20, "sleeve_length": 0.28, "pocket_scale": 0.0}
		},
		{
			"id": "#12",
			"title": "学院工装背带裙 (Pinafore Overall Dress)",
			"sub": "可调: skirt_length / skirt_flare / bib_height / bib_width / strap_width",
			"builder": "build_garment_12_pinafore_dress",
			"hair": "build_hair_06_twin_pigtails",
			"cam_y": 1.36, "ortho_size": 2.68, "span_x": 0.82,
			"p1": {"color": Color(0.28, 0.36, 0.46), "skirt_length": 0.46, "skirt_flare": 0.13},
			"p2": {"color": Color(0.68, 0.44, 0.32), "skirt_length": 0.85, "skirt_flare": 0.18, "bib_width": 0.135}
		},
		{
			"id": "#13",
			"title": "法式方领泡泡袖上衣 (Square-Neck Puff Top)",
			"sub": "可调: garment_length / neck_width / neck_depth / puff_size / peplum_flare",
			"builder": "build_garment_13_square_neck_top",
			"hair": "build_hair_04_topknot_bun",
			"cam_y": 1.76, "ortho_size": 1.68, "span_x": 0.64,
			"p1": {"color": Color(0.86, 0.74, 0.84), "garment_length": 0.45, "puff_size": 0.046, "peplum_flare": 0.068},
			"p2": {"color": Color(0.88, 0.42, 0.38), "garment_length": 0.82, "neck_width": 0.118, "puff_size": 0.062, "peplum_flare": 0.105}
		},
		{
			"id": "#14",
			"title": "高腰百慕大阔腿短裤 (High-Waist Pleated Shorts)",
			"sub": "可调: inseam_length(三分短裤至及膝百慕大) / leg_flare(裤管宽) / cuff_height(翻边)",
			"builder": "build_garment_14_pleated_shorts",
			"hair": "build_hair_02_high_ponytail",
			"cam_y": 1.34, "ortho_size": 2.68, "span_x": 0.82,
			"p1": {"color": Color(0.78, 0.71, 0.61), "inseam_length": 0.48, "leg_flare": 0.030, "cuff_height": 0.038},
			"p2": {"color": Color(0.26, 0.32, 0.42), "top_color": Color(0.92, 0.88, 0.82), "inseam_length": 0.12, "leg_flare": 0.048, "cuff_height": 0.025}
		},
		{
			"id": "#15",
			"title": "半高领无袖A字背心裙 (Mock-Neck Shift Dress)",
			"sub": "可调: dress_length / collar_height(半高领高) / hem_flare(A字摆宽) / shoulder_cut(露肩度)",
			"builder": "build_garment_15_mock_neck_shift_dress",
			"hair": "build_hair_03_half_up_long",
			"cam_y": 1.36, "ortho_size": 2.68, "span_x": 0.82,
			"p1": {"color": Color(0.68, 0.34, 0.32), "dress_length": 0.48, "hem_flare": 0.15, "collar_height": 0.068},
			"p2": {"color": Color(0.24, 0.42, 0.38), "dress_length": 0.88, "hem_flare": 0.21, "collar_height": 0.045, "shoulder_cut": 0.115}
		}
	]

	for cfg in configs:
		var vp := _make_card_viewport(grid, 620, 535, cfg["id"], cfg["title"], cfg["sub"])
		var studio := _create_studio_world(vp)

		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = float(cfg["ortho_size"])
		studio.add_child(cam)
		var cy := float(cfg["cam_y"])
		var sx := float(cfg["span_x"])
		cam.look_at_from_position(Vector3(0.0, cy + 0.04, 6.0), Vector3(0.0, cy, 0.0), Vector3.UP)

		var d1 := _spawn_v20_doll(studio)
		d1.position = Vector3(-sx, 0, 0)
		d1.rotation_degrees = Vector3(0, 6, 0)
		Catalog.invoke(cfg["hair"], d1.head_rig, {"color": Color(0.24, 0.17, 0.14)})
		Catalog.invoke(cfg["builder"], d1, cfg["p1"])

		var d2 := _spawn_v20_doll(studio)
		d2.position = Vector3(0.0, 0, -0.04)
		d2.rotation_degrees = Vector3(0, -32, 0)
		Catalog.invoke(cfg["hair"], d2.head_rig, {"color": Color(0.24, 0.17, 0.14)})
		Catalog.invoke(cfg["builder"], d2, cfg["p1"])

		var d3 := _spawn_v20_doll(studio)
		d3.position = Vector3(sx, 0, 0)
		d3.rotation_degrees = Vector3(0, 18, 0)
		Catalog.invoke(cfg["hair"], d3.head_rig, {"color": Color(0.42, 0.26, 0.18)})
		Catalog.invoke(cfg["builder"], d3, cfg["p2"])

	await _save_sheet_viewport(sheet["viewport"], "03_basic_patterns_10_to_15.png")


# ============================================================================
# SHEET 04: YI HATS (#16, #17), ESTONIAN HEADSCARF (#18) & CANVAS TOTE (#19)
# ============================================================================
func _render_sheet_04_hats_scarf_tote() -> void:
	var sheet := _create_sheet_root(1920, 1180,
		"【审核图 04】民族帽饰与包袋 (#16 彝族解放帽 / #17 彝族阿都式高筒帽 / #18 爱沙尼亚头巾 / #19 帆布袋)",
		"严格对照参考图1左、图1右、图2款式建模（不复刻纹样），消除穿模并采用正交相机展示 V20 素体佩戴效果 + 参数变体", 2)
	var grid: GridContainer = sheet["grid"]

	# --- CARD #16: Yi Liberation Cap (Image 1 Left: Bucket-Shaped Peaked Cap) ---
	var vp16 := _make_card_viewport(grid, 936, 535, "#16",
		"彝族解放帽（本质为桶型鸭舌帽：深藏青平顶圆桶身 + 拱弧形鸭舌帽檐 + 侧面细红线嵌条，吸附头顶零穿模）",
		"可调参数: barrel_height(桶高) / barrel_width(桶宽) / visor_length(帽舌长度) / wear_angle(吸附佩戴角度)")
	var st16 := _create_studio_world(vp16)
	var cam16 := Camera3D.new()
	cam16.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam16.size = 1.40
	st16.add_child(cam16)
	cam16.look_at_from_position(Vector3(0.0, 2.26, 6.0), Vector3(0.0, 2.22, 0.0), Vector3.UP)

	# Left: Standard Bucket Peaked Cap (3/4 front-left view, wear_angle = 20 deg)
	var d16_a := _spawn_v20_doll(st16)
	d16_a.position = Vector3(-0.74, 0, 0)
	d16_a.rotation_degrees = Vector3(0, 22, 0)
	Catalog.build_hair_01_bob(d16_a.head_rig, {"color": Color(0.18, 0.14, 0.12), "length": 0.22})
	Catalog.build_garment_07_cuban_shirt_remake(d16_a, {"color": Color(0.76, 0.58, 0.38)})
	Catalog.build_hat_16_yi_liberation_cap(d16_a.head_rig,
		{"barrel_height": 0.24, "barrel_width": 0.292, "visor_length": 0.155, "wear_angle": 20.0})

	# Center: Side-profile view matching Image 1 Left (wear_angle = 25 deg tilted back on crown, exposing bangs!)
	var d16_b := _spawn_v20_doll(st16)
	d16_b.position = Vector3(0.0, 0, 0)
	d16_b.rotation_degrees = Vector3(0, -54, 0)
	Catalog.build_hair_01_bob(d16_b.head_rig, {"color": Color(0.18, 0.14, 0.12), "length": 0.22})
	Catalog.build_garment_07_cuban_shirt_remake(d16_b, {"color": Color(0.76, 0.58, 0.38)})
	Catalog.build_hat_16_yi_liberation_cap(d16_b.head_rig,
		{"barrel_height": 0.25, "barrel_width": 0.292, "visor_length": 0.160, "wear_angle": 25.0})

	# Right: Parameter variant (Taller & wider barrel + longer duckbill visor + forward level wear_angle = 8 deg)
	var d16_c := _spawn_v20_doll(st16)
	d16_c.position = Vector3(0.74, 0, 0)
	d16_c.rotation_degrees = Vector3(0, -28, 0)
	Catalog.build_hair_01_bob(d16_c.head_rig, {"color": Color(0.18, 0.14, 0.12), "length": 0.22})
	Catalog.build_garment_07_cuban_shirt_remake(d16_c, {"color": Color(0.64, 0.52, 0.38)})
	Catalog.build_hat_16_yi_liberation_cap(d16_c.head_rig,
		{"color": Color(0.18, 0.22, 0.28), "barrel_height": 0.30, "barrel_width": 0.312, "visor_length": 0.195, "wear_angle": 8.0})

	# --- CARD #17: Yi Adu Style Tall Flared Hat (Image 1 Right) ---
	var vp17 := _make_card_viewport(grid, 936, 535, "#17",
		"彝族阿都式高筒帽（对应参考图1右款：上宽下窄喇叭形黑绒百褶高筒 + 暗红编织底圈 + 厚实包边顶圈）",
		"可调参数: hat_height(筒高) / top_flare_radius(顶圈外扩半径) / base_radius(底圈) / pleat_count(百褶密度) / rim_thickness(顶圈厚)")
	var st17 := _create_studio_world(vp17)
	var cam17 := Camera3D.new()
	cam17.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam17.size = 1.56
	st17.add_child(cam17)
	cam17.look_at_from_position(Vector3(0.0, 2.34, 6.0), Vector3(0.0, 2.30, 0.0), Vector3.UP)

	var d17_a := _spawn_v20_doll(st17)
	d17_a.position = Vector3(-0.82, 0, 0)
	d17_a.rotation_degrees = Vector3(0, 12, 0)
	Catalog.build_hair_04_topknot_bun(d17_a.head_rig, {"color": Color(0.14, 0.12, 0.12), "bun_radius": 0.06})
	Catalog.build_garment_15_mock_neck_shift_dress(d17_a, {"color": Color(0.14, 0.14, 0.18), "trim_color": Color(0.22, 0.62, 0.34)})
	Catalog.build_hat_17_yi_adu_hat(d17_a.head_rig, {"hat_height": 0.50, "top_flare_radius": 0.435, "pleat_count": 48})

	var d17_b := _spawn_v20_doll(st17)
	d17_b.position = Vector3(0.0, 0, 0)
	d17_b.rotation_degrees = Vector3(0, 38, 0) # 3/4 profile matching Image 1 Right!
	Catalog.build_hair_04_topknot_bun(d17_b.head_rig, {"color": Color(0.14, 0.12, 0.12), "bun_radius": 0.06})
	Catalog.build_garment_15_mock_neck_shift_dress(d17_b, {"color": Color(0.14, 0.14, 0.18), "trim_color": Color(0.22, 0.62, 0.34)})
	Catalog.build_hat_17_yi_adu_hat(d17_b.head_rig, {"hat_height": 0.50, "top_flare_radius": 0.435, "pleat_count": 48})

	var d17_c := _spawn_v20_doll(st17)
	d17_c.position = Vector3(0.82, 0, 0)
	d17_c.rotation_degrees = Vector3(0, -24, 0)
	Catalog.build_hair_04_topknot_bun(d17_c.head_rig, {"color": Color(0.14, 0.12, 0.12), "bun_radius": 0.06})
	Catalog.build_garment_15_mock_neck_shift_dress(d17_c, {"color": Color(0.22, 0.16, 0.26), "trim_color": Color(0.78, 0.24, 0.32)})
	Catalog.build_hat_17_yi_adu_hat(d17_c.head_rig,
		{"hat_height": 0.40, "top_flare_radius": 0.365, "rim_thickness": 0.046, "tilt_angle": -0.15})

	# --- CARD #18: Estonian Headscarf & Fringed Shawl (Image 2) ---
	var vp18 := _make_card_viewport(grid, 936, 535, "#18",
		"爱沙尼亚头巾（对应参考图2款式：露刘海包头巾 + 颌下打结宽大三角形双垂角 + 覆肩流苏披肩，零穿模）",
		"可调参数: hood_depth(巾罩深) / face_opening(露脸宽) / flap_length & flap_spread(颌下三角垂角长宽) / shawl_drop / fringe_length(流苏长)")
	var st18 := _create_studio_world(vp18)
	var cam18 := Camera3D.new()
	cam18.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam18.size = 1.64
	st18.add_child(cam18)
	cam18.look_at_from_position(Vector3(0.0, 2.02, 6.0), Vector3(0.0, 1.98, 0.0), Vector3.UP)

	var d18_a := _spawn_v20_doll(st18)
	d18_a.position = Vector3(-0.88, 0, 0)
	d18_a.rotation_degrees = Vector3(0, 4, 0)
	# Blonde bangs like the girl in Image 2!
	Catalog.build_hair_01_bob(d18_a.head_rig, {"color": Color(0.88, 0.78, 0.56), "length": 0.20, "bang_split": 0.15})
	Catalog.build_garment_08_babydoll_remake(d18_a, {"color": Color(0.96, 0.95, 0.92), "puff_volume": 0.045, "flare_amount": 0.04})
	Catalog.build_hat_18_estonian_headscarf(d18_a, {"flap_length": 0.25, "shawl_drop": 0.34, "fringe_length": 0.068})

	var d18_b := _spawn_v20_doll(st18)
	d18_b.position = Vector3(0.0, 0, 0)
	d18_b.rotation_degrees = Vector3(0, -30, 0)
	Catalog.build_hair_01_bob(d18_b.head_rig, {"color": Color(0.88, 0.78, 0.56), "length": 0.20})
	Catalog.build_garment_08_babydoll_remake(d18_b, {"color": Color(0.96, 0.95, 0.92), "puff_volume": 0.045, "flare_amount": 0.04})
	Catalog.build_hat_18_estonian_headscarf(d18_b, {"flap_length": 0.25, "shawl_drop": 0.34, "fringe_length": 0.068})

	var d18_c := _spawn_v20_doll(st18)
	d18_c.position = Vector3(0.88, 0, 0)
	d18_c.rotation_degrees = Vector3(0, 20, 0)
	Catalog.build_hair_01_bob(d18_c.head_rig, {"color": Color(0.88, 0.78, 0.56), "length": 0.20})
	Catalog.build_garment_08_babydoll_remake(d18_c, {"color": Color(0.96, 0.95, 0.92), "puff_volume": 0.045, "flare_amount": 0.04})
	Catalog.build_hat_18_estonian_headscarf(d18_c,
		{"color": Color(0.64, 0.18, 0.22), "border_color": Color(0.92, 0.78, 0.42), "flap_length": 0.30, "flap_spread": 1.18, "shawl_drop": 0.38, "fringe_length": 0.088})

	# --- CARD #19: Parametric Canvas Tote Bag ---
	var vp19 := _make_card_viewport(grid, 936, 535, "#19",
		"帆布袋 (Parametric Gusseted Cotton Canvas Tote Bag) — 支持素体肩背/手提实装 + 独立多规格陈列",
		"可调参数: bag_width(袋宽) / bag_height(袋高) / gusset_depth(侧风琴底宽) / strap_drop(肩带垂高) / contrast_bottom_ratio(撞色包底比例)")
	var st19 := _create_studio_world(vp19)
	var cam19 := Camera3D.new()
	cam19.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam19.size = 1.56
	st19.add_child(cam19)
	cam19.look_at_from_position(Vector3(0.0, 1.38, 6.0), Vector3(0.0, 1.32, 0.0), Vector3.UP)

	# Left: V20 doll carrying the Canvas Tote Bag on shoulder/side
	var d19 := _spawn_v20_doll(st19)
	d19.position = Vector3(-0.74, 0, 0)
	d19.rotation_degrees = Vector3(0, -18, 0)
	Catalog.build_hair_05_wavy_lob(d19.head_rig, {"color": Color(0.28, 0.19, 0.15)})
	Catalog.build_garment_07_cuban_shirt_remake(d19, {"color": Color(0.84, 0.88, 0.82)})
	var worn_bag := Catalog.build_prop_19_canvas_tote_bag(d19, {
		"bag_width": 0.34, "bag_height": 0.38, "gusset_depth": 0.11, "strap_drop": 0.36
	})
	worn_bag.position = Vector3(0.23, 1.08, 0.04)
	worn_bag.rotation_degrees = Vector3(0, 78, -6)

	# Center & Right: 3 Standalone Parametric Tote Bags on display plinths (Tall Book Tote / Standard Classic Tote / Wide Shopper Tote)
	var plinth_y := 0.82
	var bag_variants := [
		{"x": -0.05, "rot": 22.0, "params": {"bag_width": 0.36, "bag_height": 0.42, "gusset_depth": 0.12, "strap_drop": 0.26, "contrast_bottom_ratio": 0.25, "strap_color": Color(0.22, 0.34, 0.28)}},
		{"x": 0.42, "rot": -28.0, "params": {"bag_width": 0.46, "bag_height": 0.34, "gusset_depth": 0.15, "strap_drop": 0.22, "contrast_bottom_ratio": 0.30, "strap_color": Color(0.20, 0.28, 0.44)}},
		{"x": 0.88, "rot": 15.0, "params": {"bag_width": 0.28, "bag_height": 0.46, "gusset_depth": 0.09, "strap_drop": 0.32, "contrast_bottom_ratio": 0.0, "color": Color(0.88, 0.82, 0.74), "strap_color": Color(0.56, 0.28, 0.24)}}
	]
	for bv in bag_variants:
		Catalog.add_ellipsoid(st19, "BagPlinth", Vector3(bv["x"], plinth_y * 0.5, 0), Vector3(0.18, plinth_y * 0.5, 0.18), Color(0.84, 0.79, 0.72))
		var b_node := Catalog.build_prop_19_canvas_tote_bag(st19, bv["params"])
		b_node.position = Vector3(bv["x"], plinth_y, 0)
		b_node.rotation_degrees = Vector3(0, bv["rot"], 0)

	await _save_sheet_viewport(sheet["viewport"], "04_hats_scarf_tote_16_to_19.png")


# ============================================================================
# SHEET 05: MATRYOSHKA (#20), SOUVENIR DOLL (#21) & SPHERE+CONE PEG DOLL (#22)
# ============================================================================
func _render_sheet_05_matryoshka_and_souvenirs() -> void:
	var sheet := _create_sheet_root(1920, 1180,
		"【审核图 05】俄罗斯套娃与木质纪念品人偶 (#20 俄罗斯套娃 / #21 纪念品娃娃 / #22 球型脑袋+圆锥身体木偶)",
		"全参数化车削木偶建模（正交镜头无透视畸变）：套娃支持尺寸/胖瘦/层数/子母口开合；球型脑袋+圆锥木偶配有3款参数化木雕发型", 1)
	var grid: GridContainer = sheet["grid"]

	# --- ROW 1 (#20): Russian Matryoshka Nesting Dolls ---
	var vp20 := _make_card_viewport(grid, 1884, 355, "#20",
		"俄罗斯套娃 (Russian Matryoshka Nesting Dolls) — 可调外壳尺寸、胖瘦比例、层数(3/5/7层)及上下壳子母口开合嵌套",
		"左：标准5层套娃队列 + 首层外壳打开露出子母口内榫与内部嵌套2号娃 | 中：胖肚圆润比例(3层) | 右：修长高挑比例(6层)")
	var st20 := _create_studio_world(vp20)
	var cam20 := Camera3D.new()
	cam20.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam20.size = 0.78
	st20.add_child(cam20)
	cam20.look_at_from_position(Vector3(0.0, 0.38, 6.0), Vector3(0.0, 0.32, 0.0), Vector3.UP)

	# Group A (Left): 5-Layer Set with Outer Shell #1 Opened to reveal inner tenon & nested doll!
	var m_set_a := Catalog.build_prop_20_matryoshka_set(st20, {
		"layer_count": 5, "outer_height": 0.48, "outer_radius": 0.135,
		"belly_ratio": 1.0, "waist_height_ratio": 0.64, "head_ratio": 0.80,
		"open_first_shell": true, "spacing_factor": 1.15
	})
	m_set_a.position = Vector3(-0.78, 0.0, 0.0)
	m_set_a.rotation_degrees = Vector3(0, 8, 0)

	# Group B (Center): Chubby / Wide-Belly 3-Layer Set (belly_ratio = 1.24, head_ratio = 0.86)
	var m_set_b := Catalog.build_prop_20_matryoshka_set(st20, {
		"layer_count": 3, "outer_height": 0.44, "outer_radius": 0.155,
		"belly_ratio": 1.22, "waist_height_ratio": 0.60, "head_ratio": 0.85,
		"open_first_shell": false, "spacing_factor": 1.16
	})
	m_set_b.position = Vector3(0.08, 0.0, 0.0)
	m_set_b.rotation_degrees = Vector3(0, -12, 0)

	# Group C (Right): Tall / Slender 6-Layer Set (outer_height = 0.56, outer_radius = 0.115, decay = 0.78)
	var m_set_c := Catalog.build_prop_20_matryoshka_set(st20, {
		"layer_count": 6, "outer_height": 0.54, "outer_radius": 0.115,
		"belly_ratio": 0.88, "waist_height_ratio": 0.68, "head_ratio": 0.76,
		"layer_scale_decay": 0.78, "open_first_shell": false, "spacing_factor": 1.14
	})
	m_set_c.position = Vector3(0.86, 0.0, 0.0)
	m_set_c.rotation_degrees = Vector3(0, -8, 0)

	# --- ROW 2 (#21): Souvenir Folk Doll ---
	var vp21 := _make_card_viewport(grid, 1884, 345, "#21",
		"纪念品娃娃 (Turned Wooden Folk Souvenir Doll) — 车削木质底座 + 郁金香钟形裙身 + 浮雕腰封/花瓣领/侧贴木手 + 双丸子/高发髻",
		"可调参数: total_height(总高) / head_radius(头径) / head_squash(头型扁圆度) / skirt_flare(裙摆张度) / waist_ratio(腰身比) / bun_size & hair_style")
	var st21 := _create_studio_world(vp21)
	var cam21 := Camera3D.new()
	cam21.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam21.size = 0.72
	st21.add_child(cam21)
	cam21.look_at_from_position(Vector3(0.0, 0.34, 6.0), Vector3(0.0, 0.29, 0.0), Vector3.UP)

	var s21_list := [
		{"x": -0.82, "rot": 8.0, "p": {"total_height": 0.50, "head_radius": 0.115, "skirt_flare": 0.145, "hair_style": 0, "dress_color": Color(0.76, 0.24, 0.24), "sash_color": Color(0.20, 0.34, 0.46)}},
		{"x": -0.42, "rot": -35.0, "p": {"total_height": 0.50, "head_radius": 0.115, "skirt_flare": 0.145, "hair_style": 0, "dress_color": Color(0.76, 0.24, 0.24), "sash_color": Color(0.20, 0.34, 0.46)}},
		{"x": 0.0, "rot": 12.0, "p": {"total_height": 0.56, "head_radius": 0.105, "skirt_flare": 0.125, "waist_ratio": 0.48, "hair_style": 1, "dress_color": Color(0.22, 0.42, 0.36), "sash_color": Color(0.84, 0.62, 0.26)}},
		{"x": 0.42, "rot": -15.0, "p": {"total_height": 0.42, "head_radius": 0.128, "head_squash": 0.90, "skirt_flare": 0.165, "waist_ratio": 0.64, "bun_size": 0.052, "hair_style": 0, "dress_color": Color(0.26, 0.34, 0.54), "sash_color": Color(0.78, 0.28, 0.28)}},
		{"x": 0.82, "rot": 22.0, "p": {"total_height": 0.48, "head_radius": 0.112, "skirt_flare": 0.150, "hair_style": 1, "hair_color": Color(0.54, 0.34, 0.20), "dress_color": Color(0.82, 0.56, 0.24), "sash_color": Color(0.28, 0.44, 0.38)}}
	]
	for item in s21_list:
		var node := Catalog.build_prop_21_souvenir_doll(st21, item["p"])
		node.position = Vector3(item["x"], 0.0, 0.0)
		node.rotation_degrees = Vector3(0, item["rot"], 0)

	# --- ROW 3 (#22): Souvenir Spherical-Head + Cone-Body Wooden Peg Doll ---
	var vp22 := _make_card_viewport(grid, 1884, 345, "#22",
		"纪念品球型脑袋+圆锥身体木偶 (Spherical-Head + Cone-Body Peg Doll) — 正球体脑袋 + 参数化木雕头发(波波头/高丸子木髻/双圆木髻) + 车削颈槽 + 倒角圆锥身体",
		"可调参数: head_radius(正球脑半径) / hair_style(0=木雕波波头,1=高木髻,2=双侧木髻) / hair_color / cone_height(圆锥高) / cone_base_radius / neck_groove_radius")
	var st22 := _create_studio_world(vp22)
	var cam22 := Camera3D.new()
	cam22.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam22.size = 0.72
	st22.add_child(cam22)
	cam22.look_at_from_position(Vector3(0.0, 0.34, 6.0), Vector3(0.0, 0.28, 0.0), Vector3.UP)

	var s22_list := [
		# 1. Classic Balanced Peg Doll (hair_style = 0: Carved Wooden Bob + Bangs)
		{"x": -0.84, "rot": 10.0, "p": {"head_radius": 0.108, "cone_height": 0.34, "cone_base_radius": 0.135, "cone_top_radius": 0.046, "cone_color": Color(0.24, 0.42, 0.48), "hair_style": 0, "hair_color": Color(0.24, 0.16, 0.12)}},
		# 2. Natural Maple/Walnut Peg Doll (hair_style = 1: Turned Topknot Bun)
		{"x": -0.44, "rot": -24.0, "p": {"head_radius": 0.105, "cone_height": 0.35, "cone_base_radius": 0.130, "cone_top_radius": 0.044, "cone_color": Color(0.84, 0.68, 0.50), "accent_color": Color(0.58, 0.38, 0.24), "hair_style": 1, "hair_color": Color(0.42, 0.25, 0.16)}},
		# 3. Big-Head Cute Chibi Proportion (hair_style = 2: Twin Side Wooden Buns)
		{"x": -0.04, "rot": 15.0, "p": {"head_radius": 0.132, "cone_height": 0.26, "cone_base_radius": 0.155, "cone_top_radius": 0.056, "cone_color": Color(0.78, 0.28, 0.26), "hair_style": 2, "hair_color": Color(0.20, 0.14, 0.12)}},
		# 4. Tall Slender Nordic Spire Peg Doll (hair_style = 1: Topknot Bun)
		{"x": 0.38, "rot": -16.0, "p": {"head_radius": 0.092, "cone_height": 0.42, "cone_base_radius": 0.108, "cone_top_radius": 0.038, "cone_color": Color(0.28, 0.46, 0.34), "hair_style": 1, "hair_color": Color(0.54, 0.34, 0.20)}},
		# 5. Family Pair (Parent + Child with Carved Wooden Hair)
		{"x": 0.76, "rot": 8.0, "p": {"head_radius": 0.112, "cone_height": 0.36, "cone_base_radius": 0.140, "cone_top_radius": 0.048, "cone_color": Color(0.82, 0.58, 0.24), "hair_style": 0, "hair_color": Color(0.32, 0.20, 0.14)}},
		{"x": 0.98, "rot": -18.0, "p": {"head_radius": 0.078, "cone_height": 0.23, "cone_base_radius": 0.095, "cone_top_radius": 0.034, "cone_color": Color(0.68, 0.32, 0.44), "hair_style": 2, "hair_color": Color(0.26, 0.17, 0.13)}}
	]
	for item in s22_list:
		var node := Catalog.build_prop_22_sphere_cone_peg_doll(st22, item["p"])
		node.position = Vector3(item["x"], 0.0, 0.0)
		node.rotation_degrees = Vector3(0, item["rot"], 0)

	await _save_sheet_viewport(sheet["viewport"], "05_matryoshka_souvenir_dolls_20_to_22.png")


# ============================================================================
# SHEET 00: MASTER 22-ITEM NUMBERED INDEX SHEET (#01 - #22 ALL IN ONE VIEW)
# ============================================================================
func _render_sheet_00_master_overview() -> void:
	var sheet := _create_sheet_root(1920, 1280,
		"【总览索引图 00】Weave & Wander 22项新增/重制参数化基础模型汇总 (#01 - #22)",
		"全部着装与发型均基于最新验收短臂素体 v20-short-arm-0045 (GameBodyDoll) 正交镜头无透视渲染 · 请按序号审核放行", 6)
	var grid: GridContainer = sheet["grid"]

	var items := [
		{"id": "#01", "title": "齐刘海波波头", "sub": "基础发型 1", "type": "hair", "fn": "build_hair_01_bob", "p": {"color": Color(0.22, 0.16, 0.14)}},
		{"id": "#02", "title": "元气高马尾", "sub": "基础发型 2", "type": "hair", "fn": "build_hair_02_high_ponytail", "p": {"color": Color(0.28, 0.18, 0.14)}},
		{"id": "#03", "title": "披肩半扎长发", "sub": "基础发型 3", "type": "hair", "fn": "build_hair_03_half_up_long", "p": {"color": Color(0.32, 0.22, 0.17)}},
		{"id": "#04", "title": "芭蕾高丸子头", "sub": "基础发型 4", "type": "hair", "fn": "build_hair_04_topknot_bun", "p": {"color": Color(0.20, 0.15, 0.13)}},
		{"id": "#05", "title": "偏分大波浪发", "sub": "基础发型 5", "type": "hair", "fn": "build_hair_05_wavy_lob", "p": {"color": Color(0.38, 0.23, 0.17)}},
		{"id": "#06", "title": "活力双马尾", "sub": "基础发型 6", "type": "hair", "fn": "build_hair_06_twin_pigtails", "p": {"color": Color(0.25, 0.17, 0.15)}},

		{"id": "#07", "title": "古巴领重制版", "sub": "核心版型重制", "type": "top", "fn": "build_garment_07_cuban_shirt_remake", "p": {"color": Color(0.82, 0.88, 0.80)}},
		{"id": "#08", "title": "娃娃衫重制版", "sub": "核心版型重制", "type": "top", "fn": "build_garment_08_babydoll_remake", "p": {"color": Color(0.95, 0.88, 0.84)}},
		{"id": "#09", "title": "V领背心重制版", "sub": "核心版型重制", "type": "top", "fn": "build_garment_09_preppy_vest_remake", "p": {"color": Color(0.18, 0.24, 0.36)}},
		{"id": "#10", "title": "水手领基础衫", "sub": "新增基础版型", "type": "top", "fn": "build_garment_10_sailor_blouse", "p": {"color": Color(0.95, 0.94, 0.90)}},
		{"id": "#11", "title": "V领针织开衫", "sub": "新增基础版型", "type": "top", "fn": "build_garment_11_knit_cardigan", "p": {"color": Color(0.76, 0.56, 0.44)}},
		{"id": "#12", "title": "学院工装背带裙", "sub": "新增基础版型", "type": "full", "fn": "build_garment_12_pinafore_dress", "p": {"color": Color(0.28, 0.36, 0.46)}},

		{"id": "#13", "title": "法式方领泡泡袖", "sub": "新增基础版型", "type": "top", "fn": "build_garment_13_square_neck_top", "p": {"color": Color(0.86, 0.74, 0.84)}},
		{"id": "#14", "title": "高腰阔腿短裤", "sub": "新增基础版型", "type": "full", "fn": "build_garment_14_pleated_shorts", "p": {"color": Color(0.78, 0.71, 0.61)}},
		{"id": "#15", "title": "半高领无袖A字裙", "sub": "新增基础版型", "type": "full", "fn": "build_garment_15_mock_neck_shift_dress", "p": {"color": Color(0.68, 0.34, 0.32)}},
		{"id": "#16", "title": "彝族解放帽", "sub": "图1左款帽饰", "type": "hat", "fn": "build_hat_16_yi_liberation_cap", "p": {}},
		{"id": "#17", "title": "彝族阿都式高筒帽", "sub": "图1右款帽饰", "type": "hat_tall", "fn": "build_hat_17_yi_adu_hat", "p": {}},
		{"id": "#18", "title": "爱沙尼亚头巾", "sub": "图2款式头巾披肩", "type": "scarf", "fn": "build_hat_18_estonian_headscarf", "p": {}},

		{"id": "#19", "title": "帆布袋", "sub": "参数化托特包", "type": "bag", "fn": "build_prop_19_canvas_tote_bag", "p": {}},
		{"id": "#20", "title": "俄罗斯套娃(可调层数)", "sub": "尺寸/比例/子母口", "type": "matryoshka", "fn": "build_prop_20_matryoshka_set", "p": {}},
		{"id": "#21", "title": "纪念品娃娃", "sub": "车削木偶娃娃", "type": "souvenir", "fn": "build_prop_21_souvenir_doll", "p": {}},
		{"id": "#22", "title": "球型头+圆锥木偶", "sub": "带木雕头发圆锥木偶", "type": "peg", "fn": "build_prop_22_sphere_cone_peg_doll", "p": {}}
	]

	for it in items:
		var vp := _make_card_viewport(grid, 304, 282, it["id"], it["title"], it["sub"])
		var studio := _create_studio_world(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		studio.add_child(cam)

		var t_type: String = it["type"]
		if t_type == "hair":
			cam.size = 1.18
			cam.look_at_from_position(Vector3(0.0, 2.22, 6.0), Vector3(0.0, 2.20, 0.0), Vector3.UP)
			var d := _spawn_v20_doll(studio)
			d.rotation_degrees = Vector3(0, -18, 0)
			Catalog.invoke(it["fn"], d.head_rig, it["p"])
		elif t_type == "top":
			cam.size = 1.48
			cam.look_at_from_position(Vector3(0.0, 1.84, 6.0), Vector3(0.0, 1.82, 0.0), Vector3.UP)
			var d := _spawn_v20_doll(studio)
			d.rotation_degrees = Vector3(0, -12, 0)
			Catalog.build_hair_01_bob(d.head_rig, {"color": Color(0.24, 0.17, 0.14)})
			Catalog.invoke(it["fn"], d, it["p"])
		elif t_type == "full":
			cam.size = 2.68
			cam.look_at_from_position(Vector3(0.0, 1.38, 6.0), Vector3(0.0, 1.34, 0.0), Vector3.UP)
			var d := _spawn_v20_doll(studio)
			d.rotation_degrees = Vector3(0, -14, 0)
			Catalog.build_hair_02_high_ponytail(d.head_rig, {"color": Color(0.24, 0.17, 0.14)})
			Catalog.invoke(it["fn"], d, it["p"])
		elif t_type == "hat":
			cam.size = 1.24
			cam.look_at_from_position(Vector3(0.0, 2.28, 6.0), Vector3(0.0, 2.26, 0.0), Vector3.UP)
			var d := _spawn_v20_doll(studio)
			d.rotation_degrees = Vector3(0, -36, 0)
			Catalog.build_hair_01_bob(d.head_rig, {"color": Color(0.18, 0.14, 0.12), "length": 0.21})
			Catalog.build_garment_07_cuban_shirt_remake(d, {"color": Color(0.76, 0.58, 0.38)})
			Catalog.invoke(it["fn"], d.head_rig, it["p"])
		elif t_type == "hat_tall":
			cam.size = 1.44
			cam.look_at_from_position(Vector3(0.0, 2.38, 6.0), Vector3(0.0, 2.34, 0.0), Vector3.UP)
			var d := _spawn_v20_doll(studio)
			d.rotation_degrees = Vector3(0, 28, 0)
			Catalog.build_hair_04_topknot_bun(d.head_rig, {"color": Color(0.14, 0.12, 0.12), "bun_radius": 0.05})
			Catalog.invoke(it["fn"], d.head_rig, it["p"])
		elif t_type == "scarf":
			cam.size = 1.38
			cam.look_at_from_position(Vector3(0.0, 2.04, 6.0), Vector3(0.0, 2.00, 0.0), Vector3.UP)
			var d := _spawn_v20_doll(studio)
			d.rotation_degrees = Vector3(0, 6, 0)
			Catalog.build_hair_01_bob(d.head_rig, {"color": Color(0.88, 0.78, 0.56), "length": 0.20})
			Catalog.build_garment_08_babydoll_remake(d, {"color": Color(0.96, 0.95, 0.92)})
			Catalog.invoke(it["fn"], d, it["p"])
		elif t_type == "bag":
			cam.size = 0.78
			cam.look_at_from_position(Vector3(0.0, 0.36, 6.0), Vector3(0.0, 0.32, 0.0), Vector3.UP)
			var b := Catalog.build_prop_19_canvas_tote_bag(studio, {"bag_width": 0.36, "bag_height": 0.40})
			b.rotation_degrees = Vector3(0, -24, 0)
		elif t_type == "matryoshka":
			cam.size = 0.78
			cam.look_at_from_position(Vector3(0.0, 0.38, 6.0), Vector3(0.0, 0.32, 0.0), Vector3.UP)
			Catalog.build_prop_20_matryoshka_set(studio, {"layer_count": 4, "outer_height": 0.46, "outer_radius": 0.13, "open_first_shell": true})
		elif t_type == "souvenir":
			cam.size = 0.68
			cam.look_at_from_position(Vector3(0.0, 0.34, 6.0), Vector3(0.0, 0.28, 0.0), Vector3.UP)
			var s1 := Catalog.build_prop_21_souvenir_doll(studio, {"total_height": 0.50})
			s1.position = Vector3(-0.15, 0, 0)
			s1.rotation_degrees = Vector3(0, 14, 0)
			var s2 := Catalog.build_prop_21_souvenir_doll(studio, {"total_height": 0.44, "hair_style": 1, "dress_color": Color(0.24, 0.42, 0.38)})
			s2.position = Vector3(0.16, 0, 0)
			s2.rotation_degrees = Vector3(0, -18, 0)
		elif t_type == "peg":
			cam.size = 0.68
			cam.look_at_from_position(Vector3(0.0, 0.34, 6.0), Vector3(0.0, 0.28, 0.0), Vector3.UP)
			var p1 := Catalog.build_prop_22_sphere_cone_peg_doll(studio, {"head_radius": 0.108, "cone_height": 0.34, "hair_style": 0})
			p1.position = Vector3(-0.15, 0, 0)
			p1.rotation_degrees = Vector3(0, 12, 0)
			var p2 := Catalog.build_prop_22_sphere_cone_peg_doll(studio, {"head_radius": 0.118, "cone_height": 0.27, "cone_base_radius": 0.145, "cone_color": Color(0.78, 0.28, 0.26), "hair_style": 1, "hair_color": Color(0.42, 0.25, 0.16)})
			p2.position = Vector3(0.16, 0, 0)
			p2.rotation_degrees = Vector3(0, -16, 0)

	await _save_sheet_viewport(sheet["viewport"], "00_master_catalog_01_to_22.png")
