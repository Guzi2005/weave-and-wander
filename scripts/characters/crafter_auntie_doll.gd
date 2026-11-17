class_name CrafterAuntieDoll
extends "res://scripts/game_body_doll.gd"
## Character 3: Crafter / Market Auntie (阿妈/摊主) adapted faithfully onto GameBodyDoll medium body (p2 style).

const Helpers = preload("res://scripts/characters/p1_character_helpers.gd")

const COLOR_SKIN := Color("cda388")
const COLOR_HAIR := Color("232732")
const COLOR_EYE := Color("201d22")
const COLOR_CREASE := Color("9e6e58")
const COLOR_TURBAN_BASE := Color("3e4d66")
const COLOR_TURBAN_DARK := Color("2a364a")
const COLOR_GOLD := Color("cf9d2d")
const COLOR_ROBE := Color("677b85")
const COLOR_ROBE_TRIM := Color("50636d")
const COLOR_SASH := Color("2d7c86")
const COLOR_SASH_SHADOW := Color("205b63")
const COLOR_BURGUNDY := Color("5e2833")
const COLOR_EMBROIDERY_MINT := Color("5fb3b8")
const COLOR_SHOE := Color("667a84")
const COLOR_SOLE := Color("dcd7cd")


func _init() -> void:
	outfit_style = 0
	hair_style = 1
	shoe_style = 0
	skin_index = 2
	custom_skin_color = COLOR_SKIN
	custom_hair_color = COLOR_HAIR
	custom_eye_color = COLOR_EYE


func _covers_legs() -> bool:
	return true


func _keep_covered_legs() -> bool:
	return false


func _costume_palette() -> Array:
	return [COLOR_ROBE, COLOR_SASH, COLOR_ROBE]


