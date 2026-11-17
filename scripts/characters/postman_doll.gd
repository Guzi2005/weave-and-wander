class_name PostmanDoll
extends "res://scripts/game_body_doll.gd"
## Character 4: Postman / Courier (邮差) adapted faithfully onto GameBodyDoll medium body (p2 style).

const Helpers = preload("res://scripts/characters/p1_character_helpers.gd")

const COLOR_SKIN := Color("e3baa2")
const COLOR_HAIR := Color("5d4433")
const COLOR_HAIR_DARK := Color("433023")
const COLOR_EYE := Color("201d22")
const COLOR_CAP := Color("6e794e")
const COLOR_CAP_DARK := Color("555f3b")
const COLOR_COAT := Color("737f52")
const COLOR_COAT_TRIM := Color("58623d")
const COLOR_SHIRT := Color("dcd5c2")
const COLOR_TIE := Color("2a3441")
const COLOR_TROUSER := Color("5c6543")
const COLOR_BOOT := Color("302c2b")
const COLOR_SOLE := Color("211e1d")
const COLOR_SATCHEL := Color("643e29")
const COLOR_SATCHEL_DARK := Color("4d2e1d")
const COLOR_BRASS := Color("9a7740")
const COLOR_ENVELOPE := Color("ede8df")
const COLOR_ENVELOPE_LINE := Color("c6beb0")
const COLOR_WAX := Color("962420")


func _init() -> void:
	outfit_style = 2
	hair_style = 1
	shoe_style = 0
	skin_index = 1
	custom_skin_color = COLOR_SKIN
	custom_hair_color = COLOR_HAIR
	custom_eye_color = COLOR_EYE


func _covers_legs() -> bool:
	return false


func _keep_covered_legs() -> bool:
	return true


func _costume_palette() -> Array:
	return [COLOR_COAT, COLOR_COAT_TRIM, COLOR_SHIRT]


func _build_volume_body() -> void:
	super()
	# Remove generic outfit_style=2 waistcoat, standing collar & buttons
	for child in clothes_root.get_children():
		var cname := str(child.name)
		if cname.begins_with("OpenWaistcoat") or cname.begins_with("Button") or cname == "StandingCollar":
			child.free()

	if not is_instance_valid(skirt_root):
		skirt_root = Node3D.new()
		skirt_root.name = "SkirtAndTrims"
		clothes_root.add_child(skirt_root)
	else:
		for ch in skirt_root.get_children():
			ch.free()

	# 1. Olive Coat Torso over Cream Collared Shirt & Dark Navy Tie (NO deferred rebuild)
	_garment.material_override = Helpers.textured_material(_make_coat_torso_texture())
	Helpers.apply_torus_or_shell_uvs(_garment, 1.13, 1.93, 1.83, 1.21)

	# Collar, lapels, and necktie are constructed & snapped post-BodyFit in _build_fitted_cuffs().
	var old_collar := clothes_root.get_node_or_null("ShirtCollarNeck") as MeshInstance3D
	if old_collar != null:
		old_collar.free()

	# 2. Matching Moss-Olive Straight Trousers & Chunky Dark Boots
	for leg in legs:
		var old_tr := leg.get_node_or_null("Trouser")
		if old_tr != null:
			old_tr.free()
		_lathe(leg, "Trouser", [
			Vector3(-0.92, 0.108, 0.118),
			Vector3(-0.80, 0.116, 0.124),
			Vector3(-0.62, 0.124, 0.132),
			Vector3(-0.48, 0.132, 0.140),
			Vector3(-0.36, 0.140, 0.148),
			Vector3(-0.22, 0.146, 0.154),
			Vector3(0.05, 0.134, 0.142),
		], COLOR_TROUSER, 20, 0.0, false)
		for shoe in leg.find_children("*", "MeshInstance3D", true, false):
			var sname := str(shoe.name)
			if sname == "ShoeUpper":
				shoe.material_override = _material(COLOR_BOOT)
			elif sname == "FlatSole":
				shoe.material_override = _material(COLOR_SOLE)

	# 3. Closed-Waist Olive Trench Coat Tails (y = 0.56..1.31) tucked cleanly inside waist belt
	_build_split_trench_tails()
	_lathe(clothes_root, "CoatWaistBelt", [
		Vector3(1.245, 0.312, 0.236),
		Vector3(1.335, 0.308, 0.232),
	], COLOR_COAT_TRIM, 40, 0.0, false)

	# 4. Seamless Crossbody Brown Leather Satchel Strap is built post-BodyFit in _build_fitted_cuffs()
	#    so chest & shoulder points hug the fitted coat torso cleanly without shoulder horn or side kink.


