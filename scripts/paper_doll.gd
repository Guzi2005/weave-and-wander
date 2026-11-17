class_name PaperDoll
extends Node3D

signal arrived(doll: PaperDoll)
signal appearance_changed(doll: PaperDoll)

const PaperArt = preload("res://scripts/paper_art.gd")
const PRINT_SHADER: Shader = preload("res://shaders/doll_print.gdshader")
# Adult crown-to-sole height: four 0.65-unit heads, including the hair cap.
const ADULT_HEIGHT := 2.6
const HEAD_HEIGHT := 0.65
const SOLE_HEIGHT := 0.19

const SKIN_TONES := [
	Color("e9bfa9"), # 0: 瓷白/粉润浅肤 (Porcelain Peach - classic baseline 0)
	Color("cc9677"), # 1: 暖阳小麦 (Warm Tan / Ochre - classic baseline 1)
	Color("ae775c"), # 2: 焦糖古铜 (Bronze Chestnut - classic baseline 2)
	Color("805442"), # 3: 浓郁深褐 (Rich Espresso - classic baseline 3)
	Color("f6e2d5"), # 4: 象牙冷白 (Ivory Fair)
	Color("dfad91"), # 5: 柔润杏桃 (Soft Apricot)
	Color("d39371"), # 6: 蜜糖金麦 (Honey Amber)
	Color("9a6147"), # 7: 深栗可可 (Cocoa Chestnut)
	Color("5f3c2e"), # 8: 曜夜浓巧 (Deep Chocolate)
	Color("3d251d"), # 9: 乌木幽深 (Ebony Deep)
]
const HAIR_COLORS := [
	Color("4a3934"), # 0: 暖栗深棕 (Dark Chestnut - classic baseline 0)
	Color("71594c"), # 1: 柔和奶茶 (Soft Brunette - classic baseline 1)
	Color("363435"), # 2: 曜石幽黑 (Raven Charcoal - classic baseline 2)
	Color("a26848"), # 3: 暖铜红褐 (Auburn Copper - classic baseline 3)
	Color("1c1a1a"), # 4: 浓黑墨夜 (Ink Jet Black)
	Color("d8ab5c"), # 5: 璀璨暖金 (Golden Blonde)
	Color("c79c72"), # 6: 蜜糖亚麻 (Honey Flaxen)
	Color("8c5237"), # 7: 枫糖赤褐 (Maple Russet)
	Color("b5bac2"), # 8: 银灰霜雪 (Silver Frost)
	Color("e8e5de"), # 9: 白金浅羽 (Platinum Feather)
	Color("b87b87"), # 10: 暮云烟粉 (Pastel Mauve)
	Color("365049"), # 11: 苍松黛绿 (Forest Pine)
	Color("2a3c56"), # 12: 霁夜深蓝 (Midnight Navy)
]
const EYE_COLORS := [
	Color("292321"), # 0: 曜石黑褐 (Obsidian Espresso - classic baseline 0)
	Color("5a3d28"), # 1: 琥珀暖褐 (Warm Amber)
	Color("422a1d"), # 2: 浓郁栗黑 (Chestnut Brown)
	Color("2d5178"), # 3: 澄澈海蓝 (Sapphire Deep Blue)
	Color("487c9c"), # 4: 冰晶湖蓝 (Aqua Lake)
	Color("326244"), # 5: 翡翠林绿 (Emerald Forest)
	Color("5c6534"), # 6: 橄榄金绿 (Olive Hazel)
	Color("563d68"), # 7: 幽夜紫晶 (Amethyst Violet)
	Color("72313e"), # 8: 绯红石榴 (Ruby Crimson)
	Color("484e57"), # 9: 烟岚雾灰 (Slate Smoke Grey)
	Color("82682e"), # 10: 璨金琥珀 (Topaz Gold)
]
const SKIN_NAME_MAP := {
	"porcelain": 0, "fair": 4, "ivory": 4, "peach": 0, "apricot": 5,
	"tan": 1, "wheat": 1, "honey": 6, "bronze": 2, "chestnut": 2,
	"cocoa": 7, "espresso": 3, "dark": 3, "chocolate": 8, "ebony": 9, "deep": 9,
}
const HAIR_NAME_MAP := {
	"chestnut": 0, "dark_brown": 0, "brunette": 1, "brown": 1, "milk_tea": 1,
	"black": 2, "charcoal": 2, "raven": 2, "ink": 4, "jet_black": 4,
	"auburn": 3, "copper": 3, "red": 3, "russet": 7,
	"blonde": 5, "gold": 5, "golden": 5, "flaxen": 6, "honey_blonde": 6,
	"silver": 8, "grey": 8, "gray": 8, "frost": 8, "white": 9, "platinum": 9,
	"pink": 10, "mauve": 10, "rose": 10,
	"green": 11, "teal": 11, "pine": 11,
	"blue": 12, "navy": 12, "midnight": 12,
}
const EYE_NAME_MAP := {
	"black": 0, "dark": 0, "espresso": 0, "obsidian": 0,
	"amber": 1, "warm_brown": 1, "chestnut": 2, "brown": 2,
	"blue": 3, "sapphire": 3, "deep_blue": 3,
	"aqua": 4, "lake": 4, "cyan": 4, "sky": 4,
	"green": 5, "emerald": 5,
	"olive": 6, "hazel": 6,
	"violet": 7, "purple": 7, "amethyst": 7,
	"red": 8, "ruby": 8, "crimson": 8, "garnet": 8,
	"grey": 9, "gray": 9, "slate": 9, "smoke": 9,
	"gold": 10, "topaz": 10, "golden": 10,
}
const OUTFIT_PALETTES := [
	[Color("9fc7d0"), Color("9bbf9d"), Color("ede5d4")],
	[Color("bc6858"), Color("c19c59"), Color("ecd9b6")],
	[Color("658774"), Color("b3a36c"), Color("ded7c6")],
	[Color("887f9f"), Color("b97d8a"), Color("dbd9e4")],
]