func _build_volume_body() -> void:
	super()
	# Clean default buttons, flower, waist ribbon, hem trims
	for child in clothes_root.get_children():
		var cname := str(child.name)
		if cname.begins_with("Button") or cname in ["WaistRibbon", "StandingCollar"] or child.get_meta("material_role", "") == "flower":
			child.free()
	if is_instance_valid(skirt_root):
		for child in skirt_root.get_children():
			child.free()
	else:
		skirt_root = Node3D.new()
		skirt_root.name = "SkirtAndTrims"
		clothes_root.add_child(skirt_root)

	# 1. Cross-Collar Tunic Top (TailoredShell with clean kimono sleeve flare; lapels snap post-Fit)
	_garment.set("_pending", true)
	_garment.waist_height = 1.27
	_garment.sleeve_length = 0.96
	_garment.cuff_width = 1.06
	_garment.rebuild()
	var tunic_tex := _make_cross_collar_texture()
	_garment.material_override = Helpers.textured_material(tunic_tex)
	Helpers.apply_torus_or_shell_uvs(_garment, 1.27, 1.93, 1.83, 1.21)

	var standing_collar := clothes_root.get_node_or_null("StandingCollar") as MeshInstance3D
	if standing_collar != null:
		standing_collar.free()

	# 2. Straight Column Ankle-Length Dusty Slate-Blue Skirt (y = 0.26..1.31)
	var skirt_rings := [
		Vector3(0.25, 0.305, 0.235),
		Vector3(0.50, 0.302, 0.232),
		Vector3(0.82, 0.296, 0.226),
		Vector3(1.10, 0.288, 0.214),
		Vector3(1.31, 0.280, 0.204),
	]
	_skirt = _lathe(skirt_root, "LongSkirt", skirt_rings, COLOR_ROBE, 48, 0.004, false)
	_skirt.material_override = _skirt.material_override.duplicate()
	_skirt.material_override.set_shader_parameter("backface_shade", 0.18)

	# 3. Wrapped Teal-Turquoise Sash Belt (y = 1.24..1.40) hugging torso/waist smoothly (full 360° wrap uses native torso weights)
	var _sash_belt := _lathe(clothes_root, "TurquoiseWaistSash", [
		Vector3(1.23, 0.288, 0.214),
		Vector3(1.31, 0.286, 0.213),
		Vector3(1.40, 0.282, 0.210),
	], COLOR_SASH, 40, 0.0, true)

	# 4. Burgundy-Bordered Teal Geometric Embroidered Apron Panel (y = 0.78..1.25)
	var apron_mat := Helpers.textured_material(_make_embroidered_apron_texture())
	var apron := Helpers.build_uv_patch(clothes_root, "EmbroideredApronPanel", 10, 16, func(ut: float, vt: float) -> Vector3:
		var y := lerpf(1.25, 0.78, vt)
		var ang := lerpf(-0.88, 0.90, ut)
		var t_y := clampf((y - 0.50) / (1.31 - 0.50), 0.0, 1.0)
		var rx := lerpf(0.302, 0.280, t_y) + 0.011
		var rz := lerpf(0.232, 0.204, t_y) + 0.011
		return Vector3(sin(ang) * rx, y, cos(ang) * rz)
	, apron_mat)
	apron.set_meta("skin_layer_sources", PackedStringArray([str(apron.get_path_to(_skirt))]))

	# 5. Sash Front Knot & Two Hanging Turquoise Sash Tails (use native torso rig; sit crisply over apron)
	var _knot := _ellipsoid(clothes_root, "SashKnot", Vector3(0.095, 1.315, 0.230), Vector3(0.056, 0.048, 0.036), COLOR_SASH.lightened(0.06))

	# Left & Right hanging sash tails layered cleanly IN FRONT of embroidered apron
	for side_i in 2:
		var ang_c := 0.25 if side_i == 0 else 0.45
		var width_a := 0.13 if side_i == 0 else 0.12
		var tail_len := 0.88 if side_i == 0 else 0.94
		var tcol := COLOR_SASH if side_i == 0 else COLOR_SASH_SHADOW.lightened(0.10)
		var tail := Helpers.build_uv_patch(clothes_root, "SashTail%d" % side_i, 8, 4, func(ut: float, vt: float) -> Vector3:
			var y := lerpf(1.29, tail_len, vt)
			var ang := lerpf(ang_c - width_a, ang_c + width_a, ut) + 0.05 * vt * (1.0 if side_i == 1 else -0.4)
			var t_y := clampf((y - 0.50) / (1.31 - 0.50), 0.0, 1.0)
			var rx := lerpf(0.302, 0.280, t_y) + (0.024 if side_i == 0 else 0.029)
			var rz := lerpf(0.232, 0.204, t_y) + (0.024 if side_i == 0 else 0.029)
			return Vector3(sin(ang) * rx, y, cos(ang) * rz)
		, Helpers.flat_material(tcol))
		tail.set_meta("skin_layer_sources", PackedStringArray([str(tail.get_path_to(_skirt))]))

	# 6. Dusty Slate-Blue Slippers with Pale Cream Sole
	for leg in legs:
		var shoe := leg.get_node_or_null("Shoe")
		if shoe != null:
			for part in shoe.find_children("*", "MeshInstance3D", true, false):
				var pname := str(part.name)
				if pname == "ShoeUpper":
					part.material_override = _material(COLOR_SHOE)
				elif pname == "FlatSole":
					part.material_override = _material(COLOR_SOLE)


func _cross_collar_cut_y(ang: float, _p := Vector3.ZERO) -> float:
	# High neck root around back & sides (1.912), crisp linear V opening ONLY in front throat (1.752)
	var front_t := clampf(absf(atan2(sin(ang), cos(ang))) / 0.44, 0.0, 1.0)
	return lerpf(1.752, 1.912, front_t)


func _make_lapel_band_texture() -> Image:
	var w := 64
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var edge_col := COLOR_ROBE_TRIM.darkened(0.08)
	for py in h:
		for px in w:
			var ut := float(px) / float(w - 1) # 0 = outer flush cloth seam, 1 = inner overlap fold edge
			var trim_t := smoothstep(0.65, 0.85, ut)
			img.set_pixel(px, py, COLOR_ROBE.lerp(edge_col, trim_t))
	return img


