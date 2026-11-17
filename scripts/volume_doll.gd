class_name VolumeDoll
extends PaperDoll

const VOLUME_SHADER: Shader = preload("res://shaders/doll_volume.gdshader")
const RigScript = preload("res://scripts/doll_rig.gd")
const GarmentShell = preload("res://components/simple_garment.gd")
const ButtonRow = preload("res://components/button_row.gd")
const GarmentOverlay = preload("res://components/garment_overlay.gd")
const FittedPanel = preload("res://components/fitted_cloth_panel.gd")
const BasicGarment = preload("res://components/basic_garment.gd")
const PleatedSkirtNode = preload("res://components/pleated_skirt.gd")
const Expressions = preload("res://scripts/doll_expressions.gd")
const HEAD_CENTER = Vector3(0, 0.29, 0)
const HEAD_RADIUS = Vector3(0.272, 0.30, 0.29)

var body_rig: Node3D
var head_rig: Node3D
var clothes_root: Node3D
var hair_root: Node3D
var skirt_root: Node3D
var reference_costume := false
@export var hosiery: Resource = preload("res://components/hosiery_style.gd").new()
var rig: RefCounted
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var _volume_materials: Dictionary = {}
var _facing := 0.0
var _walk_blend := 0.0
var _skirt: MeshInstance3D
var _garment: MeshInstance3D
var pleated_skirt: Node3D = null
var _pleated_skirt_options: Dictionary = {}
var rest_support: WeakRef
var rest_mode := "sit"
@export_enum("Palms Under Cheek", "Curled", "Loose Legs", "Relaxed Arm") var nap_pose := 0
@export_range(.5, 4.0, .1) var nap_transition_seconds := 1.8
var _nap_pose_weights := Vector4(1,0,0,0)
var _nap_pose_from := Vector4(1,0,0,0)
var _nap_pose_target := 0
var _nap_pose_progress := 1.0
var _rest_blend := 0.0
var _rest_offset := Vector3.ZERO
var _rest_yaw := 0.0
var rest_departing := false
@export_enum("Auto", "Neutral", "Content", "Happy", "Thinking", "Surprised", "Tired", "Asleep") var expression_mode := 0:
	set(value):
		expression_mode = clampi(value, 0, Expressions.STATE_NAMES.size())
		if not _syncing_expression_mode:
			_sync_expression_mode()
@export_range(0.05, 3.0, 0.05) var expression_transition_seconds := 0.35:
	set(value):
		expression_transition_seconds = clampf(value, 0.05, 3.0) if is_finite(value) else 0.35
		if _expressions != null:
			_expressions.set_transition_seconds(expression_transition_seconds)

@export_group("Mannequin Appearance")
@export_enum("0: Porcelain Peach", "1: Warm Tan", "2: Bronze Chestnut", "3: Rich Espresso", "4: Ivory Fair", "5: Soft Apricot", "6: Honey Amber", "7: Cocoa Chestnut", "8: Deep Chocolate", "9: Ebony Deep") var skin_preset := 0:
	set(value):
		skin_preset = value
		skin_index = value
		custom_skin_color = Color(0, 0, 0, 0)
		if is_inside_tree() or is_instance_valid(body_rig):
			_build_appearance()

@export var custom_skin := Color(0, 0, 0, 0):
	set(value):
		custom_skin = value
		custom_skin_color = value
		if is_inside_tree() or is_instance_valid(body_rig):
			_build_appearance()

@export_enum("0: Dark Chestnut", "1: Soft Brunette", "2: Raven Charcoal", "3: Auburn Copper", "4: Ink Jet Black", "5: Golden Blonde", "6: Honey Flaxen", "7: Maple Russet", "8: Silver Frost", "9: Platinum Feather", "10: Pastel Mauve", "11: Forest Pine", "12: Midnight Navy") var hair_color_preset := 0:
	set(value):
		hair_color_preset = value
		hair_color_index = value
		custom_hair_color = Color(0, 0, 0, 0)
		if is_inside_tree() or is_instance_valid(body_rig):
			_build_appearance()

@export var custom_hair := Color(0, 0, 0, 0):
	set(value):
		custom_hair = value
		custom_hair_color = value
		if is_inside_tree() or is_instance_valid(body_rig):
			_build_appearance()

@export_enum("0: Obsidian Espresso", "1: Warm Amber", "2: Chestnut Brown", "3: Sapphire Blue", "4: Aqua Lake", "5: Emerald Forest", "6: Olive Hazel", "7: Amethyst Violet", "8: Ruby Crimson", "9: Slate Grey", "10: Topaz Gold") var eye_color_preset := 0:
	set(value):
		eye_color_preset = value
		eye_color_index = value
		custom_eye_color = Color(0, 0, 0, 0)
		if is_inside_tree() or is_instance_valid(body_rig):
			_build_appearance()

@export var custom_eye := Color(0, 0, 0, 0):
	set(value):
		custom_eye = value
		custom_eye_color = value
		if is_inside_tree() or is_instance_valid(body_rig):
			_build_appearance()
var _expressions: RefCounted
var _syncing_expression_mode := false
var attention: WeakRef
var attention_time := 0.0
var hand_targets: Dictionary = {}
var foot_targets: Dictionary = {}
var _pedal_contact := preload("res://scripts/pedal_cloth_contact.gd").new()
var _gaze := Vector2.ZERO


func attend(target: Node3D, seconds := 2.0) -> void:
	attention = weakref(target) if is_instance_valid(target) else null
	attention_time = seconds


func reach(side: String, world_point: Vector3) -> void:
	hand_targets[side] = world_point


func clear_interaction() -> void:
	hand_targets.clear()
	foot_targets.clear()
	attention = null
	attention_time = 0.0