var doll_name := "纸偶"
var role := "staff"
var activity := "idle"
var energy := 1.0
var costume_collection := ""
var shoe_style := 0
var hair_style := 0
var outfit_style := 0
var palette_index := 0
var skin_index := 0
var custom_skin_color := Color(0, 0, 0, 0)
var hair_color_index := 0
var custom_hair_color := Color(0, 0, 0, 0)
var eye_color_index := 0
var custom_eye_color := Color(0, 0, 0, 0)
var move_speed := 1.28
var selected := false
# Rolled once at spawn; see scripts/personality.gd. Empty means neutral traits.
var personality: Dictionary = {}

var _visual_root: Node3D
var _puppet_rig: Node3D
var _stage_base: Node3D
var _selection_root: Node3D
var _task_badge: Node3D
var _target := Vector3.ZERO
var route_provider: Callable
var navigation_version: Callable
var navigation_status := "idle"
var destination := Vector3.ZERO
var destination_anchor: WeakRef
var _planned_revision := -1
var _destination_activity := "idle"
var resting_facing := 0.0
var _waypoints := PackedVector3Array()
var _moving := false
var _phase := 0.0
var _work_phase := 0.0
var _travel_distance := 0.0
var _travel_speed := 0.0
var _motion_amount := 0.0
var _heading := Vector3.RIGHT
var _portrait_shapes: Array[Dictionary] = []
var _ink_materials: Dictionary = {}


func configure(data: Dictionary) -> void:
	doll_name = str(data.get("name", doll_name))
	role = str(data.get("role", role))
	shoe_style = int(data.get("shoe_style", shoe_style))
	hair_style = int(data.get("hair", hair_style))
	outfit_style = int(data.get("outfit", outfit_style))
	palette_index = int(data.get("palette", palette_index))
	if data.has("skin"):
		_parse_skin_param(data["skin"])
	elif data.has("skin_color"):
		_parse_skin_param(data["skin_color"])
	elif data.has("skin_index"):
		_parse_skin_param(data["skin_index"])

	if data.has("hair_color"):
		_parse_hair_color_param(data["hair_color"])
	elif data.has("hair_color_index"):
		_parse_hair_color_param(data["hair_color_index"])

	if data.has("eye"):
		_parse_eye_color_param(data["eye"])
	elif data.has("eye_color"):
		_parse_eye_color_param(data["eye_color"])
	elif data.has("eye_color_index"):
		_parse_eye_color_param(data["eye_color_index"])
	move_speed = float(data.get("speed", move_speed))
	_build_appearance()


func set_destination(world_position: Vector3, next_activity: String) -> bool:
	destination_anchor = null
	destination = world_position
	_destination_activity = next_activity
	return _plan_route()


func move_to_anchor(marker: Node3D, next_activity: String) -> bool:
	if not is_instance_valid(marker):
		stop_navigation()
		navigation_status = "blocked"
		return false
	var found := set_destination(marker.global_position, next_activity)
	destination_anchor = weakref(marker)
	return found


func stop_navigation() -> void:
	destination_anchor = null
	_waypoints.clear()
	_moving = false
	_travel_speed = 0.0
	navigation_status = "idle"


func has_arrived() -> bool:
	return navigation_status == "arrived" and global_position.distance_to(destination) < .04


func _plan_route() -> bool:
	_waypoints.clear()
	_moving = false
	_planned_revision = navigation_version.call() if navigation_version.is_valid() else -1
	if route_provider.is_valid():
		_waypoints = route_provider.call(global_position, destination)
		if _waypoints.is_empty():
			navigation_status = "blocked"
			_travel_speed = 0.0
			set_activity("waiting")
			return false
	_target = destination
	if not _waypoints.is_empty():
		_target = _waypoints[0]
		_waypoints.remove_at(0)
	_target.y = global_position.y
	_moving = true
	navigation_status = "moving"
	set_activity(_destination_activity)
	return true


func set_activity(value: String) -> void:
	activity = value
	_update_task_badge()