func _tuck_coat_seams(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null or not (mesh_node.mesh is ArrayMesh):
		return
	var am := mesh_node.mesh as ArrayMesh
	var arrays := am.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		if v.y < 1.380 and absf(v.x) < 0.290:
			var waist_t := smoothstep(1.380, 1.240, v.y)
			v.x *= lerpf(1.0, 0.88, waist_t)
			v.z *= lerpf(1.0, 0.88, waist_t)
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var weights: PackedFloat32Array = mesh_node.get_meta("garment_arm_weights", PackedFloat32Array())
	var new_am := ArrayMesh.new()
	new_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_node.mesh = new_am
	if not weights.is_empty():
		mesh_node.set_meta("garment_arm_weights", weights)


func _build_split_trench_tails() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in 15:
		var t := row / 14.0
		var y := lerpf(0.56, 1.31, t)
		var rx := lerpf(0.358, 0.288, t)
		var rz := lerpf(0.278, 0.212, t)
		# Closed at waist (y = 1.25..1.31) & subtly vented toward knee hem
		var gap := 0.20 * (1.0 - smoothstep(0.70, 1.22, y))
		for col in 49:
			var angle := lerpf(gap, TAU - gap, col / 48.0)
			verts.append(Vector3(sin(angle) * rx, y, cos(angle) * rz))
			normals.append(Vector3(sin(angle) / rx, 0.12 / rx, cos(angle) / rz).normalized())
	for row in 14:
		for col in 48:
			var a := row * 49 + col
			indices.append_array(PackedInt32Array([a, a + 49, a + 1, a + 1, a + 49, a + 50]))
	_skirt = _mesh(skirt_root, "PostalCoatSkirt", verts, normals, indices, COLOR_COAT)
	_skirt.material_override = _skirt.material_override.duplicate()
	_skirt.material_override.set_shader_parameter("backface_shade", 0.22)
	_skirt.set_meta("skin_profile", "split_coat")


func _postman_throat_cut_y(ang: float, _p := Vector3.ZERO) -> float:
	# Tight around neck root on back & sides (1.918), sloping gently at front throat (1.882)
	var front_t := clampf(absf(atan2(sin(ang), cos(ang))) / 0.62, 0.0, 1.0)
	return lerpf(1.882, 1.918, pow(front_t, 1.15))


func _make_trench_lapel_texture() -> Image:
	var w := 64
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var face_col := COLOR_COAT.lightened(0.07)
	var edge_col := COLOR_COAT_TRIM
	for py in h:
		for px in w:
			var ut := float(px) / float(w - 1) # 0 = outer stitched coat seam, 1 = crisp inner lapel fold
			var col := COLOR_COAT.lerp(face_col, smoothstep(0.08, 0.38, ut))
			if ut > 0.86:
				col = col.lerp(edge_col, smoothstep(0.86, 1.0, ut) * 0.45)
			img.set_pixel(px, py, col)
	return img


func _make_shirt_collar_texture() -> Image:
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var face_col := COLOR_SHIRT.lightened(0.06)
	var edge_col := COLOR_SHIRT.darkened(0.28)
	for py in h:
		var vt := float(py) / float(h - 1) # 0 = neck fold, 1 = bottom crisp folded collar point
		for px in w:
			var ut := float(px) / float(w - 1)
			var edge_t := maxf(smoothstep(0.70, 0.96, vt), smoothstep(0.76, 0.98, ut) * smoothstep(0.18, 0.70, vt))
			img.set_pixel(px, py, face_col.lerp(edge_col, edge_t))
	return img


func _build_coat_collar_and_tie() -> void:
	## Builds shirt collar points, tie knot/blade, flush coat back collar & notched lapels matching p1.
	var shirt_col_mat := Helpers.textured_material(_make_shirt_collar_texture(), Color.WHITE, 0.14)
	shirt_col_mat.set_shader_parameter("cloth_contact_enabled", false)
	var tie_mat := Helpers.flat_material(COLOR_TIE)
	tie_mat.set_shader_parameter("cloth_contact_enabled", false)
	var knot_mat := Helpers.flat_material(COLOR_TIE.darkened(0.08))
	knot_mat.set_shader_parameter("cloth_contact_enabled", false)
	var lapel_mat := Helpers.textured_material(_make_trench_lapel_texture(), Color.WHITE, 0.14)
	lapel_mat.set_shader_parameter("cloth_contact_enabled", false)

	# 1. Flush olive coat back & side collar snapped strictly on _garment neck root (zero saucer ring!)
	var back_collar := Helpers.build_snapped_uv_patch(clothes_root, "CoatBackCollar", 24, 4,
		func(ut: float, vt: float) -> Vector3:
			var ang := lerpf(0.41, TAU - 0.41, vt)
			var top_y := _postman_throat_cut_y(ang)
			var py := lerpf(top_y - 0.020, top_y - 0.001, ut)
			return Helpers.torso_point_at(ang, py, lerpf(0.004, 0.0025, ut)),
		func(ut: float, _vt: float) -> float:
			return lerpf(0.0024, 0.0034, ut),
		_garment, lapel_mat, true)
	back_collar.set_meta("garment_slot", "top")

	# 2. Pointed Cream Dress Shirt Collar Flaps tucking cleanly behind olive CoatLapel & meeting NecktieKnot
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side < 0.0 else "R"
		var _scol := Helpers.build_snapped_uv_patch(clothes_root, "ShirtCollarFold" + sname, 10, 8,
			func(ut: float, vt: float) -> Vector3:
				var ang := side * lerpf(0.42, 0.02 * (1.0 - vt), ut)
				var top_y := _postman_throat_cut_y(ang) - 0.002
				var bot_y := top_y - lerpf(0.020, 0.054, pow(ut, 1.10))
				var py := lerpf(top_y, bot_y, vt)
				return Helpers.torso_point_at(ang, py, 0.004),
			func(ut: float, _vt: float) -> float:
				return lerpf(0.0022, 0.0032, smoothstep(0.0, 0.65, ut)),
			_garment, shirt_col_mat, side < 0.0)
		_scol.set_meta("garment_slot", "top")

	# 3. Dark Charcoal Necktie Knot & Blade cleanly proud over cream shirt V up to throat collar
	var knot := Helpers.build_snapped_uv_patch(clothes_root, "NecktieKnot", 6, 4,
		func(ut: float, vt: float) -> Vector3:
			var hw_ang := lerpf(0.095, 0.062, vt)
			var ang := (ut - 0.5) * 2.0 * hw_ang
			var py := lerpf(1.880, 1.816, vt)
			return Helpers.torso_point_at(ang, py, 0.008),
		func(ut: float, vt: float) -> float:
			var crown := sin(ut * PI) * sin(vt * PI)
			return 0.0052 + 0.0024 * crown,
		_garment, knot_mat, true)
	knot.set_meta("garment_slot", "top")

	var tie_blade := Helpers.build_snapped_uv_patch(clothes_root, "DarkNecktie", 10, 4,
		func(ut: float, vt: float) -> Vector3:
			var hw_ang := lerpf(0.055, 0.095, sin(vt * PI * 0.80))
			if vt > 0.85:
				hw_ang *= (1.0 - smoothstep(0.85, 1.0, vt))
			var ang := (ut - 0.5) * 2.0 * hw_ang
			var py := lerpf(1.816, 1.495, vt)
			return Helpers.torso_point_at(ang, py, 0.007),
		func(_ut: float, _vt: float) -> float:
			return 0.0046,
		_garment, tie_mat, true)
	tie_blade.set_meta("garment_slot", "top")

	# 4. Wide Notched Olive Trench Coat Lapels smoothly merging into collar shoulder
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side < 0.0 else "R"
		var _lapel := Helpers.build_snapped_uv_patch(clothes_root, "CoatLapel" + sname, 16, 8,
			func(ut: float, vt: float) -> Vector3:
				var py := lerpf(1.908, 1.385, vt)
				var ang_in := side * lerpf(0.39, 0.045, pow(vt, 0.88))
				var notch := 0.085 * exp(-pow((vt - 0.22) / 0.10, 2.0))
				var ang_out := side * (lerpf(0.56, 0.25, pow(vt, 0.82)) + notch)
				var ang := lerpf(ang_out, ang_in, ut)
				return Helpers.torso_point_at(ang, py, 0.007),
			func(ut: float, vt: float) -> float:
				var bot_fade := 1.0 - 0.18 * smoothstep(0.80, 1.0, vt)
				return lerpf(0.0026, 0.0046 * bot_fade, smoothstep(0.0, 0.55, ut)),
			_garment, lapel_mat, side < 0.0)
		_lapel.set_meta("garment_slot", "top")


func _build_snapped_satchel_strap() -> void:
	## Snaps Postman's crossbody leather strap cleanly onto post-BodyFit _garment torso/shoulder
	## and outside CoatWaistBelt so it never submerges in the coat chest or juts off the shoulder.
	var s_arr := (_garment.mesh as ArrayMesh).surface_get_arrays(0)
	var s_verts: PackedVector3Array = s_arr[Mesh.ARRAY_VERTEX]
	var s_norms: PackedVector3Array = s_arr[Mesh.ARRAY_NORMAL]
	var s_inds: PackedInt32Array = s_arr[Mesh.ARRAY_INDEX]
	var s_weights: PackedFloat32Array = _garment.get_meta("garment_arm_weights", PackedFloat32Array())
	var torso_faces := PackedInt32Array()
	for f in range(0, s_inds.size(), 3):
		if not s_weights.is_empty():
			var mw := maxf(absf(s_weights[s_inds[f]]), maxf(absf(s_weights[s_inds[f + 1]]), absf(s_weights[s_inds[f + 2]])))
			if mw > 0.25:
				continue
		torso_faces.append(f)

	var basic_garment: Script = preload("res://components/basic_garment.gd")
	var guide_pts := [
		Vector3(0.352, 1.155, 0.025),
		Vector3(0.312, 1.215, 0.132),
		Vector3(0.242, 1.310, 0.205),
		Vector3(0.165, 1.435, 0.225),
		Vector3(0.055, 1.565, 0.235),
		Vector3(-0.042, 1.695, 0.205),
		Vector3(-0.068, 1.760, 0.175),
		Vector3(-0.088, 1.815, 0.135),
		Vector3(-0.104, 1.882, 0.058),
		Vector3(-0.108, 1.898, 0.018),
		Vector3(-0.100, 1.878, -0.042),
		Vector3(-0.082, 1.805, -0.115),
		Vector3(-0.055, 1.735, -0.155),
		Vector3(-0.025, 1.665, -0.185),
		Vector3(0.095, 1.465, -0.215),
		Vector3(0.218, 1.320, -0.195),
		Vector3(0.302, 1.225, -0.135),
		Vector3(0.342, 1.160, -0.068),
		Vector3(0.352, 1.155, 0.025),
	]
	var snapped := PackedVector3Array()
	for pt in guide_pts:
		var p: Vector3 = pt
		if p.y >= 1.38 and not torso_faces.is_empty():
			var best_d := INF
			var best_face := torso_faces[0]
			var best_hit := p
			for f in torso_faces:
				var hit: Vector3 = basic_garment._closest_on_triangle(p, s_verts[s_inds[f]], s_verts[s_inds[f + 1]], s_verts[s_inds[f + 2]])
				var d := p.distance_squared_to(hit)
				if d < best_d:
					best_d = d
					best_face = f
					best_hit = hit
			var bary := Geometry3D.get_triangle_barycentric_coords(best_hit, s_verts[s_inds[best_face]], s_verts[s_inds[best_face + 1]], s_verts[s_inds[best_face + 2]])
			var n := (s_norms[s_inds[best_face]] * bary.x + s_norms[s_inds[best_face + 1]] * bary.y + s_norms[s_inds[best_face + 2]] * bary.z).normalized()
			if n.length_squared() < 0.001:
				n = Vector3(p.x, 0.0, p.z).normalized()
			var off := lerpf(0.0085, 0.0025, smoothstep(1.80, 1.90, p.y))
			p = best_hit + n * off
		elif p.y >= 1.24 and p.y < 1.38:
			var rx := 0.314
			var rz := 0.238
			var nr := sqrt((p.x / rx) * (p.x / rx) + (p.z / rz) * (p.z / rz))
			if nr < 1.02 and nr > 0.001:
				p.x = (p.x / nr) * 1.02
				p.z = (p.z / nr) * 1.02
		snapped.append(p)
	var crossbody_strap := _tube(clothes_root, "SatchelCrossbodyStrap", snapped, 0.012, COLOR_SATCHEL_DARK)
	crossbody_strap.set_meta("garment_slot", "outer")


func _build_fitted_cuffs() -> void:
	super()
	# Run AFTER AcceptedBodyFit.apply() and BEFORE DollRig.bind()!
	_tuck_coat_seams(_garment)
	Helpers.sculpt_garment_neckline(_garment, Callable(self, "_postman_throat_cut_y"), 1.62, 1.93, 0.003)
	_build_coat_collar_and_tie()
	_build_snapped_satchel_strap()
	Helpers.slim_covered_limbs(arms, "ArmMannequin", 0.28, 0.22, 0.032)
	Helpers.slim_covered_limbs(legs, "LegMannequin", 0.12, 0.26, 0.0)
	var cuff := clothes_root.get_node_or_null("CuffBinding") as MeshInstance3D
	if cuff != null:
		cuff.material_override = _material(COLOR_COAT_TRIM)


func _prepare_body_for_rig() -> void:
	super()
	var seat := clothes_root.get_node_or_null("TrouserSeat")
	if seat != null:
		seat.material_override = _material(COLOR_TROUSER)
	# Add rigid Satchel Box & Held Wax-Sealed Envelope AFTER BodyFit
	# 1. Slimmer, Taller Leather Satchel on Viewer's RIGHT Hip (+X), tilted cleanly along flared trench skirt!
	var satchel := Node3D.new()
	satchel.name = "PostmanSatchel"
	clothes_root.add_child(satchel)
	var tilt_deg := 8.5
	var tilt_rad := deg_to_rad(tilt_deg)
	var pivot := Vector3(0.380, 1.005, 0.025)
	var rot_off := func(dx: float, dy: float, dz: float) -> Vector3:
		return pivot + Vector3(dx * cos(tilt_rad) - dy * sin(tilt_rad), dx * sin(tilt_rad) + dy * cos(tilt_rad), dz)
	var bag_body := Helpers.build_box_mesh(satchel, "SatchelBody", Vector3(0.105, 0.365, 0.275),
		rot_off.call(0.0, 0.0, 0.0), COLOR_SATCHEL, Vector3(0.0, 0.0, tilt_deg))
	bag_body.set_meta("attachment_bone", "Hips")
	var flap := Helpers.build_box_mesh(satchel, "SatchelFlap", Vector3(0.118, 0.165, 0.286),
		rot_off.call(0.004, 0.102, 0.0), COLOR_SATCHEL_DARK, Vector3(0.0, 0.0, tilt_deg))
	flap.set_meta("attachment_bone", "Hips")
	var strap_tab := Helpers.build_box_mesh(satchel, "SatchelTab", Vector3(0.026, 0.120, 0.056),
		rot_off.call(0.062, 0.042, 0.0), COLOR_SATCHEL_DARK.darkened(0.15), Vector3(0.0, 0.0, tilt_deg))
	strap_tab.set_meta("attachment_bone", "Hips")
	var clasp := Helpers.build_box_mesh(satchel, "SatchelBrassClasp", Vector3(0.022, 0.040, 0.036),
		rot_off.call(0.068, 0.008, 0.0), COLOR_BRASS, Vector3(0.0, 0.0, tilt_deg))
	clasp.set_meta("attachment_bone", "Hips")

	# 2. Wax-Sealed Envelope held in Viewer's LEFT Hand ("HandL")
	var env_root := Node3D.new()
	env_root.name = "WaxEnvelopeGroup"
	clothes_root.add_child(env_root)
	var env_card := Helpers.build_box_mesh(env_root, "WaxEnvelope", Vector3(0.22, 0.155, 0.016),
		Vector3(-0.355, 1.01, 0.095), COLOR_ENVELOPE, Vector3(6.0, 10.0, 24.0))
	env_card.set_meta("attachment_bone", "HandL")
	var seal := Helpers.build_cylinder_mesh(env_root, "WaxSeal", 0.025, 0.025, 0.012,
		Vector3(-0.355, 1.005, 0.107), COLOR_WAX, Vector3(90.0, 10.0, 24.0), 18)
	seal.set_meta("attachment_bone", "HandL")


func _build_volume_head() -> void:
	super()
	for node in head_rig.find_children("Eyebrow*", "MeshInstance3D", true, false):
		node.material_override = _material(COLOR_HAIR_DARK)

	for ch in hair_root.get_children():
		ch.free()

	# 1. Warm Brown Fluffy Pageboy Bob Hair (crown recessed cleanly inside cap so ZERO hair pokes out!)
	hair_style = 0
	_hair_cap(COLOR_HAIR)
	for node in hair_root.find_children("LowBun*", "MeshInstance3D", true, false):
		node.free()
	for node in hair_root.find_children("HairPart*", "MeshInstance3D", true, false):
		node.visible = false
	var hcap := hair_root.get_node_or_null("HairCap") as MeshInstance3D
	if hcap != null and hcap.mesh is ArrayMesh:
		var hc_arr := (hcap.mesh as ArrayMesh).surface_get_arrays(0)
		var hc_v: PackedVector3Array = hc_arr[Mesh.ARRAY_VERTEX]
		for i in hc_v.size():
			var hv := hc_v[i]
			if hv.y > 0.325:
				var shrink_w := smoothstep(0.325, 0.425, hv.y)
				var s := lerpf(1.0, 0.72, shrink_w)
				hv.x *= s
				hv.z = -0.015 + (hv.z + 0.015) * s
				hv.y = minf(hv.y, 0.56)
				hc_v[i] = hv
		hc_arr[Mesh.ARRAY_VERTEX] = hc_v
		var hc_out := ArrayMesh.new()
		hc_out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hc_arr)
		hcap.mesh = hc_out
	hair_style = 1

	# Pageboy bob flare skirt hugging back & cheeks cleanly below cap brim (top tucked neatly inside CapBand)
	var bob := Helpers.build_uv_patch(hair_root, "PageboyBobSides", 10, 26, func(ut: float, vt: float) -> Vector3:
		var ang := lerpf(1.15, TAU - 1.15, ut)
		var y := lerpf(0.395, 0.055, vt)
		var flare := 1.0 + 0.17 * smoothstep(0.12, 0.72, vt)
		var rx := lerpf(0.275, 0.305, smoothstep(0.0, 0.25, vt)) * flare
		var rz := lerpf(0.282, 0.312, smoothstep(0.0, 0.25, vt)) * (1.0 + 0.06 * sin(vt * PI * 0.7))
		if vt > 0.78:
			rx *= lerpf(1.0, 0.88, smoothstep(0.78, 1.0, vt))
		return Vector3(sin(ang) * rx, y, cos(ang) * rz - 0.025)
	, Helpers.flat_material(COLOR_HAIR, 0.18))

	# Front parted eyebrow-clearing bangs tucked completely INSIDE CapBand top rim and draping onto forehead
	Helpers.build_uv_patch(hair_root, "CourierCapBangs", 5, 16, func(ut: float, vt: float) -> Vector3:
		var ang := lerpf(-0.98, 0.98, ut)
		var y := lerpf(0.405, 0.335 - 0.014 * absf(sin(ut * PI * 3.0)), vt)
		var rx := lerpf(0.268, 0.288, vt)
		var rz := lerpf(0.285, 0.308, vt)
		return Vector3(sin(ang) * rx, y, cos(ang) * rz - 0.004)
	, Helpers.flat_material(COLOR_HAIR))

	# 2. Olive-Green Peaked Newsboy / Flat Cap (mounted in HeadwearSlot, fully enclosing upper hair dome)
	var hat := Node3D.new()
	hat.name = "HeadwearSlot"
	head_rig.add_child(hat)
	hat.rotation.x = -0.02

	var crown := _lathe(hat, "FlatCapCrown", [
		Vector3(0.425, 0.332, 0.352),
		Vector3(0.510, 0.382, 0.374),
		Vector3(0.600, 0.365, 0.346),
		Vector3(0.680, 0.242, 0.230),
		Vector3(0.715, 0.065, 0.065),
	], COLOR_CAP, 40)
	var band := _lathe(hat, "CapBand", [
		Vector3(0.370, 0.322, 0.344),
		Vector3(0.435, 0.336, 0.356),
	], COLOR_CAP_DARK, 40, 0.0, false)
	for part in [crown, band]:
		part.position.z = -0.016
	# Curved broad cap visor projecting cleanly over bangs
	var visor := _ellipsoid(hat, "BroadVisor", Vector3(0.0, 0.398, 0.258), Vector3(0.318, 0.025, 0.195), COLOR_CAP_DARK)
	visor.rotation.x = 0.07