func set_expression(name: String, duration := -1.0) -> bool:
	var seconds := expression_transition_seconds
	if duration >= 0.0 and is_finite(duration):
		seconds = clampf(duration, 0.0, 10.0)
	var key := name.strip_edges().to_lower()
	if key == "auto":
		clear_expression()
		return true
	var index: int = Expressions.STATE_NAMES.find(key)
	var valid := index >= 0
	if not valid:
		index = 0
		key = Expressions.STATE_NAMES[0]
	_syncing_expression_mode = true
	expression_mode = index + 1
	_syncing_expression_mode = false
	if _expressions != null:
		_expressions.set_expression(key, seconds)
	return valid


func clear_expression() -> void:
	_syncing_expression_mode = true
	expression_mode = 0
	_syncing_expression_mode = false
	if _expressions != null:
		_expressions.clear_expression(expression_transition_seconds)


func current_expression() -> String:
	return _expressions.get_expression() if _expressions != null else "content"


func expression_controller() -> RefCounted:
	return _expressions


func _sync_expression_mode() -> void:
	if _expressions == null:
		return
	if expression_mode <= 0:
		_expressions.clear_expression(expression_transition_seconds)
		return
	var index := clampi(expression_mode - 1, 0, Expressions.STATE_NAMES.size() - 1)
	_expressions.set_expression(Expressions.STATE_NAMES[index], expression_transition_seconds)


func apply_reaches() -> void:
	if get_meta("material_handling",false) and not hand_targets.is_empty():
		var lowest := 2.0
		for target in hand_targets.values(): lowest = minf(lowest,body_rig.to_local(target).y)
		var crouch := clampf((1.0-lowest)*.65,0,.55)
		if crouch > 0:
			rig._offset("Hips",Vector3(0,-crouch,0))
			for side in ["L","R"]:
				rig._rotate("Thigh"+side,Vector3(-crouch*1.65,0,0))
				rig._rotate("Shin"+side,Vector3(crouch*3.0,0,0))
				rig._rotate("Foot"+side,Vector3(-crouch*1.35,0,0))
			rig.skeleton.force_update_all_bone_transforms()
			for side in ["L","R"]:
				rig.place_foot(side,Vector3(-.15 if side == "L" else .15,.15,.05))
	if not hand_targets.is_empty() and activity == "checkout":
		rig._rotate("Spine",Vector3(-.16,0,0))
		rig.skeleton.force_update_all_bone_transforms()
	for side in hand_targets:
		var target: Vector3 = body_rig.to_local(hand_targets[side])
		rig._rest_arm(side,target,Vector3(-.40 if side == "L" else .40,1.48,.18),1.0)
	for side in foot_targets:
		rig.place_foot(side,body_rig.to_local(foot_targets[side]))
	if not foot_targets.is_empty() and _rest_blend > .8 and rest_mode != "nap":
		_pedal_contact.update(rig)
	elif _pedal_contact.active:
		_pedal_contact.clear()


func configure(data: Dictionary) -> void:
	reference_costume = bool(data.get("reference", reference_costume))
	if data.has("socks"):
		hosiery = preload("res://components/hosiery_style.gd").new()
		for key in data.socks:
			if key in ["enabled", "length", "color", "pattern_color", "pattern", "repeats", "texture", "texture_scale"]:
				hosiery.set(key, data.socks[key])
	super.configure(data)


func set_hosiery(settings: Dictionary) -> void:
	hosiery = hosiery.duplicate() if hosiery != null else preload("res://components/hosiery_style.gd").new()
	for key in settings:
		if key in ["enabled", "length", "color", "pattern_color", "pattern", "repeats", "texture", "texture_scale"]:
			hosiery.set(key, settings[key])
	_build_appearance()


func _costume_palette() -> Array:
	if reference_costume:
		return [Color("45405d"), Color("b98841"), Color("e5d9ba")]
	return OUTFIT_PALETTES[palette_index]


func face_for_wardrobe() -> void:
	_facing = 0.0
	body_rig.rotation.y = 0.0
	rig.animate(0, 0, "idle", 0)


func _build_appearance() -> void:
	# Reuse the flat illustration for staff portraits and the simulation contract.
	# Only the volumetric meshes remain in the world after construction.
	super._build_appearance()
	_task_badge.reparent(_stage_base, false)
	_task_badge.position = Vector3(0.44, 2.82, 0.05)
	_puppet_rig.free()
	_puppet_rig = null
	_visual_root = null
	_stage_base.get_node("FloorSlot").free()
	_expressions = null
	if is_instance_valid(body_rig):
		_pedal_contact.clear()
		_pedal_contact = preload("res://scripts/pedal_cloth_contact.gd").new()
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
	if costume_collection == "ukrainian_photo_001":
		preload("res://scripts/ukrainian_outfit.gd").new().apply(self)
	_build_volume_head()
	if hosiery != null:
		hosiery.build(self)
	_prepare_body_for_rig()
	rig = RigScript.new()
	rig.bind(body_rig, _covers_legs(), _keep_covered_legs())
	if hosiery != null:
		hosiery.apply(self)
	rig.animate(0, 0, "idle", 0)
	_setup_expressions()
	body_rig.rotation.y = _facing
	set_selected(selected)


func _setup_expressions() -> void:
	_expressions = Expressions.new()
	if not _expressions.bind(rig, head_rig.position, HEAD_CENTER, HEAD_RADIUS, expression_transition_seconds):
		_expressions = null
		return
	_expressions.set_auto_context(activity, false, false)
	if expression_mode > 0:
		_expressions.set_expression(Expressions.STATE_NAMES[expression_mode - 1], 0.0)
	else:
		_expressions.clear_expression(0.0)
	_expressions.update(0.0)


