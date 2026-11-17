class_name GrandmaDoll
extends "res://scripts/game_body_doll.gd"
## Protagonist 1: Grandma (奶奶) adapted cleanly onto GameBodyDoll medium body (p2 style).

const Helpers = preload("res://scripts/characters/p1_character_helpers.gd")

const COLOR_SKIN := Color("f1ccb7")
const COLOR_SILVER_HAIR := Color("dcdfe4")
const COLOR_SILVER_SHADE := Color("b6bcc4")
const COLOR_BRAID_TIE := Color("3b6c5f")
const COLOR_GLASSES := Color("343942")
const COLOR_EYE := Color("232226")
const COLOR_CREAM_KNIT := Color("ebe5d5")
const COLOR_CREAM_RIB := Color("d5cdba")
const COLOR_PONCHO_BASE := Color("a89c94")
const COLOR_PONCHO_MAROON := Color("56212c")
const COLOR_TROUSER := Color("303643")
const COLOR_SHOE := Color("252830")
const COLOR_CANE := Color("23252a")


func _init() -> void:
	outfit_style = 2
	hair_style = 1
	skin_index = 0
	custom_skin_color = COLOR_SKIN
	custom_hair_color = COLOR_SILVER_HAIR
	custom_eye_color = COLOR_EYE


func _covers_legs() -> bool:
	return false


func _keep_covered_legs() -> bool:
	return true


func _costume_palette() -> Array:
	return [COLOR_PONCHO_BASE, COLOR_CREAM_KNIT, COLOR_CREAM_KNIT]


func _build_volume_body() -> void:
	super()
	# 1. Replace outfit_style=2 generic waistcoat & buttons with Cream Ribbed Turtleneck
	for child in clothes_root.get_children():
		var cname := str(child.name)
		if cname.begins_with("OpenWaistcoat") or cname.begins_with("Button"):
			child.free()

	var knit_tex := _make_cream_rib_texture()
	_garment.material_override = Helpers.textured_material(knit_tex)
	Helpers.apply_torus_or_shell_uvs(_garment, 1.10, 1.93)
	# TurtleneckCollar is built inside _build_fitted_cuffs() after BodyFit so BodyFit never inflates base rings through poncho.

	# 2. Custom Dark Charcoal-Slate Straight Trousers with smooth dense knee rings (zero walk rip)
	for leg in legs:
		var old_tr := leg.get_node_or_null("Trouser")
		if old_tr != null:
			old_tr.free()
		var ox := -0.015 if leg.name == "LegRight" else 0.015
		_lathe(leg, "Trouser", [
			Vector3(-0.92, 0.118, 0.125),
			Vector3(-0.80, 0.125, 0.132),
			Vector3(-0.62, 0.130, 0.138),
			Vector3(-0.50, 0.138, 0.146),
			Vector3(-0.40, 0.144, 0.154),
			Vector3(-0.30, 0.146, 0.156),
			Vector3(-0.18, 0.148, 0.154),
			Vector3(0.05, 0.144, 0.150),
		], COLOR_TROUSER, 24, 0.0, false,
		[ox, ox, ox, ox, ox, ox, ox, ox])
		for shoe in leg.find_children("*", "MeshInstance3D", true, false):
			if str(shoe.name) in ["FlatSole", "ShoeUpper"]:
				shoe.material_override = _material(COLOR_SHOE if str(shoe.name) == "ShoeUpper" else COLOR_SHOE.darkened(0.25))

	# 3. Signature Pointed-V Chevron Woven Poncho (Taupe Base + Dual Maroon V-Stripes)
	_build_poncho_drape()


