class_name GranddaughterDoll
extends "res://scripts/game_body_doll.gd"
## Protagonist 2: Granddaughter (孙女) adapted cleanly onto GameBodyDoll medium body (p2 style).

const Helpers = preload("res://scripts/characters/p1_character_helpers.gd")

const COLOR_SKIN := Color("f3cfb9")
const COLOR_HAIR := Color("4e3020")
const COLOR_HAIR_DARK := Color("361e12")
const COLOR_EYE := Color("201d22")
const COLOR_CLIP_TEAL := Color("349ca8")
const COLOR_CLIP_MINT := Color("82dce0")
const COLOR_CLIP_DARK := Color("1f6873")
const COLOR_SWEATER_CREAM := Color("dfd4c0")
const COLOR_YOKE_BLUE := Color("b0c2da")
const COLOR_ZIGZAG_BLUE := Color("5a769a")
const COLOR_YOKE_WHITE := Color("eef0ec")
const COLOR_TICK_DARK := Color("7d8694")
const COLOR_SKIRT_GREEN := Color("1d4b34")
const COLOR_SOCK_WHITE := Color("f0eee9")
const COLOR_SHOE_NAVY := Color("242937")
const COLOR_TOTE_WHITE := Color("f1efe9")
const COLOR_TOTE_BOTTOM := Color("dfdcd3")


func _init() -> void:
	outfit_style = 2
	hair_style = 0
	shoe_style = 1
	skin_index = 0
	custom_skin_color = COLOR_SKIN
	custom_hair_color = COLOR_HAIR
	custom_eye_color = COLOR_EYE


func _covers_legs() -> bool:
	return true


func _keep_covered_legs() -> bool:
	return false


func _costume_palette() -> Array:
	return [COLOR_SWEATER_CREAM, COLOR_YOKE_BLUE, COLOR_YOKE_WHITE]


func _build_volume_body() -> void:
	super()
	# Clean base dress accessories (waistcoat, buttons, waist ribbon, hem ribbons, flower)
	for child in clothes_root.get_children():
		var cname := str(child.name)
		if cname.begins_with("OpenWaistcoat") or cname.begins_with("Button") or cname == "WaistRibbon" or child.get_meta("material_role", "") == "flower":
			child.free()
	if is_instance_valid(skirt_root):
		for child in skirt_root.get_children():
			child.free()
	else:
		skirt_root = Node3D.new()
		skirt_root.name = "SkirtAndTrims"
		clothes_root.add_child(skirt_root)

	# 1. Nordic Fair Isle Sweater over outfit_style=2 body shell
	var sweater_tex := _make_nordic_sweater_texture()
	_garment.material_override = Helpers.textured_material(sweater_tex)
	Helpers.apply_torus_or_shell_uvs(_garment, 1.24, 1.93, 1.82, 1.245)

	# Soft cream ribbed waist hem band hugging skirt top naturally
	var hem_band := _lathe(clothes_root, "SweaterRibbedHem", [
		Vector3(1.245, 0.284, 0.208),
		Vector3(1.275, 0.282, 0.206),
		Vector3(1.305, 0.275, 0.200),
	], COLOR_SWEATER_CREAM, 40, 0.0, false)
	hem_band.material_override = Helpers.textured_material(_make_hem_rib_texture())

	# Remove generic flat StandingCollar hoop; sculpted contoured crew-neck binding builds after BodyFit
	var collar := clothes_root.get_node_or_null("StandingCollar") as MeshInstance3D
	if collar != null:
		collar.free()

	# 2. Forest Pine-Green Pleated A-Line Skirt (y = 1.26 down to knee hem y = 0.72)
	var skirt_rings := [
		Vector3(0.72, 0.375, 0.285),
		Vector3(0.84, 0.348, 0.266),
		Vector3(0.98, 0.315, 0.240),
		Vector3(1.13, 0.272, 0.204),
		Vector3(1.26, 0.238, 0.176),
	]
	_skirt = _lathe(skirt_root, "LongSkirt", skirt_rings, COLOR_SKIRT_GREEN, 64, 0.036, false)
	_skirt.material_override = _skirt.material_override.duplicate()
	_skirt.material_override.set_shader_parameter("backface_shade", 0.28)
	_skirt.set_meta("garment_slot", "bottom")

	# 3. White Fitted Crew Socks extending smoothly DOWN into Mary-Jane Shoe opening
	for leg in legs:
		var sx := 0.018 if leg.name == "LegLeft" else -0.018
		var sock := _lathe(leg, "WhiteSock", [
			Vector3(-1.03, 0.068, 0.070),
			Vector3(-0.95, 0.076, 0.078),
			Vector3(-0.85, 0.084, 0.084),
			Vector3(-0.74, 0.092, 0.092),
			Vector3(-0.68, 0.096, 0.096),
			Vector3(-0.674, 0.087, 0.087),
		], COLOR_SOCK_WHITE, 28, 0.0, false,
		[sx, sx, sx * 0.96, sx * 0.94, sx * 0.94, sx * 0.94],
		[0.042, 0.040, 0.030, 0.022, 0.020, 0.020])
		sock.set_meta("is_underbody", true)

		var shoe := leg.get_node_or_null("Shoe")
		if shoe != null:
			for part in shoe.find_children("*", "MeshInstance3D", true, false):
				var pname := str(part.name)
				if pname == "WhiteSockInstep":
					part.material_override = _material(COLOR_SOCK_WHITE)
				elif pname == "InstepStrap":
					part.material_override = _material(COLOR_SHOE_NAVY)
				elif pname == "ShoeUpper":
					part.material_override = _material(COLOR_SHOE_NAVY)
				elif pname == "FlatSole":
					part.material_override = _material(COLOR_SHOE_NAVY.darkened(0.28))

	# 4. White Canvas Tote Bag Straps & Pouch slung on Left Shoulder / Viewer's RIGHT (+X)
	_build_tote_bag()