func _covers_legs() -> bool:
	return outfit_style != 2


func _keep_covered_legs() -> bool:
	return false


func _prepare_body_for_rig() -> void:
	pass


func _new_garment_shell() -> MeshInstance3D:
	return GarmentShell.new()


func _build_volume_body() -> void:
	var palette := _costume_palette()
	var cloth: Color = palette[0]
	var trim: Color = palette[1]
	var linen: Color = palette[2]
	var skin: Color = get_skin_color()
	var shirt: Color = linen if outfit_style != 0 else cloth
	# A continuous shoulder/chest-to-neck surface, with a gradual concave taper.
	# The upper rings enter the head; no ellipsoid bulge at the collar.
	var neck := _lathe(body_rig, "Neck", [Vector3(1.50,.210,.137),Vector3(1.68,.218,.143),
		Vector3(1.77,.208,.140),Vector3(1.82,.183,.130),Vector3(1.86,.145,.112),
		Vector3(1.90,.111,.096),Vector3(1.94,.096,.088),Vector3(1.99,.092,.085),
		Vector3(2.05,.092,.085),Vector3(2.10,.094,.087)],skin,40)
	neck.set_meta("garment_slot", "")
	_garment = _new_garment_shell()
	_garment.name = "TailoredShell"
	_garment.waist_height = 1.285 if outfit_style == 1 else (1.10 if outfit_style == 2 else 1.13)
	_garment.material_override = _material(shirt)
	clothes_root.add_child(_garment)
	_garment.rebuild()
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegLeft" if side < 0 else "LegRight"
		leg.position = Vector3(side * 0.15, 1.1, 0)
		body_rig.add_child(leg)
		legs.append(leg)
		var leg_color := cloth.darkened(0.12) if outfit_style == 2 else linen.darkened(0.07)
		_lathe(leg, "Trouser", [Vector3(-0.93, 0.095, 0.11), Vector3(-0.82, 0.11, 0.115),
			Vector3(-0.42, 0.12, 0.13), Vector3(-0.12, 0.145, 0.155), Vector3(0.05, 0.12, 0.135)], leg_color, 16)
		if outfit_style != 2:
			var calf := _lathe(leg, "Calf", [Vector3(-.95,.053,.060),Vector3(-.86,.057,.065),
				Vector3(-.65,.074,.081),Vector3(-.49,.081,.085),Vector3(-.40,.075,.079)],skin,16)
			calf.position.z = .045
		_build_shoe(leg, Color("674137") if reference_costume else trim.darkened(0.32))
		var arm := Node3D.new()
		arm.name = "ArmLeft" if side < 0 else "ArmRight"
		arm.position = Vector3(side * 0.155, 1.79, 0)
		body_rig.add_child(arm)
		arms.append(arm)
		var wrist := Node3D.new()
		wrist.name = "WristDetails"
		wrist.position = Vector3(side * 0.145, 0, 0)
		arm.add_child(wrist)
		_cuff_rim(wrist, trim, shirt.darkened(0.32))
		_build_shared_hand(wrist, side, skin)
	match outfit_style:
		0, 1:
			skirt_root = Node3D.new()
			skirt_root.name = "SkirtAndTrims"
			clothes_root.add_child(skirt_root)
			_skirt = _lathe(skirt_root, "LongSkirt", [Vector3(0.20, 0.437, 0.313), Vector3(0.24, 0.44, 0.315),
				Vector3(0.30, 0.427, 0.307), Vector3(0.48, 0.389, 0.284), Vector3(0.7, 0.345, 0.26),
				Vector3(0.99, 0.299, 0.222), Vector3(1.22, 0.281, 0.204), Vector3(1.31, 0.28, 0.202)], cloth, 40, 0.008, false)
			_skirt.material_override = _skirt.material_override.duplicate()
			_skirt.material_override.set_shader_parameter("backface_shade",.20)
			_lathe(skirt_root, "HemRibbon", [Vector3(0.235, 0.443, 0.320), Vector3(0.27, 0.440, 0.317)], trim, 40, 0.0, false)
			_lathe(skirt_root, "FineHemRibbon", [Vector3(0.32, 0.427, 0.310), Vector3(0.333, 0.424, 0.309)], linen, 40, 0.0, false)
			_lathe(clothes_root, "WaistRibbon", [Vector3(1.26, 0.288, 0.212), Vector3(1.31, 0.287, 0.213)], trim)
			if outfit_style == 0:
				_lathe(clothes_root, "StandingCollar", [Vector3(1.89, 0.13, 0.11), Vector3(1.965, 0.108, 0.099)], trim)
				if reference_costume:
					_robe_embroidery(trim)
				else:
					_flower(clothes_root, Vector3(-0.04, 1.67, 0.202), linen, trim)
					_buttons(Vector3(0.075, 1.68, 0), 3, 0.105, Vector3(0.036, 0.044, 0.009), trim)
			else:
				var apron := _fitted_panel("Apron", [{"mesh":_garment,"bottom":1.31},{"mesh":_skirt,"top":1.31}],
					FittedPanel.front_volumes([Vector3(.4,.28,0),Vector3(.46,.29,0),Vector3(.94,.22,0),Vector3(1.32,.185,0),Vector3(1.72,.14,0)]),.014,trim)
				_fitted_panel("Pocket",[{"mesh":apron}],FittedPanel.front_volumes([
					Vector3(.76,.07,0),Vector3(.8,.11,0),Vector3(.98,.11,0)]),.006,trim.darkened(.16))
				for side in [-1.0, 1.0]:
					# The bib panels stop below the shoulder; the crossed strap
					# mesh alone rides over the crown so the two never z-fight.

					# The strap continues over the shoulder and crosses the back
					# down to the waist tie instead of ending at the chest.
					var strap := BasicGarment.apron_strap(side, _garment.mesh)
					var strap_mesh := _mesh(clothes_root, "ApronStrapCrossL" if side < 0 else "ApronStrapCrossR",
						strap.vertices, strap.normals, strap.indices, trim)
					strap_mesh.set_meta("garment_slot", "outer")
				_fitted_panel("ApronTie",[{"mesh":_skirt}],[[Plane(Vector3.UP,1.27),Plane(Vector3.DOWN,-1.305),Plane(Vector3.FORWARD,-.05)]],.014,trim)
		2:
			_build_waistcoat(cloth, trim)