func _tuck_torus_under_poncho(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null or not (mesh_node.mesh is ArrayMesh):
		return
	var am := mesh_node.mesh as ArrayMesh
	var arrays := am.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array = mesh_node.get_meta("garment_arm_weights", PackedFloat32Array())
	for i in verts.size():
		var v := verts[i]
		var w := weights[i] if i < weights.size() else 0.0
		var aw := absf(w)
		var sec := Helpers.torso_section_at_y(v.y)
		if aw < 0.42:
			# Shrink inner torso & chest cleanly inside poncho so ZERO undershirt dots poke out anywhere
			v.x *= 0.62
			v.z = sec.z + (v.z - sec.z) * 0.60
			v.y = clampf(v.y, 1.248, 1.795)
		else:
			var t_arm := clampf((v.y - 1.22) / 0.58, 0.0, 1.0)
			var arm_sign := signf(w) if aw > 0.01 else signf(v.x)
			var axis_x := arm_sign * lerpf(0.268, 0.162, t_arm)
			var shrink := lerpf(0.46, 0.24, smoothstep(1.36, 1.52, v.y))
			v.x = axis_x + (v.x - axis_x) * shrink
			v.z = 0.022 + (v.z - 0.022) * shrink
			if v.y > 1.38:
				var cape_t := smoothstep(1.36, 1.50, v.y)
				v.x -= arm_sign * 0.030 * cape_t
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = Helpers.compute_smooth_normals(verts, arrays[Mesh.ARRAY_INDEX])
	var new_am := ArrayMesh.new()
	new_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_node.mesh = new_am
	if not weights.is_empty():
		mesh_node.set_meta("garment_arm_weights", weights)


func _build_fitted_cuffs() -> void:
	super()
	# Run AFTER AcceptedBodyFit.apply() and BEFORE DollRig.bind() so BodyFit never inflates base rings!
	_tuck_torus_under_poncho(_garment)
	var knit_tex := _make_cream_rib_texture()
	var collar_mat := Helpers.textured_material(knit_tex, Color.WHITE, 0.12)
	collar_mat.set_shader_parameter("cloth_contact_enabled", false)
	var collar_ys := [1.66, 1.72, 1.78, 1.84, 1.895, 1.935, 1.968, 1.992, 2.004]
	var collar_rings := []
	var collar_z := []
	for idx in collar_ys.size():
		var cy: float = collar_ys[idx]
		var sec := Helpers.torso_section_at_y(cy)
		# Hug MannequinTorso cleanly +8.5mm (softly beveled to +2.5mm under chin, zero neck clip!)
		var pad := 0.0025 if idx == collar_ys.size() - 1 else (0.0075 if idx >= 6 else 0.0085)
		collar_rings.append(Vector3(cy, sec.x + pad, sec.y + pad))
		collar_z.append(sec.z)
	var collar := Helpers.build_uv_lathe(clothes_root, "TurtleneckCollar", collar_rings, collar_mat, 36, 0.0025, false, [], collar_z)
	collar.set_meta("garment_slot", "top")

	Helpers.slim_covered_limbs(arms, "ArmMannequin", 0.28, 0.22, 0.032)
	Helpers.slim_covered_limbs(legs, "LegMannequin", 0.12, 0.28, 0.0)
	var cuff := clothes_root.get_node_or_null("CuffBinding") as MeshInstance3D
	if cuff != null:
		# Grandma's sleeves emerge softly beneath poncho hem; hide external flared CuffBinding so poncho sides stay 100% clean
		cuff.visible = false


func _build_poncho_drape() -> void:
	var poncho_mat := Helpers.textured_material(_make_poncho_texture(), Color.WHITE, 0.16)
	var rings := 30
	var cols := 64
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()

	for r in rings + 1:
		var vt := float(r) / rings
		# Smooth shoulder-draping bell envelope from V-neck collar out to pointed V-hem
		var base_rx := lerpf(0.122, 0.422, pow(vt, 0.34))
		var base_rz := lerpf(0.106, 0.274, pow(vt, 0.34))
		for c in cols + 1:
			var ut := float(c) / cols
			var angle := TAU * ut
			var cos_a := cos(angle)
			var sin_a := sin(angle)
			var abs_ang := absf(atan2(sin_a, cos_a)) # 0 = front center, PI = back center
			var sym_u := abs_ang / PI
			# Lateral fraction: 0 at front/back center V-tip, 1 at left/right sides (linear XY V edge)
			var lat := clampf(lerpf(absf(sin_a), 1.0 - absf(sym_u * 2.0 - 1.0), 0.20), 0.0, 1.0)
			var center_v := 1.0 - lat
			# Continuous V-neck opening cleanly reaching turtleneck sides (|ang| ~ 1.76) with zero shoulder corner notch
			var v_open := pow(clampf(abs_ang / (PI * 0.56), 0.0, 1.0), 0.85)
			var neck_top_y := lerpf(1.745, 1.868, v_open) + 0.012 * smoothstep(1.6, PI, abs_ang)
			var hem_y := lerpf(0.74, 1.28, lat)
			var roll_t := clampf((vt - 0.025) / 0.975, 0.0, 1.0)
			var y: float
			if vt < 0.025:
				y = lerpf(neck_top_y - 0.004, neck_top_y, vt / 0.025)
			else:
				y = lerpf(neck_top_y, hem_y, pow(roll_t, 0.90))
			var sec := Helpers.torso_section_at_y(y)
			# Inner collar lip (vt=0) rests flush against TurtleneckCollar (+9.2mm), stepping cleanly outward to poncho thickness
			var collar_ease := lerpf(0.0092, 0.0185, smoothstep(0.0, 0.03, vt))
			var neck_rx := sec.x + collar_ease
			var neck_rz := sec.y + collar_ease - 0.001
			var col_pinch := smoothstep(0.01, 0.16, vt)
			var rx := lerpf(neck_rx, base_rx, col_pinch) * (1.0 + 0.03 * lat * sin(vt * PI))
			var rz := lerpf(neck_rz, base_rz, col_pinch) * (1.0 + 0.07 * center_v * sin(vt * PI * 0.85))
			var z_shift := lerpf(sec.z, 0.008, smoothstep(0.0, 0.55, vt))
			var px := sin_a * rx
			var pz := cos_a * rz + z_shift
			verts.append(Vector3(px, y, pz))
			# Map UV.y cleanly below 0.990 so shader repeat_enable never wraps bottom hem trim (v=0) onto top collar!
			var v_above_hem := clampf((y - hem_y) / 1.12, 0.004, 0.990)
			uvs.append(Vector2(center_v, v_above_hem))
			var aw := 0.0
			if absf(px) > 0.26 and y < 1.68 and y > 1.26:
				aw = signf(px) * 0.36 * (1.0 - smoothstep(0.45, 0.95, roll_t))
			arm_weights.append(aw)

	for r in rings:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + cols + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))

	var normals := Helpers.compute_smooth_normals(verts, indices)
	var poncho := Helpers._commit_uv_mesh(clothes_root, "ChevronPoncho", verts, normals, uvs, indices, poncho_mat)
	poncho.set_meta("garment_arm_weights", arm_weights)
	poncho.set_meta("garment_slot", "outer")