func set_selected(value: bool) -> void:
	selected = value
	if is_instance_valid(_selection_root):
		_selection_root.visible = selected


func wear_ukrainian_set() -> void:
	costume_collection = "ukrainian_photo_001"
	outfit_style = 0
	hair_style = 3
	shoe_style = 1
	_build_appearance()
	appearance_changed.emit(self)


func set_shoe_style(value: int) -> void:
	shoe_style = clampi(value, 0, 1)
	_build_appearance()
	appearance_changed.emit(self)


func set_hair_style(value: int) -> void:
	hair_style = posmod(value, 4)
	_build_appearance()
	appearance_changed.emit(self)


func set_outfit_style(value: int) -> void:
	costume_collection = ""
	outfit_style = posmod(value, 3)
	_build_appearance()
	appearance_changed.emit(self)


func set_palette(value: int) -> void:
	palette_index = posmod(value, OUTFIT_PALETTES.size())
	_build_appearance()
	appearance_changed.emit(self)


func _parse_skin_param(value: Variant) -> void:
	if value is Color:
		custom_skin_color = value
	elif value is String:
		var s := str(value).strip_edges().to_lower()
		if s.begins_with("#"):
			custom_skin_color = Color(s)
		elif SKIN_NAME_MAP.has(s):
			skin_index = SKIN_NAME_MAP[s]
			custom_skin_color = Color(0, 0, 0, 0)
		elif s.is_valid_int():
			skin_index = s.to_int()
			custom_skin_color = Color(0, 0, 0, 0)
		else:
			var c := Color.from_string(s, Color(0, 0, 0, 0))
			if c.a > 0.0:
				custom_skin_color = c
			else:
				skin_index = 0
				custom_skin_color = Color(0, 0, 0, 0)
	elif value is int or value is float:
		skin_index = int(value)
		custom_skin_color = Color(0, 0, 0, 0)

func _parse_hair_color_param(value: Variant) -> void:
	if value is Color:
		custom_hair_color = value
	elif value is String:
		var s := str(value).strip_edges().to_lower()
		if s.begins_with("#"):
			custom_hair_color = Color(s)
		elif HAIR_NAME_MAP.has(s):
			hair_color_index = HAIR_NAME_MAP[s]
			custom_hair_color = Color(0, 0, 0, 0)
		elif s.is_valid_int():
			hair_color_index = s.to_int()
			custom_hair_color = Color(0, 0, 0, 0)
		else:
			var c := Color.from_string(s, Color(0, 0, 0, 0))
			if c.a > 0.0:
				custom_hair_color = c
			else:
				hair_color_index = 0
				custom_hair_color = Color(0, 0, 0, 0)
	elif value is int or value is float:
		hair_color_index = int(value)
		custom_hair_color = Color(0, 0, 0, 0)

func _parse_eye_color_param(value: Variant) -> void:
	if value is Color:
		custom_eye_color = value
	elif value is String:
		var s := str(value).strip_edges().to_lower()
		if s.begins_with("#"):
			custom_eye_color = Color(s)
		elif EYE_NAME_MAP.has(s):
			eye_color_index = EYE_NAME_MAP[s]
			custom_eye_color = Color(0, 0, 0, 0)
		elif s.is_valid_int():
			eye_color_index = s.to_int()
			custom_eye_color = Color(0, 0, 0, 0)
		else:
			var c := Color.from_string(s, Color(0, 0, 0, 0))
			if c.a > 0.0:
				custom_eye_color = c
			else:
				eye_color_index = 0
				custom_eye_color = Color(0, 0, 0, 0)
	elif value is int or value is float:
		eye_color_index = int(value)
		custom_eye_color = Color(0, 0, 0, 0)

func get_skin_color() -> Color:
	if custom_skin_color.a > 0.0:
		return custom_skin_color
	return SKIN_TONES[posmod(skin_index, SKIN_TONES.size())]

func get_hair_color() -> Color:
	if custom_hair_color.a > 0.0:
		return custom_hair_color
	return HAIR_COLORS[posmod(hair_color_index, HAIR_COLORS.size())]

func get_eye_color() -> Color:
	if custom_eye_color.a > 0.0:
		return custom_eye_color
	return EYE_COLORS[posmod(eye_color_index, EYE_COLORS.size())]

func set_skin(value: Variant) -> void:
	_parse_skin_param(value)
	_build_appearance()
	appearance_changed.emit(self)

func set_hair_color(value: Variant) -> void:
	_parse_hair_color_param(value)
	_build_appearance()
	appearance_changed.emit(self)

func set_eye_color(value: Variant) -> void:
	_parse_eye_color_param(value)
	_build_appearance()
	appearance_changed.emit(self)


func get_outfit_color() -> Color:
	return OUTFIT_PALETTES[posmod(palette_index, OUTFIT_PALETTES.size())][0]


func is_moving() -> bool:
	return _moving


