extends RefCounted

const COSTUME_SHADER: Shader = preload("res://shaders/doll_costume.gdshader")


static func textured_material(image: Image, pigment := Color.WHITE, backface_shade := 0.0, relief := 0.0) -> ShaderMaterial:
	var tex := ImageTexture.create_from_image(image)
	var mat := ShaderMaterial.new()
	mat.shader = COSTUME_SHADER
	mat.set_shader_parameter("pigment", pigment)
	mat.set_shader_parameter("pigment_map", tex)
	mat.set_shader_parameter("use_pigment_map", true)
	mat.set_shader_parameter("use_vertex_color", false)
	mat.set_shader_parameter("relief_strength", relief)
	mat.set_shader_parameter("backface_shade", backface_shade)
	return mat


static func flat_material(color: Color, backface_shade := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = COSTUME_SHADER
	mat.set_shader_parameter("pigment", color)
	mat.set_shader_parameter("use_pigment_map", false)
	mat.set_shader_parameter("use_vertex_color", false)
	mat.set_shader_parameter("backface_shade", backface_shade)
	return mat


static func apply_torus_or_shell_uvs(mesh_instance: MeshInstance3D, y_min: float, y_max: float, arm_y_top := 1.83, arm_y_bot := 1.195) -> void:
	## Assigns continuous symmetric UVs [0..0.85] for torso (u=0 front, u=0.425 side, u=0.85 back)
	## and [0.88..1.0] for sleeves (based on garment_arm_weights) with zero wrap seam.
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array = mesh_instance.get_meta("garment_arm_weights", PackedFloat32Array())
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	var dy := maxf(y_max - y_min, 0.001)
	var arm_dy := maxf(arm_y_top - arm_y_bot, 0.001)
	for i in verts.size():
		var p := verts[i]
		var arm_w := absf(weights[i]) if i < weights.size() else 0.0
		if arm_w >= 0.45:
			var sv := clampf((arm_y_top - p.y) / arm_dy, 0.0, 1.0)
			uvs[i] = Vector2(0.94, sv)
		else:
			var ang := absf(atan2(p.x, p.z)) # 0 at center front, PI at center back
			var u := clampf(ang / PI, 0.0, 1.0) * 0.85
			var v := 1.0 - clampf((p.y - y_min) / dy, 0.0, 1.0)
			uvs[i] = Vector2(u, v)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var out_mesh := ArrayMesh.new()
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = out_mesh
	if not weights.is_empty():
		mesh_instance.set_meta("garment_arm_weights", weights)
	if mesh_instance.has_meta("torso_index_count"):
		mesh_instance.set_meta("torso_index_count", mesh_instance.get_meta("torso_index_count"))


static func torso_section_at_y(y: float) -> Vector3:
	## Exact half-extents & Z-center Vector3(rx, rz, cz) of AcceptedBodyV20 MannequinTorso.
	const STOPS := [
		[1.45, 0.185, 0.136, 0.012],
		[1.58, 0.195, 0.142, 0.022],
		[1.70, 0.198, 0.138, 0.024],
		[1.78, 0.190, 0.130, 0.020],
		[1.84, 0.152, 0.114, 0.016],
		[1.90, 0.116, 0.096, 0.018],
		[1.96, 0.086, 0.080, 0.024],
		[2.02, 0.078, 0.076, 0.028],
		[2.09, 0.076, 0.074, 0.030],
	]
	if y <= STOPS[0][0]:
		return Vector3(STOPS[0][1], STOPS[0][2], STOPS[0][3])
	for i in range(STOPS.size() - 1):
		var a: Array = STOPS[i]
		var b: Array = STOPS[i + 1]
		if y <= b[0]:
			var t := clampf((y - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)
			return Vector3(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t))
	var last: Array = STOPS[STOPS.size() - 1]
	return Vector3(last[1], last[2], last[3])


static func neck_radii_at_y(y: float) -> Vector2:
	var sec := torso_section_at_y(y)
	return Vector2(sec.x, sec.y)


static func torso_point_at(ang: float, y: float, clearance := 0.004) -> Vector3:
	var sec := torso_section_at_y(y)
	return Vector3(sin(ang) * (sec.x + clearance), y, sec.z + cos(ang) * (sec.y + clearance))


static func sculpt_garment_neckline(mesh_instance: MeshInstance3D, cut_y_fn: Callable,
		y_anchor := 1.60, y_orig_top := 1.93, rim_ease := 0.003, max_arm_w := 0.28) -> void:
	## Shapes upper torso of TailoredShell into an organic neckline following MannequinTorso
	## (centered on sec.z), hugging neck root cleanly 360 deg without leaving a flared funnel gap.
	if mesh_instance == null or not (mesh_instance.mesh is ArrayMesh):
		return
	var am := mesh_instance.mesh as ArrayMesh
	var arrays := am.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty():
		return
	var weights: PackedFloat32Array = mesh_instance.get_meta("garment_arm_weights", PackedFloat32Array())
	for i in verts.size():
		var p := verts[i]
		var arm_w := absf(weights[i]) if i < weights.size() else 0.0
		if arm_w >= max_arm_w or p.y <= y_anchor:
			continue
		var sec_orig := torso_section_at_y(p.y)
		var dz_orig := p.z - sec_orig.z
		if is_zero_approx(p.x) and is_zero_approx(dz_orig):
			continue
		var t := clampf((p.y - y_anchor) / maxf(y_orig_top - y_anchor, 0.001), 0.0, 1.0)
		var arm_blend := 1.0 - smoothstep(0.06, max_arm_w, arm_w)
		# Above t=0.78 (neck collar slope above armholes), allow medial shoulder vertices to follow neck contour cleanly
		if t > 0.78:
			arm_blend = maxf(arm_blend, smoothstep(0.78, 0.94, t) * (1.0 - smoothstep(0.18, max_arm_w, arm_w)))
		var ang := atan2(p.x, dz_orig)
		var target_y: float = float(cut_y_fn.call(ang, p))
		var new_y := lerpf(y_anchor, target_y, pow(t, 0.85))
		p.y = lerpf(p.y, new_y, arm_blend)

		var sec := torso_section_at_y(p.y)
		var hug_t := smoothstep(0.46, 0.90, t) * arm_blend
		if hug_t > 0.001:
			var clear := lerpf(rim_ease + 0.014, rim_ease, smoothstep(0.46, 0.92, t))
			var target_x := sin(ang) * (sec.x + clear)
			var target_z := sec.z + cos(ang) * (sec.y + clear)
			p.x = lerpf(p.x, target_x, hug_t)
			p.z = lerpf(p.z, target_z, hug_t)

		# Guarantee sculpted chest/shoulder triangle chords never dip inside MannequinTorso skin
		var min_rx := sec.x + 0.0042
		var min_rz := sec.y + 0.0042
		var dx := p.x
		var dz := p.z - sec.z
		var norm_r := sqrt((dx / min_rx) * (dx / min_rx) + (dz / min_rz) * (dz / min_rz))
		if norm_r < 1.0 and norm_r > 0.0001:
			p.x = dx / norm_r
			p.z = sec.z + dz / norm_r
		verts[i] = p
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = compute_smooth_normals(verts, indices)
	var out_mesh := ArrayMesh.new()
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = out_mesh
	if not weights.is_empty():
		mesh_instance.set_meta("garment_arm_weights", weights)
	mesh_instance.set_meta("garment_component", "continuous_shell")


static func snap_patch_to_shell(patch_mesh: MeshInstance3D, shell_mesh: MeshInstance3D,
		offsets: PackedFloat32Array = PackedFloat32Array(), default_offset := 0.0025,
		bind_skin := true, max_arm_w := 0.25) -> void:
	## Projects every vertex of patch_mesh onto shell_mesh's torso triangles, shifts along surface
	## normal by offset so lapels/collars hug cloth flush with zero floating gap, and binds weights.
	if patch_mesh == null or shell_mesh == null:
		return
	if not (patch_mesh.mesh is ArrayMesh) or not (shell_mesh.mesh is ArrayMesh):
		return
	var s_arr := (shell_mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var s_verts: PackedVector3Array = s_arr[Mesh.ARRAY_VERTEX]
	var s_norms: PackedVector3Array = s_arr[Mesh.ARRAY_NORMAL]
	var s_inds: PackedInt32Array = s_arr[Mesh.ARRAY_INDEX]
	var s_weights: PackedFloat32Array = shell_mesh.get_meta("garment_arm_weights", PackedFloat32Array())
	var torso_faces := PackedInt32Array()
	for f in range(0, s_inds.size(), 3):
		var a := s_inds[f]
		var b := s_inds[f + 1]
		var c := s_inds[f + 2]
		if not s_weights.is_empty():
			var mw := maxf(absf(s_weights[a]), maxf(absf(s_weights[b]), absf(s_weights[c])))
			if mw > max_arm_w:
				continue
		torso_faces.append(f)
	if torso_faces.is_empty():
		return

	var basic_garment: Script = preload("res://components/basic_garment.gd")
	var p_arr := (patch_mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var p_verts: PackedVector3Array = p_arr[Mesh.ARRAY_VERTEX]
	var p_inds: PackedInt32Array = p_arr[Mesh.ARRAY_INDEX]
	var bind_tris := PackedInt32Array()
	var bind_bary := PackedVector3Array()
	var bind_src := PackedInt32Array()

	for i in p_verts.size():
		var p := p_verts[i]
		var best_d := INF
		var best_face := 0
		var best_hit := p
		for f in torso_faces:
			var a := s_verts[s_inds[f]]
			var b := s_verts[s_inds[f + 1]]
			var c := s_verts[s_inds[f + 2]]
			var hit: Vector3 = basic_garment._closest_on_triangle(p, a, b, c)
			var d := p.distance_squared_to(hit)
			if d < best_d:
				best_d = d
				best_face = f
				best_hit = hit
		var tri := PackedInt32Array([s_inds[best_face], s_inds[best_face + 1], s_inds[best_face + 2]])
		var bary := Geometry3D.get_triangle_barycentric_coords(best_hit, s_verts[tri[0]], s_verts[tri[1]], s_verts[tri[2]])
		var n := (s_norms[tri[0]] * bary.x + s_norms[tri[1]] * bary.y + s_norms[tri[2]] * bary.z).normalized()
		if n.length_squared() < 0.001:
			n = Vector3(p.x, 0.0, p.z).normalized()
		var off := offsets[i] if i < offsets.size() else default_offset
		var snapped := best_hit + n * off
		# Never allow snapped collar/lapel vertices to clip inside MannequinTorso skin
		var sec := torso_section_at_y(snapped.y)
		var min_rx := sec.x + maxf(off, 0.0025)
		var min_rz := sec.y + maxf(off, 0.0025)
		var dx := snapped.x
		var dz := snapped.z - sec.z
		var nr := sqrt((dx / min_rx) * (dx / min_rx) + (dz / min_rz) * (dz / min_rz))
		if nr < 1.0 and nr > 0.0001:
			snapped.x = dx / nr
			snapped.z = sec.z + dz / nr
		p_verts[i] = snapped
		bind_tris.append_array(tri)
		bind_bary.append(bary)
		bind_src.append(0)

	p_arr[Mesh.ARRAY_VERTEX] = p_verts
	p_arr[Mesh.ARRAY_NORMAL] = compute_smooth_normals(p_verts, p_inds)
	var out_am := ArrayMesh.new()
	out_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p_arr)
	patch_mesh.mesh = out_am
	if bind_skin:
		patch_mesh.set_meta("skin_layer_sources", PackedStringArray([str(patch_mesh.get_path_to(shell_mesh))]))
		patch_mesh.set_meta("skin_layer_triangles", bind_tris)
		patch_mesh.set_meta("skin_layer_barycentric", bind_bary)
		patch_mesh.set_meta("skin_layer_source_index", bind_src)


static func build_snapped_uv_patch(parent: Node3D, label: String, rows: int, cols: int,
		point_fn: Callable, offset_fn: Callable, shell_mesh: MeshInstance3D,
		mat: Material, reverse_winding := false, bind_skin := true) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var offsets := PackedFloat32Array()
	for r in rows + 1:
		var vt := float(r) / rows
		for c in cols + 1:
			var ut := float(c) / cols
			verts.append(point_fn.call(ut, vt))
			offsets.append(float(offset_fn.call(ut, vt)))
			uvs.append(Vector2(ut, vt))
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + cols + 1
			if reverse_winding:
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
			else:
				indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var normals := compute_smooth_normals(verts, indices)
	var mi := _commit_uv_mesh(parent, label, verts, normals, uvs, indices, mat)
	snap_patch_to_shell(mi, shell_mesh, offsets, 0.0025, bind_skin)
	return mi


static func disable_cloth_contact(body_rig: Node3D, node_paths: Array) -> void:
	## Clears post-bind cloth_contact / cloth_outer_layer / cloth_surface_lift overrides on tailored
	## collars, lapels, and fitted sleeves so sculpted contours stay flush instead of inflating off body.
	if body_rig == null:
		return
	for node_path in node_paths:
		var mi := body_rig.get_node_or_null(str(node_path)) as MeshInstance3D
		if mi != null and mi.material_override is ShaderMaterial:
			var mat := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			mat.set_shader_parameter("cloth_contact_enabled", false)
			mat.set_shader_parameter("cloth_contact_arms", false)
			mat.set_shader_parameter("cloth_outer_layer", false)
			mat.set_shader_parameter("cloth_surface_lift", 0.0)
			mi.material_override = mat


static func build_uv_lathe(parent: Node3D, label: String, rings: Array, mat: Material,
		segments := 48, folds := 0.0, caps := false, x_offsets: Array = [], z_offsets: Array = [],
		symmetric_u := true) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in rings.size():
		var ring: Vector3 = rings[row]
		var previous: Vector3 = rings[maxi(row - 1, 0)]
		var next: Vector3 = rings[mini(row + 1, rings.size() - 1)]
		var center_x: float = x_offsets[row] if not x_offsets.is_empty() else 0.0
		var center_z: float = z_offsets[row] if not z_offsets.is_empty() else 0.0
		var v := 1.0 - float(row) / maxf(float(rings.size() - 1), 1.0)
		for column in segments + 1:
			var t_col := float(column) / segments
			var angle := TAU * t_col
			var modulation := 1.0 + folds * cos(angle * 16.0)
			vertices.append(Vector3(center_x + sin(angle) * ring.y * modulation, ring.x, center_z + cos(angle) * ring.z * modulation))
			var slope := -((next.y - previous.y) + (next.z - previous.z)) * 0.5 / maxf(next.x - previous.x, 0.001)
			var normal := Vector3(sin(angle) / maxf(ring.y, 0.01), slope / maxf(ring.y, 0.01), cos(angle) / maxf(ring.z, 0.01))
			if not x_offsets.is_empty() or not z_offsets.is_empty():
				var dx: float = (x_offsets[mini(row + 1, rings.size() - 1)] - x_offsets[maxi(row - 1, 0)]) if not x_offsets.is_empty() else 0.0
				var dz: float = (z_offsets[mini(row + 1, rings.size() - 1)] - z_offsets[maxi(row - 1, 0)]) if not z_offsets.is_empty() else 0.0
				normal.y = -(normal.x * (dx + sin(angle) * (next.y - previous.y)) + normal.z * (dz + cos(angle) * (next.z - previous.z))) / maxf(next.x - previous.x, 0.001)
			normals.append(normal.normalized())
			var u := (1.0 - absf(t_col * 2.0 - 1.0)) if symmetric_u else t_col
			# Flip so t_col=0 (front, sin=0,cos=1) gives u=0 and PI gives u=1 cleanly:
			if symmetric_u:
				u = absf(atan2(sin(angle), cos(angle))) / PI
			uvs.append(Vector2(u, v))
	for row in rings.size() - 1:
		for column in segments:
			var a := row * (segments + 1) + column
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	if caps:
		for end in [0, rings.size() - 1]:
			var center_index := vertices.size()
			var ring: Vector3 = rings[end]
			var cap_x: float = x_offsets[end] if not x_offsets.is_empty() else 0.0
			var cap_z: float = z_offsets[end] if not z_offsets.is_empty() else 0.0
			vertices.append(Vector3(cap_x, ring.x, cap_z))
			normals.append(Vector3.DOWN if end == 0 else Vector3.UP)
			uvs.append(Vector2(0.5, 1.0 if end == 0 else 0.0))
			for column in segments:
				var a: int = end * (segments + 1) + column
				if end == 0:
					indices.append_array(PackedInt32Array([center_index, a, a + 1]))
				else:
					indices.append_array(PackedInt32Array([center_index, a + 1, a]))
	return _commit_uv_mesh(parent, label, vertices, normals, uvs, indices, mat)


static func build_uv_patch(parent: Node3D, label: String, rows: int, cols: int,
		point_fn: Callable, mat: Material, reverse_winding := false) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for r in rows + 1:
		var vt := float(r) / rows
		for c in cols + 1:
			var ut := float(c) / cols
			verts.append(point_fn.call(ut, vt))
			uvs.append(Vector2(ut, vt))
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + cols + 1
			if reverse_winding:
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
			else:
				indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var normals := compute_smooth_normals(verts, indices)
	return _commit_uv_mesh(parent, label, verts, normals, uvs, indices, mat)


static func compute_smooth_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for f in range(0, indices.size(), 3):
		var a := indices[f]
		var b := indices[f + 1]
		var c := indices[f + 2]
		var fn := (verts[c] - verts[a]).cross(verts[b] - verts[a])
		normals[a] += fn
		normals[b] += fn
		normals[c] += fn
	# Weld overlapping vertex positions so U=0/1 or front/back edges shade cleanly
	var buckets := {}
	for i in verts.size():
		var k := Vector3i((verts[i] * 5000.0).round())
		if not buckets.has(k):
			buckets[k] = Vector3.ZERO
		buckets[k] += normals[i]
	for i in verts.size():
		var k := Vector3i((verts[i] * 5000.0).round())
		var n: Vector3 = buckets[k]
		normals[i] = n.normalized() if n.length_squared() > 0.000000000001 else Vector3.UP
	return normals


static func _commit_uv_mesh(parent: Node3D, label: String, verts: PackedVector3Array,
		normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, mat: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.name = label
	inst.mesh = mesh
	inst.material_override = mat
	parent.add_child(inst)
	return inst


static func build_ring(parent: Node3D, label: String, center: Vector3, major_r: float, minor_r: float,
		rot_deg: Vector3, color: Color, radial_seg := 28, tube_seg := 12) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = major_r - minor_r
	torus.outer_radius = major_r + minor_r
	torus.rings = radial_seg
	torus.ring_segments = tube_seg
	# Convert PrimitiveMesh to ArrayMesh so DollRig.bind() finds arrays cleanly
	var arr := torus.get_mesh_arrays()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var inst := MeshInstance3D.new()
	inst.name = label
	inst.mesh = am
	inst.position = center
	inst.rotation_degrees = rot_deg
	inst.material_override = flat_material(color)
	parent.add_child(inst)
	return inst


static func build_box_mesh(parent: Node3D, label: String, size: Vector3, pos: Vector3, color: Color, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	var inst := MeshInstance3D.new()
	inst.name = label
	inst.mesh = am
	inst.position = pos
	inst.rotation_degrees = rot_deg
	inst.material_override = flat_material(color)
	parent.add_child(inst)
	return inst


static func build_cylinder_mesh(parent: Node3D, label: String, top_r: float, bot_r: float, height: float,
		pos: Vector3, color: Color, rot_deg := Vector3.ZERO, radial_seg := 20) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.height = height
	cyl.radial_segments = radial_seg
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cyl.get_mesh_arrays())
	var inst := MeshInstance3D.new()
	inst.name = label
	inst.mesh = am
	inst.position = pos
	inst.rotation_degrees = rot_deg
	inst.material_override = flat_material(color)
	parent.add_child(inst)
	return inst


static func build_glasses(head_rig: Node3D, frame_color: Color, eye_x := 0.112, eye_y := 0.292,
		front_z := 0.278, lens_r := 0.068, tube_r := 0.0085) -> void:
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0 else "R"
		# TorusMesh lies in XZ plane by default -> rotate X 90 deg to face forward +Z,
		# and yaw slightly +/-14 deg so outer rim hugs the curved cheek surface naturally.
		build_ring(head_rig, "GlassesRim" + suffix, Vector3(side * eye_x, eye_y, front_z),
			lens_r, tube_r, Vector3(90.0, side * 14.0, 0.0), frame_color, 32, 10)
		# Temple arm going from outer rim back toward ear top (0.270, 0.292, 0.01)
		build_box_mesh(head_rig, "GlassesTemple" + suffix,
			Vector3(0.012, 0.012, 0.25),
			Vector3(side * 0.228, eye_y + 0.008, 0.135),
			frame_color, Vector3(0.0, side * -12.0, 0.0))
	# Nose bridge between the two circular frames
	build_cylinder_mesh(head_rig, "GlassesBridge", tube_r * 0.95, tube_r * 0.95, (eye_x - lens_r) * 2.0 + 0.018,
		Vector3(0.0, eye_y + 0.010, front_z + 0.012), frame_color, Vector3(0.0, 0.0, 90.0), 12)


static func slim_covered_limbs(limbs: Array, child_name: String, bottom_clear_frac := 0.28, shrink_scale := 0.65, outward_shift := 0.0) -> void:
	## Slims upper covered limb skin (inside sleeves/trousers) around each slice centroid, leaving cuffs/hands/ankles intact.
	for limb in limbs:
		var m := limb.get_node_or_null(child_name) as MeshInstance3D
		if m == null or not (m.mesh is ArrayMesh):
			continue
		var side_sign := -1.0 if str(limb.name).contains("L") else 1.0
		var am := m.mesh as ArrayMesh
		var arrays := am.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var min_y := INF
		var max_y := -INF
		for v in verts:
			min_y = minf(min_y, v.y)
			max_y = maxf(max_y, v.y)
		var span := maxf(max_y - min_y, 0.001)
		var sums := {}
		var counts := {}
		for v in verts:
			var bin := int(round(v.y * 45.0))
			if not sums.has(bin):
				sums[bin] = Vector2.ZERO
				counts[bin] = 0
			sums[bin] += Vector2(v.x, v.z)
			counts[bin] += 1
		for i in verts.size():
			var v := verts[i]
			var frac := (v.y - min_y) / span
			if frac > bottom_clear_frac:
				var bin := int(round(v.y * 45.0))
				var c: Vector2 = sums[bin] / float(counts[bin])
				var w := smoothstep(bottom_clear_frac, bottom_clear_frac + 0.14, frac)
				var s := lerpf(1.0, shrink_scale, w)
				v.x = c.x + (v.x - c.x) * s + side_sign * outward_shift * w
				v.z = c.y + (v.z - c.y) * s
				verts[i] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		var new_am := ArrayMesh.new()
		new_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.mesh = new_am