func _prepare_body_for_rig() -> void:
	super()
	var seat := clothes_root.get_node_or_null("TrouserSeat")
	if seat != null:
		seat.material_override = _material(COLOR_TROUSER)

	# Build Walking Cane attached rigidly to Left Hand ("HandL", viewer's LEFT, matching p1!)
	var cane_root := Node3D.new()
	cane_root.name = "WalkingCane"
	clothes_root.add_child(cane_root)
	# Cane shaft passing cleanly straight out of curled HandL palm down to ground contact
	var shaft := Helpers.build_cylinder_mesh(cane_root, "CaneShaft", 0.018, 0.015, 1.045,
		Vector3(-0.308, 0.530, 0.050), COLOR_CANE, Vector3(0.0, 0.0, -1.0), 16)
	shaft.set_meta("attachment_bone", "HandL")

	# Tight J-hook crook clasped cleanly inside HandL fingers/palm (no floating gap)
	var crook_pts := PackedVector3Array()
	for i in 17:
		var ang := lerpf(0.0, PI, float(i) / 16.0)
		var cx := -0.298 - 0.043 * (1.0 - cos(ang))
		var cy := 1.048 + 0.043 * sin(ang)
		crook_pts.append(Vector3(cx, cy, 0.050))
	var crook := _tube(cane_root, "CaneCrook", crook_pts, 0.020, COLOR_CANE)
	crook.set_meta("attachment_bone", "HandL")