func simulate(delta: float, speed_scale: float) -> void:
	var scaled_delta := delta * speed_scale
	if scaled_delta <= 0.0:
		return
	if navigation_status != "idle":
		var moved := false
		if destination_anchor != null:
			var marker: Node3D = destination_anchor.get_ref()
			if not is_instance_valid(marker):
				_waypoints.clear()
				_moving = false
				navigation_status = "blocked"
				set_activity("waiting")
				return
			moved = destination.distance_squared_to(marker.global_position) > .0001
			destination = marker.global_position
		var revision: int = navigation_version.call() if navigation_version.is_valid() else -1
		if moved or revision != _planned_revision:
			_plan_route()
	_phase += scaled_delta
	if _moving:
		var previous := global_position
		var previous_step := floori((_travel_distance * 8.5 - PI * .5) / PI)
		var direction := _target - global_position
		if direction.length() > 0.01:
			_heading = direction.normalized()
		var desired_speed := move_speed if not _waypoints.is_empty() else minf(move_speed, sqrt(direction.length() * 5.0))
		_travel_speed = move_toward(_travel_speed, desired_speed, scaled_delta * 3.4)
		global_position = global_position.move_toward(_target, _travel_speed * scaled_delta)
		_travel_distance += global_position.distance_to(previous)
		# One contact per half gait cycle; travel distance prevents idle footsteps.
		if floori((_travel_distance * 8.5 - PI * .5) / PI) > previous_step and is_visible_in_tree():
			get_tree().call_group("workshop_spatial_audio", "play_footstep", self)
		var remaining := global_position.distance_to(_target)
		if remaining < 0.025:
			global_position = _target
			if not _waypoints.is_empty():
				_target = _waypoints[0]
				_waypoints.remove_at(0)
			else:
				_moving = false
				_travel_speed = 0.0
				navigation_status = "arrived"
				arrived.emit(self)
	else:
		_work_phase += scaled_delta
	_update_puppet_motion(scaled_delta)


func _update_puppet_motion(delta: float) -> void:
	var smoothing := 1.0 - exp(-8.0 * delta)
	_motion_amount = lerpf(_motion_amount, 1.0 if _moving else 0.0, smoothing)
	var wave := _travel_distance * 5.8
	# The entire cutout and its tongue rock as one piece about the floor slot.
	var lift := (0.5 - cos(wave) * 0.5) * 0.09 * _motion_amount
	var roll := (sin(wave) * 0.037 - _heading.x * 0.024) * _motion_amount
	if not _moving and activity not in ["idle", "waiting", "entering", "leaving"]:
		roll += sin(_work_phase * 2.2) * 0.008 * (1.0 - _motion_amount)
	_puppet_rig.position.y = lerpf(_puppet_rig.position.y, lift, smoothing)
	_puppet_rig.rotation.z = lerpf(_puppet_rig.rotation.z, roll, smoothing)
	_puppet_rig.rotation.y = lerpf(_puppet_rig.rotation.y, _heading.x * 0.07 * _motion_amount, smoothing)


func _build_appearance() -> void:
	if is_instance_valid(_puppet_rig):
		_puppet_rig.free()
	if is_instance_valid(_stage_base):
		_stage_base.free()
	_stage_base = Node3D.new()
	_stage_base.name = "GroundContact"
	add_child(_stage_base)
	_puppet_rig = Node3D.new()
	_puppet_rig.name = "RodPuppetPivot"
	add_child(_puppet_rig)
	_visual_root = Node3D.new()
	_visual_root.name = "LayeredPaperDoll"
	_visual_root.position.y = SOLE_HEIGHT
	_puppet_rig.add_child(_visual_root)
	_portrait_shapes.clear()

	_build_selection()
	_build_floor_shadow()
	_build_puppet_handle()
	_build_hair_back()
	_build_legs_and_shoes()
	_build_body_and_clothes()
	_build_head()
	_build_hair_front()
	_build_face()
	_build_task_badge()
	_portrait_shapes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] < b["depth"])
	set_selected(selected)


func _build_selection() -> void:
	_selection_root = Node3D.new()
	_selection_root.name = "SelectedGlow"
	_stage_base.add_child(_selection_root)
	var ring := MeshInstance3D.new()
	ring.name = "FloorSelectionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.38
	ring_mesh.outer_radius = 0.41
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.scale.z = 0.43
	ring.position = Vector3(0.0, 0.026, 0.0)
	ring.material_override = _ink_material(Color("c6a448"))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_root.add_child(ring)
	var marker := PaperArt.flat_shape(
		"SelectionMarker",
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1, 0.15), Vector2(0.0, 0.28), Vector2(-0.1, 0.15)]),
		Color("e4bd4e"),
		0.0,
		0.018
	)
	marker.position = Vector3(0.0, ADULT_HEIGHT + SOLE_HEIGHT + 0.12, 0.1)
	_selection_root.add_child(marker)


