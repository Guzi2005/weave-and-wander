extends Control
const Doll = preload("res://scripts/game_body_doll.gd")
const CurveControl = preload("res://components/garment_curve_control.gd")
const Catalog = preload("res://captures/review_20261110/parametric_models_catalog.gd")

var doll: Node3D
var stage: Node3D
var prop_stage: Node3D
var camera: Camera3D
var viewport: SubViewport
var curve_editor: Control
var mode := 0
var style := 0
var phase := 0.0
var yaw := 0.0
var manual_omega := 0.0

# 3D Orbit & Pan Camera controls
var orbit: float = 0.35
var pitch: float = 0.12
var cam_distance: float = 7.0
var target_y: float = 1.35
var cam_size: float = 3.3
var _dragging_left := false
var _dragging_right := false

# Tab selection: 0 = Garment Study, 1 = Modular Slot Layering & Catalog Review
var current_tab: int = 1

# Garment Study variables
var _curve_name := "side_ease"
var _shape: Resource
var _body_signature := 0
var physics_fields: Dictionary = {}
var shape_fields: Dictionary = {}
var style_picker: OptionButton
var motion_picker: OptionButton
var status: Label
var _built_style := 0
var motion_toggle: CheckButton
var shape_toggle: CheckButton

# Container references for tab switching
var garment_study_panel: VBoxContainer
var catalog_panel: VBoxContainer
var tab_btn_catalog: Button
var tab_btn_study: Button

# Modular Layering Slot State
var active_slots := {
	"hair": "01",
	"top": "07",
	"outer": "none",
	"bottom": "14",
	"hat": "none",
	"prop": "none",
	"figurine": "none"
}

var slot_params := {
	"hair": {},
	"top": {},
	"outer": {},
	"bottom": {},
	"hat": {},
	"prop": {},
	"figurine": {}
}

# Active Color Palette
var current_skin_color := Color("f3d0be") # Natural warm peach
var current_hair_color := Color("211e1c") # Jet black
var current_eye_color := Color("1e1b1a")  # Obsidian dark brown
var current_garment_palette := {
	"main": Color("5b8a7c"),       # Vintage teal sage
	"trim": Color("ede6d6"),       # Natural cream ecru
	"detail": Color("825438"),     # Warm chestnut leather/horn
	"outer_main": Color("24334a"), # Deep collegiate navy
	"bottom_main": Color("786e61") # Khaki pleated shorts
}

# Motion & Physics State
var motion_mode: int = 0 # 0: Rest/Still, 1: Idle Breathe, 2: Continuous Spin, 3: Snap Turn, 4: Walk, 5: Start/Stop
var cloth_secondary_enabled := true
var dynamic_hair_sway_scale := 1.0
var omega_slider: HSlider
var omega_label: Label

# UI Containers
var slot_pickers: Dictionary = {}
var silhouette_controls_container: VBoxContainer
var active_tune_slot: String = "top"
var tune_slot_picker: OptionButton

const HAS_POCKET_IDS := ["07", "11", "12", "14", "19"]

const HAIR_SLOT_OPTIONS := [
	{"id": "none", "name": "【素体光头】(None / Bald Head)", "fn": ""},
	{"id": "01", "name": "#01 齐刘海内扣波波头 (Classic Bob)", "fn": "build_hair_01_bob"},
	{"id": "02", "name": "#02 挑染高马尾 (Perky High Ponytail)", "fn": "build_hair_02_high_ponytail"},
	{"id": "03", "name": "#03 温柔半扎长发 (Half-Up Long Hair)", "fn": "build_hair_03_half_up_long"},
	{"id": "04", "name": "#04 芭蕾高丸子头 (Ballet Topknot Bun)", "fn": "build_hair_04_topknot_bun"},
	{"id": "05", "name": "#05 偏分大波浪锁骨发 (Wavy Lob)", "fn": "build_hair_05_wavy_lob"},
	{"id": "06", "name": "#06 活力双马尾 (Playful Twin Pigtails)", "fn": "build_hair_06_twin_pigtails"}
]

const TOP_SLOT_OPTIONS := [
	{"id": "none", "name": "【裸身素体】(None / Bare Torso)", "fn": ""},
	{"id": "07", "name": "#07 古巴领短袖衬衫 (Cuban Shirt)", "fn": "build_garment_07_cuban_shirt_remake"},
	{"id": "10", "name": "#10 水手领衬衫 (Sailor Blouse)", "fn": "build_garment_10_sailor_blouse"},
	{"id": "13", "name": "#13 方领泡泡袖上衣 (Square-Neck Top)", "fn": "build_garment_13_square_neck_top"},
	{"id": "08", "name": "#08 荷叶边娃娃裙 (Babydoll One-Piece)", "fn": "build_garment_08_babydoll_remake"},
	{"id": "15", "name": "#15 挂脖A字连衣裙 (Shift Dress One-Piece)", "fn": "build_garment_15_mock_neck_shift_dress"}
]

const OUTER_SLOT_OPTIONS := [
	{"id": "none", "name": "【无外搭】(None / No Layer)", "fn": ""},
	{"id": "09", "name": "#09 学院风V领背心 (Preppy V-Vest)", "fn": "build_garment_09_preppy_vest_remake"},
	{"id": "11", "name": "#11 针织开衫 (Knit Cardigan)", "fn": "build_garment_11_knit_cardigan"},
	{"id": "12", "name": "#12 围裙背心裙 (Pinafore Dress)", "fn": "build_garment_12_pinafore_dress"}
]

const BOTTOM_SLOT_OPTIONS := [
	{"id": "none", "name": "【素体下身】(None / Bare Legs)", "fn": ""},
	{"id": "14", "name": "#14 高腰百褶短裤 (Pleated Bermuda Shorts)", "fn": "build_garment_14_pleated_shorts"},
	{"id": "trouser", "name": "经典修身长裤 (Classic Trousers)", "fn": "_build_default_trouser"}
]

const HAT_SLOT_OPTIONS := [
	{"id": "none", "name": "【无头饰】(None)", "fn": ""},
	{"id": "16", "name": "#16 彝族解放帽 (Yi Liberation Cap)", "fn": "build_hat_16_yi_liberation_cap"},
	{"id": "17", "name": "#17 彝族阿都圆檐尖帽 (Yi Adu Conical Hat)", "fn": "build_hat_17_yi_adu_hat"},
	{"id": "18", "name": "#18 爱沙尼亚传统头巾 (Estonian Headscarf)", "fn": "build_hat_18_estonian_headscarf"}
]

const PROP_SLOT_OPTIONS := [
	{"id": "none", "name": "【无道具】(None)", "fn": ""},
	{"id": "19", "name": "#19 帆布托特包 (Canvas Tote Bag)", "fn": "build_prop_19_canvas_tote_bag"}
]