func _build_volume_head() -> void:
	var skin: Color = get_skin_color()
	var hair := get_hair_color()
	var eye := get_eye_color()
	head_rig = Node3D.new()
	head_rig.name = "HeadRig"
	head_rig.position = Vector3(0, 2.02, 0.035)
	body_rig.add_child(head_rig)
	_ellipsoid(head_rig, "Head", HEAD_CENTER, HEAD_RADIUS, skin)
	for side in [-1.0, 1.0]:
		_ellipsoid(head_rig, "Ear", Vector3(side * 0.267, 0.238, 0.01), Vector3(0.055, 0.076, 0.049), skin)
		_ellipsoid(head_rig, "EarInner", Vector3(side * 0.287, 0.235, 0.047), Vector3(0.021, 0.036, 0.01), skin.darkened(0.12))
		_ellipsoid(head_rig, "BeanEye", _face_point(side * 0.108, 0.292), Vector3(0.016, 0.03, 0.011), eye).set_meta("eye_state","open")
		var eyelid_anchors := PackedVector2Array([
			Vector2(side * .108 - .018, .292),
			Vector2(side * .108, .285),
			Vector2(side * .108 + .018, .292)])
		var eyelid_points := PackedVector3Array()
		for point in Expressions.closed_eye_curve(eyelid_anchors):
			eyelid_points.append(_face_point(point.x, point.y, .003))
		var closed_eye := _tube(head_rig, "ClosedEye", eyelid_points, .004, eye.darkened(0.45) if eye.get_luminance() > 0.15 else Color("292321"))
		closed_eye.set_meta("eye_state","closed")
		closed_eye.set_meta("expression_feature","closed_eye")
		closed_eye.hide()
		var brow := _tube(head_rig, "Eyebrow", PackedVector3Array([_face_point(side * 0.076, 0.355),
			_face_point(side * 0.111, 0.359), _face_point(side * 0.142, 0.351)]), 0.0055, hair)
		brow.set_meta("expression_feature","brow")
	# Embed the spherical nose in the cheek volume instead of barely touching it.
	_ellipsoid(head_rig, "RoundNose", _face_point(0, 0.214, 0.012), Vector3.ONE * 0.052, skin)
	var mouth_points := PackedVector3Array()
	for index in 9:
		var x := lerpf(-.059,.059,float(index)/8)
		mouth_points.append(_face_point(x,.114+.013*pow(x/.059,2)))
	var smile := _tube(head_rig, "Smile", mouth_points, 0.0055, skin.darkened(0.5))
	smile.set_meta("expression_feature","mouth")
	hair_root = Node3D.new()
	hair_root.name = "HairSlot"
	head_rig.add_child(hair_root)
	if hair_style != 3: _hair_cap(hair)
	match hair_style if not reference_costume else -1:
		3:
			preload("res://scripts/ukrainian_blender_mesh.gd").hair(hair_root, hair)
		0:
			for side in [-1.0, 1.0]:
				var bun := _ellipsoid(hair_root, "LowBun", Vector3(side * 0.268, 0.075, -0.13), Vector3(0.116, 0.13, 0.126), hair)
				bun.rotation.z = side * 0.2
		1:
			pass
		2:
			for side in [-1.0, 1.0]:
				for i in 5:
					_ellipsoid(hair_root, "Braid%d" % i, Vector3(side * (0.26 + 0.012 * sin(i)),
						0.03 - i * 0.087, -0.075), Vector3(0.076 - i * 0.005, 0.07, 0.074 - i * 0.005), hair)
				var tie := MeshInstance3D.new()
				tie.name = "BraidTie"
				var ring := TorusMesh.new()
				ring.inner_radius = .046
				ring.outer_radius = .063
				ring.rings = 24
				ring.ring_segments = 10
				tie.mesh = ring
				tie.position = Vector3(side*(.26+.012*sin(4.0)),-.318,-.075)
				tie.material_override = _material(get_outfit_color())
				hair_root.add_child(tie)
	if reference_costume:
		_build_hood(_costume_palette()[0])


func _face_point(x: float, y: float, offset: float = 0.0) -> Vector3:
	var radial := 1.0 - pow(x / HEAD_RADIUS.x, 2) - pow((y - HEAD_CENTER.y) / HEAD_RADIUS.y, 2)
	return Vector3(x, y, HEAD_CENTER.z + HEAD_RADIUS.z * sqrt(maxf(radial, 0.0)) + offset)