func _build_floor_shadow() -> void:
	var shadow := MeshInstance3D.new()
	shadow.name = "SoftFloorShadow"
	var mesh_value := CylinderMesh.new()
	mesh_value.top_radius = 0.46
	mesh_value.bottom_radius = 0.46
	mesh_value.height = 0.008
	mesh_value.radial_segments = 24
	shadow.mesh = mesh_value
	shadow.scale.z = 0.34
	shadow.position = Vector3(0.0, 0.012, -0.02)
	shadow.material_override = PaperArt.standard_material(Color(0.18, 0.12, 0.11, 0.17), true)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage_base.add_child(shadow)


func _build_puppet_handle() -> void:
	var handle := PaperArt.box("CardboardTongue", Vector3(0.32, 0.68, 0.055),
		Color("b6a587"), Vector3(0.0, -0.12, -0.018))
	handle.material_override = _ink_material(Color("b6a587"))
	_puppet_rig.add_child(handle)
	var crease := PaperArt.box("TongueFold", Vector3(0.012, 0.57, 0.01),
		Color("988970"), Vector3(0.13, -0.1, 0.015))
	crease.material_override = _ink_material(Color("988970"))
	_puppet_rig.add_child(crease)
	var slot := PaperArt.box("FloorSlot", Vector3(0.64, 0.004, 0.082),
		Color("5a5149"), Vector3(0.0, 0.018, -0.02))
	slot.material_override = _ink_material(Color("5a5149"))
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage_base.add_child(slot)


func _build_hair_back() -> void:
	var hair_color := get_hair_color()
	var crown := _smooth(PackedVector2Array([
		Vector2(-0.32, 2.16), Vector2(-0.325, 2.37), Vector2(-0.23, 2.54),
		Vector2(-0.05, 2.595), Vector2(0.16, 2.58), Vector2(0.3, 2.46),
		Vector2(0.33, 2.25), Vector2(0.27, 2.03), Vector2(-0.24, 2.01)
	]))
	_add_shape("HairBack", crown, hair_color, 0.0)
	match hair_style:
		0:
			for side in [-1.0, 1.0]:
				var bun := _smooth(PackedVector2Array([
					Vector2(0.26, 2.23), Vector2(0.4, 2.18), Vector2(0.445, 2.07),
					Vector2(0.405, 2.01), Vector2(0.415, 1.94), Vector2(0.32, 1.91),
					Vector2(0.265, 1.98), Vector2(0.24, 2.11)
				]))
				_add_shape("Bun%s" % side, _mirror(bun, side), hair_color, 0.006)
				_stroke("BunFold%s" % side, _mirror(PackedVector2Array([
					Vector2(0.3, 2.15), Vector2(0.34, 2.07), Vector2(0.39, 2.03)
				]), side), hair_color.darkened(0.18), 0.004, 0.014)
		1:
			_add_shape("BobBack", _smooth(PackedVector2Array([
				Vector2(-0.31, 2.38), Vector2(-0.35, 2.1), Vector2(-0.3, 1.95),
				Vector2(-0.18, 1.98), Vector2(0.22, 1.98), Vector2(0.33, 2.07),
				Vector2(0.32, 2.39), Vector2(0.1, 2.58), Vector2(-0.16, 2.58)
			])), hair_color, 0.005)
		2:
			for side in [-1.0, 1.0]:
				for braid_index in 6:
					var center := Vector2(side * (0.285 + 0.018 * sin(braid_index)), 2.03 - braid_index * 0.105)
					_add_shape("Braid%s_%d" % [side, braid_index],
						PaperArt.circle_points(center, 0.078 - braid_index * 0.003, 20, 1.06),
						hair_color.lightened(0.035 if braid_index % 2 else 0.0), 0.007)
				_add_shape("HairRibbon%s" % side, PaperArt.rounded_rect_points(
					Rect2(side * 0.28 - 0.07, 1.42, 0.14, 0.04), 0.012), get_outfit_color(), 0.015)


func _build_legs_and_shoes() -> void:
	var skin: Color = get_skin_color()
	var shoe_color: Color = OUTFIT_PALETTES[posmod(palette_index, OUTFIT_PALETTES.size())][1]
	for side in [-1.0, 1.0]:
		_add_shape("Leg%s" % side, _mirror(PackedVector2Array([
			Vector2(0.06, 1.16), Vector2(0.26, 1.16), Vector2(0.215, 0.1), Vector2(0.09, 0.1)
		]), side), skin, 0.012)
		var shoe := _smooth(PackedVector2Array([
			Vector2(0.095, 0.16), Vector2(0.225, 0.19), Vector2(0.29, 0.1),
			Vector2(0.305, 0.035), Vector2(0.23, 0.009), Vector2(0.065, 0.02)
		]))
		_add_shape("Shoe%s" % side, _mirror(shoe, side), shoe_color, 0.026)