func _crew_cut_y(ang: float, _p := Vector3.ZERO) -> float:
	# Smooth C1 oval crew-neck U curve: high around neck root (1.918), soft round front dip (1.862)
	var front_scoop := pow(clampf(cos(ang), 0.0, 1.0), 1.55)
	return lerpf(1.918, 1.862, front_scoop)


func _build_crew_neck_binding() -> void:
	# Rounded rib crew-neck collar seated directly on sculpted yoke rim and hugging neck >= +2.5mm cleanly
	var cols := 48
	var rows := 8
	var rib_mat := Helpers.flat_material(COLOR_YOKE_BLUE, 0.14)
	rib_mat.set_shader_parameter("cloth_contact_enabled", false)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var inds := PackedInt32Array()
	for r in rows + 1:
		var vt := float(r) / rows # 0 = buried flush into sweater yoke, 1 = inner top lip hugging neck >= 2.5mm
		var ang_prof := vt * PI
		var offset_r := 0.0055 * sin(ang_prof) + 0.0025
		var height_shift := lerpf(-0.010, 0.008, vt)
		for c in cols + 1:
			var ut := float(c) / cols
			var ang := TAU * ut - PI
			var cy := _crew_cut_y(ang) + height_shift
			verts.append(Helpers.torso_point_at(ang, cy, offset_r))
			uvs.append(Vector2(ut, vt))
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + cols + 1
			inds.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var normals := Helpers.compute_smooth_normals(verts, inds)
	var crew := Helpers._commit_uv_mesh(clothes_root, "CrewNeckBinding", verts, normals, uvs, inds, rib_mat)
	crew.set_meta("garment_slot", "top")