func _build_cross_collar_lapels() -> void:
	## Builds tight flush neck rim + V-edge lapels strictly OVER solid _garment (zero open-air bridge or neck halo).
	var band_mat := Helpers.textured_material(_make_lapel_band_texture(), Color.WHITE, 0.14)
	band_mat.set_shader_parameter("cloth_contact_enabled", false)

	# 1. Snug collar rim snapped cleanly along back/side neckline of tight _garment (never sticking out horizontally!)
	var rim_mat := Helpers.flat_material(COLOR_ROBE_TRIM, 0.14)
	rim_mat.set_shader_parameter("cloth_contact_enabled", false)
	var neck_rim := Helpers.build_snapped_uv_patch(clothes_root, "CrossCollarNeckRim", 24, 4,
		func(ut: float, vt: float) -> Vector3:
			var ang := lerpf(0.40, TAU - 0.40, vt)
			var top_y := _cross_collar_cut_y(ang)
			var y := lerpf(top_y - 0.018, top_y - 0.001, ut)
			return Helpers.torso_point_at(ang, y, lerpf(0.004, 0.0025, ut)),
		func(ut: float, _vt: float) -> float:
			return lerpf(0.0004, 0.0018, ut),
		_garment, rim_mat, true)
	neck_rim.set_meta("garment_slot", "top")

	# 2. Right-under lapel (/ strictly along solid +X V-wall down to V apex; zero overhang past V edge)
	var lapel_r := Helpers.build_snapped_uv_patch(clothes_root, "CrossCollarRight", 16, 4,
		func(ut: float, vt: float) -> Vector3:
			var v_ang := lerpf(0.42, 0.0, vt)
			var py := _cross_collar_cut_y(v_ang)
			var width := lerpf(0.056, 0.076, vt)
			# ut=0 lies outward on +X solid robe (+width); ut=1 inner fold aligns right on V edge (never past it)
			var a := v_ang + lerpf(width, 0.0, ut)
			return Helpers.torso_point_at(a, py, 0.005),
		func(ut: float, vt: float) -> float:
			var fade := 1.0 - 0.25 * smoothstep(0.75, 1.0, vt)
			return lerpf(0.0006, 0.0026 * fade, smoothstep(0.0, 0.65, ut)),
		_garment, band_mat)
	lapel_r.set_meta("garment_slot", "top")

	# 3. Left-over lapel (\ follows solid -X V-wall to V apex (0.0, 1.752), then crosses solid closed chest to waist sash)
	var lapel_l := Helpers.build_snapped_uv_patch(clothes_root, "CrossCollarLeft", 24, 4,
		func(ut: float, vt: float) -> Vector3:
			var v_ang: float
			var py: float
			if vt <= 0.40:
				var ft := vt / 0.40
				v_ang = lerpf(-0.42, 0.0, ft)
				py = _cross_collar_cut_y(v_ang)
			else:
				var bt := (vt - 0.40) / 0.60
				v_ang = lerpf(0.0, 0.32, bt)
				py = lerpf(1.752, 1.380, bt)
			var width := lerpf(0.060, 0.088, vt)
			var a := v_ang + lerpf(-width, 0.0, ut)
			return Helpers.torso_point_at(a, py, 0.006),
		func(ut: float, _vt: float) -> float:
			return lerpf(0.0006, 0.0030, smoothstep(0.0, 0.65, ut)),
		_garment, band_mat, true)
	lapel_l.set_meta("garment_slot", "top")