func _hair_cap(color: Color) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 48
	var rows := 18
	for row in rows + 1:
		for column in segments + 1:
			var angle := TAU * column / segments
			var front := smoothstep(-0.15, 0.65, cos(angle))
			var hairline := 1.03 + 0.84 * smoothstep(0.0, 1.0, absf(sin(angle)))
			if hair_style in [1, 3]:
				hairline = 1.39 + 0.3 * sin(angle + 0.3)
			if hair_style == 3:
				hairline = 1.10 + .16 * sin(angle + .65)
			var end_phi := lerpf(2.44 if hair_style == 1 else 2.19, hairline, front)
			var phi := lerpf(0.018, end_phi, float(row) / rows)
			var unit := Vector3(sin(phi) * sin(angle), cos(phi), sin(phi) * cos(angle))
			var ridge := 1.0 + 0.006 * sin(angle * 9.0 + phi * 4.0)
			vertices.append(Vector3(unit.x * 0.301 * ridge, 0.286 + unit.y * 0.336, unit.z * 0.326 * ridge - 0.012))
			normals.append(unit)
	for row in rows:
		for column in segments:
			var a := row * (segments + 1) + column
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	_mesh(hair_root, "HairCap", vertices, normals, indices, color)
	# Narrow ribbons on the scalp describe the part without separate inflated locks.
	if hair_style != 1:
		var part := PackedVector3Array()
		for i in 11:
			var phi := 1.02 - i * 0.095
			part.append(Vector3(0, 0.286 + cos(phi) * 0.338, sin(phi) * 0.328 - 0.012))
		_tube(hair_root, "HairPart", part, 0.003, color.darkened(0.13))


func _build_hood(color: Color) -> void:
	var hood := Node3D.new()
	hood.name = "HeadwearSlot"
	head_rig.add_child(hood)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var edge := PackedVector3Array()
	for row in 19:
		for column in 41:
			var angle := TAU * column / 40.0
			var phi := lerpf(1.01, PI - 0.01, row / 18.0)
			var normal := Vector3(sin(phi) * sin(angle), sin(phi) * cos(angle), cos(phi))
			var pleat := 1.0 + 0.012 * cos(angle * 7 + phi * 2)
			var point := Vector3(normal.x * 0.355 * pleat, 0.29 + normal.y * 0.405 * pleat, normal.z * 0.346 - 0.026)
			var crown_fold := maxf(-normal.z, 0.0) * maxf(normal.y, 0.0)
			point.y += crown_fold * 0.12
			point.z -= crown_fold * 0.1
			vertices.append(point)
			normals.append(normal)
			if row == 0:
				edge.append(point)
	for row in 18:
		for column in 40:
			var a := row * 41 + column
			indices.append_array(PackedInt32Array([a, a + 41, a + 1, a + 1, a + 41, a + 42]))
	_mesh(hood, "HoodShell", vertices, normals, indices, color)
	_tube(hood, "FoldedHoodEdge", edge, 0.015, color.darkened(0.12))
	_lathe(clothes_root, "HoodShoulder", [Vector3(1.79, 0.25, 0.18), Vector3(1.86, 0.24, 0.17),
		Vector3(1.99, 0.18, 0.155), Vector3(2.06, 0.146, 0.125)], color)


func _cuff_rim(parent: Node3D, edge_color: Color, inside_color: Color) -> void:
	_lathe(parent, "CuffBinding", [Vector3(-0.599, 0.142, 0.146), Vector3(-0.573, 0.140, 0.144)], edge_color, 24, 0.0, false)
	var points := PackedVector3Array()
	for i in 33:
		var angle := TAU * i / 32
		points.append(Vector3(sin(angle) * 0.137, -0.598, cos(angle) * 0.141))
	_tube(parent, "CuffThickness", points, 0.008, edge_color)
	var lining := _lathe(parent, "SleeveLining", [Vector3(-0.597, 0.130, 0.134), Vector3(-0.55, 0.12, 0.115)], inside_color, 24, 0.0, false)
	var material := lining.material_override.duplicate() as ShaderMaterial
	material.shader = preload("res://shaders/doll_lining.gdshader")
	lining.material_override = material


func _build_waistcoat(color: Color, trim: Color) -> void:
	var coat := GarmentOverlay.new()
	coat.name = "OpenWaistcoat"
	coat.mount_surface = NodePath("../TailoredShell")
	coat.material_override = _material(color)
	coat.border_material = _material(trim)
	clothes_root.add_child(coat)
	coat.rebuild()
	_buttons(Vector3(0, 1.61, 0), 4, 0.1, Vector3(0.026, 0.034, 0.007), trim)


func _buttons(origin: Vector3, count: int, spacing: float, size: Vector3, color: Color) -> void:
	var row := ButtonRow.new()
	row.name = "ButtonRow"
	row.position = origin
	row.count = count
	row.spacing = spacing
	row.button_size = size
	row.button_material = _material(color)
	row.mount_surface = NodePath("../TailoredShell")
	clothes_root.add_child(row)
	row.rebuild()


func _robe_embroidery(color: Color) -> void:
	for side in [-1.0, 1.0]:
		_tube(clothes_root, "RobeSeam", PackedVector3Array([Vector3(side * 0.13, 1.86, 0.15),
			Vector3(side * 0.09, 1.63, 0.188), Vector3(side * 0.082, 1.31, 0.205)]), 0.006, color)
		_tube(skirt_root, "SkirtSeam", PackedVector3Array([Vector3(side * 0.08, 1.3, 0.203),
			Vector3(side * 0.11, 0.99, 0.22), Vector3(side * 0.15, 0.7, 0.251),
			Vector3(side * 0.20, 0.36, 0.283)]), 0.006, color)
	_lathe(clothes_root, "RobeBelt", [Vector3(1.235, 0.292, 0.213), Vector3(1.34, 0.284, 0.21)], color)
	for level in 2:
		var border := PackedVector3Array()
		for i in 81:
			var angle := TAU * i / 80.0
			var y := 0.41 + level * 0.09 + sin(angle * 4.0) * 0.035
			var rx := lerpf(0.427, 0.345, (y - 0.30) / 0.40) + 0.006
			var rz := lerpf(0.307, 0.26, (y - 0.30) / 0.40) + 0.006
			border.append(Vector3(sin(angle) * rx, y, cos(angle) * rz))
		_tube(skirt_root, "EmbroideredBorder", border, 0.005, color)