func _build_volume_head() -> void:
	super()
	for node in head_rig.find_children("Eyebrow*", "MeshInstance3D", true, false):
		node.material_override = _material(COLOR_SILVER_SHADE)

	for side: float in [-1.0, 1.0]:
		var smile_crease := _tube(head_rig, "CheekCrease", PackedVector3Array([
			_face_point(side * 0.088, 0.145, 0.004),
			_face_point(side * 0.100, 0.112, 0.004)]), 0.003, Color("cc9884"))
		smile_crease.set_meta("expression_feature", "cheek_crease")

	for ch in hair_root.get_children():
		ch.free()
	hair_style = 0
	_hair_cap(COLOR_SILVER_HAIR)
	for node in hair_root.find_children("LowBun*", "MeshInstance3D", true, false):
		node.free()
	hair_style = 0

	# Sculpted spherical-contour straight bangs flush with dome (NO jutting upper corners)
	var b_rows := 7
	var b_cols := 22
	var _bangs := Helpers.build_uv_patch(hair_root, "GrandmaStraightBangs", b_rows, b_cols, func(ut: float, vt: float) -> Vector3:
		var angle := lerpf(-0.96, 0.96, ut)
		var phi_top := lerpf(0.16, 0.42, pow(absf(ut * 2.0 - 1.0), 1.4))
		var phi_bot := lerpf(1.22, 1.32, absf(ut * 2.0 - 1.0))
		var phi := lerpf(phi_top, phi_bot, vt)
		var r_x := 0.285 + 0.012 * sin(vt * PI)
		var r_y := 0.308
		var r_z := 0.302 + 0.014 * sin(vt * PI) + 0.004 * cos(ut * PI * 10.0) * smoothstep(0.3, 1.0, vt)
		var px := sin(phi) * sin(angle) * r_x
		var py := 0.290 + cos(phi) * r_y
		var pz := sin(phi) * cos(angle) * r_z
		return Vector3(px, py, pz)
	, Helpers.flat_material(COLOR_SILVER_HAIR))

	# Dual thick braided pigtails curving cleanly forward over chest front
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side < 0.0 else "R"
		var links := 6
		for i in links:
			var t := float(i) / maxf(float(links - 1), 1.0)
			var bx: float = side * (0.285 + 0.012 * sin(t * PI) - 0.020 * t)
			var by := lerpf(0.09, -0.34, t)
			var bz := lerpf(-0.04, 0.10, pow(t, 0.85))
			var rad := Vector3(0.068 - t * 0.016, 0.064 - t * 0.012, 0.064 - t * 0.014)
			var puff := _ellipsoid(hair_root, "Braid%sSeg%d" % [sname, i], Vector3(bx, by, bz), rad, COLOR_SILVER_HAIR)
			puff.rotation.z = side * (0.14 if i % 2 == 0 else -0.14)
		# Pine-green hair tie band
		Helpers.build_ring(hair_root, "Braid%sTie" % sname, Vector3(side * 0.268, -0.365, 0.108),
			0.044, 0.013, Vector3(14.0, 0.0, side * -8.0), COLOR_BRAID_TIE, 24, 10)
		# Tapered brush braid tip below tie
		_ellipsoid(hair_root, "Braid%sTip" % sname, Vector3(side * 0.266, -0.425, 0.115),
			Vector3(0.042, 0.062, 0.042), COLOR_SILVER_HAIR)

	# Dark Charcoal Round Glasses cleanly framing eyes
	Helpers.build_glasses(head_rig, COLOR_GLASSES, 0.112, 0.292, 0.286, 0.068, 0.0085)


func _make_poncho_texture() -> Image:
	var w := 128
	var h := 512
	var trim_col := COLOR_CREAM_KNIT.lerp(COLOR_PONCHO_BASE, 0.22)
	var line_col := COLOR_PONCHO_MAROON.darkened(0.08)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var vt := float(py) / float(h - 1) # 0 = bottom V-hem edge, 1 = shoulder/neck (constant metric height!)
		var d_m := vt * 1.12
		for px in w:
			var col := COLOR_PONCHO_BASE
			# Two parallel EQUAL-WIDTH maroon V-chevron stripes + crisp p1 pin-stripes parallel to bottom V-hem
			if (d_m >= 0.112 and d_m <= 0.194) or (d_m >= 0.270 and d_m <= 0.352):
				col = COLOR_PONCHO_MAROON
			elif (d_m >= 0.068 and d_m <= 0.084) or (d_m >= 0.380 and d_m <= 0.396):
				col = line_col
			elif d_m < 0.018:
				col = trim_col
			# Subtle woven yarn texture
			var weave := 1.0 + 0.025 * sin(float(px) * 0.45) * cos(float(py) * 0.7)
			img.set_pixel(px, py, col * Color(weave, weave, weave, 1.0))
	return img


func _make_cream_rib_texture() -> Image:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		for px in w:
			var rib := 1.0 if (px % 8) < 5 else 0.94
			img.set_pixel(px, py, COLOR_CREAM_KNIT * Color(rib, rib, rib, 1.0))
	return img


func _build_appearance() -> void:
	super()
	Helpers.disable_cloth_contact(body_rig, [
		"SkinnedMeshes/garment/TailoredShell",
		"SkinnedMeshes/torso/TurtleneckCollar",
		"SkinnedMeshes/garment/ChevronPoncho",
	])