func _tuck_sweater_under_skirt(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null or not (mesh_node.mesh is ArrayMesh):
		return
	var am := mesh_node.mesh as ArrayMesh
	var arrays := am.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array = mesh_node.get_meta("garment_arm_weights", PackedFloat32Array())
	for i in verts.size():
		var v := verts[i]
		var arm_w := absf(weights[i]) if i < weights.size() else 0.0
		if v.y < 1.30 and arm_w < 0.28:
			v.x *= 0.80
			v.z *= 0.80
			v.y = maxf(v.y, 1.255)
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var new_am := ArrayMesh.new()
	new_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_node.mesh = new_am
	if not weights.is_empty():
		mesh_node.set_meta("garment_arm_weights", weights)


func _strip_batwing_sleeves(mesh_node: MeshInstance3D) -> void:
	## Removes wide stiff TailoredShell batwing sleeves cleanly at armhole seams so fitted tubular sweater sleeves take over.
	if mesh_node == null or not (mesh_node.mesh is ArrayMesh):
		return
	var am := mesh_node.mesh as ArrayMesh
	var arrays := am.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var weights: PackedFloat32Array = mesh_node.get_meta("garment_arm_weights", PackedFloat32Array())
	if weights.size() != verts.size():
		return
	for i in verts.size():
		var aw := absf(weights[i])
		if aw >= 0.12:
			var t := smoothstep(0.12, 0.44, aw)
			verts[i].x = lerpf(verts[i].x, signf(weights[i]) * 0.174, t * 0.96)
			verts[i].z *= lerpf(1.0, 0.82, t)
	var kept_indices := PackedInt32Array()
	for f in range(0, indices.size(), 3):
		var a := indices[f]
		var b := indices[f + 1]
		var c := indices[f + 2]
		var max_w := maxf(absf(weights[a]), maxf(absf(weights[b]), absf(weights[c])))
		if max_w < 0.44:
			kept_indices.append_array(PackedInt32Array([a, b, c]))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = kept_indices
	arrays[Mesh.ARRAY_NORMAL] = Helpers.compute_smooth_normals(verts, kept_indices)
	var out_mesh := ArrayMesh.new()
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_node.mesh = out_mesh
	mesh_node.set_meta("garment_arm_weights", weights)
	mesh_node.set_meta("garment_component", "continuous_shell")


func _build_cozy_sleeves(mat: Material) -> void:
	## Builds gently draped rounded Fair Isle knit sweater sleeves + fitted ribbed cuffs hugging the true arm path.
	# Each stop: [y, abs_cx, cz, rx, rz, abs_arm_weight]
	const STOPS := [
		[1.780, 0.158, 0.015, 0.056, 0.062, 0.15],
		[1.700, 0.184, 0.015, 0.062, 0.066, 0.50],
		[1.600, 0.212, 0.014, 0.066, 0.068, 0.88],
		[1.500, 0.236, 0.015, 0.068, 0.070, 0.98],
		[1.400, 0.256, 0.018, 0.069, 0.072, 1.00],
		[1.345, 0.266, 0.020, 0.064, 0.066, 1.00],
		[1.315, 0.270, 0.021, 0.062, 0.064, 1.00],
		[1.310, 0.270, 0.021, 0.036, 0.036, 1.00],
	]
	var cols := 28
	var rings := STOPS.size() - 1
	for side: float in [-1.0, 1.0]:
		var sname := "SweaterSleeveL" if side < 0.0 else "SweaterSleeveR"
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		var arm_weights := PackedFloat32Array()
		for r in STOPS.size():
			var st: Array = STOPS[r]
			var y: float = st[0]
			var cx: float = side * st[1]
			var cz: float = st[2]
			var rx: float = st[3]
			var rz: float = st[4]
			var aw: float = side * st[5]
			var sv := clampf((1.80 - y) / (1.80 - 1.315), 0.0, 1.0)
			for c in cols + 1:
				var ut := float(c) / cols
				var angle := TAU * ut
				var sin_a := sin(angle)
				var cos_a := cos(angle)
				verts.append(Vector3(cx + sin_a * rx, y, cz + cos_a * rz))
				var phi := absf(atan2(sin_a, cos_a)) / PI
				uvs.append(Vector2(lerpf(0.875, 0.995, phi), sv))
				arm_weights.append(aw)
		for r in rings:
			for c in cols:
				var a := r * (cols + 1) + c
				var b := a + cols + 1
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
		var normals := Helpers.compute_smooth_normals(verts, indices)
		var sleeve_mi := Helpers._commit_uv_mesh(clothes_root, sname, verts, normals, uvs, indices, mat)
		sleeve_mi.set_meta("garment_arm_weights", arm_weights)
		sleeve_mi.set_meta("garment_component", "continuous_shell")


func _slim_legs_under_socks() -> void:
	for leg in legs:
		var m := leg.get_node_or_null("LegMannequin") as MeshInstance3D
		if m == null or not (m.mesh is ArrayMesh):
			continue
		var sx := 0.018 if leg.name == "LegLeft" else -0.018
		var am := m.mesh as ArrayMesh
		var arrays := am.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var v := verts[i]
			if v.y < -0.68:
				var depth := smoothstep(-0.68, -0.76, v.y)
				var cz := lerpf(0.020, 0.042, clampf((-0.68 - v.y) / 0.35, 0.0, 1.0))
				v.x = sx + (v.x - sx) * lerpf(1.0, 0.78, depth)
				v.z = cz + (v.z - cz) * lerpf(1.0, 0.78, depth)
				verts[i] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		var out_am := ArrayMesh.new()
		out_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.mesh = out_am


func _build_fitted_cuffs() -> void:
	super()
	# Run AFTER AcceptedBodyFit.apply() and BEFORE DollRig.bind()!
	Helpers.sculpt_garment_neckline(_garment, Callable(self, "_crew_cut_y"), 1.62, 1.93, 0.004)
	_build_crew_neck_binding()
	_tuck_sweater_under_skirt(_garment)
	_strip_batwing_sleeves(_garment)
	_build_cozy_sleeves(_garment.material_override)
	# Keep lower palm/hand below y=1.190 untouched while slimming forearm & wrist inside knitted sleeve
	Helpers.slim_covered_limbs(arms, "ArmMannequin", 0.32, 0.44)
	_slim_legs_under_socks()
	var cuff := clothes_root.get_node_or_null("CuffBinding") as MeshInstance3D
	if cuff != null:
		cuff.visible = false


func _build_tote_bag() -> void:
	# Slung cleanly from viewer's RIGHT shoulder (+X) down front & back to canvas pouch beside right hip
	var strap_pts := PackedVector3Array([
		Vector3(0.32, 1.15, 0.06),
		Vector3(0.255, 1.38, 0.178),
		Vector3(0.220, 1.62, 0.176),
		Vector3(0.174, 1.80, 0.125),
		Vector3(0.146, 1.864, 0.018),
		Vector3(0.174, 1.80, -0.105),
		Vector3(0.235, 1.56, -0.148),
		Vector3(0.31, 1.22, -0.10),
		Vector3(0.34, 1.13, -0.02),
	])
	var strap := _tube(clothes_root, "ToteShoulderStrap", strap_pts, 0.020, COLOR_TOTE_WHITE)
	strap.set_meta("garment_slot", "outer")


func _prepare_body_for_rig() -> void:
	super()
	# Add soft rounded tote pouch AFTER BodyFit so pouch volume stays crisp beside right hip
	var pouch_rings := [
		Vector3(0.84, 0.025, 0.045),
		Vector3(0.87, 0.062, 0.115),
		Vector3(0.95, 0.072, 0.145),
		Vector3(1.06, 0.066, 0.148),
		Vector3(1.16, 0.056, 0.140),
	]
	var pouch_x := [0.355, 0.355, 0.360, 0.355, 0.345]
	var pouch_z := [0.020, 0.020, 0.020, 0.020, 0.020]
	var pouch := _lathe(clothes_root, "CanvasTotePouch", pouch_rings, COLOR_TOTE_WHITE, 28, 0.0, true, pouch_x, pouch_z)
	pouch.set_meta("attachment_bone", "Hips")


func _build_volume_head() -> void:
	super()
	for node in head_rig.find_children("Eyebrow*", "MeshInstance3D", true, false):
		node.material_override = _material(COLOR_HAIR_DARK)

	for ch in hair_root.get_children():
		ch.free()

	# 1. FULL 100% Scalp & Back Skull Coverage Dome (ZERO BALD SPOTS from any angle!)
	hair_style = 0
	_hair_cap(COLOR_HAIR)
	for node in hair_root.find_children("LowBun*", "MeshInstance3D", true, false):
		node.free()
	for node in hair_root.find_children("HairPart*", "MeshInstance3D", true, false):
		node.free()

	# Additional rear nape dome cap ensuring thick seamless back silhouette down to nape
	var back_cap := Helpers.build_uv_patch(hair_root, "BackSkullVolume", 10, 22, func(ut: float, vt: float) -> Vector3:
		var ang := lerpf(PI * 0.42, PI * 1.58, ut) # sweeping across left ear -> back -> right ear
		var phi := lerpf(0.22, 2.38, vt)
		var r_x := 0.284 + 0.008 * sin(vt * PI)
		var r_y := 0.312
		var r_z := 0.306 + 0.010 * sin(vt * PI)
		return Vector3(sin(phi) * sin(ang) * r_x, 0.288 + cos(phi) * r_y, sin(phi) * cos(ang) * r_z - 0.012)
	, Helpers.flat_material(COLOR_HAIR))
	back_cap.set_meta("hair_layer", true)

	# 2. Side-Swept Spherical-Contour Front Bangs (flush onto dome, ZERO upper horns!)
	# Left smaller lobe (viewer's left)
	Helpers.build_uv_patch(hair_root, "BangsLeftSwoop", 8, 12, func(ut: float, vt: float) -> Vector3:
		var ang := lerpf(-0.22, -1.48, ut)
		var phi_top := lerpf(0.18, 0.70, pow(ut, 1.25))
		var phi_bot := lerpf(0.84, 1.48, smoothstep(0.0, 0.85, ut))
		var phi := lerpf(phi_top, phi_bot, vt)
		var bulge := 0.010 * sin(vt * PI) * sin(clampf(ut * 1.1, 0.1, 1.0) * PI * 0.8)
		var rx := 0.284 + bulge
		var ry := 0.308 + bulge * 0.6
		var rz := 0.302 + bulge
		return Vector3(sin(phi) * sin(ang) * rx, 0.290 + cos(phi) * ry, sin(phi) * cos(ang) * rz)
	, Helpers.flat_material(COLOR_HAIR))

	# Right wider sweeping lobe (viewer's right, framing right cheek cleanly)
	Helpers.build_uv_patch(hair_root, "BangsRightSwoop", 8, 16, func(ut: float, vt: float) -> Vector3:
		var ang := lerpf(-0.22, 1.52, ut)
		var phi_top := lerpf(0.18, 0.72, pow(ut, 1.25))
		var phi_bot := lerpf(0.82, 1.46, smoothstep(0.05, 0.90, ut))
		var phi := lerpf(phi_top, phi_bot, vt)
		var bulge := 0.012 * sin(vt * PI)
		var rx := 0.285 + bulge
		var ry := 0.310 + bulge * 0.6
		var rz := 0.304 + bulge
		return Vector3(sin(phi) * sin(ang) * rx, 0.290 + cos(phi) * ry, sin(phi) * cos(ang) * rz)
	, Helpers.flat_material(COLOR_HAIR))

	# Clean diagonal hairline part line
	var part_pts := PackedVector3Array()
	for i in 10:
		var t := float(i) / 9.0
		var phi := lerpf(0.86, 0.16, t)
		var ang := lerpf(-0.22, -0.05, t)
		part_pts.append(Vector3(sin(phi) * sin(ang) * 0.290, 0.290 + cos(phi) * 0.316, sin(phi) * cos(ang) * 0.310))
	_tube(hair_root, "SidePartLine", part_pts, 0.0035, COLOR_HAIR_DARK)

	# 3. Voluminous Bouncy Side Ponytail on Viewer's RIGHT (+X)
	var pony_tie_pos := Vector3(0.280, 0.365, -0.055)
	Helpers.build_ring(hair_root, "SidePonyTie", pony_tie_pos, 0.054, 0.018, Vector3(12.0, -24.0, -56.0), COLOR_CLIP_DARK, 24, 10)

	# Sculpted plush swept curve tube matching the voluminous bouncy silhouette in p1 & 2D preview
	var tail_rings := 18
	var tail_cols := 24
	var t_verts := PackedVector3Array()
	var t_inds := PackedInt32Array()
	for i in tail_rings + 1:
		var t := float(i) / tail_rings
		# Spline sweeping out from tie (+0.28, 0.365, -0.055) to full belly (+0.43, 0.16, -0.08) then flick tip (+0.47, -0.06, -0.04)
		var cx := 0.275 + 0.155 * sin(t * PI * 0.62) + 0.045 * pow(t, 1.5)
		var cy := 0.365 - 0.435 * pow(t, 1.08)
		var cz := -0.055 - 0.045 * sin(t * PI) + 0.025 * pow(t, 2.0)
		var rad := lerpf(0.052, 0.122, sin(pow(t, 0.65) * PI * 0.78))
		if t > 0.78:
			rad = lerpf(rad, 0.016, smoothstep(0.78, 1.0, t))
		var rx := rad * 0.92
		var ry := rad * 0.88
		var rz := rad * 1.04
		# Local tangent frame
		var t_next := clampf(t + 0.03, 0.0, 1.0)
		var nx := 0.275 + 0.155 * sin(t_next * PI * 0.62) + 0.045 * pow(t_next, 1.5)
		var ny := 0.365 - 0.435 * pow(t_next, 1.08)
		var nz := -0.055 - 0.045 * sin(t_next * PI) + 0.025 * pow(t_next, 2.0)
		var tang := Vector3(nx - cx, ny - cy, nz - cz).normalized()
		if tang.length_squared() < 0.01:
			tang = Vector3.DOWN
		var right_v := tang.cross(Vector3.FORWARD).normalized()
		if right_v.length_squared() < 0.01:
			right_v = Vector3.RIGHT
		var fwd_v := right_v.cross(tang).normalized()
		for c in tail_cols + 1:
			var a := TAU * float(c) / tail_cols
			var wave := 1.0 + 0.04 * cos(a * 5.0)
			var offset := right_v * (cos(a) * rx * wave) + fwd_v * (sin(a) * rz * wave)
			t_verts.append(Vector3(cx, cy, cz) + offset)
	for i in tail_rings:
		for c in tail_cols:
			var a := i * (tail_cols + 1) + c
			var b := a + tail_cols + 1
			t_inds.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var t_normals := Helpers.compute_smooth_normals(t_verts, t_inds)
	var t_arrays := []
	t_arrays.resize(Mesh.ARRAY_MAX)
	t_arrays[Mesh.ARRAY_VERTEX] = t_verts
	t_arrays[Mesh.ARRAY_NORMAL] = t_normals
	t_arrays[Mesh.ARRAY_INDEX] = t_inds
	var pony_am := ArrayMesh.new()
	pony_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, t_arrays)
	var pony_inst := MeshInstance3D.new()
	pony_inst.name = "VoluminousSidePonytail"
	pony_inst.mesh = pony_am
	pony_inst.material_override = _material(COLOR_HAIR)
	hair_root.add_child(pony_inst)

	# 4. Angled Teal Striped Rectangular Barrette Clip pressed FLUSH on Right Forehead Hair Surface
	var clip_root := Node3D.new()
	clip_root.name = "StripedBarrette"
	# Exact point sitting cleanly embedded onto BangsRightSwoop right brow curve (ZERO floating gap!)
	clip_root.position = Vector3(0.162, 0.400, 0.238)
	clip_root.rotation_degrees = Vector3(-16.0, 32.0, -38.0)
	hair_root.add_child(clip_root)

	var bar_mat := Helpers.textured_material(_make_barrette_texture())
	var bw := 0.048 # half-width
	var bh := 0.019 # half-height
	var bd := 0.008 # half-depth
	var box := BoxMesh.new()
	box.size = Vector3(bw * 2.0, bh * 2.0, bd * 2.0)
	var b_am := ArrayMesh.new()
	b_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	var bar_mesh := MeshInstance3D.new()
	bar_mesh.name = "BarrettePlate"
	bar_mesh.mesh = b_am
	bar_mesh.material_override = bar_mat
	clip_root.add_child(bar_mesh)