func simulate(delta: float, speed_scale: float) -> void:
	if (rest_support == null or rest_departing) and _rest_blend > 0.0:
		var scaled := delta*speed_scale
		if scaled > 0.0:
			_work_phase += scaled
			_update_puppet_motion(scaled)
		return
	super.simulate(delta,speed_scale)


func _update_puppet_motion(delta: float) -> void:
	if not is_instance_valid(body_rig):
		return
	var blend := 1.0 - exp(-8.0 * delta)
	_walk_blend = lerpf(_walk_blend, 1.0 if _moving and _rest_blend <= 0.0 else 0.0, blend)
	var wave := _travel_distance * 8.5
	var desired_facing := atan2(_heading.x, _heading.z) if _moving else resting_facing
	_facing = lerp_angle(_facing, desired_facing, 1.0 - exp(-5.5 * delta))
	body_rig.rotation.y = _facing
	rig.animate(wave, _walk_blend, activity, _work_phase)
	var support: Node3D = rest_support.get_ref() if rest_support != null else null
	var supported := is_instance_valid(support) and not _moving and not rest_departing
	_rest_blend = move_toward(_rest_blend,1.0 if supported else 0.0,delta/(1.6 if rest_mode == "nap" else .95))
	var pose_amount := smoothstep(0.0,1.0,_rest_blend)
	if _rest_blend > 0.0:
		if nap_pose != _nap_pose_target:
			_nap_pose_from = _nap_pose_weights
			_nap_pose_target = clampi(nap_pose,0,3)
			_nap_pose_progress = 0.0
		_nap_pose_progress = minf(1.0,_nap_pose_progress+delta/maxf(.5,nap_transition_seconds))
		var target_weights := Vector4.ZERO
		target_weights[_nap_pose_target] = 1.0
		_nap_pose_weights = _nap_pose_from.lerp(target_weights,smoothstep(0,1,_nap_pose_progress))
		rig.pose_rest(rest_mode,pose_amount,_work_phase,_nap_pose_weights)
		if supported:
			_rest_yaw = support.global_rotation.y-global_rotation.y
			var hip: Vector3 = rig.skeleton.get_bone_global_pose(rig.bones.Hips).origin
			_rest_offset = to_local(support.global_position)-Basis(Vector3.UP,_rest_yaw)*hip
		body_rig.rotation.y = lerp_angle(_facing,_rest_yaw,pose_amount)
		body_rig.position = _rest_offset*pose_amount
	else:
		body_rig.position = Vector3.ZERO
	var sleeping := supported and rest_mode == "nap" and _rest_blend > .8
	attention_time = maxf(0,attention_time-delta)
	var target_gaze := Vector2(sin(_work_phase*.29)*.12,sin(_work_phase*.17)*.035)
	var focus: Node3D = attention.get_ref() if attention != null else null
	if is_instance_valid(focus) and attention_time > 0:
		var target := focus.global_position
		if focus is PaperDoll: target += Vector3.UP*2.25
		var direction := body_rig.to_local(target)-Vector3(0,2.25,0)
		target_gaze = Vector2(clampf(atan2(direction.x,direction.z),-.55,.55),clampf(-atan2(direction.y,Vector2(direction.x,direction.z).length()),-.20,.20))
	if sleeping: target_gaze = Vector2.ZERO
	_gaze = _gaze.lerp(target_gaze,1.0-exp(-4.5*delta))
	var blink_cycle := fposmod(_work_phase+float(get_instance_id()%37)*.11,4.7)
	var blink := sin(clampf(blink_cycle/.18,0,1)*PI) if blink_cycle < .18 and not sleeping else 0.0
	var eye_closure := 0.0
	if _expressions != null:
		var napping := supported and rest_mode == "nap" and _rest_blend > .05
		_expressions.set_auto_context(activity, supported and not napping, napping)
		_expressions.update(delta)
		eye_closure = _expressions.get_eye_closure()
	var left_layout: Vector3 = _expressions.get_eye_offset(-1.0) if _expressions != null else Vector3.ZERO
	var right_layout: Vector3 = _expressions.get_eye_offset(1.0) if _expressions != null else Vector3.ZERO
	rig.look_toward(_gaze.x,_gaze.y,Vector2(_gaze.x*1.6,-_gaze.y*2.0),maxf(blink,eye_closure),left_layout,right_layout)
	apply_reaches()
	_update_pleated_skirt(delta)