const FIGURINE_OPTIONS := [
	{"id": "none", "name": "【使用模特】(Use Doll Mannequin)", "fn": ""},
	{"id": "20", "name": "#20 俄罗斯套娃 (Matryoshka Set)", "fn": "build_prop_20_matryoshka_set"},
	{"id": "21", "name": "#21 纪念品关节木偶 (Articulated Doll)", "fn": "build_prop_21_souvenir_doll"},
	{"id": "22", "name": "#22 球锥木偶 (Sphere-Cone Peg Doll)", "fn": "build_prop_22_sphere_cone_peg_doll"}
]


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen_size := DisplayServer.screen_get_size()
	var win_size := Vector2i(1420, 920)
	DisplayServer.window_set_size(win_size)
	DisplayServer.window_set_position(Vector2i(maxi(20, (screen_size.x - win_size.x) / 2), maxi(20, (screen_size.y - win_size.y) / 2)))
	DisplayServer.window_set_title("Weave & Wander · 交互调试台 (Garment Lab · 模块化槽位叠穿 & 物理动力学)")
	DisplayServer.window_move_to_foreground()

	var background := ColorRect.new()
	background.color = Color("ecf0ef")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	# 3D Viewport on the left
	var display := SubViewportContainer.new()
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display.stretch = true
	layout.add_child(display)

	viewport = SubViewport.new()
	viewport.size = Vector2i(1000, 850)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	display.add_child(viewport)
	display.gui_input.connect(_orbit_input)

	stage = Node3D.new()
	viewport.add_child(stage)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("edf1f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.70
	stage.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.15
	stage.add_child(light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(25, 150, 0)
	fill_light.light_energy = 0.50
	stage.add_child(fill_light)

	# Prop staging root for standalone figurines (#20, #21, #22)
	prop_stage = Node3D.new()
	prop_stage.name = "PropStage"
	stage.add_child(prop_stage)

	# Game Body Base Mannequin (V20 short-arm 0.045)
	doll = Doll.new()
	stage.add_child(doll)
	doll.process_mode = Node.PROCESS_MODE_INHERIT

	# Camera setup
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = cam_size
	camera.current = true

	# Right Controls Panel
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 400
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	var main_panel := VBoxContainer.new()
	main_panel.custom_minimum_size.x = 375
	main_panel.add_theme_constant_override("separation", 10)
	scroll.add_child(main_panel)

	# Header Title & Tab Bar
	var header := Label.new()
	header.text = "交互调试台 (Garment Lab 2.0)"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color("1d413a"))
	main_panel.add_child(header)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	main_panel.add_child(tab_bar)

	tab_btn_catalog = Button.new()
	tab_btn_catalog.text = "★ 模块化叠穿与模型调试"
	tab_btn_catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_btn_catalog.toggle_mode = true
	tab_btn_catalog.button_pressed = (current_tab == 1)
	tab_bar.add_child(tab_btn_catalog)

	tab_btn_study = Button.new()
	tab_btn_study.text = "衣形动力学 (Study)"
	tab_btn_study.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_btn_study.toggle_mode = true
	tab_btn_study.button_pressed = (current_tab == 0)
	tab_bar.add_child(tab_btn_study)

	tab_btn_catalog.pressed.connect(func() -> void: _switch_tab(1))
	tab_btn_study.pressed.connect(func() -> void: _switch_tab(0))

	# Quick Camera Preset Bar
	var cam_bar := HBoxContainer.new()
	cam_bar.add_theme_constant_override("separation", 4)
	main_panel.add_child(cam_bar)
	var cam_lbl := Label.new()
	cam_lbl.text = "视角:"
	cam_lbl.add_theme_color_override("font_color", Color("3f5953"))
	cam_bar.add_child(cam_lbl)

	var btn_cam_head := Button.new()
	btn_cam_head.text = "发型/头部"
	btn_cam_head.pressed.connect(func() -> void: _set_camera_view(2.15, 1.25, 0.35))
	cam_bar.add_child(btn_cam_head)

	var btn_cam_torso := Button.new()
	btn_cam_torso.text = "领口/上身"
	btn_cam_torso.pressed.connect(func() -> void: _set_camera_view(1.65, 2.05, 0.35))
	cam_bar.add_child(btn_cam_torso)

	var btn_cam_full := Button.new()
	btn_cam_full.text = "全身"
	btn_cam_full.pressed.connect(func() -> void: _set_camera_view(1.35, 3.30, 0.35))
	cam_bar.add_child(btn_cam_full)

	var sep_cam := HSeparator.new()
	main_panel.add_child(sep_cam)

	# --- Panel 1: Modular Layering & Catalog Review Panel ---
	catalog_panel = VBoxContainer.new()
	catalog_panel.add_theme_constant_override("separation", 10)
	main_panel.add_child(catalog_panel)
	_setup_modular_catalog_ui(catalog_panel)

	# --- Panel 2: Garment Study Panel ---
	garment_study_panel = VBoxContainer.new()
	garment_study_panel.add_theme_constant_override("separation", 8)
	main_panel.add_child(garment_study_panel)
	_setup_garment_study_ui(garment_study_panel)

	# Initialize tab view and load base mannequin
	_switch_tab(current_tab)
	_update_camera()


func _switch_tab(tab_idx: int) -> void:
	current_tab = tab_idx
	tab_btn_catalog.button_pressed = (tab_idx == 1)
	tab_btn_study.button_pressed = (tab_idx == 0)
	catalog_panel.visible = (tab_idx == 1)
	garment_study_panel.visible = (tab_idx == 0)

	if tab_idx == 1:
		_rebuild_modular_mannequin()
	else:
		if is_instance_valid(prop_stage):
			for child in prop_stage.get_children():
				child.free()
		doll.visible = true
		doll.position = Vector3.ZERO
		doll.rotation = Vector3.ZERO
		_rebuild()


func _set_camera_view(new_target_y: float, new_size: float, new_orbit: float) -> void:
	target_y = new_target_y
	cam_size = new_size
	camera.size = cam_size
	orbit = new_orbit
	_update_camera()


# ============================================================================
# BASE MANNEQUIN (素体) & NON-DESTRUCTIVE REBUILD
# ============================================================================

func _reset_doll_to_base_mannequin() -> void:
	if not is_instance_valid(doll):
		return

	doll.costume_collection = ""
	doll.hair_style = -1
	doll.reference_costume = false

	# Clear hair
	Catalog.clear_hair_slot(doll)
	# Clear clothes root
	if doll.clothes_root != null:
		for ch in doll.clothes_root.get_children():
			ch.free()

	# Clear hat & prop
	Catalog.clear_hat_slot(doll)
	Catalog.clear_prop_slot(doll)

	# Unhide bare limbs on V20 mannequin
	doll.set_underbody_mode(true)
	var br := Catalog._resolve_body_rig(doll)
	for arm_name in ["ArmLeft", "ArmRight"]:
		var arm := br.get_node_or_null(arm_name)
		if arm != null:
			for sub in arm.get_children():
				if str(sub.name) in ["ArmMannequin", "ArmMannequinThumb"]:
					sub.visible = true
				else:
					sub.free()
	for leg_name in ["LegLeft", "LegRight"]:
		var leg := br.get_node_or_null(leg_name)
		if leg != null:
			for sub in leg.get_children():
				if str(sub.name).begins_with("CustomShortsLeg"):
					sub.free()
				elif str(sub.name).begins_with("LegMannequin"):
					sub.visible = true
				elif str(sub.name).begins_with("Trouser"):
					sub.visible = false

	_apply_skin_color(current_skin_color)
	_apply_eye_color(current_eye_color)


func _rebuild_modular_mannequin() -> void:
	if not is_instance_valid(doll):
		return

	# Handle standalone figurine mode (#20, #21, #22)
	var fig_id: String = active_slots.get("figurine", "none")
	if fig_id != "none":
		doll.visible = false
		if is_instance_valid(prop_stage):
			for ch in prop_stage.get_children(): ch.free()
			var fn_map := {"20": "build_prop_20_matryoshka_set", "21": "build_prop_21_souvenir_doll", "22": "build_prop_22_sphere_cone_peg_doll"}
			if fn_map.has(fig_id):
				Catalog.invoke(fn_map[fig_id], prop_stage, slot_params.get("figurine", {}))
				prop_stage.position = Vector3(0, 1.15, 0)
				_set_camera_view(1.15, 1.65, 0.35)
		return

	doll.visible = true
	if is_instance_valid(prop_stage):
		for ch in prop_stage.get_children(): ch.free()

	# 1. Reset doll to pristine bare mannequin
	_reset_doll_to_base_mannequin()

	# 2. Build Hair Slot
	var hair_id: String = active_slots.get("hair", "none")
	if hair_id != "none":
		for h_opt in HAIR_SLOT_OPTIONS:
			if h_opt["id"] == hair_id and not h_opt["fn"].is_empty():
				var hp: Dictionary = slot_params.get("hair", {}).duplicate()
				hp["color"] = current_hair_color
				Catalog.invoke(h_opt["fn"], doll, hp)
				break

	# 3. Build Top Slot (Inner / Blouse / Shirt)
	var top_id: String = active_slots.get("top", "none")
	if top_id != "none":
		for t_opt in TOP_SLOT_OPTIONS:
			if t_opt["id"] == top_id and not t_opt["fn"].is_empty():
				var tp: Dictionary = slot_params.get("top", {}).duplicate()
				tp["slot_mode"] = true
				tp["slot_tag"] = "top"
				tp["color"] = current_garment_palette["main"]
				tp["collar_color"] = current_garment_palette["trim"]
				tp["trim_color"] = current_garment_palette["trim"]
				tp["button_color"] = current_garment_palette["detail"]
				Catalog.invoke(t_opt["fn"], doll, tp)
				break

	# 4. Build Outer Slot (Vest / Cardigan / Pinafore Overall)
	var outer_id: String = active_slots.get("outer", "none")
	if outer_id != "none":
		for o_opt in OUTER_SLOT_OPTIONS:
			if o_opt["id"] == outer_id and not o_opt["fn"].is_empty():
				var op: Dictionary = slot_params.get("outer", {}).duplicate()
				op["slot_mode"] = true
				op["slot_tag"] = "outer"
				op["color"] = current_garment_palette.get("outer_main", current_garment_palette["main"].darkened(0.18))
				op["stripe_color"] = current_garment_palette["trim"]
				op["rib_color"] = current_garment_palette["trim"]
				op["button_color"] = current_garment_palette["detail"]
				Catalog.invoke(o_opt["fn"], doll, op)
				break

	# 5. Build Bottom Slot (Shorts / Trousers)
	var bottom_id: String = active_slots.get("bottom", "none")
	if bottom_id == "14":
		var bp: Dictionary = slot_params.get("bottom", {}).duplicate()
		bp["slot_mode"] = true
		bp["slot_tag"] = "bottom"
		bp["color"] = current_garment_palette.get("bottom_main", current_garment_palette["main"].darkened(0.08))
		bp["belt_color"] = current_garment_palette["detail"]
		Catalog.build_garment_14_pleated_shorts(doll, bp)
	elif bottom_id == "trouser":
		_build_default_trouser()

	# 6. Build Headwear Slot (Hat / Scarf)
	var hat_id: String = active_slots.get("hat", "none")
	if hat_id != "none":
		for h_opt in HAT_SLOT_OPTIONS:
			if h_opt["id"] == hat_id and not h_opt["fn"].is_empty():
				var htp: Dictionary = slot_params.get("hat", {}).duplicate()
				Catalog.invoke(h_opt["fn"], doll, htp)
				break

	# 7. Build Prop Slot (Canvas Tote Bag)
	var prop_id: String = active_slots.get("prop", "none")
	if prop_id == "19":
		var pp: Dictionary = slot_params.get("prop", {}).duplicate()
		Catalog.build_prop_19_canvas_tote_bag(doll, pp)

	_refresh_silhouette_controls()


func _build_default_trouser() -> void:
	var br := Catalog._resolve_body_rig(doll)
	for leg_name in ["LegLeft", "LegRight"]:
		var leg := br.get_node_or_null(leg_name)
		if leg != null:
			var tr := leg.get_node_or_null("Trouser")
			if tr != null:
				tr.visible = true
				var mat: ShaderMaterial = tr.material_override
				if mat != null:
					mat.set_shader_parameter("pigment", current_garment_palette.get("bottom_main", Color("38414b")))


# ============================================================================
# LIVE COLOR MODIFIERS
# ============================================================================

func _apply_skin_color(color: Color) -> void:
	current_skin_color = color
	if not is_instance_valid(doll): return
	var br := Catalog._resolve_body_rig(doll)
	var hr := Catalog._resolve_head_rig(doll)

	# Update Torso & Pelvis
	for part_name in ["MannequinTorso", "PelvisUnderbody", "Neck"]:
		var p := br.get_node_or_null(part_name) as MeshInstance3D
		if p != null and p.material_override != null:
			p.material_override.set_shader_parameter("pigment", color)

	# Update Head, Ears, Nose
	if hr != null:
		for part_name in ["Head", "Ear", "EarInner", "RoundNose"]:
			var p := hr.get_node_or_null(part_name) as MeshInstance3D
			if p != null and p.material_override != null:
				p.material_override.set_shader_parameter("pigment", color if part_name != "EarInner" else color.darkened(0.12))

	# Update Limbs
	for arm_name in ["ArmLeft", "ArmRight"]:
		var arm := br.get_node_or_null(arm_name)
		if arm != null:
			for sub in arm.get_children():
				if str(sub.name) in ["ArmMannequin", "ArmMannequinThumb", "Hand"]:
					var m := sub as MeshInstance3D
					if m != null and m.material_override != null:
						m.material_override.set_shader_parameter("pigment", color)

	for leg_name in ["LegLeft", "LegRight"]:
		var leg := br.get_node_or_null(leg_name)
		if leg != null:
			var lm := leg.get_node_or_null("LegMannequin") as MeshInstance3D
			if lm != null and lm.material_override != null:
				lm.material_override.set_shader_parameter("pigment", color)


func _apply_eye_color(color: Color) -> void:
	current_eye_color = color
	if not is_instance_valid(doll): return
	var hr := Catalog._resolve_head_rig(doll)
	if hr == null: return
	for child in hr.get_children():
		if child.name == "BeanEye" or child.get_meta("eye_state", "") == "open":
			var m := child as MeshInstance3D
			if m != null and m.material_override != null:
				m.material_override.set_shader_parameter("pigment", color)


func _apply_hair_color(color: Color) -> void:
	current_hair_color = color
	if not is_instance_valid(doll) or doll.hair_root == null: return
	for child in doll.hair_root.get_children():
		_recursively_set_pigment(child, color)


func _recursively_set_pigment(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override != null:
			# Preserve scrunchie / ribbon colors
			if not (mi.name.contains("Tie") or mi.name.contains("Ribbon") or mi.name.contains("Scrunchie")):
				mi.material_override.set_shader_parameter("pigment", color)
	for ch in node.get_children():
		_recursively_set_pigment(ch, color)


# ============================================================================
# TAB 1: MODULAR CATALOG & LAYERED REVIEW UI
# ============================================================================

func _setup_modular_catalog_ui(parent: Control) -> void:
	# SECTION 1: MOTION & DYNAMICS
	_build_section_header(parent, "① 动作与物理动力学 (Motion & Physics)")
	var motion_box := VBoxContainer.new()
	motion_box.add_theme_constant_override("separation", 6)
	parent.add_child(motion_box)

	var motion_lbl := Label.new()
	motion_lbl.text = "预设动态模式:"
	motion_lbl.add_theme_color_override("font_color", Color("344a49"))
	motion_box.add_child(motion_lbl)

	var m_grid := GridContainer.new()
	m_grid.columns = 3
	m_grid.add_theme_constant_override("h_separation", 6)
	m_grid.add_theme_constant_override("v_separation", 4)
	motion_box.add_child(m_grid)

	var motion_modes := [
		{"name": "静止 (Rest)", "mode": 0},
		{"name": "待机呼吸 (Idle)", "mode": 1},
		{"name": "自转离心 (Spin)", "mode": 2},
		{"name": "急转摆动 (Snap)", "mode": 3},
		{"name": "走步摇摆 (Walk)", "mode": 4},
		{"name": "起停冲击 (Jolt)", "mode": 5}
	]
	for mm in motion_modes:
		var b := Button.new()
		b.text = mm["name"]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m_idx: int = mm["mode"]
		b.pressed.connect(func() -> void:
			motion_mode = m_idx
			if m_idx == 0:
				manual_omega = 0.0
				if is_instance_valid(omega_slider): omega_slider.value = 0.0)
		m_grid.add_child(b)

	# Interactive Angular Velocity Slider
	var omega_row := VBoxContainer.new()
	omega_row.add_theme_constant_override("separation", 2)
	motion_box.add_child(omega_row)

	var o_header := HBoxContainer.new()
	omega_row.add_child(o_header)

	omega_label = Label.new()
	omega_label.text = "实时角速度 ω: 0.0 rad/s (支持Shift+左键拖拽旋转)"
	omega_label.add_theme_color_override("font_color", Color("344a49"))
	omega_label.add_theme_font_size_override("font_size", 12)
	omega_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o_header.add_child(omega_label)

	var btn_zero_omega := Button.new()
	btn_zero_omega.text = "归零"
	btn_zero_omega.pressed.connect(func() -> void:
		manual_omega = 0.0
		omega_slider.value = 0.0
		omega_label.text = "实时角速度 ω: 0.0 rad/s")
	o_header.add_child(btn_zero_omega)

	omega_slider = HSlider.new()
	omega_slider.min_value = -10.0
	omega_slider.max_value = 10.0
	omega_slider.step = 0.2
	omega_slider.value = 0.0
	omega_row.add_child(omega_slider)
	omega_slider.value_changed.connect(func(val: float) -> void:
		manual_omega = val
		omega_label.text = "实时角速度 ω: %.1f rad/s" % val)

	# Secondary Motion & Hair Toggles
	var toggle_row := HBoxContainer.new()
	motion_box.add_child(toggle_row)

	var cb_cloth := CheckBox.new()
	cb_cloth.text = "布料次级动态"
	cb_cloth.button_pressed = true
	cb_cloth.toggled.connect(func(val: bool) -> void:
		cloth_secondary_enabled = val
		if doll.skirt_fabric != null: doll.skirt_fabric.enabled = val)
	toggle_row.add_child(cb_cloth)

	var cb_hair := CheckBox.new()
	cb_hair.text = "发丝物理摆动"
	cb_hair.button_pressed = true
	cb_hair.toggled.connect(func(val: bool) -> void:
		dynamic_hair_sway_scale = (1.0 if val else 0.0))
	toggle_row.add_child(cb_hair)

	parent.add_child(HSeparator.new())

	# SECTION 2: MANNEQUIN & COLORS
	_build_section_header(parent, "② 模特素体与色彩定制 (Mannequin & Colors)")
	var color_box := VBoxContainer.new()
	color_box.add_theme_constant_override("separation", 6)
	parent.add_child(color_box)

	# Skin Tone Swatches
	var skin_row := HBoxContainer.new()
	color_box.add_child(skin_row)
	var skin_lbl := Label.new()
	skin_lbl.text = "素体肤色:"
	skin_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_row.add_child(skin_lbl)

	var cp_skin := ColorPickerButton.new()
	cp_skin.color = current_skin_color
	cp_skin.custom_minimum_size = Vector2(40, 24)
	skin_row.add_child(cp_skin)
	cp_skin.color_changed.connect(_apply_skin_color)

	var skin_presets := [
		{"name": "粉白", "color": Color("f8dfd4")},
		{"name": "自然", "color": Color("f3d0be")},
		{"name": "小麦", "color": Color("dca886")},
		{"name": "原木素体", "color": Color("c8a27a")}
	]
	for sp in skin_presets:
		var b := Button.new()
		b.text = sp["name"]
		var c: Color = sp["color"]
		b.pressed.connect(func() -> void:
			cp_skin.color = c
			_apply_skin_color(c))
		skin_row.add_child(b)

	# Hair Color Swatches
	var hair_row := HBoxContainer.new()
	color_box.add_child(hair_row)
	var hair_lbl := Label.new()
	hair_lbl.text = "发丝发色:"
	hair_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hair_row.add_child(hair_lbl)

	var cp_hair := ColorPickerButton.new()
	cp_hair.color = current_hair_color
	cp_hair.custom_minimum_size = Vector2(40, 24)
	hair_row.add_child(cp_hair)
	cp_hair.color_changed.connect(_apply_hair_color)

	var hair_presets := [
		{"name": "黑", "color": Color("211e1c")},
		{"name": "栗棕", "color": Color("4c3529")},
		{"name": "蜂茶", "color": Color("987042")},
		{"name": "浅金", "color": Color("d8c69c")},
		{"name": "粉", "color": Color("cf7b8a")},
		{"name": "蓝", "color": Color("4a6782")}
	]
	for hp in hair_presets:
		var b := Button.new()
		b.text = hp["name"]
		var c: Color = hp["color"]
		b.pressed.connect(func() -> void:
			cp_hair.color = c
			_apply_hair_color(c))
		hair_row.add_child(b)

	# Eye Color Swatches
	var eye_row := HBoxContainer.new()
	color_box.add_child(eye_row)
	var eye_lbl := Label.new()
	eye_lbl.text = "瞳孔瞳色:"
	eye_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eye_row.add_child(eye_lbl)

	var cp_eye := ColorPickerButton.new()
	cp_eye.color = current_eye_color
	cp_eye.custom_minimum_size = Vector2(40, 24)
	eye_row.add_child(cp_eye)
	cp_eye.color_changed.connect(_apply_eye_color)

	var eye_presets := [
		{"name": "曜黑", "color": Color("1e1b1a")},
		{"name": "琥珀", "color": Color("86532d")},
		{"name": "蓝宝", "color": Color("2b578c")},
		{"name": "祖母绿", "color": Color("2d6b49")},
		{"name": "紫晶", "color": Color("5d3c73")}
	]
	for ep in eye_presets:
		var b := Button.new()
		b.text = ep["name"]
		var c: Color = ep["color"]
		b.pressed.connect(func() -> void:
			cp_eye.color = c
			_apply_eye_color(c))
		eye_row.add_child(b)

	# Garment Palette Swatches (Main, Trim, Detail)
	var g_palette_row := HBoxContainer.new()
	color_box.add_child(g_palette_row)
	var gp_lbl := Label.new()
	gp_lbl.text = "服装色彩:"
	gp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g_palette_row.add_child(gp_lbl)

	var cp_g_main := ColorPickerButton.new()
	cp_g_main.color = current_garment_palette["main"]
	cp_g_main.tooltip_text = "服装主色 (Main Cloth Color)"
	cp_g_main.custom_minimum_size = Vector2(36, 24)
	g_palette_row.add_child(cp_g_main)
	cp_g_main.color_changed.connect(func(c: Color) -> void:
		current_garment_palette["main"] = c
		_rebuild_modular_mannequin())

	var cp_g_trim := ColorPickerButton.new()
	cp_g_trim.color = current_garment_palette["trim"]
	cp_g_trim.tooltip_text = "服装辅色/包边 (Trim & Accent Color)"
	cp_g_trim.custom_minimum_size = Vector2(36, 24)
	g_palette_row.add_child(cp_g_trim)
	cp_g_trim.color_changed.connect(func(c: Color) -> void:
		current_garment_palette["trim"] = c
		_rebuild_modular_mannequin())

	var cp_g_detail := ColorPickerButton.new()
	cp_g_detail.color = current_garment_palette["detail"]
	cp_g_detail.tooltip_text = "扣饰/腰带/细节 (Button & Detail Color)"
	cp_g_detail.custom_minimum_size = Vector2(36, 24)
	g_palette_row.add_child(cp_g_detail)
	cp_g_detail.color_changed.connect(func(c: Color) -> void:
		current_garment_palette["detail"] = c
		_rebuild_modular_mannequin())

	parent.add_child(HSeparator.new())

	# SECTION 3: MODULAR SLOT LAYERING
	_build_section_header(parent, "③ 模块化槽位叠穿 (Modular Slot Layering)")
	var layer_box := VBoxContainer.new()
	layer_box.add_theme_constant_override("separation", 6)
	parent.add_child(layer_box)

	# Quick Outfit Layering Presets Bar
	var preset_bar := HBoxContainer.new()
	preset_bar.add_theme_constant_override("separation", 4)
	layer_box.add_child(preset_bar)

	var btn_bare := Button.new()
	btn_bare.text = "素体 (Bare)"
	btn_bare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bare.pressed.connect(func() -> void:
		_set_active_slots("none", "none", "none", "none", "none", "none", "none"))
	preset_bar.add_child(btn_bare)

	var btn_preppy := Button.new()
	btn_preppy.text = "学院叠穿"
	btn_preppy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_preppy.pressed.connect(func() -> void:
		_set_active_slots("01", "10", "09", "14", "none", "none", "none"))
	preset_bar.add_child(btn_preppy)

	var btn_cuban := Button.new()
	btn_cuban.text = "度假古巴领"
	btn_cuban.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cuban.pressed.connect(func() -> void:
		_set_active_slots("05", "07", "none", "14", "none", "19", "none"))
	preset_bar.add_child(btn_cuban)

	var btn_pinafore := Button.new()
	btn_pinafore.text = "背心工装裙"
	btn_pinafore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_pinafore.pressed.connect(func() -> void:
		_set_active_slots("04", "07", "12", "none", "16", "none", "none"))
	preset_bar.add_child(btn_pinafore)

	# Slot Pickers Grid
	var s_grid := GridContainer.new()
	s_grid.columns = 2
	s_grid.add_theme_constant_override("h_separation", 6)
	s_grid.add_theme_constant_override("v_separation", 4)
	layer_box.add_child(s_grid)

	_add_slot_selector(s_grid, "发型槽 (Hair):", "hair", HAIR_SLOT_OPTIONS)
	_add_slot_selector(s_grid, "上装/内搭 (Top):", "top", TOP_SLOT_OPTIONS)
	_add_slot_selector(s_grid, "外搭/叠穿 (Outer):", "outer", OUTER_SLOT_OPTIONS)
	_add_slot_selector(s_grid, "下装槽 (Bottom):", "bottom", BOTTOM_SLOT_OPTIONS)
	_add_slot_selector(s_grid, "头饰槽 (Headwear):", "hat", HAT_SLOT_OPTIONS)
	_add_slot_selector(s_grid, "配饰槽 (Prop):", "prop", PROP_SLOT_OPTIONS)
	_add_slot_selector(s_grid, "独立摆件 (Figurine):", "figurine", FIGURINE_OPTIONS)

	parent.add_child(HSeparator.new())

	# SECTION 4: SILHOUETTE SPECIFIC PARAMETERS
	_build_section_header(parent, "④ 当前形制专属细节 (Silhouette Parameters)")
	var tune_box := VBoxContainer.new()
	tune_box.add_theme_constant_override("separation", 6)
	parent.add_child(tune_box)

	var tune_sel_row := HBoxContainer.new()
	tune_box.add_child(tune_sel_row)
	var tune_lbl := Label.new()
	tune_lbl.text = "调节形制:"
	tune_lbl.add_theme_color_override("font_color", Color("344a49"))
	tune_sel_row.add_child(tune_lbl)

	tune_slot_picker = OptionButton.new()
	tune_slot_picker.add_item("发型 (Hair)")
	tune_slot_picker.add_item("上装/内搭 (Top)")
	tune_slot_picker.add_item("外搭/叠穿 (Outer)")
	tune_slot_picker.add_item("下装 (Bottom)")
	tune_slot_picker.add_item("头饰 (Hat)")
	tune_slot_picker.add_item("配饰 (Prop)")
	tune_slot_picker.add_item("独立摆件 (Figurine)")
	tune_slot_picker.select(1)
	tune_slot_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tune_slot_picker.item_selected.connect(func(idx: int) -> void:
		active_tune_slot = ["hair", "top", "outer", "bottom", "hat", "prop", "figurine"][idx]
		_refresh_silhouette_controls())
	tune_sel_row.add_child(tune_slot_picker)

	# Quick Buttons Bar for parameters
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	tune_box.add_child(btn_row)

	var btn_restore := Button.new()
	btn_restore.text = "★ 回退为细化前样式"
	btn_restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_restore.pressed.connect(_restore_active_slot_pre_refinement)
	btn_row.add_child(btn_restore)

	var btn_default := Button.new()
	btn_default.text = "重置默认值"
	btn_default.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_default.pressed.connect(func() -> void:
		slot_params[active_tune_slot].clear()
		_rebuild_modular_mannequin())
	btn_row.add_child(btn_default)

	silhouette_controls_container = VBoxContainer.new()
	silhouette_controls_container.add_theme_constant_override("separation", 6)
	tune_box.add_child(silhouette_controls_container)


func _set_active_slots(h: String, t: String, o: String, b: String, ht: String, p: String, f: String) -> void:
	active_slots["hair"] = h
	active_slots["top"] = t
	active_slots["outer"] = o
	active_slots["bottom"] = b
	active_slots["hat"] = ht
	active_slots["prop"] = p
	active_slots["figurine"] = f
	_sync_slot_pickers()
	_rebuild_modular_mannequin()


func _sync_slot_pickers() -> void:
	var slot_options_map := {
		"hair": HAIR_SLOT_OPTIONS,
		"top": TOP_SLOT_OPTIONS,
		"outer": OUTER_SLOT_OPTIONS,
		"bottom": BOTTOM_SLOT_OPTIONS,
		"hat": HAT_SLOT_OPTIONS,
		"prop": PROP_SLOT_OPTIONS,
		"figurine": FIGURINE_OPTIONS
	}
	for slot in slot_pickers:
		var ob: OptionButton = slot_pickers[slot]
		var cur_id: String = active_slots.get(slot, "none")
		var opts: Array = slot_options_map[slot]
		for i in opts.size():
			if opts[i]["id"] == cur_id:
				ob.select(i)
				break


func _add_slot_selector(parent: Control, label_text: String, slot_key: String, options: Array) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", Color("344a49"))
	lbl.add_theme_font_size_override("font_size", 12)
	col.add_child(lbl)

	var ob := OptionButton.new()
	for opt in options:
		ob.add_item(opt["name"])
	ob.select(0)
	for i in options.size():
		if options[i]["id"] == active_slots[slot_key]:
			ob.select(i)
			break
	ob.item_selected.connect(func(idx: int) -> void:
		active_slots[slot_key] = options[idx]["id"]
		if slot_key == "figurine" and active_slots[slot_key] != "none":
			active_tune_slot = "figurine"
			tune_slot_picker.select(6)
		else:
			active_tune_slot = slot_key
			var slot_names := ["hair", "top", "outer", "bottom", "hat", "prop", "figurine"]
			var s_idx: int = slot_names.find(slot_key)
			if s_idx >= 0: tune_slot_picker.select(s_idx)
		_rebuild_modular_mannequin())
	col.add_child(ob)
	slot_pickers[slot_key] = ob


func _build_section_header(parent: Control, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("204d43"))
	parent.add_child(lbl)


# ============================================================================
# SECTION 4: DYNAMIC SILHOUETTE CONTROLS & STRICT POCKET RULE
# ============================================================================

func _refresh_silhouette_controls() -> void:
	for child in silhouette_controls_container.get_children():
		child.free()

	var item_id: String = active_slots.get(active_tune_slot, "none")
	if item_id == "none":
		var empty_lbl := Label.new()
		empty_lbl.text = "(当前槽位未穿戴任何形制)"
		empty_lbl.add_theme_color_override("font_color", Color("7a928e"))
		silhouette_controls_container.add_child(empty_lbl)
		return

	var params: Dictionary = slot_params.get(active_tune_slot, {})

	# Pocket toggle: STRICT RULE - ONLY displayed if the garment silhouette genuinely has pockets!
	if item_id in HAS_POCKET_IDS:
		_add_checkbox(silhouette_controls_container, "衣袋开关 (Pocket Enabled)", "pocket_enabled", true, params, func(val: bool) -> void:
			params["pocket_enabled"] = val
			_rebuild_modular_mannequin())

	# Silhouette specific sliders
	if active_tune_slot == "hair":
		_add_checkbox(silhouette_controls_container, "发片分缕 (split locks)", "split", true, params, func(val: bool) -> void:
			params["split"] = val
			_rebuild_modular_mannequin())
		_add_slider(silhouette_controls_container, "发缕波浪 (wavy amp)", "wavy", 0.0, 0.08, 0.005, 0.0, params)
		_add_slider(silhouette_controls_container, "发梢斜切角 (cut angle °)", "cut_angle", -35.0, 35.0, 2.5, 0.0, params)
		_add_slider(silhouette_controls_container, "发缕单宽 (strand width)", "strand_width", 0.02, 0.08, 0.004, 0.046, params)
		_add_slider(silhouette_controls_container, "发缕间距 (strand gap)", "strand_gap", -0.015, 0.025, 0.002, 0.0, params)
		_add_slider(silhouette_controls_container, "发梢收尖 (tip taper)", "tip_taper", 0.0, 0.90, 0.05, 0.55, params)
		_add_slider(silhouette_controls_container, "长度倍率 (length scale)", "length_scale", 0.60, 1.45, 0.05, 1.0, params)

		if item_id in ["02", "06"]:
			_add_checkbox(silhouette_controls_container, "露出耳朵 (expose ears & sideburns)", "expose_ears", true, params, func(val: bool) -> void:
				params["expose_ears"] = val
				_rebuild_modular_mannequin())

		if item_id == "03":
			_add_option(silhouette_controls_container, "编发样式 (braid style)", ["3股交织编发 (three_strand)", "原版光滑扭辫 (simple)"], func(opt_idx: int) -> void:
				params["braid_style"] = ("three_strand" if opt_idx == 0 else "simple")
				_rebuild_modular_mannequin())

		if item_id == "04":
			_add_slider(silhouette_controls_container, "丸子贴合位置 (0:头顶 ~ 1:脑后)", "bun_position", 0.0, 1.0, 0.05, 0.0, params)
			_add_slider(silhouette_controls_container, "丸子半径 (bun radius)", "bun_radius", 0.08, 0.20, 0.01, 0.142, params)

	elif item_id == "07":
		_add_slider(silhouette_controls_container, "衣长 (garment length)", "garment_length", 0.0, 1.0, 0.05, 0.52, params)
		_add_slider(silhouette_controls_container, "领口展开 (collar spread)", "collar_spread", 0.72, 1.45, 0.05, 1.05, params)
		_add_slider(silhouette_controls_container, "袖长 (sleeve length)", "sleeve_length", 0.16, 0.42, 0.02, 0.27, params)
		_add_slider(silhouette_controls_container, "身筒松量 (body ease)", "body_ease", 0.016, 0.052, 0.004, 0.028, params)

	elif item_id == "08":
		_add_slider(silhouette_controls_container, "荷叶边裙摆张力 (flare)", "flare_amount", 0.04, 0.22, 0.01, 0.105, params)
		_add_slider(silhouette_controls_container, "衣长 (garment length)", "garment_length", 0.0, 1.0, 0.05, 0.55, params)
		_add_slider(silhouette_controls_container, "泡泡袖充盈度 (puff volume)", "puff_volume", 0.01, 0.08, 0.005, 0.038, params)

	elif item_id == "09":
		_add_slider(silhouette_controls_container, "V领深度 (v depth)", "v_depth", 0.16, 0.36, 0.01, 0.27, params)
		_add_slider(silhouette_controls_container, "肩宽比例 (shoulder width)", "shoulder_width", 0.82, 1.15, 0.02, 1.0, params)
		_add_slider(silhouette_controls_container, "衣长 (garment length)", "garment_length", 0.0, 1.0, 0.05, 0.48, params)
		_add_checkbox(silhouette_controls_container, "内置内搭衬衫 (layered shirt)", "layered_shirt", false, params, func(val: bool) -> void:
			params["layered_shirt"] = val
			_rebuild_modular_mannequin())

	elif item_id == "10":
		_add_slider(silhouette_controls_container, "领巾背片下垂 (collar drop)", "collar_drop", 0.14, 0.32, 0.01, 0.22, params)
		_add_slider(silhouette_controls_container, "袖长 (sleeve length)", "sleeve_length", 0.16, 0.44, 0.02, 0.26, params)
		_add_slider(silhouette_controls_container, "领带长度 (tie length)", "tie_length", 0.10, 0.28, 0.01, 0.18, params)

	elif item_id == "11":
		_add_slider(silhouette_controls_container, "衣长 (garment length)", "garment_length", 0.0, 1.0, 0.05, 0.58, params)
		_add_slider(silhouette_controls_container, "V领开深 (v drop)", "v_drop", 0.16, 0.38, 0.02, 0.26, params)
		_add_slider(silhouette_controls_container, "衣袋缩放 (pocket scale)", "pocket_scale", 0.60, 1.40, 0.05, 1.0, params)
		_add_checkbox(silhouette_controls_container, "内置吊带内搭 (has inner)", "has_inner", false, params, func(val: bool) -> void:
			params["has_inner"] = val
			_rebuild_modular_mannequin())

	elif item_id == "12":
		_add_slider(silhouette_controls_container, "裙长 (skirt length)", "skirt_length", 0.0, 1.0, 0.05, 0.52, params)
		_add_slider(silhouette_controls_container, "裙摆张力 (skirt flare)", "skirt_flare", 0.06, 0.24, 0.01, 0.13, params)
		_add_slider(silhouette_controls_container, "胸前围布高度 (bib height)", "bib_height", 0.22, 0.42, 0.02, 0.34, params)
		_add_checkbox(silhouette_controls_container, "内置圆领衬衫 (has inner)", "has_inner", false, params, func(val: bool) -> void:
			params["has_inner"] = val
			_rebuild_modular_mannequin())

	elif item_id == "13":
		_add_slider(silhouette_controls_container, "方领宽度 (neck width)", "neck_width", 0.07, 0.14, 0.005, 0.102, params)
		_add_slider(silhouette_controls_container, "方领深度 (neck depth)", "neck_depth", 0.10, 0.22, 0.01, 0.165, params)
		_add_slider(silhouette_controls_container, "法式泡泡袖 (puff size)", "puff_size", 0.02, 0.08, 0.005, 0.046, params)

	elif item_id == "14":
		_add_slider(silhouette_controls_container, "裤长/内长 (inseam length)", "inseam_length", 0.0, 1.0, 0.05, 0.50, params)
		_add_slider(silhouette_controls_container, "阔腿张力 (leg flare)", "leg_flare", 0.01, 0.08, 0.005, 0.030, params)
		_add_slider(silhouette_controls_container, "卷边裤脚 (cuff height)", "cuff_height", 0.01, 0.07, 0.005, 0.038, params)
		_add_checkbox(silhouette_controls_container, "内置针织上衣 (has top)", "has_top", false, params, func(val: bool) -> void:
			params["has_top"] = val
			_rebuild_modular_mannequin())

	elif item_id == "15":
		_add_slider(silhouette_controls_container, "裙长 (dress length)", "dress_length", 0.0, 1.0, 0.05, 0.55, params)
		_add_slider(silhouette_controls_container, "A字张力 (hem flare)", "hem_flare", 0.08, 0.24, 0.01, 0.155, params)
		_add_slider(silhouette_controls_container, "半高领高 (collar height)", "collar_height", 0.04, 0.10, 0.005, 0.068, params)

	elif item_id == "16":
		_add_slider(silhouette_controls_container, "桶高 (barrel height)", "barrel_height", 0.08, 0.22, 0.01, 0.14, params)
		_add_slider(silhouette_controls_container, "桶半径 (cap radius)", "cap_radius", 0.28, 0.38, 0.01, 0.325, params)
		_add_slider(silhouette_controls_container, "帽舌长度 (visor length)", "visor_length", 0.04, 0.14, 0.01, 0.088, params)

	elif item_id == "17":
		_add_slider(silhouette_controls_container, "圆锥高度 (cone height)", "cone_height", 0.16, 0.36, 0.02, 0.25, params)
		_add_slider(silhouette_controls_container, "圆檐展开半径 (brim radius)", "brim_radius", 0.34, 0.54, 0.02, 0.44, params)

	elif item_id == "18":
		_add_slider(silhouette_controls_container, "贴合半径 (snug radius)", "snug_radius", 0.29, 0.35, 0.005, 0.312, params)
		_add_slider(silhouette_controls_container, "后系绳下垂 (knot drop)", "knot_drop", 0.10, 0.28, 0.01, 0.18, params)

	elif item_id == "19":
		_add_slider(silhouette_controls_container, "包身宽度 (bag width)", "bag_width", 0.16, 0.42, 0.01, 0.34, params)
		_add_slider(silhouette_controls_container, "包身高度 (bag height)", "bag_height", 0.20, 0.48, 0.01, 0.38, params)
		_add_slider(silhouette_controls_container, "提手下垂 (strap drop)", "strap_drop", 0.14, 0.36, 0.01, 0.26, params)

	elif item_id == "22":
		_add_option(silhouette_controls_container, "木雕发型 (hair style)", ["0: 纯净光头车木 (无发)", "1: 车木顶丸子发髻", "2: 左右双丸子木雕"], func(opt_idx: int) -> void:
			params["hair_style"] = opt_idx
			_rebuild_modular_mannequin())


func _restore_active_slot_pre_refinement() -> void:
	var params: Dictionary = slot_params.get(active_tune_slot, {})
	params["split"] = false
	params["split_strands"] = false
	params["expose_ears"] = false
	params["braid_style"] = "simple"
	params["three_strand_braid"] = false
	params["bun_position"] = 0.0
	params["wavy"] = 0.0
	params["cut_angle"] = 0.0
	params["strand_gap"] = 0.0
	params["tip_taper"] = 0.0
	_rebuild_modular_mannequin()


func _add_slider(parent: Control, label_text: String, param_key: String, min_val: float, max_val: float, step: float, default_val: float, params: Dictionary) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var val: float = float(params.get(param_key, default_val))
	var lbl := Label.new()
	lbl.text = "%s: %.3f" % [label_text, val]
	lbl.add_theme_color_override("font_color", Color("344a49"))
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = val
	row.add_child(slider)

	slider.value_changed.connect(func(new_val: float) -> void:
		lbl.text = "%s: %.3f" % [label_text, new_val]
		params[param_key] = new_val
		_rebuild_modular_mannequin())


func _add_checkbox(parent: Control, label_text: String, param_key: String, default_val: bool, params: Dictionary, on_toggle: Callable) -> void:
	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = bool(params.get(param_key, default_val))
	cb.add_theme_color_override("font_color", Color("344a49"))
	cb.toggled.connect(on_toggle)
	parent.add_child(cb)


func _add_option(parent: Control, label_text: String, items: Array, on_select: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", Color("344a49"))
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

	var ob := OptionButton.new()
	for it in items:
		ob.add_item(it)
	row.add_child(ob)
	ob.item_selected.connect(on_select)


# ============================================================================
# TAB 2: ORIGINAL GARMENT STUDY UI (DRESS, APRON, WAISTCOAT & CURVES)
# ============================================================================
func _setup_garment_study_ui(panel: VBoxContainer) -> void:
	_label(panel, "Garment Style:")
	style_picker = _option(panel, ["Dress", "Apron", "Waistcoat"])
	style_picker.item_selected.connect(func(index: int) -> void:
		style = index
		_rebuild())

	_label(panel, "Motion Mode:")
	motion_picker = _option(panel, ["Still", "Turn", "Start / stop", "Walk"])
	motion_picker.item_selected.connect(func(index: int) -> void:
		mode = index
		phase = 0.0
		doll.body_contact.motion.clear())

	var toggle := CheckButton.new()
	motion_toggle = toggle
	toggle.text = "Secondary motion"
	toggle.add_theme_color_override("font_color", Color("344a49"))
	toggle.button_pressed = true
	panel.add_child(toggle)
	toggle.toggled.connect(func(value: bool) -> void: doll.skirt_fabric.enabled = value)

	_spin(panel, "Density (g/m2)", "density_gsm", 40, 800, 5)
	_spin(panel, "Thickness (mm)", "thickness_mm", 0.1, 4, 0.1)
	_spin(panel, "Bending", "bending_stiffness", 0, 1, 0.01)
	_spin(panel, "Stretch resistance", "stretch_stiffness", 0, 1, 0.01)
	_spin(panel, "Damping", "internal_damping", 0, 1, 0.01)
	_spin(panel, "Pleat count", "pleat_count", 0, 128, 1)
	_spin(panel, "Pleat depth (cm)", "pleat_depth_cm", 0, 4, 0.1)

	panel.add_child(HSeparator.new())

	shape_toggle = CheckButton.new()
	shape_toggle.text = "Contour fitting"
	shape_toggle.add_theme_color_override("font_color", Color("344a49"))
	shape_toggle.button_pressed = true
	panel.add_child(shape_toggle)
	shape_toggle.toggled.connect(func(value: bool) -> void:
		_shape.enabled = value
		_rebuild())

	_spin(panel, "Contour reach", "contour_span", 0, 0.8, 0.01, true)
	_spin(panel, "Contour tension", "bridge_tension", 0, 1, 0.01, true)

	var curve_picker := _option(panel, ["Side ease", "Front ease", "Back ease", "Shape retention", "Motion freedom"])
	curve_picker.item_selected.connect(func(index: int) -> void:
		_curve_name = ["side_ease", "front_ease", "back_ease", "contour_strength", "motion_freedom"][index]
		_bind_curve())

	curve_editor = CurveControl.new()
	panel.add_child(curve_editor)
	curve_editor.edited.connect(func() -> void:
		if _curve_name != "motion_freedom": _rebuild())

	status = Label.new()
	status.add_theme_color_override("font_color", Color("344a49"))
	panel.add_child(status)

	_bind_curve()
	status.text = "V20 / arm 0.045"


func _body_hash() -> int:
	var data := []
	for part in doll.rig.meshes:
		if part.get_meta("is_underbody", false): data.append(part.mesh.surface_get_arrays(0))
	for i in doll.rig.skeleton.get_bone_count(): data.append(doll.rig.skeleton.get_bone_rest(i))
	return hash(var_to_bytes(data))


func _rebuild() -> void:
	var previous := _body_hash()
	doll.configure({"outfit": style, "hair": 0, "palette": style})
	_body_signature = _body_hash()
	if style == _built_style: assert(previous == _body_signature, "Garment controls changed the accepted body")
	_built_style = style
	_bind_curve()
	if is_instance_valid(status): status.text = "V20 / arm 0.045"


func _bind_curve() -> void:
	_shape = doll.shell_shape if style == 2 else doll.skirt_shape
	if is_instance_valid(motion_toggle): motion_toggle.set_pressed_no_signal(doll.skirt_fabric.enabled)
	if is_instance_valid(shape_toggle): shape_toggle.set_pressed_no_signal(_shape.enabled)
	for field in shape_fields: shape_fields[field].set_value_no_signal(_shape.get(field))
	var resource: Resource = doll.skirt_fabric if _curve_name == "motion_freedom" else _shape
	var curve: Curve = resource.get(_curve_name)
	curve_editor.curve = curve
	curve_editor.maximum = 1.0 if _curve_name in ["motion_freedom", "contour_strength"] else 0.12
	curve_editor.queue_redraw()


func _spin(parent: Control, label: String, field: String, minimum: float, maximum: float, step: float, for_shape := false) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var text := _label(row, label)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = doll.skirt_shape.get(field) if for_shape else doll.skirt_fabric.get(field)
	spin.custom_minimum_size.x = 90
	row.add_child(spin)
	if for_shape:
		shape_fields[field] = spin
		spin.value_changed.connect(func(value: float) -> void:
			_shape.set(field, value)
			_rebuild())
	else:
		physics_fields[field] = spin
		spin.value_changed.connect(func(value: float) -> void: doll.skirt_fabric.set(field, value))


func _label(parent: Control, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", Color("344a49"))
	parent.add_child(label)
	return label


func _option(parent: Control, labels: Array) -> OptionButton:
	var option := OptionButton.new()
	for label in labels: option.add_item(label)
	parent.add_child(option)
	return option


# ============================================================================
# 3D ORBIT, PAN & INTERACTIVE DIRECT SPIN (SHIFT + DRAG)
# ============================================================================

func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_left = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_right = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_size = clampf(cam_size - 0.18, 0.70, 5.2)
			camera.size = cam_size
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_size = clampf(cam_size + 0.18, 0.70, 5.2)
			camera.size = cam_size
			_update_camera()

	if event is InputEventMouseMotion:
		if _dragging_left:
			if Input.is_key_pressed(KEY_SHIFT):
				# Shift + Drag directly spins the model around Y, driving physics!
				var spin_impulse: float = -event.relative.x * 0.05
				yaw += spin_impulse
				manual_omega = clampf(spin_impulse / 0.016, -10.0, 10.0)
				if is_instance_valid(omega_slider):
					omega_slider.set_value_no_signal(manual_omega)
				if is_instance_valid(omega_label):
					omega_label.text = "实时角速度 ω: %.1f rad/s (Shift拖拽驱动)" % manual_omega
			else:
				orbit -= event.relative.x * 0.008
				pitch = clampf(pitch + event.relative.y * 0.006, -0.45, 1.25)
				_update_camera()
		elif _dragging_right:
			target_y = clampf(target_y + event.relative.y * 0.003 * cam_size, 0.4, 2.6)
			_update_camera()


func _update_camera() -> void:
	var cos_p := cos(pitch)
	var sin_p := sin(pitch)
	var cx := sin(orbit) * cos_p * cam_distance
	var cy := target_y + sin_p * cam_distance
	var cz := cos(orbit) * cos_p * cam_distance
	camera.position = Vector3(cx, cy, cz)
	camera.look_at(Vector3(0, target_y, 0))


# ============================================================================
# MAIN SIMULATION PROCESS & SECONDARY PHYSICS REACTIVITY
# ============================================================================

func _process(delta: float) -> void:
	if not is_instance_valid(doll) or doll.body_rig == null or doll.rig == null:
		return

	phase += delta
	var current_omega := manual_omega
	var walk := 0.0

	if current_tab == 0:
		# Original study motion
		if mode == 1:
			yaw += delta * 2.6
		elif mode == 2 and fmod(phase, 4.0) < 1.6:
			yaw += delta * 3.2
		walk = (1.0 if mode == 3 else 0.0)
		doll.rig.animate(phase * 6.0, walk, "idle", phase)
		doll.body_rig.rotation.y = yaw
		doll.position.x = (sin(phase * 1.5) * 0.3 if mode == 3 else 0.0)
		if doll.body_contact != null:
			doll.body_contact.advance(delta)
			doll.body_contact.update()
		return

	# Modular Catalog Tab Physics
	match motion_mode:
		0: # Still / Manual
			pass
		1: # Idle Breathe
			var breath := sin(phase * 2.5) * 0.05
			current_omega += breath * 0.4
			doll.rig.animate(phase * 3.0, 0.0, "idle", phase)
			doll.position.x = 0.0
		2: # Continuous Spin
			current_omega += 2.8
			doll.rig.animate(phase * 4.0, 0.0, "idle", phase)
			doll.position.x = 0.0
		3: # Snap Turn
			var osc := cos(phase * 3.2) * 5.2
			current_omega += osc
			doll.rig.animate(phase * 5.0, 0.0, "idle", phase)
			doll.position.x = 0.0
		4: # Walk Sway
			walk = 1.0
			doll.position.x = sin(phase * 2.2) * 0.22
			doll.rig.animate(phase * 6.0, walk, "idle", phase)
		5: # Start / Stop Jolt
			var cycle := fmod(phase, 3.6)
			if cycle < 1.4:
				current_omega += 4.5
			doll.position.x = (sin(phase * 3.0) * 0.15 if cycle < 1.4 else 0.0)
			doll.rig.animate(phase * 5.0, (1.0 if cycle < 1.4 else 0.0), "idle", phase)

	# Decay manual omega gently towards zero if mouse released
	if not _dragging_left and absf(manual_omega) > 0.01 and motion_mode == 0:
		manual_omega = lerpf(manual_omega, 0.0, delta * 3.5)
		if is_instance_valid(omega_slider):
			omega_slider.set_value_no_signal(manual_omega)
		if is_instance_valid(omega_label):
			omega_label.text = "实时角速度 ω: %.1f rad/s" % manual_omega

	# Apply rotation to root body_rig
	yaw += current_omega * delta
	doll.body_rig.rotation.y = yaw

	# Advance cloth physics
	if doll.body_contact != null:
		doll.body_contact.advance(delta)
		doll.body_contact.update()

	# Hair secondary dynamic physics reaction
	_update_hair_secondary_physics(delta, current_omega, walk)


func _update_hair_secondary_physics(delta: float, omega: float, walk: float) -> void:
	if doll.hair_root == null or dynamic_hair_sway_scale <= 0.01:
		return

	var target_lag := -clampf(omega * 0.035 * dynamic_hair_sway_scale, -0.65, 0.65)
	var target_flare := clampf(omega * omega * 0.0075 * dynamic_hair_sway_scale, 0.0, 0.45)
	var bounce := sin(phase * 12.0) * 0.012 * walk * dynamic_hair_sway_scale

	# React to ponytails, twin tails, and long mantles
	for child in doll.hair_root.get_children():
		var c_name := str(child.name)
		if c_name.contains("Ponytail") or c_name.contains("TwinPigtail") or c_name.contains("Braid") or c_name.contains("HalfUp") or c_name.contains("Canopy"):
			var n := child as Node3D
			if n != null:
				n.rotation.z = lerpf(n.rotation.z, target_lag, delta * 10.0)
				n.rotation.x = lerpf(n.rotation.x, target_flare, delta * 10.0)
				n.position.y = lerpf(n.position.y, bounce, delta * 8.0)