func _make_hem_rib_texture() -> Image:
	var w := 256
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var vt := float(py) / float(h - 1)
		for px in w:
			var col := COLOR_SWEATER_CREAM.darkened(0.02)
			if vt > 0.15 and vt < 0.85 and (px % 6) < 2:
				col = COLOR_TICK_DARK
			img.set_pixel(px, py, col)
	return img


func _make_nordic_sweater_texture() -> Image:
	var w := 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var vt := float(py) / float(h - 1) # 0 = neckline/shoulder top, 1 = waist/wrist hem
		for px in w:
			var ut := float(px) / float(w - 1)
			var is_sleeve := ut > 0.87
			var col := COLOR_SWEATER_CREAM
			if is_sleeve:
				# Continuous circular Fair Isle yoke wraps smoothly onto upper sleeve cap + cream ribbed wrist cuff
				var s_u := clampf((ut - 0.875) / 0.12, 0.0, 1.0)
				var zig_s := absf(fposmod(s_u * 4.0, 1.0) * 2.0 - 1.0)
				var chev_s := 0.175 + 0.036 * zig_s
				var ds := vt - chev_s
				if vt < chev_s - 0.025:
					col = COLOR_YOKE_BLUE
				elif absf(ds) <= 0.014:
					col = COLOR_ZIGZAG_BLUE
				elif ds > 0.014 and ds <= 0.034:
					col = COLOR_YOKE_WHITE
				elif ds > 0.034 and ds <= 0.048:
					col = COLOR_ZIGZAG_BLUE
				elif vt > 0.88:
					col = COLOR_TICK_DARK.lerp(COLOR_SWEATER_CREAM, 0.65) if (px % 5) < 2 else COLOR_SWEATER_CREAM.darkened(0.03)
			else:
				# Circular Fair Isle yoke across torso front/sides/back (symmetric u in [0 .. 0.85])
				var zig := absf(fposmod(ut * 11.5, 1.0) * 2.0 - 1.0)
				var chevron_y := 0.205 + 0.046 * zig
				var d := vt - chevron_y
				if vt < 0.045:
					col = COLOR_YOKE_BLUE.darkened(0.05) # knit crew neck trim continuation
				elif vt < chevron_y - 0.038:
					# Subtle small Fair Isle star/dot flecks near mid-yoke
					var dot_u := fposmod(ut * 18.0, 1.0)
					if vt > 0.105 and vt < 0.145 and absf(dot_u - 0.5) < 0.22:
						col = COLOR_YOKE_WHITE
					else:
						col = COLOR_YOKE_BLUE
				elif absf(d) <= 0.017:
					col = COLOR_ZIGZAG_BLUE
				elif d > 0.017 and d <= 0.040:
					col = COLOR_YOKE_WHITE
				elif d > 0.040 and d <= 0.056:
					col = COLOR_ZIGZAG_BLUE
				elif vt >= 0.88 and vt <= 0.96:
					col = COLOR_TICK_DARK if (px % 6) < 2 else COLOR_SWEATER_CREAM.darkened(0.03)
			var grain := 1.0 + 0.02 * sin(float(px) * 0.45) * cos(float(py) * 0.65)
			img.set_pixel(px, py, col * Color(grain, grain, grain, 1.0))
	return img


func _make_barrette_texture() -> Image:
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		for px in w:
			var diag := fposmod(float(px) * 0.14 + float(py) * 0.12, 1.0)
			var col := COLOR_CLIP_TEAL
			if diag < 0.26:
				col = COLOR_CLIP_MINT
			elif diag > 0.72 and diag < 0.84:
				col = COLOR_CLIP_DARK
			img.set_pixel(px, py, col)
	return img


func _build_appearance() -> void:
	super()
	Helpers.disable_cloth_contact(body_rig, [
		"SkinnedMeshes/garment/SweaterSleeveL",
		"SkinnedMeshes/garment/SweaterSleeveR",
		"SkinnedMeshes/torso/CrewNeckBinding",
	])