func equip_pleated_skirt(design_or_path: Variant = null, options: Dictionary = {}) -> Node3D:
	if not is_instance_valid(body_rig) or not is_instance_valid(clothes_root):
		return null
	_pleated_skirt_options = options.duplicate(true)
	if not is_instance_valid(skirt_root) or not is_instance_valid(_skirt):
		skirt_root = Node3D.new()
		skirt_root.name = "SkirtAndTrims"
		clothes_root.add_child(skirt_root)
		var palette := _costume_palette()
		_skirt = _lathe(skirt_root, "LongSkirt", [Vector3(0.20, 0.437, 0.313), Vector3(0.24, 0.44, 0.315),
			Vector3(0.30, 0.427, 0.307), Vector3(0.48, 0.389, 0.284), Vector3(0.7, 0.345, 0.26),
			Vector3(0.99, 0.299, 0.222), Vector3(1.22, 0.281, 0.204), Vector3(1.31, 0.28, 0.202)], palette[0], 40, 0.008, false)
		if rig != null:
			rig.bind(body_rig, true, _keep_covered_legs())
	if is_instance_valid(_skirt):
		_skirt.visible = false
	if is_instance_valid(skirt_root):
		for trim_name in ["HemRibbon", "FineHemRibbon", "SkirtSeam", "EmbroideredBorder"]:
			for child in skirt_root.get_children():
				if String(child.name).begins_with(trim_name) and child is Node3D:
					(child as Node3D).visible = false
	if not is_instance_valid(pleated_skirt):
		pleated_skirt = PleatedSkirtNode.new()
		pleated_skirt.name = "EquippedPleatedSkirt"
		clothes_root.add_child(pleated_skirt)
	if typeof(design_or_path) == TYPE_DICTIONARY and not (design_or_path as Dictionary).is_empty():
		pleated_skirt.configure(design_or_path)
	elif typeof(design_or_path) == TYPE_STRING and not String(design_or_path).is_empty():
		pleated_skirt.load_design(String(design_or_path))
	elif pleated_skirt.design.is_empty():
		pleated_skirt.rebuild()
	pleated_skirt.bind_to_doll(self)
	_update_pleated_skirt(0.0)
	return pleated_skirt


func unequip_pleated_skirt() -> void:
	if is_instance_valid(pleated_skirt):
		pleated_skirt.free()
	pleated_skirt = null
	_pleated_skirt_options.clear()
	if is_instance_valid(_skirt):
		_skirt.visible = true
	if is_instance_valid(skirt_root):
		for child in skirt_root.get_children():
			if child is Node3D:
				(child as Node3D).visible = true


func _update_pleated_skirt(delta: float) -> void:
	if not is_instance_valid(pleated_skirt):
		return
	var motion := String(_pleated_skirt_options.get("motion", ""))
	if motion.is_empty():
		var support: Node3D = rest_support.get_ref() if rest_support != null else null
		var supported := is_instance_valid(support) and not _moving and not rest_departing and _rest_blend > 0.25
		if supported and rest_mode == "nap":
			motion = "lie"
		elif supported or activity in ["weaving", "sewing"]:
			motion = "sit"
		elif activity in ["display", "spin"]:
			motion = activity
		elif _moving:
			motion = "walk"
		else:
			motion = "stand"
	var pose_opts := _pleated_skirt_options.duplicate(true)
	var progress := clampf(_rest_blend if motion in ["sit", "lie"] else fposmod(_work_phase, 1.0), 0.0, 1.0)
	pleated_skirt.pose_on_doll(motion, progress, _work_phase, pose_opts)