func _build_body_and_clothes() -> void:
	var palette: Array = OUTFIT_PALETTES[posmod(palette_index, OUTFIT_PALETTES.size())]
	var main_color: Color = palette[0]
	var accent: Color = palette[1]
	var light: Color = palette[2]
	var skin: Color = get_skin_color()
	_add_shape("Neck", _smooth(PackedVector2Array([
		Vector2(-0.095, 2.06), Vector2(0.095, 2.06), Vector2(0.105, 1.84), Vector2(-0.1, 1.84)
	])), skin, 0.03)
	var sleeve_color := light if outfit_style == 1 else main_color
	for side in [-1.0, 1.0]:
		var sleeve := _smooth(PackedVector2Array([
			Vector2(0.225, 1.88), Vector2(0.34, 1.8), Vector2(0.49, 1.52),
			Vector2(0.445, 1.12), Vector2(0.315, 1.13), Vector2(0.3, 1.48),
			Vector2(0.19, 1.71)
		]), 0.19)
		_add_shape("Sleeve%s" % side, _mirror(sleeve, side), sleeve_color, 0.018)
		var hand := _smooth(PackedVector2Array([
			Vector2(0.34, 1.15), Vector2(0.43, 1.13), Vector2(0.435, 1.03),
			Vector2(0.407, 0.974), Vector2(0.369, 0.985), Vector2(0.335, 1.04)
		]))
		_add_shape("Hand%s" % side, _mirror(hand, side), skin, 0.033)

	match outfit_style:
		0:
			var dress := _smooth(PackedVector2Array([
				Vector2(-0.17, 1.92), Vector2(0.16, 1.92), Vector2(0.3, 1.79),
				Vector2(0.31, 1.46), Vector2(0.325, 0.81), Vector2(0.365, 0.33),
				Vector2(0.27, 0.255), Vector2(-0.29, 0.25), Vector2(-0.36, 0.34),
				Vector2(-0.33, 0.92), Vector2(-0.32, 1.47), Vector2(-0.29, 1.79)
			]), 0.15)
			_add_shape("LongDress", dress, main_color, 0.045)
			_add_shape("Collar", PackedVector2Array([
				Vector2(-0.13, 1.94), Vector2(0.13, 1.94), Vector2(0.16, 1.872), Vector2(-0.16, 1.862)
			]), main_color.lerp(accent, 0.42).lightened(0.1), 0.059)
			_add_shape("FlouncedHem", _smooth(PackedVector2Array([
				Vector2(-0.35, 0.37), Vector2(0.35, 0.36), Vector2(0.44, 0.17),
				Vector2(0.22, 0.135), Vector2(0.02, 0.15), Vector2(-0.22, 0.135), Vector2(-0.43, 0.17)
			]), 0.14), main_color.darkened(0.03), 0.06)
			_stroke("HemJoin", PackedVector2Array([Vector2(-0.34, 0.365), Vector2(0.0, 0.348), Vector2(0.34, 0.36)]),
				main_color.lerp(accent, 0.6), 0.015, 0.077)
			_stroke("Waistband", PackedVector2Array([Vector2(-0.295, 1.52), Vector2(0.0, 1.54), Vector2(0.3, 1.55)]),
				main_color.lerp(accent, 0.5).lightened(0.08), 0.027, 0.077)
			for side in [-1.0, 1.0]:
				_stroke("SleeveSeam%s" % side, _mirror(PackedVector2Array([
					Vector2(0.3, 1.5), Vector2(0.34, 1.27), Vector2(0.345, 1.1)
				]), side), main_color.darkened(0.15), 0.004, 0.078)
			for fold_index in 5:
				var x := -0.28 + fold_index * 0.14
				_stroke("HemFold%d" % fold_index, PackedVector2Array([
					Vector2(x, 0.325), Vector2(x * 1.13, 0.235), Vector2(x * 1.2, 0.172)
				]), main_color.darkened(0.15), 0.0035, 0.078)
			_add_flower(Vector2(0.0, 1.69), light, Color("ba795c"), 0.06)
		1:
			_add_shape("Blouse", _smooth(PackedVector2Array([
				Vector2(-0.16, 1.93), Vector2(0.16, 1.93), Vector2(0.3, 1.78),
				Vector2(0.295, 1.19), Vector2(-0.29, 1.19), Vector2(-0.3, 1.78)
			])), light, 0.045)
			_add_shape("Skirt", _smooth(PackedVector2Array([
				Vector2(-0.285, 1.3), Vector2(0.285, 1.3), Vector2(0.43, 0.23),
				Vector2(0.12, 0.2), Vector2(-0.15, 0.21), Vector2(-0.43, 0.245)
			]), 0.1), main_color, 0.05)
			_add_shape("Apron", _smooth(PackedVector2Array([
				Vector2(-0.17, 1.74), Vector2(0.17, 1.74), Vector2(0.21, 1.28),
				Vector2(0.31, 0.47), Vector2(0.0, 0.43), Vector2(-0.31, 0.47), Vector2(-0.21, 1.29)
			]), 0.12), accent, 0.065)
			_stroke("ApronStrap", PackedVector2Array([
				Vector2(-0.14, 1.73), Vector2(-0.105, 1.87), Vector2(0.12, 1.87), Vector2(0.14, 1.73)
			]), accent, 0.028, 0.077)
			_add_shape("Pocket", _smooth(PackedVector2Array([
				Vector2(-0.14, 0.98), Vector2(0.14, 0.98), Vector2(0.12, 0.8),
				Vector2(0.0, 0.765), Vector2(-0.12, 0.8)
			])), accent.darkened(0.13), 0.078)
			for stripe in 2:
				var y := 0.28 + stripe * 0.038
				_stroke("SkirtBorder%d" % stripe, PackedVector2Array([
					Vector2(-0.407, y), Vector2(0.0, y - 0.012), Vector2(0.406, y - 0.006)
				]), light, 0.012, 0.071)
		2:
			for side in [-1.0, 1.0]:
				_add_shape("TrouserLeg%s" % side, _mirror(_smooth(PackedVector2Array([
					Vector2(0.005, 1.31), Vector2(0.28, 1.31), Vector2(0.28, 0.92),
					Vector2(0.24, 0.17), Vector2(0.07, 0.165), Vector2(0.026, 0.82)
				]), 0.12), side), main_color.darkened(0.05), 0.04)
			_add_shape("Jacket", _smooth(PackedVector2Array([
				Vector2(-0.16, 1.93), Vector2(0.16, 1.93), Vector2(0.3, 1.79),
				Vector2(0.315, 1.23), Vector2(0.18, 1.19), Vector2(-0.2, 1.19), Vector2(-0.305, 1.24),
				Vector2(-0.3, 1.79)
			]), 0.16), light, 0.052)
			for side in [-1.0, 1.0]:
				_add_shape("Waistcoat%s" % side, _mirror(PackedVector2Array([
					Vector2(0.15, 1.91), Vector2(0.27, 1.84), Vector2(0.3, 1.23),
					Vector2(0.19, 1.15), Vector2(0.1, 1.26), Vector2(0.08, 1.69)
				]), side), main_color, 0.063)
			for stripe in 4:
				var y := 1.36 + stripe * 0.125
				_stroke("ShirtStripe%d" % stripe, PackedVector2Array([
					Vector2(-0.087, y), Vector2(0.078, y + 0.003)
				]), main_color.lightened(0.25), 0.024, 0.078)
			_stroke("Belt", PackedVector2Array([Vector2(-0.105, 1.28), Vector2(0.1, 1.28)]), accent, 0.055, 0.079)