func _build_fitted_cuffs() -> void:
	super()
	Helpers.sculpt_garment_neckline(_garment, Callable(self, "_cross_collar_cut_y"), 1.62, 1.93, 0.0045)
	_build_cross_collar_lapels()
	Helpers.slim_covered_limbs(arms, "ArmMannequin", 0.26, 0.24, 0.032)
	var cuff := clothes_root.get_node_or_null("CuffBinding") as MeshInstance3D
	if cuff != null:
		cuff.material_override = _material(COLOR_ROBE_TRIM)


func _build_volume_head() -> void:
	super()
	for node in head_rig.find_children("Eyebrow*", "MeshInstance3D", true, false):
		node.material_override = _material(COLOR_HAIR)

	# Subtle warm smile crease lines beside mouth
	for side in [-1.0, 1.0]:
		var crease := _tube(head_rig, "SmileCrease", PackedVector3Array([
			_face_point(side * 0.090, 0.145, 0.004),
			_face_point(side * 0.104, 0.110, 0.004)]), 0.0032, COLOR_CREASE)
		crease.set_meta("expression_feature", "cheek_crease")

	# Center-parted black hair below turban + sculpted slate-navy folded turban cap
	for ch in hair_root.get_children():
		ch.free()
	hair_style = 0
	_hair_cap(COLOR_HAIR)
	for node in hair_root.find_children("LowBun*", "MeshInstance3D", true, false):
		node.free()
	hair_style = 1

	# Gentle nape tucked hair volume behind ears/neck
	_ellipsoid(hair_root, "NapeHairBun", Vector3(0.0, 0.07, -0.185), Vector3(0.24, 0.12, 0.14), COLOR_HAIR)

	# Sculpted Multi-Tier Cloth-Wrapped Turban (layers integrated as thick stepped pleats, ZERO floating tubes!)
	var turban_mat := Helpers.textured_material(_make_turban_texture())
	var t_rings := 28
	var t_cols := 56
	var t_verts := PackedVector3Array()
	var t_uvs := PackedVector2Array()
	var t_inds := PackedInt32Array()
	for r in t_rings + 1:
		var vt := float(r) / t_rings # 0 = bottom brow rim, 1 = top crown cap
		for c in t_cols + 1:
			var ut := float(c) / t_cols
			var angle := TAU * ut
			var cos_a := cos(angle)
			var sin_a := sin(angle)
			var front := smoothstep(0.0, 1.0, maxf(cos_a, 0.0))
			# Two slightly crossed wrap tier seams defining layered cloth overlap thickness
			var seam1 := 0.34 + 0.055 * front * sin_a
			var seam2 := 0.63 - 0.050 * front * sin_a
			# Outward layered cloth thickness bulge on each tier + crisp tucked crease inside seams
			var bulge1 := sin(clampf(vt / maxf(seam1, 0.05), 0.0, 1.0) * PI) * 0.009 if vt <= seam1 else 0.0
			var bulge2 := sin(clampf((vt - seam1) / maxf(seam2 - seam1, 0.05), 0.0, 1.0) * PI) * 0.012 if (vt > seam1 and vt <= seam2) else 0.0
			var bulge3 := sin(clampf((vt - seam2) / maxf(0.84 - seam2, 0.05), 0.0, 1.0) * PI) * 0.010 if (vt > seam2 and vt <= 0.84) else 0.0
			var crease := -0.011 * exp(-pow((vt - seam1) / 0.026, 2.0)) - 0.011 * exp(-pow((vt - seam2) / 0.026, 2.0))
			var tier_step := 0.007 * smoothstep(seam1 - 0.02, seam1 + 0.04, vt) + 0.008 * smoothstep(seam2 - 0.02, seam2 + 0.04, vt)
			var fold_relief := bulge1 + bulge2 + bulge3 + crease + tier_step
			# Soft upward boat-crown flare matching p1 wrapped headcloth
			var rx := lerpf(0.312, 0.376, sin(vt * PI * 0.62)) + fold_relief
			if vt > 0.74:
				rx = lerpf(rx, 0.05, smoothstep(0.74, 1.0, vt))
			var rz := lerpf(0.318, 0.304, pow(vt, 0.8)) + fold_relief * 0.82
			if vt > 0.74:
				rz = lerpf(rz, 0.04, smoothstep(0.74, 1.0, vt))
			var brow_y := lerpf(0.355, 0.415, front * (1.0 - absf(sin_a)))
			var top_y := 0.642 + 0.016 * (1.0 - absf(cos_a))
			var y := lerpf(brow_y, top_y, vt)
			t_verts.append(Vector3(sin_a * rx, y, cos_a * rz - 0.020))
			# Encode crease distance smoothly into UV so texture shadow aligns exactly with 3D tuck grooves
			var d_crease := minf(absf(vt - seam1), absf(vt - seam2))
			t_uvs.append(Vector2(ut, clampf(d_crease / 0.055, 0.0, 1.0)))
	for r in t_rings:
		for c in t_cols:
			var a := r * (t_cols + 1) + c
			var b := a + t_cols + 1
			t_inds.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var t_normals := Helpers.compute_smooth_normals(t_verts, t_inds)
	Helpers._commit_uv_mesh(hair_root, "SlateNavyTurban", t_verts, t_normals, t_uvs, t_inds, turban_mat)

	# Single Large Gold Hoop Earring on Viewer's RIGHT Ear (+X, matching p1!)
	Helpers.build_ring(head_rig, "GoldHoopEarring", Vector3(0.285, 0.155, 0.020),
		0.052, 0.011, Vector3(90.0, 22.0, 0.0), COLOR_GOLD, 28, 10)