func _build_shoe(parent: Node3D, color: Color) -> void:
	var shoe := Node3D.new()
	shoe.name = "Shoe"
	shoe.position = Vector3(0, -1.1, 0.145)
	parent.add_child(shoe)
	shoe.set_meta("design_id", "basic_shoes")
	shoe.set_meta("culture_attribution", "")
	shoe.set_meta("wiki_record_id", "WW-GEN-001")
	if shoe_style == 1:
		color = Color("684333")
		_ellipsoid(shoe, "WhiteSockInstep", Vector3(0, .108, -.065), Vector3(.093, .083, .139), Color("efede5"))
		var strap := PackedVector3Array()
		for step in 17:
			var angle := PI * step / 16.0
			strap.append(Vector3(.108 * cos(angle), .096 + .102 * sin(angle), -.042))
		_tube(shoe, "InstepStrap", strap, .008, color.darkened(.18))
	var sole := _lathe(shoe, "FlatSole", [Vector3(.009,.134,.216),Vector3(.017,.141,.220),Vector3(.033,.141,.220)],color.darkened(.20),32,0.0,true,[],[-.002,-.002,-.002])
	# Generic low shoe: rounded toe, closed vamp and a real open collar around
	# the ankle. The last rows turn down inside the shoe instead of sealing it.
	var rows := [Vector4(.033,.139,.220,-.002),Vector4(.070,.140,.218,-.002),
		Vector4(.110,.131,.204,-.018),Vector4(.143,.110,.166,-.052),
		Vector4(.158,.077,.111,-.098),Vector4(.151,.067,.101,-.098),
		Vector4(.074,.062,.096,-.098),Vector4(.044,.056,.089,-.098)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 32
	for row in rows:
		for column in segments + 1:
			var angle := TAU * column / segments
			vertices.append(Vector3(sin(angle)*row.y,row.x,cos(angle)*row.z+row.w))
	for row in rows.size() - 1:
		for column in segments:
			var a := row * (segments + 1) + column
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	normals.resize(vertices.size())
	for face in range(0,indices.size(),3):
		var a := indices[face]
		var b := indices[face+1]
		var c := indices[face+2]
		var normal := (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for row in rows.size():
		var seam := row * (segments + 1)
		var smooth := normals[seam] + normals[seam+segments]
		normals[seam] = smooth
		normals[seam+segments] = smooth
	for index in normals.size(): normals[index] = normals[index].normalized()
	var upper := _mesh(shoe,"ShoeUpper",vertices,normals,indices,color)
	for part in [sole,upper]:
		part.set_meta("design_id","basic_shoes")
		part.set_meta("culture_attribution", "")
		part.set_meta("wiki_record_id","WW-GEN-001")


func _material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _volume_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = VOLUME_SHADER
		material.set_shader_parameter("pigment", color)
		_volume_materials[key] = material
	return _volume_materials[key]


func _ellipsoid(parent: Node3D, label: String, center: Vector3, radius: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position = center
	instance.scale = radius
	instance.material_override = _material(color)
	parent.add_child(instance)
	return instance


func _build_shared_hand(parent: Node3D, side: float, color: Color) -> void:
	var source: Dictionary = preload("res://assets/shared_hand.json").data
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array(source.indices)
	for p in source.vertices:
		vertices.append(Vector3(p[0]*side, p[1]-.659, p[2]+.03))
	for n in source.normals:
		normals.append(Vector3(n[0]*side,n[1],n[2]))
	if side < 0:
		for i in range(0, indices.size(), 3):
			var swap := indices[i]
			indices[i] = indices[i+2]
			indices[i+2] = swap
	_mesh(parent,"Mitten",vertices,normals,indices,color)


func _lathe(parent: Node3D, label: String, rings: Array, color: Color, segments: int = 24, folds: float = 0.0, caps: bool = true, x_offsets: Array = [], z_offsets: Array = []) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in rings.size():
		var ring: Vector3 = rings[row]
		var previous: Vector3 = rings[maxi(row - 1, 0)]
		var next: Vector3 = rings[mini(row + 1, rings.size() - 1)]
		var center_x: float = x_offsets[row] if not x_offsets.is_empty() else 0.0
		var center_z: float = z_offsets[row] if not z_offsets.is_empty() else 0.0
		for column in segments + 1:
			var angle := TAU * column / segments
			var modulation := 1.0 + folds * cos(angle * 8.0)
			vertices.append(Vector3(center_x + sin(angle) * ring.y * modulation, ring.x, center_z + cos(angle) * ring.z * modulation))
			var slope := -((next.y - previous.y) + (next.z - previous.z)) * 0.5 / maxf(next.x - previous.x, 0.001)
			var normal := Vector3(sin(angle) / maxf(ring.y, 0.01), slope / maxf(ring.y, 0.01), cos(angle) / maxf(ring.z, 0.01))
			if not x_offsets.is_empty() or not z_offsets.is_empty():
				var dx: float = (x_offsets[mini(row + 1, rings.size() - 1)] - x_offsets[maxi(row - 1, 0)]) if not x_offsets.is_empty() else 0.0
				var dz: float = (z_offsets[mini(row + 1, rings.size() - 1)] - z_offsets[maxi(row - 1, 0)]) if not z_offsets.is_empty() else 0.0
				normal.y = -(normal.x * (dx + sin(angle) * (next.y - previous.y)) + normal.z * (dz + cos(angle) * (next.z - previous.z))) / maxf(next.x - previous.x, 0.001)
			normals.append(normal.normalized())
	for row in rings.size() - 1:
		for column in segments:
			var a := row * (segments + 1) + column
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	for end in [0, rings.size() - 1]:
		if not caps:
			continue
		var center_index := vertices.size()
		var ring: Vector3 = rings[end]
		var cap_x: float = x_offsets[end] if not x_offsets.is_empty() else 0.0
		var cap_z: float = z_offsets[end] if not z_offsets.is_empty() else 0.0
		vertices.append(Vector3(cap_x, ring.x, cap_z))
		normals.append(Vector3.DOWN if end == 0 else Vector3.UP)
		for column in segments:
			var a: int = end * (segments + 1) + column
			if end == 0:
				indices.append_array(PackedInt32Array([center_index, a, a + 1]))
			else:
				indices.append_array(PackedInt32Array([center_index, a + 1, a]))
	return _mesh(parent, label, vertices, normals, indices, color)


func _surface_panel(parent: Node3D, label: String, rows: Array, color: Color) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in rows:
		for column in 13:
			var u := (float(column) / 12.0 - 0.5) * 2.0
			vertices.append(Vector3(u * row.y, row.x, row.z - u * u * 0.042))
			normals.append(Vector3(u * 0.15, 0, 1).normalized())
	for row in rows.size() - 1:
		for column in 12:
			var a := row * 13 + column
			indices.append_array(PackedInt32Array([a, a + 13, a + 1, a + 1, a + 13, a + 14]))
	return _mesh(parent, label, vertices, normals, indices, color)


func _fitted_panel(label: String, sources: Array, volumes: Array, gap: float, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = label
	panel.material_override = _material(color)
	clothes_root.add_child(panel)
	FittedPanel.build(panel,sources,volumes,gap)
	return panel


func _mesh(parent: Node3D, label: String, vertices: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, color: Color) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = _material(color)
	parent.add_child(instance)
	return instance


func _tube(parent: Node3D, label: String, points: PackedVector3Array, radius: float, color: Color) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var horizontal := tangent.cross(Vector3.FORWARD)
		if horizontal.length_squared() < 0.01:
			horizontal = tangent.cross(Vector3.RIGHT)
		horizontal = horizontal.normalized()
		var vertical := tangent.cross(horizontal).normalized()
		for column in 9:
			var angle := TAU * column / 8.0
			var normal := horizontal * cos(angle) + vertical * sin(angle)
			vertices.append(points[i] + normal * radius)
			normals.append(normal)
	for row in points.size() - 1:
		for column in 8:
			var a := row * 9 + column
			indices.append_array(PackedInt32Array([a, a + 9, a + 1, a + 1, a + 9, a + 10]))
	return _mesh(parent, label, vertices, normals, indices, color)


func _flower(parent: Node3D, center: Vector3, petal: Color, core: Color) -> void:
	for index in 5:
		var angle := TAU * index / 5
		var piece := _ellipsoid(parent, "Petal%d" % index, center + Vector3(sin(angle), cos(angle), 0) * 0.051,
			Vector3(0.022, 0.041, 0.011), petal)
		piece.rotation.z = -angle
		piece.set_meta("material_role","flower")
	_ellipsoid(parent, "FlowerCenter", center + Vector3(0, 0, 0.013), Vector3(0.025, 0.025, 0.014), core).set_meta("material_role","flower")