func _build_head() -> void:
	var skin: Color = get_skin_color()
	_add_shape("LeftEar", PaperArt.circle_points(Vector2(-0.29, 2.19), 0.048, 24, 1.26), skin, 0.03)
	_add_shape("RightEar", PaperArt.circle_points(Vector2(0.29, 2.19), 0.048, 24, 1.26), skin, 0.03)
	_add_shape("Face", _smooth(PackedVector2Array([
		Vector2(-0.274, 2.34), Vector2(-0.215, 2.482), Vector2(-0.04, 2.53),
		Vector2(0.17, 2.49), Vector2(0.285, 2.35), Vector2(0.281, 2.18),
		Vector2(0.185, 2.027), Vector2(0.035, 1.958), Vector2(-0.12, 1.987),
		Vector2(-0.259, 2.1)
	]), 0.24), skin, 0.045)


func _build_hair_front() -> void:
	var hair_color := get_hair_color()
	if hair_style == 1:
		_add_shape("SweptFringe", _smooth(PackedVector2Array([
			Vector2(-0.32, 2.21), Vector2(-0.325, 2.41), Vector2(-0.16, 2.57),
			Vector2(0.16, 2.58), Vector2(0.31, 2.42), Vector2(0.3, 2.2),
			Vector2(0.235, 2.29), Vector2(0.18, 2.43), Vector2(-0.06, 2.33),
			Vector2(-0.245, 2.335), Vector2(-0.27, 2.2)
		]), 0.15), hair_color, 0.072)
		for i in 3:
			var offset := i * 0.035
			_stroke("SweptStrand%d" % i, PackedVector2Array([
				Vector2(0.13, 2.55 - offset), Vector2(-0.025, 2.47 - offset), Vector2(-0.23, 2.405 - offset)
			]), hair_color.darkened(0.2), 0.004, 0.081)
	else:
		for side in [-1.0, 1.0]:
			var sweep := _smooth(PackedVector2Array([
				Vector2(0.0, 2.56), Vector2(0.16, 2.58), Vector2(0.295, 2.44),
				Vector2(0.317, 2.24), Vector2(0.22, 2.27), Vector2(0.084, 2.38)
			]), 0.18)
			_add_shape("PartedFringe%s" % side, _mirror(sweep, side), hair_color, 0.072)
			for i in 2:
				var offset := i * 0.045
				_stroke("HairStrand%s_%d" % [side, i], _mirror(PackedVector2Array([
					Vector2(0.025 + offset, 2.54), Vector2(0.14 + offset, 2.4), Vector2(0.28, 2.295 + offset)
				]), side), hair_color.darkened(0.19), 0.0035, 0.081)