func _make_cross_collar_texture() -> Image:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var vt := float(py) / float(h - 1)
		for px in w:
			var ut := float(px) / float(w - 1)
			var col := COLOR_ROBE
			if ut > 0.87 and vt >= 0.90:
				col = COLOR_ROBE_TRIM
			var grain := 1.0 + 0.018 * sin(float(px) * 0.5) * cos(float(py) * 0.6)
			img.set_pixel(px, py, col * Color(grain, grain, grain, 1.0))
	return img


func _make_turban_texture() -> Image:
	var w := 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		# vt=0 is inside recessed wrap tuck crease, vt=1 is outer folded cloth tier surface
		var vt := float(py) / float(h - 1)
		var fold_shade := smoothstep(0.0, 0.48, vt)
		var col := COLOR_TURBAN_DARK.lerp(COLOR_TURBAN_BASE, fold_shade)
		for px in w:
			var weave := 1.0 + 0.02 * sin(float(px) * 0.6)
			img.set_pixel(px, py, col * Color(weave, weave, weave, 1.0))
	return img


func _make_embroidered_apron_texture() -> Image:
	var w := 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var vt := float(py) / float(h - 1)
		for px in w:
			var ut := float(px) / float(w - 1)
			var col := COLOR_SASH
			# Solid Burgundy outer left/right/bottom border frame matching p1!
			if ut < 0.095 or ut > 0.905 or vt > 0.875:
				col = COLOR_BURGUNDY
			else:
				# Inner horizontal geometric bands: diamond & zigzag motifs
				var band_y := fposmod(vt * 4.5, 1.0)
				var u_cell := fposmod(ut * 6.5, 1.0)
				var d := absf(u_cell - 0.5) + absf(band_y - 0.5)
				if band_y < 0.12 or band_y > 0.88:
					col = COLOR_BURGUNDY
				elif absf(d - 0.38) < 0.085:
					col = COLOR_EMBROIDERY_MINT
				elif d < 0.15:
					col = COLOR_BURGUNDY
			img.set_pixel(px, py, col)
	return img


func _build_appearance() -> void:
	super()
	Helpers.disable_cloth_contact(body_rig, [
		"SkinnedMeshes/garment/TailoredShell",
		"SkinnedMeshes/torso/CrossCollarNeckRim",
		"SkinnedMeshes/torso/CrossCollarRight",
		"SkinnedMeshes/torso/CrossCollarLeft",
	])