func _make_coat_torso_texture() -> Image:
	var w := 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var vt := float(py) / float(h - 1)
		for px in w:
			var ut := float(px) / float(w - 1)
			var col := COLOR_COAT
			if ut > 0.87:
				# Sleeves: Moss olive + darker folded cuff near wrist
				if vt > 0.80:
					col = COLOR_COAT_TRIM
			else:
				# Torso center front white shirt V behind 3D DarkNecktie (matches wide CoatLapel opening)
				if vt < 0.50:
					var shirt_half := lerpf(0.108, 0.010, vt / 0.50)
					if ut < shirt_half:
						col = COLOR_SHIRT
			img.set_pixel(px, py, col)
	return img


func _build_appearance() -> void:
	super()
	Helpers.disable_cloth_contact(body_rig, [
		"SkinnedMeshes/garment/TailoredShell",
		"SkinnedMeshes/torso/CoatBackCollar",
		"SkinnedMeshes/torso/ShirtCollarFoldL",
		"SkinnedMeshes/torso/ShirtCollarFoldR",
		"SkinnedMeshes/torso/NecktieKnot",
		"SkinnedMeshes/torso/DarkNecktie",
		"SkinnedMeshes/torso/CoatLapelL",
		"SkinnedMeshes/torso/CoatLapelR",
		"SkinnedMeshes/torso/SatchelCrossbodyStrap",
	])