func _build_face() -> void:
	var skin: Color = get_skin_color()
	var blush := skin.lerp(Color("bd6e64"), 0.18)
	for side in [-1.0, 1.0]:
		_add_shape("Cheek%s" % side, PaperArt.circle_points(Vector2(side * 0.183, 2.126), 0.05, 24, 0.5), blush, 0.081)
		_add_shape("Eye%s" % side, PaperArt.circle_points(Vector2(side * 0.103, 2.237), 0.026, 24, 1.13),
			get_eye_color(), 0.086)
	_stroke("Smile", PackedVector2Array([
		Vector2(-0.065, 2.094), Vector2(-0.024, 2.068), Vector2(0.027, 2.069), Vector2(0.068, 2.097)
	]), Color("62423b"), 0.007, 0.09)
	_stroke("Nose", PackedVector2Array([
		Vector2(-0.006, 2.18), Vector2(-0.01, 2.149), Vector2(0.012, 2.143), Vector2(0.026, 2.151)
	]), skin.darkened(0.33), 0.0035, 0.09)


func _build_task_badge() -> void:
	_task_badge = Node3D.new()
	_task_badge.name = "TaskBadge"
	_task_badge.position = Vector3(0.39, ADULT_HEIGHT + 0.02, 0.095)
	_visual_root.add_child(_task_badge)
	_update_task_badge()


func _update_task_badge() -> void:
	if not is_instance_valid(_task_badge):
		return
	for child in _task_badge.get_children():
		child.free()
	var badge_color := Color("e9c662")
	match activity:
		"sewing": badge_color = Color("d46c62")
		"stocking": badge_color = Color("6fa28a")
		"checkout": badge_color = Color("e3aa57")
		"browsing": badge_color = Color("8fa9c5")
		"fitting": badge_color = Color("bb82a2")
		"resting": badge_color = Color("8db8be")
		_: badge_color = Color("d8cdbb")
	_task_badge.add_child(PaperArt.flat_shape(
		"BadgePaper",
		PaperArt.circle_points(Vector2.ZERO, 0.105, 16),
		badge_color,
		0.0,
		0.018,
		Color("fff8e7")
	))
	_task_badge.visible = activity not in ["idle", "waiting", "entering", "leaving"]


func _add_flower(center: Vector2, petal_color: Color, center_color: Color, radius: float) -> void:
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var petal_center := center + Vector2(cos(angle), sin(angle)) * radius
		_add_shape("Petal%d" % index, PaperArt.circle_points(petal_center, radius * 0.58, 10, 1.25), petal_color, 0.073, 0.0)
	_add_shape("FlowerCenter", PaperArt.circle_points(center, radius * 0.38, 10), center_color, 0.076, 0.0)


func _add_shape(
		name_value: String,
		points: PackedVector2Array,
		color: Color,
		z_offset: float,
		_outline_width: float = 0.0
	) -> void:
	var shape := PaperArt.flat_shape(name_value, points, color, z_offset, 0.0)
	var mesh := shape.get_node("Paper") as MeshInstance3D
	mesh.material_override = _ink_material(color)
	_visual_root.add_child(shape)
	var portrait_clip := PackedVector2Array([
		Vector2(-0.7, 1.57), Vector2(0.7, 1.57), Vector2(0.7, 2.68), Vector2(-0.7, 2.68)
	])
	for polygon in Geometry2D.intersect_polygons(points, portrait_clip):
		_portrait_shapes.append({"points": polygon, "color": color, "depth": z_offset})


func portrait_layers() -> Array[Dictionary]:
	return _portrait_shapes


func _ink_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _ink_materials.has(key):
		var ink := ShaderMaterial.new()
		ink.shader = PRINT_SHADER
		ink.set_shader_parameter("ink_color", color)
		_ink_materials[key] = ink
	return _ink_materials[key]


func _mirror(points: PackedVector2Array, side: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(Vector2(point.x * side, point.y))
	return result


func _smooth(points: PackedVector2Array, roundness: float = 0.23) -> PackedVector2Array:
	var curve := Curve2D.new()
	for index in points.size() + 1:
		var current := index % points.size()
		var previous := points[posmod(current - 1, points.size())]
		var next := points[(current + 1) % points.size()]
		var tangent := (next - previous).normalized()
		var handle := minf(points[current].distance_to(previous), points[current].distance_to(next)) * roundness
		curve.add_point(points[current], -tangent * handle, tangent * handle)
	var result := curve.tessellate(4, 3.0)
	result.remove_at(result.size() - 1)
	return result


func _stroke(name_value: String, points: PackedVector2Array, color: Color, width: float, depth: float) -> void:
	var curve := Curve2D.new()
	for index in points.size():
		var previous := points[maxi(index - 1, 0)]
		var next := points[mini(index + 1, points.size() - 1)]
		var tangent := (next - previous) * 0.18
		curve.add_point(points[index], -tangent, tangent)
	var contours := Geometry2D.offset_polyline(curve.tessellate(4, 3.0), width * 0.5,
		Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	for contour in contours:
		_add_shape(name_value, contour, color, depth)


func is_off_shift() -> bool:
	return bool(get_meta("shift_home",false)) or bool(get_meta("shift_departing",false))
