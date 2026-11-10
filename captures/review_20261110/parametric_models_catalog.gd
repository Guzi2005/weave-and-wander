class_name ParametricModelsCatalog
extends RefCounted

## Standalone parametric model generators for user review (#01 - #22).
## Built specifically for the accepted V20 short-arm mannequin (GameBodyDoll /
## shorter_arm_body.gd, arm_shortening = 0.045) and standalone craft props.
## Does not modify any live game scripts or scenes.

const VOLUME_SHADER: Shader = preload("res://shaders/doll_volume.gdshader")
const ROOM_SHADER: Shader = preload("res://shaders/room_paper.gdshader")


static func make_volume_material(color: Color, backface_shade: float = 0.22) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VOLUME_SHADER
	mat.set_shader_parameter("pigment", color)
	mat.set_shader_parameter("backface_shade", backface_shade)
	return mat


static func make_prop_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROOM_SHADER
	mat.set_shader_parameter("pigment", color)
	return mat


static func build_mesh_instance(parent: Node3D, label: String, vertices: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array, color: Color,
		is_prop_or_rough: Variant = false, double_sided_or_wobble: Variant = true) -> MeshInstance3D:
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
	var use_prop := (typeof(is_prop_or_rough) == TYPE_BOOL and bool(is_prop_or_rough))
	var use_double := true
	if typeof(double_sided_or_wobble) == TYPE_BOOL:
		use_double = bool(double_sided_or_wobble)
	instance.material_override = make_prop_material(color) if use_prop else make_volume_material(color, 0.25 if use_double else 0.0)
	parent.add_child(instance)
	return instance


static func compute_welded_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var n := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	var first := {}
	for i in vertices.size():
		var p := vertices[i]
		var key := "%d,%d,%d" % [roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0)]
		if first.has(key):
			normals[first[key]] += normals[i]
		else:
			first[key] = i
	for i in vertices.size():
		var p := vertices[i]
		var key := "%d,%d,%d" % [roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0)]
		var v: Vector3 = normals[first[key]]
		normals[i] = v.normalized() if v.length_squared() > 1e-10 else Vector3.UP
	return normals


static func emit_quad_outward(vertices: PackedVector3Array, indices: PackedInt32Array,
		q0: int, q1: int, q2: int, q3: int, center_axis: Vector3) -> void:
	var mid := (vertices[q0] + vertices[q1] + vertices[q2] + vertices[q3]) * 0.25
	var n := (vertices[q2] - vertices[q0]).cross(vertices[q1] - vertices[q0])
	if n.dot(mid - center_axis) >= 0.0:
		indices.append_array(PackedInt32Array([q0, q1, q2, q0, q2, q3]))
	else:
		indices.append_array(PackedInt32Array([q0, q2, q1, q0, q3, q2]))


static func emit_triangle_outward(vertices: PackedVector3Array, indices: PackedInt32Array,
		i0: int, i1: int, i2: int, interior_point: Vector3) -> void:
	var mid := (vertices[i0] + vertices[i1] + vertices[i2]) / 3.0
	var n := (vertices[i2] - vertices[i0]).cross(vertices[i1] - vertices[i0])
	if n.dot(mid - interior_point) >= 0.0:
		indices.append_array(PackedInt32Array([i0, i1, i2]))
	else:
		indices.append_array(PackedInt32Array([i0, i2, i1]))


static func add_ellipsoid(parent: Node3D, label: String, center: Vector3, radius: Vector3,
		color: Color, arg6: Variant = false, arg7: Variant = Vector3.ZERO) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = int(arg6) if typeof(arg6) == TYPE_INT else 28
	sphere.rings = int(arg7) if typeof(arg7) == TYPE_INT else 14
	var inst := MeshInstance3D.new()
	inst.name = label
	inst.mesh = sphere
	inst.position = center
	inst.scale = radius
	if typeof(arg7) == TYPE_VECTOR3:
		inst.rotation = arg7
	var is_prop := (typeof(arg6) == TYPE_BOOL and bool(arg6))
	inst.material_override = make_prop_material(color) if is_prop else make_volume_material(color)
	parent.add_child(inst)
	return inst


static func add_ValidationBand(parent: Node3D, label: String, points: PackedVector3Array,
		band_width: float, band_thickness: float, color: Color) -> MeshInstance3D:
	if points.size() < 2:
		return null
	var radii := PackedFloat32Array()
	var r := maxf(0.0025, band_width * 0.52)
	for _i in points.size():
		radii.append(r)
	var flat_ratio := clampf(band_thickness / maxf(0.002, band_width), 0.22, 0.95)
	return add_tube(parent, label, points, radii, color, 10, false, flat_ratio)


static func build_lathe_mesh(parent: Node3D, label: String, profile: PackedVector2Array,
		sides: int, color: Color, _roughness: float = 0.78, _wobble: float = 0.0003) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var p_count := profile.size()
	var y_mid := 0.0
	for pt in profile:
		y_mid += pt.y
	y_mid /= maxf(1.0, float(p_count))

	for i in p_count:
		var r := maxf(0.0, profile[i].x)
		var y := profile[i].y
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			vertices.append(Vector3(cos(a) * r, y, sin(a) * r))
	for i in p_count - 1:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			var ring_y := (profile[i].y + profile[i + 1].y) * 0.5
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, Vector3(0.0, clampf(ring_y, profile[0].y + 0.01, profile[p_count - 1].y - 0.01), 0.0))
	return build_mesh_instance(parent, label, vertices, compute_welded_normals(vertices, indices), indices, color)


static func add_tube(parent: Node3D, label: String, points: PackedVector3Array,
		radii: PackedFloat32Array, color: Color, sides: int = 12, is_prop: bool = false,
		flatten_z: float = 1.0) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var count := points.size()
	for i in count:
		var tangent := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector3.DOWN
		var ref := Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var right := tangent.cross(ref).normalized()
		var forward := right.cross(tangent).normalized()
		var r: float = radii[i] if i < radii.size() else radii[radii.size() - 1]
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var offset := right * (cos(a) * r) + forward * (sin(a) * r * flatten_z)
			vertices.append(points[i] + offset)
	for i in count - 1:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, (points[i] + points[i + 1]) * 0.5)
	var normals := compute_welded_normals(vertices, indices)
	return build_mesh_instance(parent, label, vertices, normals, indices, color, is_prop)


# ============================================================================
# V20 SHORT-ARM MANNEQUIN ENVELOPE HELPERS
# ============================================================================
# Exact torso rings from accepted_body_v20.gd: [y, rx, rz, z_offset]
const V20_TORSO_TABLE := [
	[0.85, 0.215, 0.155, -0.004],
	[1.05, 0.205, 0.150, -0.004],
	[1.08, 0.208, 0.154, -0.008],
	[1.12, 0.228, 0.166, -0.014],
	[1.16, 0.230, 0.166, -0.014],
	[1.20, 0.222, 0.156, -0.010],
	[1.24, 0.208, 0.144, -0.005],
	[1.28, 0.188, 0.134,  0.000],
	[1.32, 0.176, 0.130,  0.006],
	[1.45, 0.185, 0.136,  0.012],
	[1.58, 0.195, 0.142,  0.022],
	[1.70, 0.198, 0.138,  0.024],
	[1.78, 0.190, 0.130,  0.020],
	[1.84, 0.152, 0.114,  0.016],
	[1.90, 0.116, 0.096,  0.018],
	[1.96, 0.086, 0.080,  0.024],
	[2.02, 0.078, 0.076,  0.028],
	[2.09, 0.076, 0.074,  0.030],
]


static func v20_torso_slice(y: float) -> Dictionary:
	# Returns {"rx": float, "rz": float, "z": float} at world height y on V20 torso.
	if y <= float(V20_TORSO_TABLE[0][0]):
		var r0: Array = V20_TORSO_TABLE[0]
		return {"rx": float(r0[1]), "rz": float(r0[2]), "z": float(r0[3])}
	for i in V20_TORSO_TABLE.size() - 1:
		var a: Array = V20_TORSO_TABLE[i]
		var b: Array = V20_TORSO_TABLE[i + 1]
		if y <= float(b[0]):
			var t := clampf((y - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
			return {
				"rx": lerpf(float(a[1]), float(b[1]), t),
				"rz": lerpf(float(a[2]), float(b[2]), t),
				"z": lerpf(float(a[3]), float(b[3]), t)
			}
	var last: Array = V20_TORSO_TABLE.back()
	return {"rx": float(last[1]), "rz": float(last[2]), "z": float(last[3])}


static func v20_arm_slice(local_y: float) -> Dictionary:
	# Returns {"cx": float, "rx": float, "rz": float, "z": float} in ArmLeft/ArmRight local space
	# Exact match to accepted_body_v20.gd / shorter_arm_body.gd (arm_shortening = 0.045)
	var t := clampf((0.01 - local_y) / 0.48, 0.0, 1.0)
	var cx := lerpf(0.005, 0.108, t)
	var rx := lerpf(0.034, 0.074, t)
	var rz := lerpf(0.034, 0.070, t)
	var z_off := lerpf(0.018, 0.016, sin(t * PI * 0.7))
	return {"cx": cx, "rx": rx, "rz": rz, "z": z_off}


static func _resolve_body_rig(doll: Node3D) -> Node3D:
	if "body_rig" in doll and doll.get("body_rig") != null:
		return doll.get("body_rig")
	if doll.get_node_or_null("VolumeDollRig") != null:
		return doll.get_node("VolumeDollRig")
	return doll


static func _resolve_clothes_root(doll: Node3D) -> Node3D:
	if "clothes_root" in doll and doll.get("clothes_root") != null:
		return doll.get("clothes_root")
	var br := _resolve_body_rig(doll)
	if br.get_node_or_null("OutfitSlot") != null:
		return br.get_node("OutfitSlot")
	return br


static func _resolve_head_rig(doll_or_head: Node3D) -> Node3D:
	if "head_rig" in doll_or_head and doll_or_head.get("head_rig") != null:
		return doll_or_head.get("head_rig")
	if doll_or_head.get_node_or_null("HeadRig") != null:
		return doll_or_head.get_node("HeadRig")
	var br := _resolve_body_rig(doll_or_head)
	if br.get_node_or_null("HeadRig") != null:
		return br.get_node("HeadRig")
	return doll_or_head


# ============================================================================
# CATEGORY 1: MORE BASIC HAIRSTYLES (#01 - #06)
# ============================================================================
# HeadRig local space: HEAD_CENTER = (0, 0.29, 0), HEAD_RADIUS = (0.272, 0.30, 0.29)
# Eyes are at y=0.292, Eyebrows at y=0.355..0.359, Ears at (±0.267, 0.238, 0.01) with radius (0.055, 0.076, 0.049).

static func clear_hair_slot(doll_or_head: Node3D) -> Node3D:
	var hair_root: Node3D = null
	if "hair_root" in doll_or_head and doll_or_head.get("hair_root") != null:
		hair_root = doll_or_head.get("hair_root")
	else:
		var hr := _resolve_head_rig(doll_or_head)
		if hr.get_node_or_null("HairSlot") != null:
			hair_root = hr.get_node("HairSlot")
		elif hr.get_node_or_null("Hair") != null:
			hair_root = hr.get_node("Hair")
		else:
			hair_root = Node3D.new()
			hair_root.name = "HairSlot"
			hr.add_child(hair_root)
	for child in hair_root.get_children():
		child.free()
	return hair_root


static func clear_hat_slot(doll_or_head: Node3D) -> void:
	var hr := _resolve_head_rig(doll_or_head)
	var old := hr.get_node_or_null("CustomHat")
	if old != null:
		old.free()


static func clear_prop_slot(doll: Node3D) -> void:
	var old := doll.get_node_or_null("CanvasToteBag")
	if old != null:
		old.free()


static func clear_garment_slot(doll: Node3D, slot_tag: String) -> void:
	_clear_doll_garment_nodes(doll, false, slot_tag)


# Helper: minimum safe clearance radius (rx, rz) in HeadRig local space at height y and azimuth angle (0 = +Z front, PI = -Z back)
static func _head_neck_min_radii(y: float, angle: float, cover_ears: bool = false) -> Vector2:
	var ca := cos(angle) # +1 at front (+Z), -1 at back (-Z)
	var sa := absf(sin(angle)) # +1 at left/right sides (±X)
	var rx := 0.0
	var rz := 0.0

	# 1. Head cranium ellipsoid envelope: center (0, 0.290, 0), semi-axes (0.276, 0.308, 0.294)
	# Tapers smoothly to 0 at the crown pole (y = 0.598) so the crown never flattens into a bottle-cap rim
	if y >= -0.02 and y <= 0.615:
		var ny := clampf((y - 0.290) / 0.308, -0.99, 0.999)
		var ring := sqrt(maxf(0.0, 1.0 - ny * ny))
		rx = 0.276 * ring
		rz = 0.294 * ring

	# 2. Ear envelope: center (±0.267, 0.238, 0.01), outer extent |x| = 0.322 for y in [0.15, 0.32]
	if cover_ears and y >= 0.13 and y <= 0.34:
		var ear_y_factor := clampf(1.0 - pow((y - 0.238) / 0.105, 2.0), 0.0, 1.0)
		var ear_side_factor := smoothstep(0.65, 0.92, sa) * (1.0 - smoothstep(0.25, 0.65, absf(ca - 0.03)))
		rx = maxf(rx, (0.280 + 0.052 * ear_y_factor) * ear_side_factor)

	# 3. V20 Neck & Shoulder/Torso envelope below head (HeadRig origin is world (0, 2.02, 0.035))
	var world_y := 2.02 + y
	if world_y <= 2.00:
		var sl := v20_torso_slice(clampf(world_y, 1.05, 1.95))
		var shoulder_extra_x := 0.045 * smoothstep(1.62, 1.84, world_y) * smoothstep(1.94, 1.84, world_y) * sa
		rx = maxf(rx, float(sl["rx"]) + shoulder_extra_x + 0.034)
		rz = maxf(rz, float(sl["rz"]) + 0.036 + (0.025 if ca < 0.0 else 0.015))
	elif y < 0.15:
		# Lower neck base below cranium
		rx = maxf(rx, 0.115)
		rz = maxf(rz, 0.105)

	return Vector2(rx, rz)


# Build a closed 3D volumetric hair shell from outer & inner grids (rows+1 x cols+1) so hair never has paper-thin edges or missing backfaces
static func _build_thick_hair_curtain(parent: Node3D, label: String, outer_grid: PackedVector3Array,
		inner_grid: PackedVector3Array, rows: int, cols: int, color: Color, wrap_u: bool = false) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var stride := cols + 1
	var grid_count := (rows + 1) * stride
	vertices.append_array(outer_grid)
	vertices.append_array(inner_grid)

	# Outer surface (outward normals) and Inner surface (inward normals)
	for r in rows:
		for c in cols:
			var a := r * stride + c
			var b := a + stride
			var center_pt := Vector3(0, outer_grid[a].y, -0.02)
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, center_pt)
			var ia := grid_count + a
			var ib := grid_count + b
			# Reverse interior reference for inner wall so normals point inward toward head
			emit_quad_outward(vertices, indices, ia, ib, ib + 1, ia + 1, outer_grid[a] * 2.0 - center_pt)

	# Stitch top hem (r = 0) so hair roots are completely sealed against scalp without open gaps
	for c in cols:
		var oa := c
		var ia := grid_count + oa
		emit_quad_outward(vertices, indices, ia, ia + 1, oa + 1, oa, Vector3(0, outer_grid[oa].y - 0.02, -0.02))

	# Stitch bottom hem (r = rows)
	for c in cols:
		var oa := rows * stride + c
		var ia := grid_count + oa
		emit_quad_outward(vertices, indices, oa, oa + 1, ia + 1, ia, Vector3(0, outer_grid[oa].y + 0.08, -0.02))

	# Stitch left edge (c = 0) and right edge (c = cols) ONLY when not wrapping around!
	if not wrap_u:
		for r in rows:
			var l_out := r * stride
			var l_in := grid_count + l_out
			emit_quad_outward(vertices, indices, l_out, l_out + stride, l_in + stride, l_in, Vector3(0, outer_grid[l_out].y, -0.02))
			var r_out := r * stride + cols
			var r_in := grid_count + r_out
			emit_quad_outward(vertices, indices, r_out, r_in, r_in + stride, r_out + stride, Vector3(0, outer_grid[r_out].y, -0.02))

	return build_mesh_instance(parent, label, vertices, compute_welded_normals(vertices, indices), indices, color)


static func build_base_scalp_cap(hair_root: Node3D, color: Color, front_phi: float = 1.02,
		back_phi: float = 2.28, crown_scale: float = 1.02, part_x: float = 0.0,
		expose_ears: bool = false) -> void:
	# Full anatomical scalp cap covering crown, temples (in front of ears), and nape (behind ears) without any bald gaps.
	# When expose_ears=true, arches cleanly above the ear root so ears emerge naturally from skull skin without clipping.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 64
	var rows := 22
	for r in rows + 1:
		var v := float(r) / rows
		for c in segments + 1:
			var angle := TAU * float(c) / segments # 0 = +Z front, PI/2 = +X right, PI = -Z back
			var ca := cos(angle)
			var sa := absf(sin(angle))
			# Natural hairline:
			# - Front forehead (ca > 0.5): phi ~ front_phi (1.02 -> y ~ 0.45)
			# - Sideburns / temples in front of ear (ca in [0.10, 0.55], sa > 0.7): dips down to phi ~ 1.68 (y ~ 0.24)
			# - Ear arch (ca in [-0.22, 0.10], sa > 0.90): arches cleanly around the top of the ear at phi ~ 1.44 (y ~ 0.32)
			# - Back skull & nape (ca < -0.22): extends down to back_phi (2.28 -> y ~ 0.06)
			var front_blend := smoothstep(-0.15, 0.60, ca)
			var sideburn_dip := 0.64 * smoothstep(0.45, 0.92, sa) * smoothstep(-0.05, 0.35, ca) * (1.0 - smoothstep(0.55, 0.92, ca))
			var ear_arch_lift := -0.22 * smoothstep(0.88, 0.99, sa) * exp(-pow((ca + 0.04) / 0.16, 2.0))
			if expose_ears:
				var ear_dist := sqrt(pow((ca - 0.03) / 0.22, 2.0) + pow((sa - 0.96) / 0.18, 2.0))
				var cutout := smoothstep(1.0, 0.0, ear_dist)
				ear_arch_lift -= 0.72 * cutout
				sideburn_dip *= (1.0 - cutout)
			var front_hairline := front_phi + sideburn_dip + ear_arch_lift
			var target_phi := lerpf(back_phi, front_hairline, front_blend)
			if expose_ears and sa > 0.82 and ca > -0.20 and ca < 0.20:
				target_phi = minf(target_phi, 1.34)
			var phi := lerpf(0.012, target_phi, v)
			var unit := Vector3(sin(phi) * sin(angle), cos(phi), sin(phi) * cos(angle))
			var strand_wave := 1.0 + 0.004 * sin(angle * 14.0) * sin(phi * 3.0)
			var part_indent := 0.008 * exp(-pow((unit.x * 0.30 - part_x) / 0.022, 2.0)) * smoothstep(0.1, 0.85, v) * smoothstep(-0.1, 0.5, ca)
			# Anatomical cranium envelope: hugs HEAD_RADIUS (0.272, 0.300, 0.290) snugly with organic 4-6mm hair clearance
			# Eliminates bloated swimming-cap / bottle-cap bulge across the frontal skull
			var rx := (0.274 + 0.003 * crown_scale) * strand_wave
			var ry := (0.302 + 0.004 * crown_scale) - part_indent
			var rz := (0.292 + 0.003 * crown_scale) * strand_wave
			var back_z_shift := -0.016 * smoothstep(0.1, -0.8, ca) * sin(phi)
			vertices.append(Vector3(unit.x * rx, 0.290 + unit.y * ry, unit.z * rz + back_z_shift))
	for r in rows:
		for c in segments:
			var a := r * (segments + 1) + c
			var b := a + segments + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, Vector3(0, 0.29, 0.0))
	build_mesh_instance(hair_root, "ScalpCap", vertices, compute_welded_normals(vertices, indices), indices, color)


static func build_front_bangs(hair_root: Node3D, color: Color, bang_bottom_y: float = 0.378,
		arch_amount: float = 0.020, split_width: float = 0.0, split_center_x: float = 0.0,
		side_lock_drop: float = 0.16, strand_params: Dictionary = {}) -> void:
	# Volumetric 3D front bangs + cheek-framing sideburn locks that stay strictly outside forehead/brow skin
	var cols := 40
	var rows := 14
	var outer_grid := PackedVector3Array()
	var inner_grid := PackedVector3Array()

	for r in rows + 1:
		var t := float(r) / rows
		for c in cols + 1:
			var u := (float(c) / cols - 0.5) * 2.0 # -1 to +1
			var abs_u := absf(u)
			# Angle sweeps from -1.04 to +1.04 (staying in front of the ears which are at angle = ±1.53)
			var angle := u * 1.04
			var temple_blend := smoothstep(0.62, 0.90, abs_u)
			var center_arch := arch_amount * (1.0 - u * u)
			var split_lift := 0.0
			if split_width > 0.001:
				split_lift = 0.048 * exp(-pow((u - split_center_x) / maxf(0.08, split_width), 2.0))
			var end_y := lerpf(bang_bottom_y + center_arch + split_lift, bang_bottom_y - side_lock_drop, temple_blend)
			# Front bangs root emerges at true cranial crown (y ~ 0.598) flush with ScalpCap & canopy locks
			var start_y := 0.598 - 0.018 * abs_u * abs_u
			var y := lerpf(start_y, end_y, t)

			# Exact head surface at height y so inner surface hugs forehead/brow snugly without clipping
			var norm_y := clampf((y - 0.290) / 0.304, -0.95, 0.992)
			var ring_r := sqrt(maxf(0.01, 1.0 - norm_y * norm_y))
			var min_rx := 0.274 * ring_r + 0.005
			var min_rz := 0.292 * ring_r + 0.005

			# Plush 3D bang thickness with feathered root so roots blend flush into the scalp cap without bottle-cap ledge
			var root_blend := smoothstep(0.0, 0.22, t)
			var flute := 0.0035 * cos(u * PI * 9.0) * sin(t * PI)
			var thickness := lerpf(0.005, 0.020, sin(t * PI * 0.78)) * (1.0 - 0.45 * pow(t, 3.0)) * lerpf(0.25, 1.0, root_blend) + flute
			var out_rx := min_rx + thickness
			var out_rz := min_rz + thickness

			outer_grid.append(Vector3(sin(angle) * out_rx, y, cos(angle) * out_rz))
			inner_grid.append(Vector3(sin(angle) * min_rx, y, cos(angle) * min_rz))

	var bang_sp := strand_params
	if bang_sp.is_empty():
		bang_sp = _strand_params({}, "bang_", _BANG_STRAND_DEFAULTS)
	_build_strand_locks(hair_root, "FrontBangs", outer_grid, inner_grid, rows, cols, color, bang_sp, false)


# ============================================================================
# HAIR STRAND / LOCK (发片) SYSTEM
# ----------------------------------------------------------------------------
# Every hair section (bangs, canopy/mantle, tails) is generated as a continuous
# guide surface (outer + inner grid, rows = root->tip, cols = across the section),
# then SPLIT into separate lock meshes ("<Section>_LockNN") that follow the
# original guide path. Per-section parameters (flat keys with optional prefix,
# e.g. "bang_wavy", or a nested dict params["strands"] / params["bang_strands"]):
#   wavy          lock waviness amplitude in m (oscillates AROUND the original path)
#   wavy_freq     waves per full lock length
#   length_scale  lock length multiplier on top of the style's total length
#   cut_angle     slant-cut angle in degrees (applied on top of total length)
#   thickness     lock thickness multiplier
#   strand_width  single lock width in m      (density part 1)
#   strand_gap    spacing between locks in m  (density part 2, negative = overlap)
#   tip_taper     0..0.9 narrowing of lock tips
#   length_jitter random per-lock length variation in m
# ============================================================================
const _BANG_STRAND_DEFAULTS := {"strand_width": 0.040, "strand_gap": 0.0, "cut_mode": "linear",
	"cut_span": 0.30, "length_jitter": 0.006, "tip_taper": 0.45, "wavy_freq": 1.0}

const _STRAND_KEYS := ["wavy", "wavy_freq", "length_scale", "cut_angle", "thickness",
	"strand_width", "strand_gap", "tip_taper", "length_jitter", "cut_mode", "cut_span", "head_push", "split"]


static func _strand_params(params: Dictionary, prefix: String, defaults: Dictionary = {}) -> Dictionary:
	var sp := {"wavy": 0.0, "wavy_freq": 2.0, "length_scale": 1.0, "cut_angle": 0.0, "thickness": 1.0,
		"strand_width": 0.052, "strand_gap": 0.0, "tip_taper": 0.55, "length_jitter": 0.018,
		"cut_mode": "symmetric", "cut_span": 0.42, "head_push": true, "split": true}
	for k in defaults:
		sp[k] = defaults[k]
	if params.has("split"):
		sp["split"] = bool(params["split"])
	if params.has("split_strands"):
		sp["split"] = bool(params["split_strands"])
	if params.has(prefix + "split"):
		sp["split"] = bool(params[prefix + "split"])
	if params.has(prefix + "split_strands"):
		sp["split"] = bool(params[prefix + "split_strands"])
	var nested: Dictionary = params.get(prefix + "strands", {})
	for k in _STRAND_KEYS:
		if params.has(prefix + k):
			sp[k] = params[prefix + k]
		if nested.has(k):
			sp[k] = nested[k]
	sp["strand_width"] = clampf(float(sp["strand_width"]), 0.012, 0.20)
	sp["strand_gap"] = clampf(float(sp["strand_gap"]), -0.5 * float(sp["strand_width"]), 0.05)
	sp["thickness"] = clampf(float(sp["thickness"]), 0.25, 3.0)
	sp["length_scale"] = clampf(float(sp["length_scale"]), 0.3, 1.35)
	sp["cut_angle"] = clampf(float(sp["cut_angle"]), -60.0, 60.0)
	sp["wavy"] = clampf(float(sp["wavy"]), 0.0, 0.06)
	sp["tip_taper"] = clampf(float(sp["tip_taper"]), 0.0, 0.9)
	return sp


# Bilinear sample of a (rows+1) x (cols+1) guide grid at (t, u); t > 1 extrapolates along the last segment.
static func _grid_sample(grid: PackedVector3Array, rows: int, cols: int, t: float, u: float, wrap_u: bool) -> Vector3:
	var stride := cols + 1
	u = fposmod(u, 1.0) if wrap_u else clampf(u, 0.0, 1.0)
	var fu := u * cols
	var c0 := clampi(int(floor(fu)), 0, cols - 1)
	var au := fu - c0
	if t > 1.0:
		var q_last: Vector3 = grid[rows * stride + c0].lerp(grid[rows * stride + c0 + 1], au)
		var q_prev: Vector3 = grid[(rows - 1) * stride + c0].lerp(grid[(rows - 1) * stride + c0 + 1], au)
		return q_last + (q_last - q_prev) * ((t - 1.0) * rows)
	var fr := maxf(t, 0.0) * rows
	var r0 := clampi(int(floor(fr)), 0, rows - 1)
	var ar := fr - r0
	var top: Vector3 = grid[r0 * stride + c0].lerp(grid[r0 * stride + c0 + 1], au)
	var bot: Vector3 = grid[(r0 + 1) * stride + c0].lerp(grid[(r0 + 1) * stride + c0 + 1], au)
	return top.lerp(bot, ar)


# Push a HeadRig-local point radially outside the head / ear / neck-shoulder envelope.
static func _push_outside_head(p: Vector3, margin: float = 0.0) -> Vector3:
	# 1. Upper cranial dome (y >= 0.35): push along 3D ellipsoid normal so crown vertices round upward naturally instead of flaring into a flat cylinder/bottle-cap
	if p.y >= 0.35:
		var head_cy := 0.290
		var rx_3d := 0.274 + margin
		var ry_3d := 0.302 + margin
		var rz_3d := 0.292 + margin
		var dx := p.x / rx_3d
		var dy := (p.y - head_cy) / ry_3d
		var dz := p.z / rz_3d
		var d3 := sqrt(dx * dx + dy * dy + dz * dz)
		if d3 < 1.0 and d3 > 0.0001:
			p.x = dx / d3 * rx_3d
			p.y = head_cy + dy / d3 * ry_3d
			p.z = dz / d3 * rz_3d
		return p

	# 2. Lower head, ears & neck: horizontal envelope push
	var ang := atan2(p.x, p.z)
	var env := _head_neck_min_radii(p.y, ang, true)
	var rx := maxf(0.01, env.x + margin)
	var rz := maxf(0.01, env.y + margin)
	var radial := sqrt(pow(p.x / rx, 2.0) + pow(p.z / rz, 2.0))
	if radial < 1.0 and radial > 0.0001:
		p.x /= radial
		p.z /= radial
	return p


# Split a guide surface into individual hair locks. Returns the shortest lock end (in guide-t units).
# When split=false: treated as 缕=1 (single continuous strand lock spanning the whole guide section).
static func _build_strand_locks(parent: Node3D, label: String, outer_grid: PackedVector3Array,
		inner_grid: PackedVector3Array, rows: int, cols: int, color: Color, sp: Dictionary,
		wrap_u: bool = false) -> float:
	var group := Node3D.new()
	group.name = label
	parent.add_child(group)

	var is_split: bool = bool(sp.get("split", true))
	var stride := cols + 1

	# Lock count from the real arc width of the section (measured on a lower guide row)
	var ref_r := int(round(rows * 0.62))
	var arc := 0.0
	for c in cols:
		arc += outer_grid[ref_r * stride + c].distance_to(outer_grid[ref_r * stride + c + 1])
	var w: float = float(sp["strand_width"])
	var g: float = float(sp["strand_gap"])

	var n: int = 1
	if is_split:
		n = maxi(1, int(round(arc / maxf(0.01, w + g))))
		if not wrap_u and n < 2 and arc > w * 1.5:
			n = 2
	else:
		# 用户指令：“可以留着“发片分缕”开关，但是将其视为缕=1”
		n = 1

	var pitch := 1.0 / float(n)
	var fill := 1.0 if not is_split else clampf(w / maxf(0.005, w + g), 0.2, 2.0)

	var path_len := 0.0
	var mid_c := cols / 2
	for r in rows:
		path_len += outer_grid[r * stride + mid_c].distance_to(outer_grid[(r + 1) * stride + mid_c])
	path_len = maxf(0.05, path_len)

	var tan_a := tan(deg_to_rad(float(sp["cut_angle"])))
	var cut_span: float = float(sp["cut_span"])
	var wav: float = float(sp["wavy"])
	var freq: float = float(sp["wavy_freq"])
	var lock_rows := maxi(14, rows)
	# For multi-strand locks (n > 1), lock_cols = 4 is sufficient per narrow strand.
	# For single strand lock (n = 1), lock_cols = maxi(cols, 16) to ensure silky smooth curvature across the full curtain.
	var lock_cols := maxi(cols, 16) if not is_split else 4
	var min_t_end := 9.0

	for i in n:
		var u_c := (float(i) + 0.5) * pitch
		var h := u_c * 2.0 - 1.0
		var dy: float
		match str(sp["cut_mode"]):
			"symmetric":
				dy = tan_a * absf(h) * cut_span # e.g. A-line: front locks longer than back
			"radial":
				dy = tan_a * cos(u_c * TAU) * cut_span # tubes: slant across the tail cross-section
			_:
				dy = tan_a * h * cut_span # linear: diagonal cut from one side to the other
		var jitter := (float(sp["length_jitter"]) * sin(float(i) * 12.9898 + 4.1) * 0.5 * (1.0 + cos(float(i) * 7.31))) if is_split else 0.0
		var t_end := clampf(float(sp["length_scale"]) + (dy + jitter) / path_len, 0.2, 1.4)
		min_t_end = minf(min_t_end, t_end)
		var half_u := 0.5 if not is_split else (pitch * fill * 0.5)
		var phase := float(i) * 2.399

		var o_pts := PackedVector3Array()
		var i_pts := PackedVector3Array()
		for r in lock_rows + 1:
			var lt := float(r) / lock_rows
			var taper := 1.0 - float(sp["tip_taper"]) * smoothstep(0.70, 1.0, lt)

			# Crown fit & feathering:
			# 1. At the crown (lt -> 0), locks smoothly converge side-by-side with zero gap to form a continuous cranial crown
			var root_blend := smoothstep(0.0, 0.24, lt)
			var root_fill: float
			if not is_split:
				# 缕=1: spans full width 0.0 .. 1.0 from crown to tip, with gentle tip taper if set
				root_fill = lerpf(0.5, 0.5 * (1.0 - float(sp["tip_taper"]) * 0.25 * smoothstep(0.70, 1.0, lt)), root_blend)
			else:
				root_fill = lerpf(pitch * 0.505, half_u, root_blend)

			# 2. Waves start only below the cranial dome so the crown stays snug against skull
			var wave_env := smoothstep(0.18, 0.50, lt * t_end)
			var wave_s := sin(TAU * freq * (lt * t_end) + phase)
			var wave_c := 0.5 + 0.5 * cos(TAU * freq * (lt * t_end) + phase)

			# 3. Root thickness feathers flush to scalp cap: eliminates stair-stepped edge or bottle-cap lid
			var root_thick := lerpf(0.12, 1.0, root_blend)

			for c in lock_cols + 1:
				var s := float(c) / float(lock_cols)
				var u: float
				var cur_t_end := t_end
				if not is_split:
					# 缕=1: u covers entire section width 0.0 to 1.0 across columns
					u = u_c + (s * 2.0 - 1.0) * root_fill
					if not wrap_u:
						u = clampf(u, 0.0, 1.0)
					# Allow cut angle (e.g. A-line or diagonal) to vary across the single strand width!
					if absf(tan_a) > 0.001:
						var col_h := s * 2.0 - 1.0
						var col_dy := 0.0
						match str(sp["cut_mode"]):
							"symmetric":
								col_dy = tan_a * absf(col_h) * cut_span
							"radial":
								col_dy = tan_a * cos(s * TAU) * cut_span
							_:
								col_dy = tan_a * col_h * cut_span
						cur_t_end = clampf(float(sp["length_scale"]) + col_dy / path_len, 0.2, 1.4)
				else:
					u = u_c + (s * 2.0 - 1.0) * root_fill * taper

				var t := lt * cur_t_end
				var p_in := _grid_sample(inner_grid, rows, cols, t, u, wrap_u)
				var p_out := _grid_sample(outer_grid, rows, cols, t, u, wrap_u)
				var pa := _grid_sample(outer_grid, rows, cols, t, u + 0.012, wrap_u)
				var pb := _grid_sample(outer_grid, rows, cols, t, u - 0.012, wrap_u)
				var tan_u := (pa - pb).normalized() if pa.distance_squared_to(pb) > 1e-10 else Vector3.RIGHT
				var nrm := p_out - p_in
				var depth := nrm.length()
				var ndir: Vector3
				if depth > 1e-5:
					ndir = nrm / depth
				else:
					ndir = Vector3(p_out.x, 0.0, p_out.z).normalized()
				# Waviness oscillates around the ORIGINAL guide path (sideways + slight outward lift), roots stay fixed
				var disp := (tan_u * wave_s + ndir * 0.45 * wave_c) * wav * wave_env

				var edge: float = 1.0
				if not is_split:
					# 缕=1: seamless cylindrical or smooth open curtain with soft edge taper
					edge = 1.0 if wrap_u else lerpf(0.78, 1.0, sin(s * PI))
				else:
					# Multi-strand: pillowed rounded lock edges
					edge = 0.45 + 0.55 * sin(s * PI)

				var tip_thin := 1.0 - 0.55 * smoothstep(0.80, 1.0, lt)
				var thick := maxf(0.003, depth) * float(sp["thickness"]) * edge * tip_thin * root_thick
				var base_p := p_in + disp
				if bool(sp["head_push"]):
					base_p = _push_outside_head(base_p)
				i_pts.append(base_p)
				o_pts.append(base_p + ndir * thick)
		var tint := (0.022 * sin(float(i) * 3.7)) if is_split else 0.0
		var lock_color := color.lightened(tint) if tint > 0.0 else color.darkened(-tint)
		var is_curtain_wrapped := wrap_u and not is_split
		_build_thick_hair_curtain(group, "%s_Lock%02d" % [label, i], o_pts, i_pts, lock_rows, lock_cols, lock_color, is_curtain_wrapped)
	group.set_meta("lock_count", n)
	return min_t_end


# Build a solid core tube under split tail locks, truncated to t_max so it never pokes past the shortest lock.
static func _build_tube_core(parent: Node3D, label: String, core_grid: PackedVector3Array, rows: int, cols: int,
		t_max: float, color: Color, center_ref: Vector3) -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var c_rows := maxi(8, rows)
	for r in c_rows + 1:
		var t := float(r) / c_rows * clampf(t_max, 0.1, 1.0)
		var shrink := 1.0 - 0.8 * smoothstep(0.85, 1.0, float(r) / c_rows)
		var center := Vector3.ZERO
		for c in cols:
			center += _grid_sample(core_grid, rows, cols, t, float(c) / cols, true)
		center /= float(cols)
		for c in cols + 1:
			var p := _grid_sample(core_grid, rows, cols, t, float(c) / cols, true)
			vertices.append(center + (p - center) * shrink)
	for r in c_rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + cols + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, center_ref)
	build_mesh_instance(parent, label, vertices, compute_welded_normals(vertices, indices), indices, color.darkened(0.04))


# Dedicated ear-front sideburn / temple locks that frame the face in front of the tragus,
# cleanly separating the front hair from the ear so the ear root emerges naturally from bare skin.
static func _build_ear_front_sideburns(parent: Node3D, color: Color, length: float = 0.16) -> void:
	for side: float in [-1.0, 1.0]:
		var rows := 8
		var cols := 3
		var outer_grid := PackedVector3Array()
		var inner_grid := PackedVector3Array()
		for r in rows + 1:
			var t := float(r) / rows
			# Stays strictly in front of ear (z in [0.054, 0.082], ear root is at z=0.010, tragus at z=0.040)
			var y := lerpf(0.385, 0.385 - length, t)
			var base_x := side * lerpf(0.262, 0.252, t)
			var base_z := lerpf(0.082, 0.054, t)
			for c in cols + 1:
				var u := float(c) / cols
				var w_x := (u - 0.5) * 0.024 * (1.0 - 0.4 * t)
				var w_z := (u - 0.5) * 0.016
				var p_in := Vector3(base_x + w_x * 0.3, y, base_z + w_z)
				p_in = _push_outside_head(p_in, 0.003)
				var normal := Vector3(p_in.x, 0.0, p_in.z).normalized()
				var thick := 0.010 * (1.0 - 0.35 * t) * (0.6 + 0.4 * sin(u * PI))
				var p_out := p_in + normal * thick
				inner_grid.append(p_in)
				outer_grid.append(p_out)
		_build_thick_hair_curtain(parent, "SideburnLock" + ("L" if side < 0 else "R"),
			outer_grid, inner_grid, rows, cols, color)


# Adaptive surface-snapped hair scrunchie / tie ring
# Wraps around a bundle axis (bundle_dir) at mount point (mount_origin),
# resting snugly on the skull without clipping or floating.
static func _build_adaptive_hair_tie(parent: Node3D, label: String, mount_origin: Vector3,
		bundle_dir: Vector3, ring_radius: float, tube_radius: float, color: Color,
		ripple_count: int = 8, ripple_amp: float = 0.14) -> MeshInstance3D:
	var tangent := bundle_dir.normalized()
	if tangent.length_squared() < 0.001:
		tangent = Vector3.UP
	var ref := Vector3.RIGHT if absf(tangent.x) < 0.85 else Vector3.UP
	var u_axis := tangent.cross(ref).normalized()
	var v_axis := tangent.cross(u_axis).normalized()

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var ring_steps := 28
	var tube_steps := 12
	var center_lift := mount_origin + tangent * (tube_radius * 0.90)

	for r in ring_steps + 1:
		var theta := TAU * float(r) / ring_steps
		var ripple := 1.0 + ripple_amp * sin(theta * float(ripple_count))
		var r_ring := ring_radius * ripple
		var r_dir := (u_axis * cos(theta) + v_axis * sin(theta)).normalized()
		var p_center := center_lift + r_dir * r_ring

		for t in tube_steps + 1:
			var phi := TAU * float(t) / tube_steps
			var tube_off := r_dir * (tube_radius * cos(phi)) + tangent * (tube_radius * sin(phi))
			var p := p_center + tube_off
			p = _push_outside_head(p, 0.003)
			vertices.append(p)

	for r in ring_steps:
		for t in tube_steps:
			var a := r * (tube_steps + 1) + t
			var b := a + tube_steps + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, center_lift)

	return build_mesh_instance(parent, label, vertices, compute_welded_normals(vertices, indices), indices, color)


# #01: 齐刘海内扣波波头 (Classic Chin Bob with Bangs)
static func build_hair_01_bob(doll: Node3D, params: Dictionary = {}) -> void:
	var hair_root := clear_hair_slot(doll)
	var color: Color = params.get("color", Color(0.24, 0.17, 0.14))
	var raw_len: float = params.get("bob_length", params.get("length", 0.34))
	var bob_length: float = clampf(raw_len, 0.22, 0.46)
	var raw_curl: float = params.get("inward_curl", params.get("curl_in", 0.068))
	var inward_curl: float = clampf(raw_curl, 0.02, 0.12)
	var crown_puff: float = clampf(params.get("crown_puff", 1.04), 0.98, 1.14)
	var bang_y: float = clampf(params.get("bang_y", 0.378), 0.368, 0.420)
	var bang_split: float = clampf(params.get("bang_split", 0.0), 0.0, 0.35)

	build_base_scalp_cap(hair_root, color, 1.00, 2.24, crown_puff, 0.0)
	var bang_sp := _strand_params(params, "bang_", _BANG_STRAND_DEFAULTS)
	build_front_bangs(hair_root, color, bang_y, 0.016, bang_split, 0.0, 0.17, bang_sp)

	# Continuous 3D ellipsoidal cranial dome + C-curl bob canopy guide grid
	var cols := 64
	var rows := 26
	var outer_grid := PackedVector3Array()
	var inner_grid := PackedVector3Array()
	var head_cy := 0.290
	var R_x := 0.276 * crown_puff + 0.005
	var R_y := 0.304 * crown_puff + 0.006 # apex at 0.290 + 0.316 = 0.606
	var R_z := 0.294 * crown_puff + 0.005
	var bottom_y := 0.34 - bob_length
	var dome_ratio := 0.35

	for r in rows + 1:
		var t := float(r) / rows
		var local_y: float
		var base_rx: float
		var base_rz: float
		var wall_thick: float
		var z_shift := 0.0

		if t <= dome_ratio:
			var dt := t / dome_ratio
			var phi := lerpf(0.08, 1.46, pow(dt, 0.94))
			local_y = head_cy + R_y * cos(phi)
			var ring := sin(phi)
			base_rx = R_x * ring
			base_rz = R_z * ring
			wall_thick = lerpf(0.006, 0.022, smoothstep(0.0, 0.8, dt))
			z_shift = -0.010 * ring
		else:
			var lt := (t - dome_ratio) / (1.0 - dome_ratio)
			local_y = lerpf(head_cy + R_y * cos(1.46), bottom_y, lt)
			var bell := sin(lt * PI * 0.78)
			var c_curl := inward_curl * pow(maxf(0.0, (lt - 0.45) / 0.55), 1.75)
			base_rx = R_x + 0.048 * bell - c_curl
			base_rz = R_z + 0.038 * bell - c_curl * 0.85
			wall_thick = lerpf(0.022, 0.014, lt)
			z_shift = -0.010

		for c in cols + 1:
			var u := float(c) / cols
			var angle := lerpf(0.62, TAU - 0.62, u)
			var flute := 1.0 + 0.006 * cos(u * PI * 16.0) * sin(clampf((t - 0.15) / 0.85, 0.0, 1.0) * PI)

			var min_env := _head_neck_min_radii(local_y, angle, true)
			var in_rx := maxf(min_env.x, base_rx - wall_thick)
			var in_rz := maxf(min_env.y, base_rz - wall_thick)
			var out_rx := maxf(in_rx + 0.006, base_rx * flute)
			var out_rz := maxf(in_rz + 0.006, base_rz * flute)

			outer_grid.append(Vector3(sin(angle) * out_rx, local_y, cos(angle) * out_rz + z_shift))
			inner_grid.append(Vector3(sin(angle) * in_rx, local_y, cos(angle) * in_rz + z_shift))

	var bob_sp := _strand_params(params, "bob_", {"strand_width": 0.046, "strand_gap": 0.0,
		"tip_taper": 0.65, "cut_mode": "symmetric", "cut_span": 0.32})
	_build_strand_locks(hair_root, "BobCanopy", outer_grid, inner_grid, rows, cols, color, bob_sp, false)


# #02: 元气高马尾 (Perky High Ponytail)
static func build_hair_02_high_ponytail(doll: Node3D, params: Dictionary = {}) -> void:
	var hair_root := clear_hair_slot(doll)
	var color: Color = params.get("color", Color(0.24, 0.17, 0.14))
	var accent: Color = params.get("scrunchie_color", params.get("accent", Color("d96b52")))
	var crown_height: float = clampf(params.get("crown_height", params.get("tail_height", 0.48)), 0.36, 0.56)
	var tail_length: float = clampf(params.get("tail_length", 0.50), 0.32, 0.72)
	var tail_flare: float = clampf(params.get("tail_flare", 0.135), 0.08, 0.20)
	var tail_arch: float = clampf(params.get("tail_arch", 0.15), 0.06, 0.25)

	var expose_ears: bool = bool(params.get("expose_ears", true))
	# 1. Scalp cap with ear cutout so ears emerge naturally from skull skin
	build_base_scalp_cap(hair_root, color, 1.00, 2.32, 1.02, 0.0, expose_ears)
	# 2. Front bangs stay neatly on forehead without dropping over ears
	var bang_sp := _strand_params(params, "bang_", _BANG_STRAND_DEFAULTS)
	var bang_drop: float = (0.04 if expose_ears else 0.18)
	build_front_bangs(hair_root, color, 0.382, 0.022, 0.14, 0.0, bang_drop, bang_sp)
	# 3. Dedicated ear-front sideburn locks
	if expose_ears:
		_build_ear_front_sideburns(hair_root, color, 0.15)

	# 4. Ponytail mount point on skull surface
	var dy := clampf((crown_height - 0.290) / 0.306, -0.92, 0.92)
	var beta := acos(dy)
	var mount_pos := Vector3(0.0, crown_height, -0.296 * sin(beta))
	var n_skull := Vector3(0.0, dy / 0.306, -sin(beta) / 0.296).normalized()
	var tail_tan := (n_skull + Vector3(0.0, 0.20, -0.40)).normalized()

	# 5. Adaptive surface-snapped scrunchie torus
	_build_adaptive_hair_tie(hair_root, "PonytailScrunchie", mount_pos, tail_tan, 0.062, 0.022, accent, 10, 0.14)

	# 6. Sculpted fluted ponytail guide grid
	var rings := 24
	var cols := 16
	var outer_grid := PackedVector3Array()
	var inner_grid := PackedVector3Array()

	var spine_pts: Array[Vector3] = []
	for i in rings + 1:
		var t := float(i) / rings
		var spine := Vector3(
			0.0,
			mount_pos.y + tail_arch * sin(t * PI * 0.52) - tail_length * pow(t, 1.32),
			mount_pos.z - 0.045 * t - tail_arch * 1.22 * sin(t * PI * 0.76) - 0.09 * t * t
		)
		spine_pts.append(spine)

	for i in rings + 1:
		var t := float(i) / rings
		var spine: Vector3 = spine_pts[i]
		var next_spine: Vector3 = (spine_pts[i + 1] if i < rings else spine_pts[i] + Vector3.DOWN * 0.05)
		var tangent := (next_spine - spine).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector3.DOWN
		var right := Vector3.RIGHT
		var normal_dir := right.cross(tangent).normalized()
		var profile_r := lerpf(0.048, tail_flare, sin(pow(t, 0.68) * PI)) * (1.0 - 0.75 * pow(t, 3.0))
		profile_r = maxf(0.010, profile_r)
		var inner_r := profile_r * 0.72

		for c in cols + 1:
			var a := TAU * float(c) / cols
			var flute := 1.0 + 0.08 * cos(a * 5.0 + t * 2.5) * sin(t * PI)
			var off_out := right * (cos(a) * profile_r * flute) + normal_dir * (sin(a) * profile_r * 0.82 * flute)
			var off_in := right * (cos(a) * inner_r) + normal_dir * (sin(a) * inner_r * 0.82)
			outer_grid.append(spine + off_out)
			inner_grid.append(spine + off_in)

	var tail_sp := _strand_params(params, "tail_", {"strand_width": 0.042, "strand_gap": -0.004,
		"tip_taper": 0.55, "cut_mode": "radial", "cut_span": 0.28, "wavy_freq": 1.5})
	var min_t := _build_strand_locks(hair_root, "HighPonytail", outer_grid, inner_grid, rings, cols, color, tail_sp, true)
	_build_tube_core(hair_root, "HighPonytailCore", inner_grid, rings, cols, min_t, color, mount_pos)


# #03: 温柔披肩半扎长发 (Half-Up Flowing Long Hair)
static func build_hair_03_half_up_long(doll: Node3D, params: Dictionary = {}) -> void:
	var hair_root := clear_hair_slot(doll)
	var color: Color = params.get("color", Color(0.24, 0.17, 0.14))
	var accent: Color = params.get("accent", Color("e4c97a"))
	var raw_len: float = params.get("hair_length", params.get("length", 0.62))
	var hair_length: float = clampf(raw_len, 0.44, 0.82)
	var wave_amp: float = clampf(params.get("wave_amp", 0.024), 0.005, 0.050)
	var raw_spread: float = params.get("back_spread", 0.35)
	var back_spread: float = clampf(raw_spread if raw_spread > 0.22 else 0.26 + raw_spread * 0.75, 0.28, 0.44)
	var crown_bun_size: float = clampf(params.get("crown_bun_size", 0.068), 0.045, 0.095)

	build_base_scalp_cap(hair_root, color, 1.00, 2.24, 1.03, 0.0)
	var bang_sp := _strand_params(params, "bang_", _BANG_STRAND_DEFAULTS)
	build_front_bangs(hair_root, color, 0.382, 0.020, 0.16, 0.0, 0.16, bang_sp)

	# 1. Flowing long hair mantle guide grid with continuous 3D ellipsoidal cranial dome
	var cols := 52
	var rows := 30
	var outer_grid := PackedVector3Array()
	var inner_grid := PackedVector3Array()
	var head_cy := 0.290
	var R_x := 0.276 * 1.02 + 0.005
	var R_y := 0.304 * 1.02 + 0.006 # apex at 0.606
	var R_z := 0.294 * 1.02 + 0.005
	var bottom_y := 0.36 - hair_length
	var dome_ratio := 0.32

	for r in rows + 1:
		var t := float(r) / rows
		var local_y: float
		var base_rx: float
		var base_rz: float
		var wall_thick: float
		var z_drape := 0.0

		if t <= dome_ratio:
			var dt := t / dome_ratio
			var phi := lerpf(0.08, 1.44, pow(dt, 0.94))
			local_y = head_cy + R_y * cos(phi)
			var ring := sin(phi)
			base_rx = R_x * ring
			base_rz = R_z * ring
			wall_thick = lerpf(0.006, 0.022, smoothstep(0.0, 0.8, dt))
			z_drape = -0.010 * ring
		else:
			var lt := (t - dome_ratio) / (1.0 - dome_ratio)
			local_y = lerpf(head_cy + R_y * cos(1.44), bottom_y, lt)
			var wave_z := wave_amp * sin(lt * PI * 2.6) * smoothstep(0.05, 0.45, lt)
			var width := lerpf(0.298, back_spread, smoothstep(0.0, 0.68, lt)) * (1.0 - 0.10 * pow(lt, 3.0))
			base_rx = width
			base_rz = 0.312 + 0.030 * sin(lt * PI)
			wall_thick = lerpf(0.022, 0.014, lt)
			z_drape = -0.014 - 0.045 * smoothstep(0.15, 0.65, lt) + wave_z

		for c in cols + 1:
			var u := float(c) / cols
			var angle := lerpf(0.72, TAU - 0.72, u)
			var lock_ripple := 0.006 * cos(u * PI * 12.0) * sin(clampf((t - 0.20) / 0.80, 0.0, 1.0) * PI)
			var y_wave := local_y + 0.015 * cos((u - 0.5) * PI) * clampf((t - 0.25) / 0.75, 0.0, 1.0)
			var min_env := _head_neck_min_radii(y_wave, angle, true)

			var in_rx := maxf(min_env.x, base_rx - wall_thick)
			var in_rz := maxf(min_env.y, base_rz - wall_thick)
			var out_rx := maxf(in_rx + 0.006, base_rx + lock_ripple)
			var out_rz := maxf(in_rz + 0.006, base_rz + lock_ripple)

			outer_grid.append(Vector3(sin(angle) * out_rx, y_wave, cos(angle) * out_rz + z_drape))
			inner_grid.append(Vector3(sin(angle) * in_rx, y_wave, cos(angle) * in_rz + z_drape))

	var mantle_sp := _strand_params(params, "mantle_", {"strand_width": 0.048, "strand_gap": 0.0,
		"cut_mode": "symmetric", "cut_span": 0.35, "wavy": wave_amp, "wavy_freq": 2.2})
	_build_strand_locks(hair_root, "LongWavyMantle", outer_grid, inner_grid, rows, cols, color, mantle_sp, false)

	# 2. Side braids: interwoven 3-strand braid by default, or simple smooth twist fallback (braid_style: "simple")
	var braid_mode: String = String(params.get("braid_style", "three_strand"))
	var three_strand: bool = bool(params.get("three_strand_braid", braid_mode != "simple"))

	for side: float in [-1.0, 1.0]:
		if not three_strand:
			# Backward-compatibility: original simple smooth twist tube
			var lock_pts := PackedVector3Array()
			var lock_r := PackedFloat32Array()
			for i in 15:
				var s := float(i) / 14.0
				var a := lerpf(side * 1.12, side * PI, s)
				lock_pts.append(Vector3(sin(a) * 0.314, lerpf(0.35, 0.30, s) + 0.010 * sin(s * PI * 4.0), cos(a) * 0.330 - 0.014))
				lock_r.append(lerpf(0.026, 0.034, sin(s * PI)))
			add_tube(hair_root, "HalfUpTwistL" if side < 0 else "HalfUpTwistR", lock_pts, lock_r, color.lightened(0.05), 10)
		else:
			# Continuous delicate interwoven 3-strand side braids meeting at back center
			var p_start := Vector3(side * 0.258, 0.358, 0.090)
			var p_mid := Vector3(side * 0.284, 0.334, -0.115)
			var p_end := Vector3(side * 0.035, 0.315, -0.320)
			var steps := 36
			var freq := 5.0 * TAU
			for strand in 3:
				var strand_phase := float(strand) * TAU / 3.0
				var pts := PackedVector3Array()
				var rads := PackedFloat32Array()
				for i in steps + 1:
					var u := float(i) / steps
					var p_guide := (1.0 - u) * (1.0 - u) * p_start + 2.0 * (1.0 - u) * u * p_mid + u * u * p_end
					var tangent := (2.0 * (1.0 - u) * (p_mid - p_start) + 2.0 * u * (p_end - p_mid)).normalized()
					var n_head := (p_guide - Vector3(0.0, 0.290, 0.0)).normalized()
					var binormal := tangent.cross(n_head).normalized()

					var phase := u * freq + strand_phase
					var width := 0.016 * (1.0 - 0.25 * u)
					var off_b := binormal * (cos(phase) * width)
					var off_n := n_head * (sin(2.0 * phase) * 0.007 + 0.012)
					var p_strand := p_guide + off_b + off_n
					p_strand = _push_outside_head(p_strand, 0.004)
					pts.append(p_strand)
					rads.append(lerpf(0.010, 0.013, sin(u * PI)))
				var tint := 0.04 * (float(strand) - 1.0)
				var strand_color := color.lightened(tint) if tint > 0.0 else color.darkened(-tint)
				add_tube(hair_root, "HalfUpBraid_%s_Strand%d" % ["L" if side < 0 else "R", strand],
					pts, rads, strand_color, 8)

		add_ellipsoid(hair_root, "HalfUpBowLoop", Vector3(side * 0.058, 0.285, -0.352), Vector3(0.052, 0.032, 0.018), accent, false, Vector3(0, 0, side * 0.25))

	add_ellipsoid(hair_root, "HalfUpCrownBun", Vector3(0.0, 0.325, -0.345), Vector3(crown_bun_size, crown_bun_size * 0.88, crown_bun_size * 0.82), color.lightened(0.03))
	add_ellipsoid(hair_root, "HalfUpBowKnot", Vector3(0.0, 0.285, -0.360), Vector3(0.024, 0.024, 0.020), accent.darkened(0.12))


# #04: 芭蕾高丸子头 / 花苞头 (Topknot Bun with Crown-to-Nape Sliding Positioning)
static func build_hair_04_topknot_bun(doll: Node3D, params: Dictionary = {}) -> void:
	var hair_root := clear_hair_slot(doll)
	var color: Color = params.get("color", Color(0.24, 0.17, 0.14))
	var accent: Color = params.get("ribbon_color", params.get("accent", Color("72a498")))
	var bun_radius: float = clampf(params.get("bun_radius", 0.142), 0.05, 0.21)
	var raw_bh: float = params.get("bun_height", 0.115)
	var bun_v_radius: float = (raw_bh if raw_bh < 0.35 else bun_radius * 0.82)
	var bun_pos: float = clampf(params.get("bun_position", params.get("bun_pos", 0.0)), 0.0, 1.0)
	var wisp_length: float = clampf(params.get("wisp_length", params.get("side_wisps", 0.17)), 0.08, 0.26)

	build_base_scalp_cap(hair_root, color, 1.00, 2.30, 1.02, 0.0)
	var bang_sp := _strand_params(params, "bang_", _BANG_STRAND_DEFAULTS)
	build_front_bangs(hair_root, color, 0.384, 0.022, 0.08, 0.0, wisp_length, bang_sp)

	# Sagittal skull trajectory: beta = 0.14 (high topknot) .. 1.95 (low nape bun)
	var beta := lerpf(0.14, 1.95, bun_pos)
	var mount_y := 0.290 + 0.306 * cos(beta)
	var mount_z := -0.296 * sin(beta)
	var mount_pos := Vector3(0.0, mount_y, mount_z)

	var n_raw := Vector3(0.0, cos(beta) / 0.306, -sin(beta) / 0.296)
	var normal_dir := n_raw.normalized()
	var u_dir := Vector3.RIGHT
	var v_dir := normal_dir.cross(u_dir).normalized()

	var bun_center := mount_pos + normal_dir * (bun_v_radius * 0.85)

	# Helical flower-bud bun oriented along surface normal
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var r_steps := 18
	var c_steps := 36
	for r in r_steps + 1:
		var phi := PI * float(r) / r_steps
		for c in c_steps + 1:
			var theta := TAU * float(c) / c_steps
			var twist := 1.0 + 0.075 * sin(theta * 5.0 + phi * 3.0) * sin(phi)
			var p_local := u_dir * (sin(phi) * sin(theta) * bun_radius * twist) \
				+ v_dir * (sin(phi) * cos(theta) * bun_radius * twist) \
				+ normal_dir * (cos(phi) * bun_v_radius)
			var p := bun_center + p_local
			p = _push_outside_head(p, 0.002)
			vertices.append(p)
	for r in r_steps:
		for c in c_steps:
			var a := r * (c_steps + 1) + c
			var b := a + c_steps + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, bun_center)
	build_mesh_instance(hair_root, "CrownTopknotBun", vertices, compute_welded_normals(vertices, indices), indices, color)

	# Adaptive surface-snapped ribbon collar wrapping around bun base
	_build_adaptive_hair_tie(hair_root, "BunRibbonWrap", mount_pos, normal_dir, bun_radius * 0.90, 0.018, accent, 14, 0.10)


# #05: 偏分大波浪锁骨发 (Side-Parted Wavy Lob)
static func build_hair_05_wavy_lob(doll: Node3D, params: Dictionary = {}) -> void:
	var hair_root := clear_hair_slot(doll)
	var color: Color = params.get("color", Color(0.24, 0.17, 0.14))
	var part_side: float = clampf(params.get("part_side", -0.11), -0.16, 0.16)
	var raw_len: float = params.get("lob_length", params.get("length", 0.44))
	var lob_length: float = clampf(raw_len, 0.32, 0.58)
	var wave_depth: float = clampf(params.get("wave_depth", params.get("wave_amp", 0.032)), 0.010, 0.058)
	var wave_freq: float = clampf(params.get("wave_freq", 2.4), 1.8, 4.2)
	var flip_out: float = clampf(params.get("flip_out", 0.048), 0.0, 0.10)

	build_base_scalp_cap(hair_root, color, 1.00, 2.24, 1.03, part_side)
	var bang_sp := _strand_params(params, "bang_", _BANG_STRAND_DEFAULTS)
	build_front_bangs(hair_root, color, 0.382, 0.016, 0.22, part_side * 3.0, 0.18, bang_sp)

	# Continuous 3D ellipsoidal cranial dome + S-wave lob canopy guide grid
	var cols := 60
	var rows := 28
	var outer_grid := PackedVector3Array()
	var inner_grid := PackedVector3Array()
	var head_cy := 0.290
	var R_x := 0.276 * 1.02 + 0.005
	var R_y := 0.304 * 1.02 + 0.006 # apex at 0.606
	var R_z := 0.294 * 1.02 + 0.005
	var bottom_y := 0.34 - lob_length
	var dome_ratio := 0.34

	for r in rows + 1:
		var t := float(r) / rows
		var local_y: float
		var base_rx: float
		var base_rz: float
		var wall_thick: float
		var z_shift := 0.0

		if t <= dome_ratio:
			var dt := t / dome_ratio
			var phi := lerpf(0.08, 1.45, pow(dt, 0.94))
			local_y = head_cy + R_y * cos(phi)
			var ring := sin(phi)
			base_rx = R_x * ring
			base_rz = R_z * ring
			wall_thick = lerpf(0.006, 0.022, smoothstep(0.0, 0.8, dt))
			z_shift = -0.010 * ring
		else:
			var lt := (t - dome_ratio) / (1.0 - dome_ratio)
			local_y = lerpf(head_cy + R_y * cos(1.45), bottom_y, lt)
			var s_wave := wave_depth * sin(lt * PI * wave_freq) * smoothstep(0.0, 0.25, lt)
			var tip_flip := flip_out * pow(maxf(0.0, (lt - 0.60) / 0.40), 1.6)
			base_rx = R_x + 0.040 * sin(lt * PI) + s_wave + tip_flip
			base_rz = R_z + 0.030 * sin(lt * PI) + (s_wave + tip_flip) * 0.65
			wall_thick = lerpf(0.022, 0.014, lt)
			z_shift = -0.010 - 0.025 * smoothstep(0.25, 0.85, lt)

		for c in cols + 1:
			var u := float(c) / cols
			var angle := lerpf(0.60, TAU - 0.60, u)
			var asym := 0.016 * sin(angle) * signf(-part_side) * sin(clampf((t - 0.20) / 0.80, 0.0, 1.0) * PI)
			var flute := 1.0 + 0.008 * cos(u * PI * 14.0 + t * 2.0) * sin(clampf((t - 0.15) / 0.85, 0.0, 1.0) * PI)
			var min_env := _head_neck_min_radii(local_y, angle, true)

			var in_rx := maxf(min_env.x, (base_rx + asym) - wall_thick)
			var in_rz := maxf(min_env.y, base_rz - wall_thick)
			var out_rx := maxf(in_rx + 0.006, (base_rx + asym) * flute)
			var out_rz := maxf(in_rz + 0.006, base_rz * flute)

			outer_grid.append(Vector3(sin(angle) * out_rx, local_y, cos(angle) * out_rz + z_shift))
			inner_grid.append(Vector3(sin(angle) * in_rx, local_y, cos(angle) * in_rz + z_shift))

	var lob_sp := _strand_params(params, "lob_", {"strand_width": 0.048, "strand_gap": 0.0,
		"tip_taper": 0.55, "cut_mode": "symmetric", "cut_span": 0.36, "wavy": wave_depth, "wavy_freq": wave_freq})
	_build_strand_locks(hair_root, "WavyLobCanopy", outer_grid, inner_grid, rows, cols, color, lob_sp, false)


# #06: 活力双马尾 (Playful High Twin Pigtails)
static func build_hair_06_twin_pigtails(doll: Node3D, params: Dictionary = {}) -> void:
	var hair_root := clear_hair_slot(doll)
	var color: Color = params.get("color", Color(0.24, 0.17, 0.14))
	var accent: Color = params.get("accent", Color("d87a68"))
	var mount_y: float = clampf(params.get("mount_y", params.get("mount_height", 0.42)), 0.32, 0.52)
	var mount_x: float = clampf(params.get("mount_x", 0.270), 0.23, 0.31)
	var tail_length: float = clampf(params.get("tail_length", 0.48), 0.28, 0.68)
	var bounce_flare: float = clampf(params.get("bounce_flare", 0.15), 0.08, 0.24)

	var expose_ears: bool = bool(params.get("expose_ears", true))
	# 1. Scalp cap with ear cutout so ears emerge naturally from skull skin
	build_base_scalp_cap(hair_root, color, 1.00, 2.30, 1.02, 0.0, expose_ears)
	# 2. Front bangs stay neatly on forehead without dropping over ears
	var bang_sp := _strand_params(params, "bang_", _BANG_STRAND_DEFAULTS)
	var bang_drop: float = (0.04 if expose_ears else 0.16)
	build_front_bangs(hair_root, color, 0.380, 0.020, 0.12, 0.0, bang_drop, bang_sp)
	# 3. Dedicated ear-front sideburn locks
	if expose_ears:
		_build_ear_front_sideburns(hair_root, color, 0.14)

	for side: float in [-1.0, 1.0]:
		# Compute mount point directly on skull surface
		var dy := clampf((mount_y - 0.290) / 0.306, -0.90, 0.90)
		var dx := clampf(mount_x / 0.278, 0.20, 0.94)
		var rem_z := sqrt(maxf(0.02, 1.0 - dy * dy - dx * dx))
		var mount_pos := Vector3(side * mount_x, mount_y, -0.296 * rem_z)
		var n_skull := Vector3(side * dx / 0.278, dy / 0.306, -rem_z / 0.296).normalized()
		var tail_tan := (n_skull + Vector3(side * 0.35, 0.16, -0.24)).normalized()

		# Surface-snapped adaptive hair tie
		_build_adaptive_hair_tie(hair_root, "TwinTie" + ("L" if side < 0 else "R"),
			mount_pos, tail_tan, 0.046, 0.018, accent, 8, 0.12)

		# Guide tube grid around arching pigtail spine
		var rings := 22
		var cols := 14
		var outer_grid := PackedVector3Array()
		var inner_grid := PackedVector3Array()

		var spine_pts: Array[Vector3] = []
		for i in rings + 1:
			var t := float(i) / rings
			var spine := Vector3(
				mount_pos.x + side * (0.042 * sin(t * PI * 0.5) + bounce_flare * sin(t * PI * 0.74) + 0.065 * t),
				mount_pos.y + 0.055 * sin(t * PI * 0.42) - tail_length * pow(t, 1.25),
				mount_pos.z - 0.045 * sin(t * PI) + 0.03 * pow(t, 2.0)
			)
			spine_pts.append(spine)

		for i in rings + 1:
			var t := float(i) / rings
			var spine: Vector3 = spine_pts[i]
			var next_spine: Vector3 = (spine_pts[i + 1] if i < rings else spine_pts[i] + Vector3(side * 0.02, -0.05, 0))
			var tangent := (next_spine - spine).normalized()
			if tangent.length_squared() < 0.001:
				tangent = Vector3.DOWN
			var right := Vector3.RIGHT
			var normal_dir := right.cross(tangent).normalized()
			var profile_r := lerpf(0.042, 0.092, sin(pow(t, 0.68) * PI)) * (1.0 - 0.75 * pow(t, 2.8))
			profile_r = maxf(0.010, profile_r)
			var inner_r := profile_r * 0.72

			for c in cols + 1:
				var a := TAU * float(c) / cols
				var flute := 1.0 + 0.08 * cos(a * 4.0 + t * 2.5) * sin(t * PI)
				var off_out := right * (cos(a) * profile_r * flute) + normal_dir * (sin(a) * profile_r * 0.82 * flute)
				var off_in := right * (cos(a) * inner_r) + normal_dir * (sin(a) * inner_r * 0.82)
				outer_grid.append(spine + off_out)
				inner_grid.append(spine + off_in)

		var pig_sp := _strand_params(params, "pigtail_", {"strand_width": 0.038, "strand_gap": -0.003,
			"tip_taper": 0.55, "cut_mode": "radial", "cut_span": 0.25})
		var label := "TwinPigtail" + ("L" if side < 0 else "R")
		var min_t := _build_strand_locks(hair_root, label, outer_grid, inner_grid, rings, cols, color, pig_sp, true)
		_build_tube_core(hair_root, label + "Core", inner_grid, rings, cols, min_t, color, mount_pos)



# ============================================================================
# SHARED GARMENT HELPERS FOR V20 SHORT-ARM MANNEQUIN
# ============================================================================

static func _clear_doll_garment_nodes(doll: Node3D, remove_trouser: bool = false, slot_tag: String = "") -> void:
	var br := _resolve_body_rig(doll)
	var cr := _resolve_clothes_root(doll)
	if not slot_tag.is_empty():
		# Non-destructive modular slot removal: clears ONLY nodes tagged for this slot
		for child in cr.get_children():
			if child.get_meta("garment_slot", "") == slot_tag or child.name == ("SlotGarment_" + slot_tag):
				child.free()
		if slot_tag in ["top", "outer"]:
			for arm_name in ["ArmLeft", "ArmRight"]:
				var arm := br.get_node_or_null(arm_name)
				if arm == null: continue
				for sub in arm.get_children():
					if sub.get_meta("garment_slot", "") == slot_tag:
						sub.free()
		if slot_tag == "bottom":
			for leg_name in ["LegLeft", "LegRight"]:
				var leg := br.get_node_or_null(leg_name)
				if leg == null: continue
				for sub in leg.get_children():
					if str(sub.name).begins_with("CustomShortsLeg"):
						sub.free()
					elif str(sub.name).begins_with("Trouser"):
						if remove_trouser:
							sub.free()
						else:
							sub.visible = true
		return

	# Full wipe (original default behavior):
	for child in cr.get_children():
		if not remove_trouser and str(child.name) in ["TrouserWaistband", "TrouserSeat"]:
			continue
		child.free()
	if "_garment" in doll:
		doll.set("_garment", null)
	for arm_name in ["ArmLeft", "ArmRight"]:
		var arm := br.get_node_or_null(arm_name)
		if arm == null:
			continue
		for sub in arm.get_children():
			if str(sub.name) in ["ArmMannequin", "ArmMannequinThumb"]:
				continue
			sub.free()
	for leg_name in ["LegLeft", "LegRight"]:
		var leg := br.get_node_or_null(leg_name)
		if leg == null:
			continue
		for sub in leg.get_children():
			if str(sub.name).begins_with("CustomShortsLeg"):
				sub.free()
			elif str(sub.name).begins_with("Trouser"):
				if remove_trouser:
					sub.free()
				else:
					sub.visible = true

# Anatomical neckline height around torso angle `a` (cos(a)=±1 at sides ±X, sin(a)=+1 at front +Z, -1 at back -Z)
# Real garment necklines are NEVER parallel to the ground: back neck (C7) sits high (~1.908), side neck (SNP) sits at ~1.886,
# and front neckline (clavicle hollow) dips naturally lower (~1.805..1.840 for crew/mock/round, or deeper for scoop/V)!
static func _anatomical_neck_y(angle: float, y_back: float = 1.908, y_side: float = 1.885, y_front: float = 1.808) -> float:
	var sa := sin(angle) # +1 front (+Z), -1 back (-Z)
	if sa >= 0.0:
		return lerpf(y_side, y_front, pow(clampf(sa, 0.0, 1.0), 1.25))
	else:
		return lerpf(y_side, y_back, pow(clampf(-sa, 0.0, 1.0), 1.15))


# Natural human shoulder slope: drops smoothly from the side-neck point (|x| ~ 0.088) outward toward the acromion/deltoid (|x| ~ 0.195)
static func _anatomical_shoulder_drop(px: float, max_drop: float = 0.056) -> float:
	var st := clampf((absf(px) - 0.086) / 0.112, 0.0, 1.0)
	return max_drop * pow(st, 1.15)


# Shrinkwrap + Extrude a 2D surface grid (rows+1 x cols+1) along its outward normals:
# Outer face sits at +extrude_out, while inner face is embedded -embed_in into the host garment so trims NEVER float!
static func _build_extruded_surface_strip(parent: Node3D, label: String, base_grid: PackedVector3Array,
		rows: int, cols: int, extrude_out: float, embed_in: float, interior_ref: Vector3, color: Color) -> MeshInstance3D:
	var stride := cols + 1
	var count := (rows + 1) * stride
	var base_inds := PackedInt32Array()
	for r in rows:
		for c in cols:
			var a := r * stride + c
			var b := a + stride
			emit_quad_outward(base_grid, base_inds, a, a + 1, b + 1, b, interior_ref)
	var base_normals := compute_welded_normals(base_grid, base_inds)

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in count:
		vertices.append(base_grid[i] + base_normals[i] * extrude_out)
	for i in count:
		vertices.append(base_grid[i] - base_normals[i] * embed_in)

	for r in rows:
		for c in cols:
			var a := r * stride + c
			var b := a + stride
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, interior_ref)
			var ia := count + a
			var ib := count + b
			emit_quad_outward(vertices, indices, ia, ib, ib + 1, ia + 1, base_grid[a] * 2.0 - interior_ref)

	# Close all 4 perimeter bevel walls back into the embedded inner surface
	for c in cols:
		var t0 := c
		var b0 := count + t0
		emit_quad_outward(vertices, indices, t0, t0 + 1, b0 + 1, b0, interior_ref)
		var t1 := rows * stride + c
		var b1 := count + t1
		emit_quad_outward(vertices, indices, t1, b1, b1 + 1, t1 + 1, interior_ref)
	for r in rows:
		var l0 := r * stride
		var lb0 := count + l0
		emit_quad_outward(vertices, indices, l0, lb0, lb0 + stride, l0 + stride, interior_ref)
		var r0 := r * stride + cols
		var rb0 := count + r0
		emit_quad_outward(vertices, indices, r0, r0 + stride, rb0 + stride, rb0, interior_ref)

	return build_mesh_instance(parent, label, vertices, compute_welded_normals(vertices, indices), indices, color, 0.85, 0.0003)


# Bilinearly sample a UV sub-patch [v0, v1] x [u0, u1] directly from a host mesh grid and extrude it along the surface normals
static func _extrude_uv_strip_from_grid(parent: Node3D, label: String, host_grid: PackedVector3Array,
		host_rows: int, host_cols: int, v0: float, v1: float, u0: float, u1: float,
		sub_rows: int, sub_cols: int, extrude_out: float, embed_in: float,
		interior_ref: Vector3, color: Color) -> MeshInstance3D:
	var h_stride := host_cols + 1
	var sub_grid := PackedVector3Array()
	for ir in sub_rows + 1:
		var vt := lerpf(v0, v1, float(ir) / float(maxi(1, sub_rows)))
		var rf := clampf(vt * float(host_rows), 0.0, float(host_rows))
		var r0 := mini(int(floor(rf)), host_rows - 1)
		var r1 := r0 + 1
		var rt := rf - float(r0)
		for ic in sub_cols + 1:
			var ut := lerpf(u0, u1, float(ic) / float(maxi(1, sub_cols)))
			var cf := clampf(ut * float(host_cols), 0.0, float(host_cols))
			var c0 := mini(int(floor(cf)), host_cols - 1)
			var c1 := c0 + 1
			var ct := cf - float(c0)
			var p00 := host_grid[r0 * h_stride + c0]
			var p01 := host_grid[r0 * h_stride + c1]
			var p10 := host_grid[r1 * h_stride + c0]
			var p11 := host_grid[r1 * h_stride + c1]
			var p0 := p00.lerp(p01, ct)
			var p1 := p10.lerp(p11, ct)
			sub_grid.append(p0.lerp(p1, rt))
	return _build_extruded_surface_strip(parent, label, sub_grid, sub_rows, sub_cols, extrude_out, embed_in, interior_ref, color)


static func _build_v20_sleeve_pair(doll: Node3D, node_name: String, color: Color, y_top: float, y_bottom: float,
		top_ease: float, bottom_ease: float, puff_amount: float = 0.0,
		cuff_color: Color = Color(0, 0, 0, 0), cuff_height: float = 0.0,
		roughness: float = 0.88, wobble: float = 0.0005) -> void:
	var br := _resolve_body_rig(doll)
	var rings := 18
	var sides := 28
	for side_idx in 2:
		var arm_name := "ArmLeft" if side_idx == 0 else "ArmRight"
		var side_sign := -1.0 if side_idx == 0 else 1.0
		var arm := br.get_node_or_null(arm_name) as Node3D
		if arm == null:
			continue
		var sleeve_root := Node3D.new()
		sleeve_root.name = node_name
		arm.add_child(sleeve_root)

		var sleeve_grid := PackedVector3Array()
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		for i in rings + 1:
			var t := float(i) / rings
			var y := lerpf(y_top, y_bottom, t)
			var slice := v20_arm_slice(y)
			var cx: float = side_sign * float(slice["cx"])
			var ease_here := lerpf(top_ease, bottom_ease, t)
			var puff_here := puff_amount * pow(sin(t * PI), 0.82)
			var rx: float = float(slice["rx"]) + ease_here + puff_here
			var rz: float = float(slice["rz"]) + ease_here + puff_here * 0.92
			var shoulder_tuck := clampf(1.0 - t / 0.28, 0.0, 1.0)
			for s in sides + 1:
				var a := TAU * float(s) / sides
				var ca := cos(a)
				var sa := sin(a)
				var gather_wave := 1.0 + (0.045 * cos(a * 8.0) * sin(t * PI) if puff_amount > 0.015 else 0.0)
				var px := cx + ca * rx * gather_wave
				var pz := sa * rz * gather_wave + float(slice["z"])
				var py := y
				var outer_ness := clampf(ca * side_sign, 0.0, 1.0)
				var inner_ness := clampf(-ca * side_sign, 0.0, 1.0)
				py += shoulder_tuck * (0.028 * outer_ness - 0.024 * inner_ness)
				# Natural angled sleeve opening perpendicular to the slight outward arm hang
				py -= (1.0 - shoulder_tuck) * 0.008 * outer_ness
				px -= side_sign * shoulder_tuck * 0.018 * outer_ness
				var pt := Vector3(px, py, pz)
				sleeve_grid.append(pt)
				vertices.append(pt)

		for i in rings:
			for s in sides:
				var a := i * (sides + 1) + s
				var b := a + sides + 1
				var mid_y := lerpf(y_top, y_bottom, (i + 0.5) / rings)
				var mid_sl := v20_arm_slice(mid_y)
				emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, Vector3(side_sign * float(mid_sl["cx"]), mid_y, float(mid_sl["z"])))

		# Thick hem fold ring at bottom of sleeve returning cleanly to the arm surface
		var bottom_ring_start := rings * (sides + 1)
		var inner_ring_start := vertices.size()
		var slice_bot := v20_arm_slice(y_bottom)
		var bot_cx: float = side_sign * float(slice_bot["cx"])
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var rx_in: float = float(slice_bot["rx"]) + 0.003
			var rz_in: float = float(slice_bot["rz"]) + 0.003
			vertices.append(Vector3(bot_cx + cos(a) * rx_in, y_bottom + 0.003, sin(a) * rz_in + float(slice_bot["z"])))
		for s in sides:
			emit_quad_outward(vertices, indices, bottom_ring_start + s, bottom_ring_start + s + 1,
				inner_ring_start + s + 1, inner_ring_start + s, Vector3(bot_cx, y_bottom + 0.05, float(slice_bot["z"])))

		build_mesh_instance(sleeve_root, "SleeveMesh", vertices,
			compute_welded_normals(vertices, indices), indices, color, roughness, wobble)

		# Extrude SleeveCuff directly from the bottom rings of sleeve_grid so cuff is 100% welded to the sleeve body!
		if cuff_height > 0.004 and cuff_color.a > 0.01:
			var total_span := maxf(0.05, absf(y_top - y_bottom))
			var v0 := clampf(1.0 - cuff_height / total_span, 0.55, 0.94)
			_extrude_uv_strip_from_grid(sleeve_root, "SleeveCuff", sleeve_grid, rings, sides,
				v0, 1.0, 0.0, 1.0, 5, sides, 0.0045, 0.0020,
				Vector3(bot_cx, y_bottom + cuff_height * 0.5, float(slice_bot["z"])), cuff_color)


# ============================================================================
# CATEGORY 2: REMADE CORE GARMENTS (#07 - #09) ON V20 SHORT-ARM MANNEQUIN
# ============================================================================

# Helper: extrude a 2D surface grid (rows+1 x cols+1) along its outward normals into a solid 3D flat-folded collar/lapel slab
static func _build_thick_collar_slab(parent: Node3D, label: String, top_grid: PackedVector3Array,
		rows: int, cols: int, thickness: float, interior_ref: Vector3, color: Color) -> MeshInstance3D:
	return _build_extruded_surface_strip(parent, label, top_grid, rows, cols, thickness * 0.55, thickness * 0.45, interior_ref, color)


# #07 古巴领重制版 (Cuban Collar Camp Shirt Remake)
# Adjustable: garment_length (0..1 moves hem only), collar_spread (0.7..1.45),
# sleeve_length (0.18..0.42), body_ease (0.018..0.052), pocket_enabled (bool)
static func build_garment_07_cuban_shirt_remake(doll: Node3D, params: Dictionary = {}) -> Node3D:
	var remove_tr: bool = params.get("remove_trouser", false)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "top" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var shirt_color: Color = params.get("color", Color(0.84, 0.89, 0.82))
	var collar_color: Color = params.get("collar_color", shirt_color.lightened(0.09))
	var trim_color: Color = params.get("trim_color", shirt_color.darkened(0.22))
	var button_color: Color = params.get("button_color", Color(0.94, 0.90, 0.82))
	var garment_length: float = clampf(params.get("garment_length", 0.52), 0.0, 1.0)
	var collar_spread: float = clampf(params.get("collar_spread", 1.05), 0.72, 1.45)
	var sleeve_length: float = clampf(params.get("sleeve_length", 0.27), 0.16, 0.42)
	var body_ease: float = clampf(params.get("body_ease", 0.028), 0.016, 0.052)
	var pocket_enabled: bool = params.get("pocket_enabled", true)

	var hem_y := lerpf(1.36, 1.06, garment_length)
	var v_open_bottom_y := 1.635

	# Shared parametric surface evaluator for Cuban Shirt Torso so all collars, lapels, plackets & pockets shrinkwrap with 0mm gap
	# Note: y = 1.78..1.934 is the sloping shoulder ("自然溜肩"), and y = 1.934 is the true short neck root!
	var eval_cuban_radii := func(y: float) -> Vector3:
		var sl := v20_torso_slice(y)
		var ch_sl := v20_torso_slice(1.62)
		var boxy_b := clampf((1.62 - y) / 0.42, 0.0, 1.0) * 0.55
		var t_approx := clampf((y - hem_y) / maxf(0.1, 1.934 - hem_y), 0.0, 1.0)
		var shoulder_taper := smoothstep(1.80, 1.934, y)
		var ease_y := lerpf(body_ease + 0.008 * (1.0 - t_approx), 0.016, shoulder_taper)
		var rx := lerpf(float(sl["rx"]), float(ch_sl["rx"]), boxy_b) + ease_y
		var rz := lerpf(float(sl["rz"]), float(ch_sl["rz"]), boxy_b * 0.75) + ease_y * 0.92
		return Vector3(rx, rz, float(sl["z"]))

	var eval_cuban_front_z := func(px: float, py: float) -> float:
		var r_vec: Vector3 = eval_cuban_radii.call(py)
		var nx := clampf(px / maxf(0.04, r_vec.x + 0.012), -0.97, 0.97)
		return r_vec.z + r_vec.y * sqrt(maxf(0.04, 1.0 - nx * nx))

	# 1. Main boxy camp-shirt torso shell covering the sloping shoulders all the way to the short neck root (top_y = 1.932)
	var top_y := 1.932
	var rings := 32
	var sides := 48
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(hem_y, top_y, t)
		var r_vec: Vector3 = eval_cuban_radii.call(y)
		var v_open_ang := 0.0
		if y > v_open_bottom_y:
			var vt := clampf((y - v_open_bottom_y) / (top_y - v_open_bottom_y), 0.0, 1.0)
			v_open_ang = lerpf(0.01, 0.72, pow(vt, 0.88))

		var start_ang := PI * 0.5 - v_open_ang
		var end_ang := -PI * 1.5 + v_open_ang
		for s in sides + 1:
			var u := float(s) / sides
			var a := lerpf(start_ang, end_ang, u)
			var back_rise := 0.010 * maxf(0.0, -sin(a)) * pow(t, 2.0)
			var px := cos(a) * r_vec.x
			var pz := sin(a) * r_vec.y + r_vec.z
			vertices.append(Vector3(px, y + back_rise, pz))

	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, Vector3(0, lerpf(hem_y, top_y, (i + 0.5) / rings), 0))

	build_mesh_instance(root, "CubanTorsoShell", vertices,
		compute_welded_normals(vertices, indices), indices, shirt_color, 0.87, 0.0005)

	# 2. Solid 3D Folded Cuban Camp Collar at the Short Neck Root (y = 1.925..1.958) with Extruded Border Stitching:
	var back_stand_grid := PackedVector3Array()
	var bs_rows := 5
	var bs_cols := 22
	for r in bs_rows + 1:
		var vt := float(r) / bs_rows
		var cy := lerpf(1.922, 1.956, vt)
		var r_vec: Vector3 = eval_cuban_radii.call(cy)
		for c in bs_cols + 1:
			var ut := float(c) / bs_cols
			var ang := lerpf(PI * 0.14, -PI * 1.14, ut)
			var flare := 0.006 + 0.006 * sin(vt * PI)
			back_stand_grid.append(Vector3(cos(ang) * (r_vec.x + flare), cy, sin(ang) * (r_vec.y + flare) + r_vec.z))
	_build_extruded_surface_strip(root, "CubanBackCollarStand", back_stand_grid, bs_rows, bs_cols, 0.0050, 0.0030, Vector3(0, 1.93, 0), collar_color)

	for side_sign: float in [-1.0, 1.0]:
		# (A) Upper Cuban Collar Leaf (上领片): sits cleanly proud (+7mm..+11mm) on top of shirt chest/shoulder with extruded border stitch
		var upper_grid := PackedVector3Array()
		var u_cols := 16
		var u_rows := 8
		var gorge_y := 1.795

		for iv in u_rows + 1:
			var vt := float(iv) / u_rows # 0 = neck fold crease, 1 = outer leaf edge
			for iu in u_cols + 1:
				var ut := float(iu) / u_cols # 0 = shoulder neck crest, 1 = front gorge line
				var inner_x := side_sign * lerpf(0.088, 0.062, pow(ut, 0.90))
				var inner_y := lerpf(1.942, gorge_y, pow(ut, 0.92))

				var tip_profile := sin(clampf(ut / 0.84, 0.0, 1.0) * PI * 0.5)
				var notch_recess := smoothstep(0.82, 1.0, ut)
				var span_w := lerpf(0.056, 0.108 * collar_spread, tip_profile) * (1.0 - 0.46 * notch_recess)
				var outer_x := inner_x + side_sign * span_w
				var outer_y := inner_y - lerpf(0.028, 0.056 * collar_spread, tip_profile) * (1.0 - 0.68 * notch_recess)

				var px := lerpf(inner_x, outer_x, vt)
				var py := lerpf(inner_y, outer_y, vt) + 0.005 * sin(vt * PI)
				var surf_z: float = eval_cuban_front_z.call(px, py)
				var shoulder_wrap := -0.028 * pow(1.0 - ut, 2.6)
				var pz := surf_z + 0.007 + 0.005 * vt + shoulder_wrap
				upper_grid.append(Vector3(px, py, pz))

		_build_extruded_surface_strip(root, "CubanUpperLeafL" if side_sign < 0 else "CubanUpperLeafR",
			upper_grid, u_rows, u_cols, 0.0040, 0.0035, Vector3(0, 1.80, -0.05), collar_color)
		_extrude_uv_strip_from_grid(root, "CubanUpperStitchL" if side_sign < 0 else "CubanUpperStitchR",
			upper_grid, u_rows, u_cols, 0.82, 1.0, 0.0, 1.0, 2, u_cols, 0.0052, 0.0010, Vector3(0, 1.80, -0.05), trim_color)

		# (B) Lower Notched Lapel Wing (下翻驳头): sits cleanly on chest with extruded lapel stitch & V-roll binding
		var lapel_grid := PackedVector3Array()
		var l_cols := 14
		var l_rows := 7
		for iv in l_rows + 1:
			var vt := float(iv) / l_rows
			for iu in l_cols + 1:
				var ut := float(iu) / l_cols
				var roll_y := lerpf(gorge_y, v_open_bottom_y, ut)
				var roll_x := side_sign * lerpf(0.066, 0.008, pow(ut, 0.92))

				var peak_ramp := smoothstep(0.0, 0.18, ut) * (1.0 - pow(clampf((ut - 0.18) / 0.82, 0.0, 1.0), 0.88))
				var lapel_w := (0.088 * collar_spread) * peak_ramp + 0.014 * (1.0 - ut)
				var outer_x := roll_x + side_sign * lapel_w
				var outer_y := roll_y - 0.018 * peak_ramp

				var px := lerpf(roll_x, outer_x, vt)
				var py := lerpf(roll_y, outer_y, vt)
				var surf_z: float = eval_cuban_front_z.call(px, py)
				var pz := surf_z + 0.007 + 0.004 * vt
				lapel_grid.append(Vector3(px, py, pz))

		_build_extruded_surface_strip(root, "CubanLowerLapelL" if side_sign < 0 else "CubanLowerLapelR",
			lapel_grid, l_rows, l_cols, 0.0040, 0.0035, Vector3(0, 1.70, -0.05), collar_color)
		_extrude_uv_strip_from_grid(root, "CubanLapelStitchL" if side_sign < 0 else "CubanLapelStitchR",
			lapel_grid, l_rows, l_cols, 0.82, 1.0, 0.0, 1.0, 2, l_cols, 0.0052, 0.0010, Vector3(0, 1.70, -0.05), trim_color)
		_extrude_uv_strip_from_grid(root, "CubanInnerVRollL" if side_sign < 0 else "CubanInnerVRollR",
			lapel_grid, l_rows, l_cols, 0.0, 0.18, 0.0, 1.0, 2, l_cols, 0.0048, 0.0020, Vector3(0, 1.70, -0.05), trim_color)

	# 3. Shrinkwrapped & Extruded Center Front Placket + Buttons from v_open_bottom_y down to hem_y
	var pl_grid := PackedVector3Array()
	var pl_rows := 14
	var pl_cols := 4
	for r in pl_rows + 1:
		var rt := float(r) / pl_rows
		var py := lerpf(v_open_bottom_y, hem_y + 0.002, rt)
		for c in pl_cols + 1:
			var px := lerpf(-0.016, 0.016, float(c) / pl_cols)
			var pz: float = eval_cuban_front_z.call(px, py)
			pl_grid.append(Vector3(px, py, pz))
	_build_extruded_surface_strip(root, "CenterPlacket", pl_grid, pl_rows, pl_cols, 0.0040, 0.0020, Vector3(0, 1.35, 0), collar_color)

	var btn_count := 4
	for b_idx in btn_count:
		var bt := (float(b_idx) + 0.35) / float(btn_count)
		var by := lerpf(v_open_bottom_y - 0.015, hem_y + 0.04, bt)
		var bz: float = eval_cuban_front_z.call(0.0, by) + 0.0055
		add_ellipsoid(root, "Button%d" % b_idx, Vector3(0.0, by, bz), Vector3(0.011, 0.011, 0.004), button_color)

	# 4. Left chest patch pocket + top welt shrinkwrapped & extruded directly from CubanTorsoShell
	if pocket_enabled:
		var pk_grid := PackedVector3Array()
		var pk_rows := 6
		var pk_cols := 6
		for r in pk_rows + 1:
			var py := lerpf(1.495, 1.582, float(r) / pk_rows)
			for c in pk_cols + 1:
				var px := lerpf(0.046, 0.122, float(c) / pk_cols)
				pk_grid.append(Vector3(px, py, eval_cuban_front_z.call(px, py)))
		_build_extruded_surface_strip(root, "ChestPocketBody", pk_grid, pk_rows, pk_cols, 0.0042, 0.0020, Vector3(0, 1.54, 0), shirt_color.darkened(0.06))
		_extrude_uv_strip_from_grid(root, "ChestPocketWelt", pk_grid, pk_rows, pk_cols, 0.80, 1.0, 0.0, 1.0, 2, pk_cols, 0.0056, 0.0020, Vector3(0, 1.54, 0), trim_color)

	# 5. Relaxed Cuban short sleeves with extruded cuffs on V20 arms
	_build_v20_sleeve_pair(doll, "CustomSleeve", shirt_color, 0.02, -sleeve_length,
		0.018, 0.028, 0.006, trim_color, 0.032, 0.87, 0.0005)
	return root



# #08 娃娃衫重制版 (Babydoll Blouse Remake)
# Anatomical front-sloped round neckline + extruded/shrinkwrapped Peter Pan collar + high empire seam + monotonically flaring peplum
static func build_garment_08_babydoll_remake(doll: Node3D, params: Dictionary = {}) -> Node3D:
	var remove_tr: bool = params.get("remove_trouser", false)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "top" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var blouse_color: Color = params.get("color", Color(0.95, 0.89, 0.84))
	var collar_color: Color = params.get("collar_color", Color(0.98, 0.96, 0.92))
	var ribbon_color: Color = params.get("ribbon_color", Color(0.76, 0.42, 0.44))
	var garment_length: float = clampf(params.get("garment_length", 0.55), 0.0, 1.0)
	var flare_amount: float = params.get("flare_amount", 0.105)
	var gather_pleats: int = int(params.get("gather_pleats", 14))
	var puff_volume: float = params.get("puff_volume", 0.038)

	var empire_y := 1.56
	var hem_y := lerpf(1.34, 1.04, garment_length)

	# 1. Continuous Babydoll Torso + Monotonically Flaring Peplum Skirt with Anatomical Sloped Neckline
	var rings := 34
	var sides := 56
	var body_grid := PackedVector3Array()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var empire_slice := v20_torso_slice(empire_y)
	var empire_rx: float = float(empire_slice["rx"]) + 0.016
	var empire_rz: float = float(empire_slice["rz"]) + 0.016

	for i in rings + 1:
		var t := float(i) / rings
		for s in sides + 1:
			var u := float(s) / sides
			var a := -PI * 0.5 + TAU * u
			var ca := cos(a)
			var sa := sin(a)

			# Anatomical round neckline at the TRUE short neck base (covering the sloping shoulder up to y = 1.935!):
			# High at back neck (1.946), side neck (1.934), dipping gently to 1.886 at front clavicle!
			var y_profile := lerpf(hem_y, 1.935, t)
			var neck_top_y := _anatomical_neck_y(a, 1.946, 1.934, 1.886)
			var y := lerpf(hem_y, neck_top_y, t)
			var slice_x := v20_torso_slice(y_profile)
			var slice := v20_torso_slice(y)
			var z_off: float = float(slice["z"])

			var rx: float
			var rz: float
			if y >= empire_y:
				rx = float(slice_x["rx"]) + 0.015
				rz = float(slice["rz"]) + 0.015
			else:
				var p_t := clampf((empire_y - y) / maxf(0.05, empire_y - hem_y), 0.0, 1.0)
				var cone_flare := flare_amount * pow(p_t, 0.88)
				var pleat_wave := (0.006 + 0.018 * pow(p_t, 0.95)) * (0.5 + 0.5 * cos(a * float(gather_pleats)))
				rx = maxf(float(slice_x["rx"]) + 0.022, empire_rx + cone_flare) + pleat_wave
				rz = maxf(float(slice["rz"]) + 0.022, empire_rz + cone_flare * 0.88) + pleat_wave * 0.92
				z_off = lerpf(float(empire_slice["z"]), float(slice["z"]), 0.45)

			var py := y
			if i <= 2:
				var hem_w := (1.0 - float(i) / 2.0) * 0.008 * cos(a * float(gather_pleats))
				py += hem_w
			var pt := Vector3(ca * rx, py, sa * rz + z_off)
			body_grid.append(pt)
			vertices.append(pt)

	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, Vector3(0, lerpf(hem_y, 1.90, (i + 0.5) / rings), 0))

	build_mesh_instance(root, "BabydollBodyShell", vertices,
		compute_welded_normals(vertices, indices), indices, blouse_color, 0.86, 0.0005)

	# 2. Double-Petal Rounded Peter Pan Collar (彼得潘圆领) hugging the short neck root and draping over the upper sloping shoulders!
	for side_sign: float in [-1.0, 1.0]:
		var c_grid := PackedVector3Array()
		var u_steps := 20
		var v_steps := 8
		for iv in v_steps + 1:
			var vt := float(iv) / v_steps # 0 = welded to anatomical neckline seam, 1 = outer rounded petal edge on chest/shoulder
			for iu in u_steps + 1:
				var ut := float(iu) / u_steps # 0 = center front split, 1 = center back split
				var local_ang := lerpf(PI * 0.44, -PI * 0.46, ut)
				var world_a := (PI - local_ang) if side_sign < 0 else local_ang
				var seam_y := _anatomical_neck_y(world_a, 1.946, 1.934, 1.886)
				var petal_profile := pow(sin(ut * PI), 0.52)
				var drop_y := 0.068 * petal_profile * vt
				var py := seam_y - drop_y
				var py_profile := 1.935 - drop_y
				var sl_x := v20_torso_slice(py_profile)
				var sl_z := v20_torso_slice(py)
				# Keep collar strictly proud (+5mm..+22mm) outside BabydollBodyShell (which is at +0.015) so it never sinks into the bodice!
				var rx_here := float(sl_x["rx"]) + 0.020 + 0.024 * vt * petal_profile
				var rz_here := float(sl_z["rz"]) + 0.020 + 0.022 * vt * petal_profile
				var p := Vector3(
					side_sign * cos(local_ang) * rx_here,
					py + 0.005 * sin(vt * PI),
					sin(local_ang) * rz_here + float(sl_z["z"])
				)
				c_grid.append(p)
		_build_extruded_surface_strip(root, "PeterPanCollarL" if side_sign < 0 else "PeterPanCollarR",
			c_grid, v_steps, u_steps, 0.0040, 0.0030, Vector3(0, 1.88, 0), collar_color)
		# Extrude contrast collar border trim directly from outer 20% of c_grid (zero floating!)
		_extrude_uv_strip_from_grid(root, "PeterPanCollarPipingL" if side_sign < 0 else "PeterPanCollarPipingR",
			c_grid, v_steps, u_steps, 0.80, 1.0, 0.0, 1.0, 2, u_steps, 0.0052, 0.0010, Vector3(0, 1.88, 0), ribbon_color.lightened(0.12))

	# 3. High Empire Waist Ribbon extruded directly from BabydollBodyShell + Shrinkwrapped Bow & Buttons
	var emp_v := clampf((empire_y - hem_y) / maxf(0.1, 1.85 - hem_y), 0.15, 0.85)
	_extrude_uv_strip_from_grid(root, "EmpirePipingBand", body_grid, rings, sides,
		emp_v - 0.022, emp_v + 0.022, 0.0, 1.0, 3, sides, 0.0045, 0.0020, Vector3(0, empire_y, 0), ribbon_color)

	var front_emp_z := empire_rz + float(empire_slice["z"]) + 0.008
	add_ellipsoid(root, "EmpireBowKnot", Vector3(0, empire_y, front_emp_z), Vector3(0.016, 0.013, 0.008), ribbon_color)
	add_ellipsoid(root, "EmpireBowLoopL", Vector3(-0.026, empire_y + 0.003, front_emp_z - 0.002), Vector3(0.022, 0.014, 0.006), ribbon_color.lightened(0.06))
	add_ellipsoid(root, "EmpireBowLoopR", Vector3(0.026, empire_y + 0.003, front_emp_z - 0.002), Vector3(0.022, 0.014, 0.006), ribbon_color.lightened(0.06))

	for b_idx in 3:
		var by := lerpf(1.76, 1.62, float(b_idx) / 2.0)
		var b_sl := v20_torso_slice(by)
		add_ellipsoid(root, "BodiceButton%d" % b_idx,
			Vector3(0, by, float(b_sl["rz"]) + float(b_sl["z"]) + 0.018),
			Vector3(0.009, 0.009, 0.004), collar_color)

	# 4. Gathered Lantern Puff Short Sleeves with Extruded Cuffs
	_build_v20_sleeve_pair(doll, "CustomSleeve", blouse_color, 0.025, -0.22,
		0.018, 0.016, puff_volume, collar_color, 0.024, 0.86, 0.0005)
	return root


# #09 学院风V领背心重制版 (Preppy V-Neck Sweater Vest Remake)
# Restores crisp V-neck knit torso shell + compact inner shirt collar & tie + non-floating extruded V-neck/hem/armhole varsity stripes
static func build_garment_09_preppy_vest_remake(doll: Node3D, params: Dictionary = {}) -> Node3D:
	var remove_tr: bool = params.get("remove_trouser", false)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "outer" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var vest_color: Color = params.get("color", Color(0.18, 0.24, 0.36))
	var stripe_color: Color = params.get("stripe_color", Color(0.93, 0.88, 0.76))
	var accent_stripe: Color = params.get("accent_stripe", Color(0.68, 0.22, 0.24))
	var under_shirt_color: Color = params.get("under_shirt_color", Color(0.95, 0.94, 0.90))
	var layered_shirt: bool = bool(params.get("layered_shirt", not slot_mode))
	var garment_length: float = clampf(params.get("garment_length", 0.48), 0.0, 1.0)
	var v_depth: float = clampf(params.get("v_depth", 0.27), 0.16, 0.36)
	var shoulder_width: float = clampf(params.get("shoulder_width", 1.0), 0.82, 1.15)
	var rib_width: float = params.get("rib_width", 0.056)

	var hem_y := lerpf(1.35, 1.08, garment_length)
	var top_y := 1.936 # Reaches the true short neck root, covering the sloping shoulders!
	var v_apex_y := top_y - v_depth - 0.035

	# Optional crisp inner collared shirt under the sweater vest (covering the sloping shoulders up to the short neck root)
	if layered_shirt:
		var under_rings := 14
		var under_sides := 36
		var u_verts := PackedVector3Array()
		var u_inds := PackedInt32Array()
		for i in under_rings + 1:
			var t := float(i) / under_rings
			var y_profile := lerpf(v_apex_y - 0.05, 1.938, t)
			var sl_x := v20_torso_slice(y_profile)
			for s in under_sides + 1:
				var a := -PI * 0.5 + TAU * float(s) / under_sides
				var neck_y := _anatomical_neck_y(a, 1.948, 1.936, 1.888)
				var y := lerpf(v_apex_y - 0.05, neck_y, t)
				var sl_z := v20_torso_slice(y)
				u_verts.append(Vector3(cos(a) * (float(sl_x["rx"]) + 0.009), y, sin(a) * (float(sl_z["rz"]) + 0.009) + float(sl_z["z"])))
		for i in under_rings:
			for s in under_sides:
				var a := i * (under_sides + 1) + s
				var b := a + under_sides + 1
				emit_quad_outward(u_verts, u_inds, a, a + 1, b + 1, b, Vector3(0, 1.78, 0))
		build_mesh_instance(root, "InnerShirtYoke", u_verts, compute_welded_normals(u_verts, u_inds), u_inds, under_shirt_color, 0.86, 0.0003)

		# Compact pointed shirt collar wings tucked cleanly inside the V-neck opening at the short neck root + flat-woven necktie
		for side_sign: float in [-1.0, 1.0]:
			var col_grid := PackedVector3Array()
			var c_rows := 4
			var c_cols := 8
			for iv in c_rows + 1:
				var vt := float(iv) / c_rows
				for iu in c_cols + 1:
					var ut := float(iu) / c_cols
					var px := side_sign * lerpf(lerpf(0.074, 0.034, ut), lerpf(0.078, 0.044, ut), vt)
					var py := lerpf(lerpf(1.946, 1.898, ut), lerpf(1.918, 1.860, ut), vt)
					var sl := v20_torso_slice(py)
					var nx := clampf(px / maxf(0.05, float(sl["rx"]) + 0.015), -0.95, 0.95)
					var pz := float(sl["z"]) + (float(sl["rz"]) + 0.012) * sqrt(maxf(0.05, 1.0 - nx * nx)) + 0.004 * vt
					col_grid.append(Vector3(px, py, pz))
			_build_extruded_surface_strip(root, "InnerCollarL" if side_sign < 0 else "InnerCollarR",
				col_grid, c_rows, c_cols, 0.0040, 0.0020, Vector3(0, 1.88, 0), under_shirt_color.lightened(0.04))

		var tie_grid := PackedVector3Array()
		var t_rows := 8
		var t_cols := 4
		for r in t_rows + 1:
			var rt := float(r) / t_rows
			var ty := lerpf(1.885, v_apex_y + 0.008, rt)
			var sl := v20_torso_slice(ty)
			var hw := lerpf(0.013, 0.018, sin(rt * PI * 0.7))
			for c in t_cols + 1:
				var tx := lerpf(-hw, hw, float(c) / t_cols)
				var tz := float(sl["rz"]) + float(sl["z"]) + 0.013
				tie_grid.append(Vector3(tx, ty, tz))
		_build_extruded_surface_strip(root, "PreppyNecktie", tie_grid, t_rows, t_cols, 0.0045, 0.0020, Vector3(0, 1.76, 0), accent_stripe)
		_build_v20_sleeve_pair(doll, "UnderSleeve", under_shirt_color, 0.02, -0.22,
			0.012, 0.018, 0.004, under_shirt_color.lightened(0.02), 0.022, 0.86, 0.0004)

	# 1. Main Knit Sweater Vest Shell:
	# - Covers the sloping shoulders all the way up to the neck root (top_y = 1.936, neck_half_w = 0.094)
	# - Front has a crisp V-neck cutout from (|x| = 0.094, y = 1.936) down to (x = 0, y = v_apex_y)
	# - Back has a snug round neckline hugging the base of the neck (y = 1.936..1.944)
	var rings := 32
	var sides := 52
	var vest_grid := PackedVector3Array()
	var indices := PackedInt32Array()
	var neck_half_w := 0.094

	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(hem_y, top_y, t)
		var sl := v20_torso_slice(y)
		var ease := lerpf(0.022, 0.014, smoothstep(1.82, top_y, y))
		if y < hem_y + rib_width:
			ease = lerpf(0.015, 0.022, (y - hem_y) / maxf(0.01, rib_width))
		var rx := float(sl["rx"]) + ease
		var rz := float(sl["rz"]) + ease * 0.95
		var z_off := float(sl["z"])

		var max_x := 99.0
		if y > 1.54:
			var arm_t := clampf((y - 1.54) / (1.86 - 1.54), 0.0, 1.0)
			max_x = lerpf(0.205, 0.140 * shoulder_width, sin(arm_t * PI * 0.5))

		for s in sides + 1:
			var u := float(s) / sides
			var a := -PI * 0.5 + TAU * u
			var ca := cos(a)
			var sa := sin(a)
			var wale_tex := 0.0018 * cos(a * 32.0)
			var px := clampf(ca * (rx + wale_tex), -max_x, max_x)
			# Snug round collar in back rising gently to 1.944 at back neck
			var py := y + 0.008 * maxf(0.0, -sa) * pow(t, 2.0)
			var pz := sa * (rz + wale_tex) + z_off

			# Crisp front V-neck cutout from left/right neck root (|x| = neck_half_w, y = top_y) down to v_apex_y
			if y > v_apex_y and sa > 0.12:
				var vt := clampf((y - v_apex_y) / (top_y - v_apex_y), 0.0, 1.0)
				var v_half_w := lerpf(0.004, neck_half_w, vt)
				if absf(px) < v_half_w:
					var diag_ratio := absf(px) / neck_half_w
					py = minf(py, lerpf(v_apex_y, top_y, diag_ratio))
					var d_sl := v20_torso_slice(py)
					pz = maxf(pz, float(d_sl["rz"]) + float(d_sl["z"]) + 0.021)
			vest_grid.append(Vector3(px, py, pz))

	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(vest_grid, indices, a, a + 1, b + 1, b, Vector3(0, lerpf(hem_y, top_y, (i + 0.5) / rings), 0))

	build_mesh_instance(root, "PreppyVestShell", vest_grid,
		compute_welded_normals(vest_grid, indices), indices, vest_color, 0.90, 0.0005)

	# 2. Varsity Striped V-Neck (Front) + Round-Neck (Back) Ribbing Band — Continuous around the entire neck!
	var eval_vest_front_z := func(px: float, py: float) -> float:
		var sl := v20_torso_slice(py)
		var ease_v := lerpf(0.022, 0.014, smoothstep(1.82, top_y, py))
		var rx_v := float(sl["rx"]) + ease_v
		var rz_v := float(sl["rz"]) + ease_v * 0.95
		var nx := clampf(px / maxf(0.05, rx_v + 0.015), -0.96, 0.96)
		return float(sl["z"]) + rz_v * sqrt(maxf(0.05, 1.0 - nx * nx))

	var vn_grid := PackedVector3Array()
	var vn_rows := 6
	var vn_cols := 28 # 0..14 = left V-wing down to apex, 14..28 = apex up to right V-wing (true mitered V!)
	for iv in vn_rows + 1:
		var vt := float(iv) / vn_rows # 0 = inner V-edge, 1 = outer V-rib edge
		for iu in vn_cols + 1:
			var s_u := (float(iu) / float(vn_cols)) * 2.0 - 1.0 # -1 = left neck, 0 = V-apex, +1 = right neck
			var abs_u := absf(s_u)
			var side_s := -1.0 if s_u < 0.0 else (1.0 if s_u > 0.0 else 0.0)
			var in_x := side_s * lerpf(0.0, neck_half_w, abs_u)
			var in_y := lerpf(v_apex_y, top_y, abs_u)
			var out_x := side_s * lerpf(0.0, neck_half_w + 0.022, abs_u)
			var out_y := lerpf(v_apex_y - 0.036, top_y - 0.014, abs_u)
			var px := lerpf(in_x, out_x, vt)
			var py := lerpf(in_y, out_y, vt)
			var pz: float = eval_vest_front_z.call(px, py) - 0.014 * pow(abs_u, 2.4)
			vn_grid.append(Vector3(px, py, pz))
	_build_extruded_surface_strip(root, "VNeckRibBase", vn_grid, vn_rows, vn_cols,
		0.0038, 0.0025, Vector3(0, 1.74, 0), vest_color.darkened(0.08))
	_extrude_uv_strip_from_grid(root, "VNeckStripe1", vn_grid, vn_rows, vn_cols,
		0.22, 0.42, 0.0, 1.0, 2, vn_cols, 0.0048, 0.0020, Vector3(0, 1.74, 0), stripe_color)
	_extrude_uv_strip_from_grid(root, "VNeckStripe2", vn_grid, vn_rows, vn_cols,
		0.58, 0.78, 0.0, 1.0, 2, vn_cols, 0.0048, 0.0020, Vector3(0, 1.74, 0), accent_stripe)

	# Continuous Back Round-Neck Rib Band (wrapping around back & side neck to meet VNeckRibBase seamlessly!)
	for back_part in 2:
		var u_start := 0.0 if back_part == 0 else 0.72
		var u_end := 0.28 if back_part == 0 else 1.0
		var b_suf := "R" if back_part == 0 else "L"
		_extrude_uv_strip_from_grid(root, "BackNeckRibBase" + b_suf, vest_grid, rings, sides,
			0.93, 1.0, u_start, u_end, 3, 14, 0.0036, 0.0020, Vector3(0, 1.92, 0), vest_color.darkened(0.08))
		_extrude_uv_strip_from_grid(root, "BackNeckStripe1" + b_suf, vest_grid, rings, sides,
			0.965, 0.982, u_start, u_end, 2, 14, 0.0046, 0.0020, Vector3(0, 1.92, 0), stripe_color)
		_extrude_uv_strip_from_grid(root, "BackNeckStripe2" + b_suf, vest_grid, rings, sides,
			0.940, 0.957, u_start, u_end, 2, 14, 0.0046, 0.0020, Vector3(0, 1.92, 0), accent_stripe)

	# 3. Varsity Striped Ribbed Waist Hem Band extruded DIRECTLY from the bottom rings of vest_grid!
	_extrude_uv_strip_from_grid(root, "HemRibBase", vest_grid, rings, sides,
		0.0, 0.13, 0.0, 1.0, 4, sides, 0.0032, 0.0020, Vector3(0, hem_y + 0.03, 0), vest_color.darkened(0.08))
	_extrude_uv_strip_from_grid(root, "HemVarsityStripe0", vest_grid, rings, sides,
		0.028, 0.060, 0.0, 1.0, 2, sides, 0.0044, 0.0020, Vector3(0, hem_y + 0.03, 0), stripe_color)
	_extrude_uv_strip_from_grid(root, "HemVarsityStripe1", vest_grid, rings, sides,
		0.082, 0.114, 0.0, 1.0, 2, sides, 0.0044, 0.0020, Vector3(0, hem_y + 0.03, 0), accent_stripe)

	# 4. Contoured Armhole Rib Bindings extruded DIRECTLY from the left/right armhole columns of vest_grid!
	for side_idx in 2:
		var u_center := 0.25 if side_idx == 1 else 0.75
		var suffix := "R" if side_idx == 1 else "L"
		_extrude_uv_strip_from_grid(root, "ArmholeRib" + suffix, vest_grid, rings, sides,
			0.48, 0.96, u_center - 0.055, u_center + 0.055, 10, 6, 0.0034, 0.0020, Vector3(0, 1.72, 0), vest_color.darkened(0.08))
		_extrude_uv_strip_from_grid(root, "ArmholeStripe" + suffix, vest_grid, rings, sides,
			0.50, 0.94, u_center - 0.025, u_center + 0.025, 10, 4, 0.0045, 0.0020, Vector3(0, 1.72, 0), stripe_color)

	return root


# ============================================================================
# CATEGORY 3: MORE BASIC GARMENT PATTERNS (#10 - #15) ON V20 SHORT-ARM MANNEQUIN
# ============================================================================

# #10 水手领基础衫 (Classic Sailor Collar Blouse)
static func build_garment_10_sailor_blouse(doll: Node3D, params: Dictionary = {}) -> Node3D:
	var remove_tr: bool = params.get("remove_trouser", false)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "top" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var body_color: Color = params.get("color", Color(0.95, 0.94, 0.90))
	var collar_color: Color = params.get("collar_color", Color(0.16, 0.24, 0.38))
	var stripe_color: Color = params.get("stripe_color", Color(0.96, 0.95, 0.92))
	var scarf_color: Color = params.get("scarf_color", Color(0.76, 0.22, 0.24))
	var garment_length: float = clampf(params.get("garment_length", 0.46), 0.0, 1.0)
	var collar_drop: float = clampf(params.get("collar_drop", 0.22), 0.14, 0.32)
	var sleeve_length: float = clampf(params.get("sleeve_length", 0.26), 0.16, 0.44)
	var tie_length: float = clampf(params.get("tie_length", 0.18), 0.10, 0.28)

	var hem_y := lerpf(1.36, 1.08, garment_length)
	var top_y := 1.934
	var v_apex_y := 1.615

	var eval_sailor_front_z := func(px: float, py: float) -> float:
		var sl := v20_torso_slice(py)
		var ease_s := lerpf(0.022, 0.015, smoothstep(1.82, top_y, py))
		var t_rx := float(sl["rx"]) + ease_s
		var t_rz := float(sl["rz"]) + ease_s * 0.92
		var nx := clampf(px / maxf(0.05, t_rx + 0.028), -0.96, 0.96)
		return float(sl["z"]) + t_rz * sqrt(maxf(0.06, 1.0 - nx * nx))

	var eval_sailor_back_z := func(px: float, py: float) -> float:
		var sl := v20_torso_slice(py)
		var ease_s := lerpf(0.022, 0.015, smoothstep(1.82, top_y, py))
		var t_rx := float(sl["rx"]) + ease_s
		var t_rz := float(sl["rz"]) + ease_s * 0.92
		var nx := clampf(px / maxf(0.05, t_rx + 0.045), -0.96, 0.96)
		return float(sl["z"]) - (t_rz + 0.006) * sqrt(maxf(0.04, 1.0 - nx * nx))

	# 1. Tailored Blouse Torso Shell covering the sloping shoulders up to the short neck root (top_y = 1.934) with Open Front V-Neckline above v_apex_y
	var rings := 30
	var sides := 46
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(hem_y, top_y, t)
		var sl := v20_torso_slice(y)
		var ease_s := lerpf(0.022, 0.015, smoothstep(1.82, top_y, y))
		var rx := float(sl["rx"]) + ease_s
		var rz := float(sl["rz"]) + ease_s * 0.92
		var v_open_ang := 0.0
		if y > v_apex_y:
			var vt := clampf((y - v_apex_y) / (top_y - v_apex_y), 0.0, 1.0)
			v_open_ang = lerpf(0.01, 0.72, pow(vt, 0.90))
		var start_ang := PI * 0.5 - v_open_ang
		var end_ang := -PI * 1.5 + v_open_ang
		for s in sides + 1:
			var u := float(s) / sides
			var a := lerpf(start_ang, end_ang, u)
			var back_rise := 0.010 * maxf(0.0, -sin(a)) * pow(t, 2.0)
			vertices.append(Vector3(cos(a) * rx, y + back_rise, sin(a) * rz + float(sl["z"])))
	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, Vector3(0, (hem_y + top_y) * 0.5, 0))
	build_mesh_instance(root, "SailorBlouseTorso", vertices,
		compute_welded_normals(vertices, indices), indices, body_color, 0.86, 0.0004)

	# 2. Classic Sailor Triangular Modesty Dickie Inset (水手服前胸V字三角挡布) with Curved Top Neckline & Extruded Stripe
	var dickie_top_y := 1.795
	var d_grid := PackedVector3Array()
	var d_rows := 7
	var d_cols := 12
	for r in d_rows + 1:
		var vt := float(r) / d_rows
		var half_w := lerpf(0.010, 0.068, vt)
		for c in d_cols + 1:
			var ut := float(c) / d_cols
			var dx := lerpf(-half_w, half_w, ut)
			var top_curve_y := dickie_top_y + 0.012 * pow((ut - 0.5) * 2.0, 2.0)
			var dy := lerpf(v_apex_y - 0.01, top_curve_y, vt)
			var dz: float = eval_sailor_front_z.call(dx, dy) - 0.002
			d_grid.append(Vector3(dx, dy, dz))
	_build_extruded_surface_strip(root, "SailorModestyDickie", d_grid, d_rows, d_cols, 0.0035, 0.0020, Vector3(0, 1.70, 0), body_color)
	_extrude_uv_strip_from_grid(root, "DickieTopStripe", d_grid, d_rows, d_cols,
		0.78, 0.94, 0.0, 1.0, 2, d_cols, 0.0048, 0.0010, Vector3(0, 1.70, 0), collar_color)

	# 3. Continuous 3D Flat-Folded Sailor Collar Shawl at the Short Neck Root with Extruded Nautical Stripes (0mm floating!)
	var back_grid := PackedVector3Array()
	var bw_cols := 22
	var bh_rows := 12
	var back_top_y := 1.936
	var back_bot_y := 1.936 - collar_drop
	for iv in bh_rows + 1:
		var vt := float(iv) / bh_rows
		var cy := lerpf(back_top_y, back_bot_y, vt)
		var half_w := lerpf(0.162, 0.152, vt)
		for iu in bw_cols + 1:
			var ut := float(iu) / bw_cols
			var cx := lerpf(-half_w, half_w, ut)
			var bz: float = eval_sailor_back_z.call(cx, cy) - 0.004
			back_grid.append(Vector3(cx, cy, bz))
	_build_extruded_surface_strip(root, "SailorBackSquareFlap", back_grid, bh_rows, bw_cols, 0.0045, 0.0030, Vector3(0, 1.80, 0.05), collar_color)

	_extrude_uv_strip_from_grid(root, "SailorBackStripeBottom0", back_grid, bh_rows, bw_cols,
		0.86, 0.91, 0.04, 0.96, 2, bw_cols, 0.0056, 0.0010, Vector3(0, 1.80, 0.05), stripe_color)
	_extrude_uv_strip_from_grid(root, "SailorBackStripeBottom1", back_grid, bh_rows, bw_cols,
		0.76, 0.81, 0.08, 0.92, 2, bw_cols, 0.0056, 0.0010, Vector3(0, 1.80, 0.05), stripe_color)
	for side_u in [0.0, 1.0]:
		var suf := "L" if side_u < 0.5 else "R"
		var u0_outer := 0.04 if side_u < 0.5 else 0.92
		var u1_outer := 0.08 if side_u < 0.5 else 0.96
		var u0_inner := 0.09 if side_u < 0.5 else 0.87
		var u1_inner := 0.13 if side_u < 0.5 else 0.91
		_extrude_uv_strip_from_grid(root, "SailorBackStripeSide0" + suf, back_grid, bh_rows, bw_cols,
			0.0, 0.91, u0_outer, u1_outer, bh_rows, 2, 0.0056, 0.0010, Vector3(0, 1.80, 0.05), stripe_color)
		_extrude_uv_strip_from_grid(root, "SailorBackStripeSide1" + suf, back_grid, bh_rows, bw_cols,
			0.0, 0.81, u0_inner, u1_inner, bh_rows, 2, 0.0056, 0.0010, Vector3(0, 1.80, 0.05), stripe_color)

	# (B) Left & Right 3D Flat-Folded Front Sailor V-Wings & Over-Shoulder Bridges (hugging short neck root + extruded stripes!)
	for side_sign: float in [-1.0, 1.0]:
		var wing_grid := PackedVector3Array()
		var w_cols := 22
		var w_rows := 8

		for iv in w_rows + 1:
			var vt := float(iv) / w_rows
			for iu in w_cols + 1:
				var ut := float(iu) / w_cols
				var wy: float
				var inner_x: float
				var outer_x: float
				var px: float
				var py: float
				var pz: float
				if ut <= 0.72:
					var ft := ut / 0.72
					wy = lerpf(v_apex_y, 1.936, pow(ft, 0.90))
					inner_x = side_sign * lerpf(0.004, 0.094, pow(ft, 0.86))
					var wing_w := lerpf(0.026, 0.070, sin(ft * PI * 0.5))
					outer_x = inner_x + side_sign * wing_w
					px = lerpf(inner_x, outer_x, vt)
					py = wy - 0.010 * vt * (1.0 - 0.5 * ft)
					var front_z: float = eval_sailor_front_z.call(px, py)
					var top_curve := -0.024 * pow(ft, 3.2)
					pz = front_z + 0.009 + 0.004 * vt + top_curve
				else:
					var bt := (ut - 0.72) / 0.28
					wy = lerpf(1.936, 1.936, bt) + 0.006 * sin(bt * PI)
					inner_x = side_sign * lerpf(0.094, 0.090, bt)
					outer_x = side_sign * lerpf(0.164, 0.162, bt)
					px = lerpf(inner_x, outer_x, vt)
					py = wy
					var f_z: float = eval_sailor_front_z.call(px, 1.936) + 0.009 - 0.024
					var b_z: float = eval_sailor_back_z.call(px, 1.936) - 0.004
					pz = lerpf(f_z, b_z, bt)
				wing_grid.append(Vector3(px, py, pz))

		_build_extruded_surface_strip(root, "SailorFrontWingL" if side_sign < 0 else "SailorFrontWingR",
			wing_grid, w_rows, w_cols, 0.0045, 0.0030, Vector3(0, 1.74, -0.02), collar_color)
		_extrude_uv_strip_from_grid(root, "SailorWingStripe1L" if side_sign < 0 else "SailorWingStripe1R",
			wing_grid, w_rows, w_cols, 0.82, 0.90, 0.0, 1.0, 2, w_cols, 0.0056, 0.0010, Vector3(0, 1.74, -0.02), stripe_color)
		_extrude_uv_strip_from_grid(root, "SailorWingStripe2L" if side_sign < 0 else "SailorWingStripe2R",
			wing_grid, w_rows, w_cols, 0.66, 0.74, 0.0, 1.0, 2, w_cols, 0.0056, 0.0010, Vector3(0, 1.74, -0.02), stripe_color)

	# 4. Sculpted Sailor Neckerchief Knot + Shrinkwrapped Overlapping Scarf Tails at V-Apex
	var knot_z: float = eval_sailor_front_z.call(0.0, v_apex_y) + 0.010
	var knot_pos := Vector3(0, v_apex_y - 0.004, knot_z)
	add_ellipsoid(root, "SailorTieKnot", knot_pos, Vector3(0.023, 0.020, 0.012), scarf_color)
	for side_sign: float in [-1.0, 1.0]:
		var t_grid := PackedVector3Array()
		var t_rows := 8
		var t_cols := 5
		for r in t_rows + 1:
			var vt := float(r) / t_rows
			var ty := knot_pos.y - 0.010 - tie_length * vt
			var center_x := side_sign * (0.005 + 0.018 * pow(vt, 0.85))
			var tail_hw := lerpf(0.010, 0.021, sin(clampf(vt / 0.75, 0.0, 1.0) * PI * 0.5)) * (1.0 - 0.92 * smoothstep(0.75, 1.0, vt))
			for c in t_cols + 1:
				var ut := float(c) / t_cols - 0.5
				var tx := center_x + ut * tail_hw * 2.0
				var tz: float = eval_sailor_front_z.call(tx, ty) + 0.004 + (0.0025 if side_sign > 0 else 0.0)
				t_grid.append(Vector3(tx, ty, tz))
		_build_extruded_surface_strip(root, "SailorTieTailL" if side_sign < 0 else "SailorTieTailR",
			t_grid, t_rows, t_cols, 0.0040, 0.0015, Vector3(0, knot_pos.y - 0.1, 0), scarf_color.lightened(0.04 if side_sign > 0 else -0.03))

	# 5. Sleeves with Nautical Striped Cuffs
	_build_v20_sleeve_pair(doll, "CustomSleeve", body_color, 0.02, -sleeve_length,
		0.016, 0.024, 0.008, collar_color, 0.032, 0.86, 0.0004)
	return root



# #11 经典V领针织开衫 (Relaxed V-Neck Button Knit Cardigan over Inner Camisole)
static func build_garment_11_knit_cardigan(doll: Node3D, params: Dictionary = {}) -> Node3D:
	var remove_tr: bool = params.get("remove_trouser", false)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "outer" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var cardi_color: Color = params.get("color", Color(0.76, 0.56, 0.44))
	var rib_color: Color = params.get("rib_color", cardi_color.darkened(0.12))
	var inner_color: Color = params.get("inner_color", Color(0.95, 0.93, 0.88))
	var button_color: Color = params.get("button_color", Color(0.36, 0.24, 0.16))
	var garment_length: float = clampf(params.get("garment_length", 0.58), 0.0, 1.0)
	var v_drop: float = params.get("v_drop", 0.26)
	var sleeve_length: float = params.get("sleeve_length", 0.44)
	var body_ease: float = params.get("body_ease", 0.030)
	var pocket_enabled: bool = bool(params.get("pocket_enabled", true))
	var pocket_scale: float = params.get("pocket_scale", 1.0)
	var has_inner: bool = bool(params.get("has_inner", not slot_mode))

	var hem_y := lerpf(1.34, 1.02, garment_length)
	var top_y := 1.934
	var v_bottom_y := top_y - v_drop - 0.035

	# 1. Inner U-Scoop Camisole/Tee covering the sloping shoulders up to the short neck root + Extruded Binding
	if has_inner:
		var inner_grid := PackedVector3Array()
		var inner_inds := PackedInt32Array()
		var in_rings := 14
		var in_sides := 36
		var scoop_front_y := maxf(v_bottom_y + 0.065, 1.785)
		for i in in_rings + 1:
			var t := float(i) / in_rings
			var y_profile := lerpf(v_bottom_y - 0.05, 1.936, t)
			var sl_x := v20_torso_slice(y_profile)
			for s in in_sides + 1:
				var a := -PI * 0.5 + TAU * float(s) / in_sides
				var neck_y := _anatomical_neck_y(a, 1.942, 1.932, scoop_front_y)
				var y := lerpf(v_bottom_y - 0.05, neck_y, t)
				var sl_z := v20_torso_slice(y)
				inner_grid.append(Vector3(cos(a) * (float(sl_x["rx"]) + 0.010), y, sin(a) * (float(sl_z["rz"]) + 0.010) + float(sl_z["z"])))
		for i in in_rings:
			for s in in_sides:
				var a := i * (in_sides + 1) + s
				var b := a + in_sides + 1
				emit_quad_outward(inner_grid, inner_inds, a, a + 1, b + 1, b, Vector3(0, 1.76, 0))
		build_mesh_instance(root, "InnerCamisole", inner_grid, compute_welded_normals(inner_grid, inner_inds), inner_inds, inner_color, 0.86, 0.0003)
		_extrude_uv_strip_from_grid(root, "InnerCamisoleTrim", inner_grid, in_rings, in_sides,
			0.86, 1.0, 0.0, 1.0, 2, in_sides, 0.0025, 0.0015, Vector3(0, 1.80, 0), inner_color.darkened(0.05))

	# Shared evaluator for Cardigan front/back surface
	var eval_cardi_z := func(px: float, py: float, is_front: bool) -> float:
		var sl := v20_torso_slice(py)
		var ch_sl := v20_torso_slice(1.60)
		var slouch := clampf((1.60 - py) / 0.45, 0.0, 1.0) * 0.45
		var ease_c := lerpf(body_ease, 0.016, smoothstep(1.82, top_y, py))
		var rx := lerpf(float(sl["rx"]), float(ch_sl["rx"]), slouch) + ease_c
		var rz := lerpf(float(sl["rz"]), float(ch_sl["rz"]), slouch * 0.75) + ease_c * 0.92
		var nx := clampf(px / maxf(0.04, rx + 0.015), -0.97, 0.97)
		var dz := rz * sqrt(maxf(0.04, 1.0 - nx * nx))
		return float(sl["z"]) + (dz if is_front else -dz)

	var eval_cardi_front_z := func(px: float, py: float) -> float:
		return eval_cardi_z.call(px, py, true)

	# 2. Outer Knit Cardigan Shell covering the sloping shoulders up to the short neck root (top_y = 1.934) with V-Neck in front & Round Neck in back
	var rings := 32
	var sides := 52
	var cardi_grid := PackedVector3Array()
	var indices := PackedInt32Array()
	var ch_sl := v20_torso_slice(1.60)
	var cardi_neck_w := 0.092
	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(hem_y, top_y, t)
		var sl := v20_torso_slice(y)
		var slouch := clampf((1.60 - y) / 0.45, 0.0, 1.0) * 0.45
		var ease_c := lerpf(body_ease, 0.016, smoothstep(1.82, top_y, y))
		var rx := lerpf(float(sl["rx"]), float(ch_sl["rx"]), slouch) + ease_c
		var rz := lerpf(float(sl["rz"]), float(ch_sl["rz"]), slouch * 0.75) + ease_c * 0.92
		if y < hem_y + 0.055:
			var rib_t := 1.0 - clampf((y - hem_y) / 0.055, 0.0, 1.0)
			rx -= 0.008 * rib_t
			rz -= 0.006 * rib_t
		for s in sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / sides
			var ca := cos(a)
			var sa := sin(a)
			var knit_wale := 0.0018 * cos(a * 28.0)
			var px := ca * (rx + knit_wale)
			var pz := sa * (rz + knit_wale) + float(sl["z"])
			var py := y + 0.008 * maxf(0.0, -sa) * pow(t, 2.0)
			if y > v_bottom_y and sa > 0.12:
				var vt := clampf((y - v_bottom_y) / (top_y - v_bottom_y), 0.0, 1.0)
				var gap_x := lerpf(0.010, cardi_neck_w, vt)
				if absf(px) < gap_x:
					py = minf(py, lerpf(v_bottom_y, top_y, absf(px) / cardi_neck_w))
			cardi_grid.append(Vector3(px, py, pz))

	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(cardi_grid, indices, a, a + 1, b + 1, b, Vector3(0, (hem_y + top_y) * 0.5, 0))
	build_mesh_instance(root, "CardiganShell", cardi_grid, compute_welded_normals(cardi_grid, indices), indices, cardi_color, 0.90, 0.0005)

	# 3. Extruded V-Neck Rib Band + Back Round-Neck Rib + Center Front Button Placket + Bottom Rib Hem (0mm floating!)
	for side_sign: float in [-1.0, 1.0]:
		var cv_grid := PackedVector3Array()
		var cv_rows := 5
		var cv_cols := 16
		for iv in cv_rows + 1:
			var vt := float(iv) / cv_rows
			for iu in cv_cols + 1:
				var ut := float(iu) / cv_cols
				var in_x := side_sign * lerpf(0.008, cardi_neck_w, ut)
				var in_y := lerpf(v_bottom_y, top_y, ut)
				var out_x := side_sign * lerpf(0.022, cardi_neck_w + 0.024, ut)
				var out_y := lerpf(v_bottom_y - 0.020, top_y - 0.012, ut)
				var px := lerpf(in_x, out_x, vt)
				var py := lerpf(in_y, out_y, vt)
				cv_grid.append(Vector3(px, py, eval_cardi_z.call(px, py, true)))
		_build_extruded_surface_strip(root, "CardiganVNeckRibL" if side_sign < 0 else "CardiganVNeckRibR",
			cv_grid, cv_rows, cv_cols, 0.0042, 0.0020, Vector3(0, 1.78, 0), rib_color)

	for back_part in 2:
		var u_start := 0.0 if back_part == 0 else 0.72
		var u_end := 0.28 if back_part == 0 else 1.0
		var b_suf := "R" if back_part == 0 else "L"
		_extrude_uv_strip_from_grid(root, "CardiganBackNeckRib" + b_suf, cardi_grid, rings, sides,
			0.93, 1.0, u_start, u_end, 3, 14, 0.0038, 0.0020, Vector3(0, 1.92, 0), rib_color)

	_extrude_uv_strip_from_grid(root, "CardiganHemRibBand", cardi_grid, rings, sides,
		0.0, 0.11, 0.0, 1.0, 3, sides, 0.0035, 0.0020, Vector3(0, hem_y + 0.03, 0), rib_color)

	var pl_grid := PackedVector3Array()
	var pl_rows := 14
	var pl_cols := 4
	for r in pl_rows + 1:
		var py := lerpf(v_bottom_y + 0.012, hem_y, float(r) / pl_rows)
		for c in pl_cols + 1:
			var px := lerpf(-0.018, 0.018, float(c) / pl_cols)
			pl_grid.append(Vector3(px, py, eval_cardi_front_z.call(px, py)))
	_build_extruded_surface_strip(root, "CardiganPlacket", pl_grid, pl_rows, pl_cols, 0.0045, 0.0020, Vector3(0, 1.40, 0), rib_color)

	for b_idx in 4:
		var by := lerpf(v_bottom_y - 0.025, hem_y + 0.055, float(b_idx) / 3.0)
		var bz: float = eval_cardi_front_z.call(0.0, by) + 0.006
		add_ellipsoid(root, "CardiButton%d" % b_idx, Vector3(0, by, bz), Vector3(0.013, 0.013, 0.005), button_color)

	# 4. Shrinkwrapped & Extruded Front Knit Patch Pockets
	if pocket_enabled and pocket_scale > 0.05:
		var pk_y := lerpf(hem_y + 0.11, 1.28, 0.35)
		var pk_hw := 0.038 * pocket_scale
		var pk_hh := 0.044 * pocket_scale
		for side_sign: float in [-1.0, 1.0]:
			var pk_grid := PackedVector3Array()
			var p_rows := 6
			var p_cols := 6
			var cx := side_sign * 0.095
			for r in p_rows + 1:
				var py := lerpf(pk_y - pk_hh, pk_y + pk_hh, float(r) / p_rows)
				for c in p_cols + 1:
					var px := lerpf(cx - pk_hw, cx + pk_hw, float(c) / p_cols)
					pk_grid.append(Vector3(px, py, eval_cardi_front_z.call(px, py)))
			_build_extruded_surface_strip(root, "CardiPocketL" if side_sign < 0 else "CardiPocketR",
				pk_grid, p_rows, p_cols, 0.0050, 0.0020, Vector3(0, pk_y, 0), cardi_color.darkened(0.06))
			_extrude_uv_strip_from_grid(root, "CardiPocketRibL" if side_sign < 0 else "CardiPocketRibR",
				pk_grid, p_rows, p_cols, 0.78, 1.0, 0.0, 1.0, 2, p_cols, 0.0065, 0.0020, Vector3(0, pk_y, 0), rib_color)

	# 5. Long Cozy Knit Sleeves with Extruded Ribbed Cuffs
	_build_v20_sleeve_pair(doll, "CustomSleeve", cardi_color, 0.02, -sleeve_length,
		0.020, 0.022, 0.014, rib_color, 0.042, 0.90, 0.0005)
	return root


# #12 学院工装背带裙 (Overall / Pinafore Bib Jumper Dress over Inner Blouse, Exposing V20 Legs)
static func build_garment_12_pinafore_dress(doll: Node3D, params: Dictionary = {}) -> Node3D:
	# Hide trousers so V20 LegMannequin bare legs show cleanly beneath the skirt!
	var remove_tr: bool = params.get("remove_trouser", true)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "outer" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var dress_color: Color = params.get("color", Color(0.28, 0.36, 0.46))
	var shirt_color: Color = params.get("shirt_color", Color(0.96, 0.94, 0.90))
	var button_color: Color = params.get("button_color", Color(0.82, 0.68, 0.42))
	var skirt_length: float = clampf(params.get("skirt_length", 0.52), 0.0, 1.0)
	var skirt_flare: float = params.get("skirt_flare", 0.13)
	var bib_height: float = params.get("bib_height", 0.34)
	var bib_width: float = params.get("bib_width", 0.115)
	var strap_width: float = params.get("strap_width", 0.036)
	var pocket_enabled: bool = bool(params.get("pocket_enabled", true))
	var has_inner: bool = bool(params.get("has_inner", not slot_mode))

	var waist_y := 1.34
	var skirt_hem_y := lerpf(0.92, 0.56, skirt_length)

	# 1. Fitted Inner Crew-Neck Blouse covering the sloping shoulders up to the short neck root (1.946 back -> 1.934 side -> 1.895 front!) + Extruded Collar Band
	if has_inner:
		var b_rings := 22
		var b_sides := 44
		var b_grid := PackedVector3Array()
		var b_inds := PackedInt32Array()
		for i in b_rings + 1:
			var t := float(i) / b_rings
			var y_profile := lerpf(waist_y - 0.03, 1.936, t)
			var sl_x := v20_torso_slice(y_profile)
			for s in b_sides + 1:
				var a := -PI * 0.5 + TAU * float(s) / b_sides
				var neck_y := _anatomical_neck_y(a, 1.946, 1.934, 1.895)
				var y := lerpf(waist_y - 0.03, neck_y, t)
				var sl_z := v20_torso_slice(y)
				b_grid.append(Vector3(cos(a) * (float(sl_x["rx"]) + 0.014), y, sin(a) * (float(sl_z["rz"]) + 0.014) + float(sl_z["z"])))
		for i in b_rings:
			for s in b_sides:
				var a := i * (b_sides + 1) + s
				var b := a + b_sides + 1
				emit_quad_outward(b_grid, b_inds, a, a + 1, b + 1, b, Vector3(0, 1.66, 0))
		build_mesh_instance(root, "InnerBlouseTorso", b_grid, compute_welded_normals(b_grid, b_inds), b_inds, shirt_color, 0.85, 0.0003)
		_extrude_uv_strip_from_grid(root, "InnerBlouseCollar", b_grid, b_rings, b_sides,
			0.89, 1.0, 0.0, 1.0, 3, b_sides, 0.0032, 0.0015, Vector3(0, 1.90, 0), shirt_color.darkened(0.06))
		_build_v20_sleeve_pair(doll, "UnderSleeve", shirt_color, 0.02, -0.24, 0.014, 0.020, 0.010, shirt_color.darkened(0.05), 0.022, 0.85, 0.0004)

	# 2. A-Line Pinafore Skirt from waist_y down to skirt_hem_y + Extruded Waistband
	var s_rings := 24
	var s_sides := 52
	var s_grid := PackedVector3Array()
	var s_inds := PackedInt32Array()
	var w_sl := v20_torso_slice(waist_y)
	var w_rx: float = float(w_sl["rx"]) + 0.024
	var w_rz: float = float(w_sl["rz"]) + 0.024
	for i in s_rings + 1:
		var t := float(i) / s_rings
		var y := lerpf(skirt_hem_y, waist_y, t)
		var st := 1.0 - t # 0 at waist, 1 at hem
		var sl := v20_torso_slice(maxf(1.05, y))
		var flare := skirt_flare * pow(st, 0.90)
		var pleat := 0.012 * pow(st, 0.95)
		var rx := maxf(float(sl["rx"]) + 0.026, w_rx + flare)
		var rz := maxf(float(sl["rz"]) + 0.026, w_rz + flare * 0.86)
		for s in s_sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / s_sides
			var wave := pleat * cos(a * 10.0)
			s_grid.append(Vector3(cos(a) * (rx + wave), y, sin(a) * (rz + wave) + float(w_sl["z"]) * (1.0 - 0.5 * st)))
	for i in s_rings:
		for s in s_sides:
			var a := i * (s_rings_stride(s_sides)) + s
			var b := a + s_sides + 1
			emit_quad_outward(s_grid, s_inds, a, a + 1, b + 1, b, Vector3(0, (waist_y + skirt_hem_y) * 0.5, 0))
	build_mesh_instance(root, "PinaforeSkirt", s_grid, compute_welded_normals(s_grid, s_inds), s_inds, dress_color, 0.88, 0.0005)

	# 3. Structured Waistband extruded directly from top of PinaforeSkirt
	_extrude_uv_strip_from_grid(root, "PinaforeWaistband", s_grid, s_rings, s_sides,
		0.90, 1.0, 0.0, 1.0, 3, s_sides, 0.0045, 0.0020, Vector3(0, waist_y - 0.02, 0), dress_color.darkened(0.08))

	# Helper to evaluate InnerBlouseTorso surface Z at (px, py)
	var eval_blouse_z := func(px: float, py: float, is_front: bool) -> float:
		var sl := v20_torso_slice(py)
		var rx_b := float(sl["rx"]) + 0.014
		var rz_b := float(sl["rz"]) + 0.014
		var nx := clampf(px / maxf(0.04, rx_b + 0.015), -0.97, 0.97)
		var dz := rz_b * sqrt(maxf(0.04, 1.0 - nx * nx))
		return float(sl["z"]) + (dz if is_front else -dz)

	# 4. Shrinkwrapped & Extruded Front Rectangular Chest Bib + Center Patch Pocket
	var bib_grid := PackedVector3Array()
	var bu_steps := 12
	var bv_steps := 10
	var bib_top_y := waist_y + bib_height
	for iv in bv_steps + 1:
		var vt := float(iv) / bv_steps
		var by := lerpf(waist_y - 0.01, bib_top_y, vt)
		var hw := lerpf(bib_width * 1.08, bib_width, vt)
		for iu in bu_steps + 1:
			var ut := float(iu) / bu_steps
			var bx := lerpf(-hw, hw, ut)
			bib_grid.append(Vector3(bx, by, eval_blouse_z.call(bx, by, true)))
	_build_extruded_surface_strip(root, "PinaforeBib", bib_grid, bv_steps, bu_steps, 0.0055, 0.0020, Vector3(0, (waist_y + bib_top_y) * 0.5, 0), dress_color)
	if pocket_enabled:
		_extrude_uv_strip_from_grid(root, "BibCenterPocket", bib_grid, bv_steps, bu_steps,
			0.24, 0.72, 0.22, 0.78, 5, 6, 0.0095, 0.0010, Vector3(0, (waist_y + bib_top_y) * 0.5, 0), dress_color.darkened(0.07))

	# 5. Shrinkwrapped & Extruded Shoulder Suspender Straps + Brass Overall Buttons (hugs chest & sloped shoulders with 0mm gap!)
	for side_sign: float in [-1.0, 1.0]:
		var sx := side_sign * (bib_width * 0.76)
		var strap_grid := PackedVector3Array()
		var st_rows := 22
		var st_cols := 4
		for r in st_rows + 1:
			var kt := float(r) / st_rows # 0 = front bib top, 0.45 = shoulder crest, 1.0 = back waistband
			for c in st_cols + 1:
				var px := sx + (float(c) / st_cols - 0.5) * strap_width
				var sh_y := 1.928 - _anatomical_shoulder_drop(px, 0.042)
				var sy: float
				var sz: float
				if kt <= 0.42:
					var ft := kt / 0.42
					sy = lerpf(bib_top_y - 0.015, sh_y, ft)
					sz = eval_blouse_z.call(px, sy, true)
				elif kt <= 0.54:
					# Smooth arch over top of sloped shoulder crest from front (+Z) to back (-Z)
					var mt := (kt - 0.42) / 0.12
					var f_z: float = eval_blouse_z.call(px, sh_y, true)
					var b_z: float = eval_blouse_z.call(px, sh_y, false)
					sz = lerpf(f_z, b_z, mt)
					sy = sh_y + 0.006 * sin(mt * PI)
				else:
					var bt := (kt - 0.54) / 0.46
					sy = lerpf(sh_y, waist_y, bt)
					sz = eval_blouse_z.call(px, sy, false)
				strap_grid.append(Vector3(px, sy, sz))
		_build_extruded_surface_strip(root, "OverallStrapL" if side_sign < 0 else "OverallStrapR",
			strap_grid, st_rows, st_cols, 0.0065, 0.0020, Vector3(0, 1.62, 0), dress_color.lightened(0.04))

		var b_y := bib_top_y - 0.025
		var b_z: float = eval_blouse_z.call(sx, b_y, true) + 0.008
		add_ellipsoid(root, "OverallButtonL" if side_sign < 0 else "OverallButtonR",
			Vector3(sx, b_y, b_z), Vector3(0.015, 0.015, 0.005), button_color)

	return root

static func s_rings_stride(sides: int) -> int:
	return sides + 1


# #13 法式方领泡泡袖上衣 (French Square-Neck Shirred Puff-Sleeve Peplum Top)
static func build_garment_13_square_neck_top(doll: Node3D, params: Dictionary = {}) -> Node3D:
	var remove_tr: bool = params.get("remove_trouser", false)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "top" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var top_color: Color = params.get("color", Color(0.86, 0.74, 0.84))
	var trim_color: Color = params.get("trim_color", Color(0.96, 0.92, 0.95))
	var garment_length: float = clampf(params.get("garment_length", 0.45), 0.0, 1.0)
	var neck_width: float = params.get("neck_width", 0.102)
	var neck_depth: float = params.get("neck_depth", 0.165)
	var puff_size: float = params.get("puff_size", 0.046)
	var peplum_flare: float = params.get("peplum_flare", 0.068)

	var hem_y := lerpf(1.36, 1.12, garment_length)
	var top_y := 1.926 # Covers the sloping shoulders up to the inner shoulder strap crest!
	var sq_bottom_y := top_y - neck_depth - 0.025
	var sq_back_y := top_y - neck_depth * 0.42
	var waist_y := 1.44

	# 1. Square-Neck Bodice + Flared Peplum Hem (Horizontal-ring architectural square cutout in front & higher square cutout in back)
	var rings := 30
	var sides := 56
	var bodice_grid := PackedVector3Array()
	var indices := PackedInt32Array()
	var w_sl := v20_torso_slice(waist_y)
	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(hem_y, top_y, t)
		var sl := v20_torso_slice(y)
		var rx := float(sl["rx"]) + 0.018
		var rz := float(sl["rz"]) + 0.018
		if y < waist_y:
			var pt := clampf((waist_y - y) / maxf(0.04, waist_y - hem_y), 0.0, 1.0)
			var flare := peplum_flare * pow(pt, 0.9)
			rx = maxf(rx, float(w_sl["rx"]) + 0.018 + flare)
			rz = maxf(rz, float(w_sl["rz"]) + 0.018 + flare * 0.85)
		for s in sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / sides
			var ca := cos(a)
			var sa := sin(a)
			var shirring := (0.0030 * cos(a * 36.0) if y >= waist_y else 0.007 * cos(a * 16.0) * clampf((waist_y - y) / 0.22, 0.0, 1.0))
			var px := ca * (rx + shirring)
			var pz := sa * (rz + shirring) + float(sl["z"])
			var py := y
			# Crisp architectural square-neck cutout on front and higher square cutout on back
			if y > sq_bottom_y and sa > 0.12 and absf(px) < neck_width:
				py = sq_bottom_y
			elif y > sq_back_y and sa < -0.12 and absf(px) < neck_width * 0.92:
				py = sq_back_y
			bodice_grid.append(Vector3(px, py, pz))

	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(bodice_grid, indices, a, a + 1, b + 1, b, Vector3(0, (hem_y + top_y) * 0.5, 0))
	build_mesh_instance(root, "SquareNeckBodice", bodice_grid, compute_welded_normals(bodice_grid, indices), indices, top_color, 0.86, 0.0005)

	# 2. 3-Sided Architectural Square-Neck Ruffle Trim Shrinkwrapped & Extruded Flush onto SquareNeckBodice (Left vertical + Bottom horizontal + Right vertical, 0mm gap!)
	var eval_sq_front_z := func(px: float, py: float) -> float:
		var sl := v20_torso_slice(py)
		var rx_b := float(sl["rx"]) + 0.018
		var rz_b := float(sl["rz"]) + 0.018
		var nx := clampf(px / maxf(0.04, rx_b + 0.015), -0.97, 0.97)
		return float(sl["z"]) + rz_b * sqrt(maxf(0.04, 1.0 - nx * nx))

	# Bottom horizontal ruffle bar along y = sq_bottom_y
	var b_trim_grid := PackedVector3Array()
	var bt_rows := 5
	var bt_cols := 22
	for r in bt_rows + 1:
		var vt := float(r) / bt_rows
		var py := lerpf(sq_bottom_y + 0.004, sq_bottom_y - 0.022, vt)
		for c in bt_cols + 1:
			var ut := float(c) / bt_cols
			var px := lerpf(-(neck_width + 0.016), neck_width + 0.016, ut)
			var ruffle_dz := 0.0020 * sin(ut * PI * 14.0)
			b_trim_grid.append(Vector3(px, py, eval_sq_front_z.call(px, py) + ruffle_dz))
	_build_extruded_surface_strip(root, "SquareNeckTrimBottom", b_trim_grid, bt_rows, bt_cols,
		0.0048, 0.0020, Vector3(0, sq_bottom_y - 0.05, 0), trim_color)

	# Left & Right vertical inner-strap ruffle trims from sq_bottom_y up to top_y
	for side_sign: float in [-1.0, 1.0]:
		var v_trim_grid := PackedVector3Array()
		var vt_rows := 14
		var vt_cols := 4
		for r in vt_rows + 1:
			var rt := float(r) / vt_rows
			var py := lerpf(sq_bottom_y - 0.010, top_y, rt)
			for c in vt_cols + 1:
				var ct := float(c) / vt_cols
				var px := side_sign * lerpf(neck_width - 0.002, neck_width + 0.020, ct)
				var ruffle_dz := 0.0018 * sin(rt * PI * 10.0)
				v_trim_grid.append(Vector3(px, py, eval_sq_front_z.call(px, py) + ruffle_dz))
		_build_extruded_surface_strip(root, "SquareNeckTrimL" if side_sign < 0 else "SquareNeckTrimR",
			v_trim_grid, vt_rows, vt_cols, 0.0048, 0.0020, Vector3(0, (sq_bottom_y + top_y) * 0.5, 0), trim_color)

	# 3. Sculpted French Puff Sleeves
	_build_v20_sleeve_pair(doll, "CustomSleeve", top_color, 0.03, -0.21,
		0.020, 0.014, puff_size, trim_color, 0.022, 0.86, 0.0005)
	return root


# #14 高腰百慕大阔腿短裤 (High-Waist Pleated Bermuda Shorts / Culottes with Fitted Knit Top)
static func build_garment_14_pleated_shorts(doll: Node3D, params: Dictionary = {}) -> Node3D:
	# Hide full-length trousers so V20 LegMannequin lower legs & knees are visible!
	var remove_tr: bool = params.get("remove_trouser", true)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "bottom" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var shorts_color: Color = params.get("color", Color(0.78, 0.71, 0.61))
	var belt_color: Color = params.get("belt_color", Color(0.38, 0.25, 0.16))
	var top_color: Color = params.get("top_color", Color(0.24, 0.30, 0.28))
	var inseam_length: float = clampf(params.get("inseam_length", 0.50), 0.0, 1.0)
	var leg_flare: float = params.get("leg_flare", 0.030)
	var cuff_height: float = params.get("cuff_height", 0.038)
	var pocket_enabled: bool = bool(params.get("pocket_enabled", true))
	var has_top: bool = bool(params.get("has_top", not slot_mode))

	var waist_y := 1.38
	var crotch_y := 0.99
	var world_hem_y := lerpf(0.86, 0.50, inseam_length)
	var local_hem_y := world_hem_y - 1.10

	# 1. Tucked-in Fitted Knit Crew-Neck Top covering the sloping shoulders up to the short neck root (1.946 back -> 1.934 side -> 1.895 front!) + Extruded Rib Collar
	if has_top:
		var t_rings := 20
		var t_sides := 44
		var t_grid := PackedVector3Array()
		var t_inds := PackedInt32Array()
		for i in t_rings + 1:
			var t := float(i) / t_rings
			var y_profile := lerpf(waist_y - 0.02, 1.936, t)
			var sl_x := v20_torso_slice(y_profile)
			for s in t_sides + 1:
				var a := -PI * 0.5 + TAU * float(s) / t_sides
				var neck_y := _anatomical_neck_y(a, 1.946, 1.934, 1.895)
				var y := lerpf(waist_y - 0.02, neck_y, t)
				var sl_z := v20_torso_slice(y)
				t_grid.append(Vector3(cos(a) * (float(sl_x["rx"]) + 0.012), y, sin(a) * (float(sl_z["rz"]) + 0.012) + float(sl_z["z"])))
		for i in t_rings:
			for s in t_sides:
				var a := i * (t_sides + 1) + s
				var b := a + t_sides + 1
				emit_quad_outward(t_grid, t_inds, a, a + 1, b + 1, b, Vector3(0, 1.68, 0))
		build_mesh_instance(root, "TuckedKnitTop", t_grid, compute_welded_normals(t_grid, t_inds), t_inds, top_color, 0.88, 0.0004)
		_extrude_uv_strip_from_grid(root, "TuckedTopCollar", t_grid, t_rings, t_sides,
			0.88, 1.0, 0.0, 1.0, 3, t_sides, 0.0032, 0.0015, Vector3(0, 1.90, 0), top_color.lightened(0.06))
		_build_v20_sleeve_pair(doll, "UnderSleeve", top_color, 0.02, -0.18, 0.012, 0.016, 0.0, top_color.lightened(0.05), 0.020, 0.88, 0.0004)

	# 2. High-Waisted Pleated Hip & Pelvis Shorts Block (waist_y down to crotch_y)
	var p_rings := 14
	var p_sides := 46
	var p_grid := PackedVector3Array()
	var p_inds := PackedInt32Array()
	for i in p_rings + 1:
		var t := float(i) / p_rings
		var y := lerpf(crotch_y, waist_y, t)
		var sl := v20_torso_slice(y)
		var ease := lerpf(0.032 + leg_flare * 0.4, 0.020, pow(t, 0.85))
		var rx := float(sl["rx"]) + ease
		var rz := float(sl["rz"]) + ease * 0.92
		for s in p_sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / p_sides
			var ca := cos(a)
			var sa := sin(a)
			var pleat_bump := 0.0
			if sa > 0.25:
				pleat_bump = 0.010 * (1.0 - t * 0.6) * exp(-pow((absf(ca) - 0.45) / 0.14, 2.0))
			p_grid.append(Vector3(ca * (rx + pleat_bump * 0.5), y, sa * (rz + pleat_bump) + float(sl["z"])))
	for i in p_rings:
		for s in p_sides:
			var a := i * (p_sides + 1) + s
			var b := a + p_sides + 1
			emit_quad_outward(p_grid, p_inds, a, a + 1, b + 1, b, Vector3(0, (crotch_y + waist_y) * 0.5, 0))
	build_mesh_instance(root, "ShortsHipBlock", p_grid, compute_welded_normals(p_grid, p_inds), p_inds, shorts_color, 0.87, 0.0005)

	# 3. Extruded Leather Belt + Brass Buckle directly on ShortsHipBlock waist
	_extrude_uv_strip_from_grid(root, "ShortsBelt", p_grid, p_rings, p_sides,
		0.84, 0.96, 0.0, 1.0, 3, p_sides, 0.0045, 0.0020, Vector3(0, waist_y - 0.02, 0), belt_color)
	var w_sl := v20_torso_slice(waist_y - 0.015)
	add_ellipsoid(root, "BeltBuckle", Vector3(0, waist_y - 0.015, float(w_sl["rz"]) + float(w_sl["z"]) + 0.026),
		Vector3(0.024, 0.019, 0.006), Color(0.84, 0.70, 0.42))

	# Slant Hip Slash Pockets
	if pocket_enabled:
		for side_sign: float in [-1.0, 1.0]:
			var pk_grid := PackedVector3Array()
			var pk_rows := 6
			var pk_cols := 3
			for r in pk_rows + 1:
				var py := lerpf(1.21, 1.35, float(r) / pk_rows)
				var sl := v20_torso_slice(py)
				var rx := float(sl["rx"]) + 0.027
				var rz := float(sl["rz"]) + 0.025
				for c in pk_cols + 1:
					var a: float = side_sign * lerpf(0.55, 0.92, float(c) / pk_cols)
					pk_grid.append(Vector3(cos(a) * rx, py, sin(a) * rz + float(sl["z"])))
			_build_extruded_surface_strip(root, "ShortsPocket" + ("L" if side_sign < 0 else "R"),
				pk_grid, pk_rows, pk_cols, 0.0042, 0.0016, Vector3(0, 1.28, 0), shorts_color.darkened(0.08))

	# 4. Left & Right Wide Pleated Shorts Leg Tubes with Extruded Turned-Up Cuffs
	for side_idx in 2:
		var leg_name := "LegLeft" if side_idx == 0 else "LegRight"
		var side_sign := -1.0 if side_idx == 0 else 1.0
		var leg := _resolve_body_rig(doll).get_node_or_null(leg_name) as Node3D
		if leg == null:
			continue
		var leg_short := Node3D.new()
		leg_short.name = "CustomShortsLeg"
		leg.add_child(leg_short)
		for old_ch in leg.get_children():
			if old_ch != leg_short and old_ch.name.begins_with("CustomShortsLeg"):
				old_ch.queue_free()

		var l_rings := 14
		var l_sides := 28
		var l_grid := PackedVector3Array()
		var l_inds := PackedInt32Array()
		var top_ly := 0.04
		for i in l_rings + 1:
			var t := float(i) / l_rings
			var ly := lerpf(top_ly, local_hem_y, t)
			var cx := -side_sign * 0.016
			var rx := lerpf(0.114, 0.112 + leg_flare, t)
			var rz := lerpf(0.146, 0.116 + leg_flare, pow(t, 0.65))
			for s in l_sides + 1:
				var a := TAU * float(s) / l_sides
				var crease := 0.006 * pow(sin(a), 4.0)
				l_grid.append(Vector3(cx + cos(a) * rx, ly, sin(a) * (rz + crease)))
		for i in l_rings:
			for s in l_sides:
				var a := i * (l_sides + 1) + s
				var b := a + l_sides + 1
				emit_quad_outward(l_grid, l_inds, a, a + 1, b + 1, b, Vector3(-side_sign * 0.016, (top_ly + local_hem_y) * 0.5, 0))
		build_mesh_instance(leg_short, "ShortsTube", l_grid, compute_welded_normals(l_grid, l_inds), l_inds, shorts_color, 0.87, 0.0005)

		if cuff_height > 0.006:
			var leg_span := maxf(0.08, absf(top_ly - local_hem_y))
			var v0 := clampf(1.0 - cuff_height / leg_span, 0.60, 0.94)
			_extrude_uv_strip_from_grid(leg_short, "ShortsTurnedCuff", l_grid, l_rings, l_sides,
				v0, 1.0, 0.0, 1.0, 4, l_sides, 0.0050, 0.0020,
				Vector3(-side_sign * 0.016, local_hem_y + cuff_height * 0.5, 0), shorts_color.lightened(0.05))

	return root


# #15 半高领无袖A字背心裙 (Sleeveless Mock-Neck A-Line Tent Shift Dress, Exposing V20 Arms & Calves)
static func build_garment_15_mock_neck_shift_dress(doll: Node3D, params: Dictionary = {}) -> Node3D:
	# Hide trousers and sleeves so both V20 bare arms (ArmMannequin) and bare calves (LegMannequin) are shown!
	var remove_tr: bool = params.get("remove_trouser", true)
	var slot_mode: bool = bool(params.get("slot_mode", false))
	var slot_tag: String = str(params.get("slot_tag", "top" if slot_mode else ""))
	_clear_doll_garment_nodes(doll, remove_tr, slot_tag)
	for leg_name in ["LegLeft", "LegRight"]:
		var leg := _resolve_body_rig(doll).get_node_or_null(leg_name)
		if leg != null:
			for ch in leg.get_children():
				if ch.name.begins_with("CustomShortsLeg"):
					ch.queue_free()
					leg.remove_child(ch)

	var root := Node3D.new()
	root.name = ("SlotGarment_" + slot_tag) if slot_mode else "CustomGarment"
	if slot_mode: root.set_meta("garment_slot", slot_tag)
	_resolve_clothes_root(doll).add_child(root)

	var dress_color: Color = params.get("color", Color(0.68, 0.34, 0.32))
	var trim_color: Color = params.get("trim_color", dress_color.lightened(0.14))
	var dress_length: float = clampf(params.get("dress_length", 0.55), 0.0, 1.0)
	var collar_height: float = params.get("collar_height", 0.068)
	var hem_flare: float = params.get("hem_flare", 0.155)
	var shoulder_cut: float = clampf(params.get("shoulder_cut", 0.132), 0.105, 0.165)

	var hem_y := lerpf(0.94, 0.52, dress_length)

	# 1. Unbroken A-Line Shift Dress Shell with Anatomical Tilted Neckline (1.912 back -> 1.884 side -> 1.836 front!) & Cutaway Armholes
	var rings := 36
	var sides := 52
	var shift_grid := PackedVector3Array()
	var indices := PackedInt32Array()
	var chest_sl := v20_torso_slice(1.64)
	var chest_rx: float = float(chest_sl["rx"]) + 0.018
	var chest_rz: float = float(chest_sl["rz"]) + 0.018

	for i in rings + 1:
		var t := float(i) / rings
		var y_profile := lerpf(hem_y, 1.894, t)
		var sl_x := v20_torso_slice(maxf(1.05, y_profile))
		for s in sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / sides
			var ca := cos(a)
			var sa := sin(a)

			# Anatomical tilted neckline: higher at back of neck (1.912), medium at side neck (1.888), lower at front clavicle (1.836)!
			var neck_seam_y := _anatomical_neck_y(a, 1.912, 1.888, 1.836)
			var y := lerpf(hem_y, neck_seam_y, t)
			var sl_z := v20_torso_slice(maxf(1.05, y))
			var rx: float
			var rz: float
			var z_off: float
			if y >= 1.64:
				rx = float(sl_x["rx"]) + 0.018
				rz = float(sl_z["rz"]) + 0.018
				z_off = float(sl_z["z"])
			else:
				var dt := clampf((1.64 - y) / maxf(0.1, 1.64 - hem_y), 0.0, 1.0)
				var flare := hem_flare * pow(dt, 0.92)
				var drape_flute := 0.014 * pow(dt, 1.1)
				rx = maxf(float(sl_x["rx"]) + 0.024, chest_rx + flare) + drape_flute
				rz = maxf(float(sl_z["rz"]) + 0.024, chest_rz + flare * 0.88) + drape_flute
				z_off = lerpf(float(chest_sl["z"]), 0.0, dt * 0.65)

			var max_x := 99.0
			if y_profile > 1.56:
				var at := clampf((y_profile - 1.56) / maxf(0.05, 1.894 - 1.56), 0.0, 1.0)
				max_x = lerpf(0.205, shoulder_cut, pow(at, 0.65))

			var wave := (0.010 * cos(a * 8.0) * clampf((1.55 - y) / 0.6, 0.0, 1.0) if y < 1.55 else 0.0)
			var px := clampf(ca * (rx + wave), -max_x, max_x)
			var pz := sa * (rz + wave) + z_off
			shift_grid.append(Vector3(px, y, pz))

	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(shift_grid, indices, a, a + 1, b + 1, b, Vector3(0, (hem_y + 1.88) * 0.5, 0))
	build_mesh_instance(root, "MockNeckShiftShell", shift_grid,
		compute_welded_normals(shift_grid, indices), indices, dress_color, 0.86, 0.0005)

	# 2. Extruded & Tilted Standing Ribbed Mock-Neck Collar (半高领：沿倾斜的前后领口自然拔起，前低后高贴合颈部)
	var c_rings := 8
	var c_sides := 44
	var c_grid := PackedVector3Array()
	for i in c_rings + 1:
		var ct := float(i) / c_rings
		var sl_cx := v20_torso_slice(lerpf(1.892, 1.95, ct))
		for s in c_sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / c_sides
			var ca := cos(a)
			var sa := sin(a)
			var base_ny := _anatomical_neck_y(a, 1.912, 1.888, 1.836)
			# Collar height is slightly taller in back and slightly softer in front, following the natural forward neck tilt
			var eff_h := collar_height * lerpf(0.92, 1.04, 0.5 - 0.5 * sa)
			var cy := lerpf(base_ny - 0.012, base_ny + eff_h, ct)
			var sl_cz := v20_torso_slice(minf(1.95, cy))
			var crx := minf(shoulder_cut, float(sl_cx["rx"]) + 0.016 - 0.005 * ct)
			var crz := float(sl_cz["rz"]) + 0.016 - 0.005 * ct
			var rib := 0.0014 * cos(a * 28.0)
			c_grid.append(Vector3(ca * (crx + rib), cy, sa * (crz + rib) + float(sl_cz["z"])))
	_build_extruded_surface_strip(root, "MockNeckCollar", c_grid, c_rings, c_sides,
		0.0045, 0.0025, Vector3(0, 1.90, 0), trim_color)

	# 3. Extruded Hem Border Band & Sleeveless Armhole Bindings directly from shift_grid (0mm floating!)
	_extrude_uv_strip_from_grid(root, "ShiftHemBorder", shift_grid, rings, sides,
		0.0, 0.042, 0.0, 1.0, 3, sides, 0.0040, 0.0020, Vector3(0, hem_y + 0.02, 0), trim_color)
	for side_idx in 2:
		var u_c := 0.25 if side_idx == 1 else 0.75
		var suf := "R" if side_idx == 1 else "L"
		_extrude_uv_strip_from_grid(root, "ShiftArmholeTrim" + suf, shift_grid, rings, sides,
			0.68, 0.99, u_c - 0.045, u_c + 0.045, 8, 4, 0.0032, 0.0020, Vector3(0, 1.72, 0), trim_color)

	return root


# ============================================================================
# CATEGORY 4: ETHNIC HATS, HEADSCARF & CANVAS TOTE BAG (#16 - #19)
# ============================================================================

# Helper: Smoothly tuck any hair & upper skull vertices inside a hat's crown envelope so zero hair or skin ever clips through the hat
static func _tuck_hair_under_hat(target_head: Node3D, pivot: Node3D, inner_rx: float, inner_rz: float, max_local_y: float, min_local_y: float = -0.025) -> void:
	var inv_xf := pivot.transform.affine_inverse()
	var xf := pivot.transform
	var targets: Array[MeshInstance3D] = []
	var hair_slot := target_head.get_node_or_null("HairSlot")
	if hair_slot != null:
		for ch in hair_slot.get_children():
			if ch is MeshInstance3D:
				targets.append(ch as MeshInstance3D)
	var head_mesh := target_head.get_node_or_null("HeadMesh")
	if head_mesh is MeshInstance3D:
		targets.append(head_mesh as MeshInstance3D)

	for mi in targets:
		var arr_mesh := mi.mesh as ArrayMesh
		if arr_mesh == null or arr_mesh.get_surface_count() == 0:
			continue
		var mat := arr_mesh.surface_get_material(0)
		var arrays := arr_mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var inds: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty():
			continue
		var modified := false
		for idx in verts.size():
			var v_local := inv_xf * verts[idx]
			if v_local.y > min_local_y:
				var blend := clampf((v_local.y - min_local_y) / 0.032, 0.0, 1.0)
				# Keep hair/head strictly inside the hat crown above the brim, and slightly tighter near the brow
				var rx_lim := inner_rx * (0.92 if v_local.y < 0.04 else 0.96)
				var rz_lim := inner_rz * (0.92 if v_local.y < 0.04 else 0.96)
				var radial := sqrt(pow(v_local.x / maxf(0.01, rx_lim), 2.0) + pow(v_local.z / maxf(0.01, rz_lim), 2.0))
				if radial > 1.0:
					var clamped_x := v_local.x / radial
					var clamped_z := v_local.z / radial
					v_local.x = lerpf(v_local.x, clamped_x, blend)
					v_local.z = lerpf(v_local.z, clamped_z, blend)
					modified = true
				if v_local.y > max_local_y:
					v_local.y = lerpf(v_local.y, max_local_y, blend)
					modified = true
				if modified:
					verts[idx] = xf * v_local
		if modified:
			arrays[Mesh.ARRAY_VERTEX] = verts
			if not inds.is_empty():
				arrays[Mesh.ARRAY_NORMAL] = compute_welded_normals(verts, inds)
			var new_mesh := ArrayMesh.new()
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if mat != null:
				new_mesh.surface_set_material(0, mat)
			mi.mesh = new_mesh


# #16 彝族解放帽（图1左款：高筒黑色硬挺圆筒帽身 + 平帽顶 + 前伸弧形硬质鸭舌帽檐 + 下圈结构性帽箍；不含红色装饰带，筒高上限提升3倍）
# Can be mounted onto HeadRig (or standalone preview node)
static func build_hat_16_yi_liberation_cap(parent: Node3D, params: Dictionary = {}) -> Node3D:
	var target_head := _resolve_head_rig(parent)
	var old := target_head.get_node_or_null("CustomHat")
	if old != null:
		old.queue_free()
		target_head.remove_child(old)
	var hat_root := Node3D.new()
	hat_root.name = "CustomHat"
	target_head.add_child(hat_root)

	var crown_color: Color = params.get("color", Color(0.12, 0.14, 0.18)) # Deep black-charcoal cloth
	var visor_color: Color = params.get("visor_color", Color(0.08, 0.09, 0.12))

	# 核心参数：
	# 1. 筒高 (barrel_height / crown_height) — 上限提升3倍至 1.05+，默认 0.38 还原图1左款挺拔高筒
	var barrel_height: float = clampf(float(params.get("barrel_height", params.get("crown_height", 0.38))), 0.08, 1.05)
	# 2. 筒宽/半径 (barrel_width / cap_radius / crown_radius)
	var barrel_width: float = clampf(float(params.get("barrel_width", params.get("cap_radius", params.get("crown_radius", 0.302)))), 0.25, 0.42)
	# 3. 帽舌长度 (visor_length)
	var visor_length: float = clampf(float(params.get("visor_length", 0.135)), 0.05, 0.26)
	# 4. 佩戴倾角 (wear_angle / mount_angle / tilt_back)
	var raw_angle: float = float(params.get("wear_angle", params.get("mount_angle", params.get("tilt_back", 16.0))))
	var wear_rad: float
	if absf(raw_angle) > 1.2:
		wear_rad = deg_to_rad(absf(raw_angle))
	else:
		wear_rad = absf(raw_angle)
	wear_rad = clampf(wear_rad, 0.0, 0.65)

	# 5. 帽顶微锥度/微喇度 (top_taper)
	var top_taper: float = clampf(float(params.get("top_taper", 1.015)), 0.85, 1.25)
	var visor_arch: float = 0.024 # Duckbill cross-sectional arch
	var visor_droop: float = 0.022 # Downward projection angle

	# Pivot anchored near upper-forehead brow transition so front brim stays locked near brow while cap tilts
	var pivot := Node3D.new()
	pivot.name = "CapPivot"
	var anchor_y := 0.378 + 0.015 * cos(wear_rad)
	var anchor_z := 0.032 - 0.050 * sin(wear_rad)
	pivot.position = Vector3(0.0, anchor_y, anchor_z)
	pivot.rotation.x = -wear_rad
	hat_root.add_child(pivot)

	var sides := 48

	# 1. Tall Cylindrical Bucket Crown (高筒帽身) + Crisp Beveled Rim + Flat Top Disk
	# A) Outer Cylinder Wall with contoured lower rim cupping brow & occiput
	var wall_rings := 24
	var wall_verts := PackedVector3Array()
	var wall_inds := PackedInt32Array()

	var rx_base := barrel_width
	var rz_base := barrel_width * 1.05
	var rx_top := barrel_width * top_taper
	var rz_top := barrel_width * 1.05 * top_taper

	for i in wall_rings + 1:
		var t := float(i) / wall_rings
		var r_blend := pow(t, 0.90)
		var rx := lerpf(rx_base, rx_top, r_blend)
		var rz := lerpf(rz_base, rz_top, r_blend)

		for s in sides + 1:
			var a := TAU * float(s) / sides
			var ca := cos(a)
			var sa := sin(a)
			# Contoured lower rim: front rests at brow, back drops slightly (-0.026) to cup occiput
			var base_drop := -0.026 * (1.0 - sa) * 0.5 # sa = 1 is front (+Z), sa = -1 is back (-Z)
			var cur_y := lerpf(base_drop, barrel_height, t)
			wall_verts.append(Vector3(ca * rx, cur_y, sa * rz))

	for i in wall_rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(wall_verts, wall_inds, a, a + 1, b + 1, b, Vector3(0, barrel_height * 0.5, 0))

	# Double-sided inner wall so the cap has true fabric thickness when viewed from below
	var inner_offset := 0.004
	var wall_vert_count := wall_verts.size()
	for vi in wall_vert_count:
		var p := wall_verts[vi]
		var in_p := p * Vector3(1.0 - inner_offset / rx_base, 1.0, 1.0 - inner_offset / rz_base)
		wall_verts.append(in_p)
	for i in wall_rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			var ia := wall_vert_count + a
			var ib := wall_vert_count + b
			emit_quad_outward(wall_verts, wall_inds, ia, ib, ib + 1, ia + 1, Vector3(0, barrel_height * 0.5, 0))

	# Bottom edge closure (sealing outer wall to inner wall)
	for s in sides:
		var a := s
		var ia := wall_vert_count + a
		emit_quad_outward(wall_verts, wall_inds, a, a + 1, ia + 1, ia, Vector3(0, -0.05, 0))

	build_mesh_instance(pivot, "CapBarrel", wall_verts,
		compute_welded_normals(wall_verts, wall_inds), wall_inds, crown_color, 0.88, 0.0004)

	# B) Razor-Flat Top Lid Disk (平顶帽盖) with crisp beveled edge
	var disk_rings := 8
	var disk_verts := PackedVector3Array()
	var disk_inds := PackedInt32Array()
	var top_y := barrel_height

	for i in disk_rings + 1:
		var dt := float(i) / disk_rings
		# dt = 0 is outer rim, dt = 1 is disk center
		var r_fac := 1.0 - dt
		# Outer bevel at rim (dt in [0, 0.25]): slight 2mm chamfer
		var chamfer_y := -0.003 * (1.0 - smoothstep(0.0, 0.25, dt))
		var cur_rx := rx_top * r_fac
		var cur_rz := rz_top * r_fac
		for s in sides + 1:
			var a := TAU * float(s) / sides
			disk_verts.append(Vector3(cos(a) * cur_rx, top_y + chamfer_y, sin(a) * cur_rz))

	for i in disk_rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(disk_verts, disk_inds, a, a + 1, b + 1, b, Vector3(0, top_y - 0.2, 0))

	build_mesh_instance(pivot, "CapTopLid", disk_verts,
		compute_welded_normals(disk_verts, disk_inds), disk_inds, crown_color, 0.88, 0.0004)

	# 2. Structured Lower Headband (下圈结构性帽圈/帽箍) — 贴合帽身底部，增强军帽/解放帽挺拔结构感
	var band_height := minf(0.055, barrel_height * 0.22)
	var band_rings := 4
	var band_verts := PackedVector3Array()
	var band_inds := PackedInt32Array()
	for i in band_rings + 1:
		var bt := float(i) / band_rings
		var by := bt * band_height
		var b_rx := (rx_base + 0.0025) * (1.0 + 0.005 * bt)
		var b_rz := (rz_base + 0.0025) * (1.0 + 0.005 * bt)
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var sa := sin(a)
			var base_drop := -0.026 * (1.0 - sa) * 0.5
			band_verts.append(Vector3(cos(a) * b_rx, by + base_drop * (1.0 - bt * 0.6), sin(a) * b_rz))

	for i in band_rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(band_verts, band_inds, a, a + 1, b + 1, b, Vector3(0, band_height * 0.5, 0))

	build_mesh_instance(pivot, "CapHeadband", band_verts,
		compute_welded_normals(band_verts, band_inds), band_inds, crown_color.darkened(0.06), 0.90, 0.0004)

	# 3. 前伸硬质弧形鸭舌帽檐 (Visor) — 严格遵照图1左款鸭舌轮廓，前伸挺拔、截面自然拱弧
	var v_grid := PackedVector3Array()
	var u_steps := 28
	var v_steps := 10
	for iv in v_steps + 1:
		var vt := float(iv) / v_steps # 0 = welded to front headband, 1 = outer edge
		for iu in u_steps + 1:
			var ut := float(iu) / u_steps # 0 = left temple, 0.5 = center front (+Z), 1 = right temple
			# Front ~126° arc around +Z
			var ang := lerpf(PI * 0.15, PI * 0.85, ut)
			var arch_env := sin(ut * PI)
			var root_x := cos(ang) * (rx_base + 0.003)
			var root_z := sin(ang) * (rz_base + 0.003)
			var root_y := 0.008 + visor_arch * pow(arch_env, 0.82)

			# Duckbill visor projection: forward_reach reaches full visor_length at center front
			var forward_reach := visor_length * pow(arch_env, 0.55)
			var tip_x := root_x * (1.0 - 0.045 * vt * arch_env)
			var tip_z := root_z + forward_reach * vt
			var tip_y := root_y - visor_droop * vt - 0.012 * vt * (1.0 - arch_env)

			v_grid.append(Vector3(tip_x, tip_y, tip_z))

	_build_extruded_surface_strip(pivot, "CapVisor", v_grid, v_steps, u_steps,
		0.0055, 0.0045, Vector3(0, -0.25, 0.0), visor_color)
	_extrude_uv_strip_from_grid(pivot, "CapVisorRimBinding", v_grid, v_steps, u_steps,
		0.80, 1.0, 0.0, 1.0, 2, u_steps, 0.0065, 0.0050, Vector3(0, -0.25, 0.0), visor_color.lightened(0.04))

	# 4. Tuck any hair/head vertices above the brim inside the bucket crown
	_tuck_hair_under_hat(target_head, pivot, barrel_width, barrel_width * 1.05, maxf(0.32, barrel_height * 0.90), -0.024)

	return hat_root


# #17 彝族阿都式高筒帽（图1右款：上宽下窄喇叭形黑色绒布百褶高筒帽 + 缠绕式暗红织带帽圈 + 厚实圆润包边顶圈）
static func build_hat_17_yi_adu_hat(parent: Node3D, params: Dictionary = {}) -> Node3D:
	var target_head := _resolve_head_rig(parent)
	var old := target_head.get_node_or_null("CustomHat")
	if old != null:
		old.queue_free()
		target_head.remove_child(old)
	var hat_root := Node3D.new()
	hat_root.name = "CustomHat"
	target_head.add_child(hat_root)

	var velvet_color: Color = params.get("color", Color(0.08, 0.08, 0.10)) # Deep plush black velvet
	var band_color: Color = params.get("band_color", Color(0.46, 0.14, 0.18)) # Braided crimson-purple base band
	var band_accent: Color = params.get("band_accent", Color(0.16, 0.14, 0.18))
	var hat_height: float = params.get("hat_height", 0.50)
	var base_radius: float = maxf(0.280, float(params.get("base_radius", 0.288)))
	var top_flare_radius: float = params.get("top_flare_radius", 0.435)
	var pleat_count: int = int(params.get("pleat_count", 48))
	var pleat_depth: float = params.get("pleat_depth", 0.0085)
	var rim_thickness: float = params.get("rim_thickness", 0.038)
	var tilt_angle: float = params.get("tilt_angle", -0.20) # Signature Adu-style backward tilt framing forehead

	var pivot := Node3D.new()
	pivot.name = "AduHatPivot"
	pivot.position = Vector3(0.0, 0.42, -0.012)
	pivot.rotation.x = tilt_angle
	hat_root.add_child(pivot)

	# 1. Tall Inverted-Frustum Trumpet-Flared Black Velvet Body with Dense Vertical Pleats (密集竖向百褶高筒)
	var rings := 28
	var sides := 96
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	for i in rings + 1:
		var t := float(i) / rings
		var y: float
		var r_base: float
		var pleat_amp: float
		if t <= 0.82:
			# Flared trumpet wall from base (0.005) up to upper rim (hat_height)
			var wt := t / 0.82
			y = lerpf(0.005, hat_height, wt)
			# Concave-to-flared silhouette matching Image 1 Right
			var flare_curve := 0.65 * wt + 0.35 * pow(wt, 1.65)
			r_base = lerpf(base_radius, top_flare_radius, flare_curve)
			pleat_amp = pleat_depth * lerpf(0.45, 1.0, wt)
		elif t <= 0.91:
			# Rounded cushioned upper rim roll (厚实圆润包边顶圈)
			var rt := (t - 0.82) / 0.09
			var rim_ang := lerpf(0.0, PI, rt)
			y = hat_height + sin(rim_ang) * rim_thickness * 0.65
			r_base = top_flare_radius + sin(rim_ang * 0.5) * rim_thickness * 0.45 - (1.0 - cos(rim_ang)) * rim_thickness * 0.55
			pleat_amp = pleat_depth * (1.0 - 0.7 * rt)
		else:
			# Recessed concave top crown well
			var ct := (t - 0.91) / 0.09
			y = hat_height - 0.035 * sin(ct * PI * 0.5)
			r_base = lerpf(top_flare_radius - rim_thickness * 0.65, 0.002, pow(ct, 1.2))
			pleat_amp = pleat_depth * 0.25 * (1.0 - ct)

		var rx := r_base
		var rz := r_base * 1.05
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var flute := pleat_amp * cos(a * float(pleat_count))
			vertices.append(Vector3(cos(a) * (rx + flute), y, sin(a) * (rz + flute)))

	for i in rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			emit_quad_outward(vertices, indices, a, a + 1, b + 1, b, Vector3(0, hat_height * 0.45, 0))

	build_mesh_instance(pivot, "AduVelvetFlaredCrown", vertices,
		compute_welded_normals(vertices, indices), indices, velvet_color, 0.94, 0.0004)

	# 2. Braided Crimson & Dark Woven Base Headband Rings — Extruded directly from AduVelvetFlaredCrown base rings
	_extrude_uv_strip_from_grid(pivot, "AduBaseBraid0", vertices, rings, sides,
		0.00, 0.045, 0.0, 1.0, 3, sides, 0.0055, 0.0015, Vector3(0, 0.02, 0), band_color)
	_extrude_uv_strip_from_grid(pivot, "AduBaseBraid1", vertices, rings, sides,
		0.045, 0.090, 0.0, 1.0, 3, sides, 0.0050, 0.0015, Vector3(0, 0.04, 0), band_accent)

	# 3. Cushioned Upper Rim Velvet Cord Accent — Extruded directly from AduVelvetFlaredCrown upper rim roll
	_extrude_uv_strip_from_grid(pivot, "AduTopCushionRim", vertices, rings, sides,
		0.80, 0.90, 0.0, 1.0, 5, sides, 0.0055, 0.0020, Vector3(0, hat_height, 0), velvet_color.lightened(0.05))

	# Tuck any hair/head vertices above the braided base ring neatly inside the hat crown
	_tuck_hair_under_hat(target_head, pivot, base_radius, base_radius * 1.05, hat_height * 0.80, -0.015)

	return hat_root


# #18 爱沙尼亚头巾（图2款式：贴合头顶与太阳穴的A字垂坠包头红头巾 + 腮边折角 + 颌下平缓系结与两片宽大斜方垂片 + 覆肩三角流苏披肩）
# Mounts onto doll (or HeadRig) so hood frames the face & bangs closely while wide tie flaps and fringed shawl drape over shoulders
static func build_hat_18_estonian_headscarf(doll_or_head: Node3D, params: Dictionary = {}) -> Node3D:
	var head_rig: Node3D = _resolve_head_rig(doll_or_head)

	# Keep neat forehead bangs inside the headscarf face opening so blonde hair peeks out in front without poking through the hood sides
	var hair_col: Color = params.get("hair_color", Color(0.88, 0.78, 0.56))
	var hr := clear_hair_slot(head_rig)
	build_base_scalp_cap(hr, hair_col, 0.99, 1.62, 0.94, 0.0)
	build_front_bangs(hr, hair_col, 0.376, 0.018, 0.22, 0.0, 0.06)

	# Hide protruding ear meshes while wearing the wrap-around headscarf hood so ear tips at |x|=0.322 never poke through cheek fabric
	for ch in head_rig.get_children():
		if ch is MeshInstance3D and (ch.name.begins_with("Ear")):
			ch.visible = false

	var old := head_rig.get_node_or_null("CustomHat")
	if old != null:
		old.queue_free()
		head_rig.remove_child(old)
	var scarf_root := Node3D.new()
	scarf_root.name = "CustomHat"
	head_rig.add_child(scarf_root)

	var scarf_color: Color = params.get("color", Color(0.78, 0.16, 0.15)) # Warm Estonian folk red
	var pattern_band_color: Color = params.get("pattern_band_color", Color(0.58, 0.14, 0.13)) # Deep woven crimson-brown folk band
	var border_color: Color = params.get("border_color", Color(0.88, 0.68, 0.24)) # Warm gold corner border accent
	var fringe_color: Color = params.get("fringe_color", Color(0.82, 0.18, 0.16))
	var hood_depth: float = params.get("hood_depth", 1.0)
	var face_opening: float = params.get("face_opening", 1.0)
	var flap_length: float = params.get("flap_length", 0.23)
	var flap_spread: float = params.get("flap_spread", 1.0)
	var shawl_drop: float = params.get("shawl_drop", 0.32)
	var fringe_length: float = params.get("fringe_length", 0.072)
	var fringe_count: int = int(params.get("fringe_count", 42))

	# HeadRig local space: HEAD_CENTER = (0, 0.29, 0), HEAD_RADIUS = (0.272, 0.30, 0.29).
	# 1. Draped Kerchief Hood (包头巾本体):
	#    Instead of a bloated spherical helmet, models the authentic folded triangular cloth kerchief from Image 2:
	#    - Snugly hugs the crown & temples at the top (no ballooning halo)
	#    - Drops nearly straight / slightly A-flared down past the cheeks
	#    - Forms a soft horizontal cheek-corner fold at jaw level before gathering inward under the chin!
	var h_rings := 24
	var h_sides := 48
	var hood_center := Vector3(0.0, 0.290, -0.005)
	var min_skull_radii := Vector3(0.280, 0.306, 0.298)

	var eval_hood_inner := func(v: float, u: float) -> Vector3:
		var a := TAU * u # 0 = top forehead crown, 0.25 = right cheek, 0.5 = under chin, 0.75 = left cheek
		var ca := cos(a)
		var sa := sin(a)

		# Front face-framing edge (v = 0):
		# Closely frames the forehead & temples above, drops slightly wider at lower cheeks (ca around -0.35),
		# and folds sharply horizontally inward under the chin (ca -> -1.0)
		var cheek_flare := exp(-pow((ca + 0.38) / 0.36, 2.0)) # Subtle outward fold at lower cheek/jaw corner
		var chin_gather := smoothstep(-0.98, -0.45, ca)
		var front_half_w := (lerpf(0.055, 0.205, chin_gather) + 0.032 * cheek_flare) * face_opening
		var front_x := sa * front_half_w
		var front_y := lerpf(-0.012, 0.535, 0.5 + 0.5 * ca) - 0.018 * cheek_flare
		var front_z := 0.232 + 0.018 * ca - 0.012 * pow(sa, 2.0) + 0.014 * cheek_flare

		# Mid-head kerchief drape (v = 0.45):
		# Snug at top crown (y = 0.596) and temples (|x| = 0.276), flaring gently into a tented A-line curtain at jaw level!
		var tent_w := lerpf(0.298, 0.274, smoothstep(-0.4, 0.6, ca)) + 0.026 * cheek_flare
		var mid_x := sa * lerpf(0.145, tent_w, smoothstep(-0.98, -0.32, ca))
		var mid_y := lerpf(-0.020, 0.596, 0.5 + 0.5 * ca) - 0.015 * cheek_flare
		var mid_z := 0.015 - 0.035 * hood_depth + 0.035 * ca

		# Back nape gather (v = 1.0): tapers cleanly down to the nape of the neck
		var back_x := sa * 0.145 * (1.0 - 0.45 * maxf(0.0, ca))
		var back_y := 0.12 + ca * 0.19
		var back_z := -0.305 * hood_depth + 0.035 * ca

		var p: Vector3
		if v < 0.48:
			var vt := v / 0.48
			var w0 := cos(vt * PI * 0.5)
			var w1 := sin(vt * PI * 0.5)
			p = Vector3(front_x * w0 + mid_x * w1, front_y * w0 + mid_y * w1, front_z * w0 + mid_z * w1)
		else:
			var vt := (v - 0.48) / 0.52
			var w0 := cos(vt * PI * 0.5)
			var w1 := sin(vt * PI * 0.5)
			p = Vector3(mid_x * w0 + back_x * w1, mid_y * w0 + back_y * w1, mid_z * w0 + back_z * w1)

		# Strict skull clearance without puffing out the lower cheeks
		var rel := p - hood_center
		var norm_d := Vector3(rel.x / min_skull_radii.x, rel.y / min_skull_radii.y, rel.z / min_skull_radii.z).length()
		if norm_d < 1.0 and norm_d > 0.0001:
			var push_k := lerpf(1.0, 1.0 / norm_d, smoothstep(0.02, 0.18, p.y))
			p = hood_center + rel * push_k

		# Subtle horizontal cloth fold crease at the lower cheek/jaw corner matching Image 2
		var jaw_crease := 0.006 * sin(v * PI) * exp(-pow((ca + 0.42) / 0.22, 2.0))
		p += Vector3(sa * jaw_crease, -jaw_crease * 0.4, jaw_crease * 0.5)
		return p

	var outer_hood_grid := PackedVector3Array()
	for i in h_rings + 1:
		var v := float(i) / h_rings
		for s in h_sides + 1:
			var u := float(s) / h_sides
			outer_hood_grid.append(eval_hood_inner.call(v, u))

	_build_extruded_surface_strip(scarf_root, "HeadscarfHood", outer_hood_grid, h_rings, h_sides,
		0.0065, 0.0015, hood_center, scarf_color)

	# Subtle folded red cloth selvedge at the front face edge (NO bright yellow circular O-ring around the face!)
	_extrude_uv_strip_from_grid(scarf_root, "HoodFoldedBrim", outer_hood_grid, h_rings, h_sides,
		0.00, 0.055, 0.0, 1.0, 3, h_sides, 0.0076, 0.0010, hood_center, scarf_color.darkened(0.05))

	# Horizontal folk woven band across the lower left & right cheek folds (图2脸颊下方两侧的水平织纹带):
	for side_band in 2:
		var u0 := 0.30 if side_band == 0 else 0.58
		var u1 := 0.42 if side_band == 0 else 0.70
		var suf := "R" if side_band == 0 else "L"
		_extrude_uv_strip_from_grid(scarf_root, "HoodCheekFolkBand" + suf, outer_hood_grid, h_rings, h_sides,
			0.02, 0.38, u0, u1, 6, 8, 0.0078, 0.0010, hood_center, pattern_band_color)
		_extrude_uv_strip_from_grid(scarf_root, "HoodCheekGoldLine" + suf, outer_hood_grid, h_rings, h_sides,
			0.03, 0.36, u0 + 0.03, u0 + 0.055, 6, 3, 0.0084, 0.0010, hood_center, border_color)

	# 2. Shoulder-Draped Triangular Folk Shawl (覆肩三角流苏披肩) + Fine Red Yarn Fringe Tassels
	var s_rings := 18
	var s_sides := 52
	var s_verts := PackedVector3Array()
	var s_inds := PackedInt32Array()

	var eval_shawl_point := func(t: float, a: float) -> Vector3:
		var ca := cos(a)
		var sa := sin(a)
		# Drapes over the sloping shoulders and forms a V-shaped front & back shawl point
		# Shorter on the outer arms (|ca| near 1) and deeper at front/back center (|sa| near 1) so the hem slants diagonally!
		var diag_taper := 0.72 + 0.38 * pow(absf(sa), 1.15)
		var shoulder_arch := pow(absf(ca), 1.3) * sin(t * PI * 0.68) * 0.042
		var drop_profile := shawl_drop * diag_taper
		var py := -0.052 - drop_profile * pow(t, 0.92) + shoulder_arch
		var world_y := 2.02 + py
		var sl := v20_torso_slice(world_y)
		var rx := maxf(float(sl["rx"]) + 0.048, lerpf(0.135, 0.375, sin(t * PI * 0.56)))
		var rz := maxf(float(sl["rz"]) + 0.054, lerpf(0.135, 0.248, pow(t, 0.74)))
		var drape_wave := 0.007 * pow(t, 1.2) * cos(a * 10.0)
		var px := ca * (rx + drape_wave)
		var pz := sa * (rz + drape_wave) + float(sl["z"]) - 0.022 + 0.022 * maxf(0.0, sa)
		return Vector3(px, py, pz)

	for i in s_rings + 1:
		var t := float(i) / s_rings
		for s in s_sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / s_sides
			s_verts.append(eval_shawl_point.call(t, a))

	for i in s_rings:
		for s in s_sides:
			var a := i * (s_sides + 1) + s
			var b := a + s_sides + 1
			emit_quad_outward(s_verts, s_inds, a, a + 1, b + 1, b, Vector3(0, -0.20, -0.02))
	build_mesh_instance(scarf_root, "ShoulderShawlCape", s_verts,
		compute_welded_normals(s_verts, s_inds), s_inds, scarf_color.darkened(0.04), 0.88, 0.0005)

	# Subtle dark-crimson & gold woven border band near the diagonal shawl hem
	_extrude_uv_strip_from_grid(scarf_root, "ShawlWovenBorder", s_verts, s_rings, s_sides,
		0.76, 0.92, 0.0, 1.0, 4, s_sides, 0.0036, 0.0015, Vector3(0, -0.20, -0.02), pattern_band_color)
	_extrude_uv_strip_from_grid(scarf_root, "ShawlGoldThread", s_verts, s_rings, s_sides,
		0.91, 0.95, 0.0, 1.0, 2, s_sides, 0.0042, 0.0015, Vector3(0, -0.20, -0.02), border_color)

	# Tuck any upper garment/sleeve vertices directly underneath the shawl so white blouse body never pokes through the shawl
	var doll_root := head_rig.get_parent()
	if doll_root != null:
		var garment := doll_root.get_node_or_null("CustomGarment")
		if garment != null:
			var min_shawl_world_y := 2.02 - 0.052 - shawl_drop * 1.15 - fringe_length * 0.5
			for ch in garment.get_children():
				if ch is MeshInstance3D:
					var g_mi := ch as MeshInstance3D
					if g_mi.name.begins_with("Empire") or g_mi.name.begins_with("BodiceButton") or g_mi.name.begins_with("PeterPan"):
						g_mi.visible = false
						continue
					var g_mesh := g_mi.mesh as ArrayMesh
					if g_mesh == null or g_mesh.get_surface_count() == 0:
						continue
					var g_mat := g_mesh.surface_get_material(0)
					var g_arr := g_mesh.surface_get_arrays(0)
					var g_verts: PackedVector3Array = g_arr[Mesh.ARRAY_VERTEX]
					var g_inds: PackedInt32Array = g_arr[Mesh.ARRAY_INDEX]
					var g_mod := false
					for vi in g_verts.size():
						var gv := g_verts[vi]
						if gv.y > min_shawl_world_y:
							var gt := clampf((1.965 - gv.y) / maxf(0.05, 1.965 - min_shawl_world_y), 0.0, 1.0)
							var ga := atan2(gv.z + 0.02, gv.x)
							var sp: Vector3 = eval_shawl_point.call(minf(1.0, gt), ga)
							var cur_r := Vector2(gv.x, gv.z + 0.02).length()
							var lim_r := Vector2(sp.x, sp.z + 0.02).length() - 0.022
							if cur_r > lim_r and cur_r > 0.001 and lim_r > 0.02:
								var blend := smoothstep(min_shawl_world_y, min_shawl_world_y + 0.06, gv.y)
								var scale_r := lerpf(1.0, lim_r / cur_r, blend)
								gv.x *= scale_r
								gv.z = -0.02 + (gv.z + 0.02) * scale_r
								g_verts[vi] = gv
								g_mod = true
					if g_mod:
						g_arr[Mesh.ARRAY_VERTEX] = g_verts
						if not g_inds.is_empty():
							g_arr[Mesh.ARRAY_NORMAL] = compute_welded_normals(g_verts, g_inds)
						var nm := ArrayMesh.new()
						nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g_arr)
						if g_mat != null:
							nm.surface_set_material(0, g_mat)
						g_mi.mesh = nm

	# Fine Hanging Red Yarn Fringe Tassels along the Diagonal Shawl Perimeter (图2披肩边缘细密红流苏)
	var total_fringe := maxi(20, fringe_count)
	for f_idx in total_fringe:
		var ft := float(f_idx) / float(total_fringe)
		var idx := s_rings * (s_sides + 1) + clampi(int(round(ft * s_sides)), 0, s_sides)
		var root_pt := s_verts[idx]
		var a := -PI * 0.5 + TAU * ft
		var ca := cos(a)
		var sa := sin(a)
		var sway := 0.009 * sin(float(f_idx) * 2.7)
		var tip_pt := root_pt + Vector3(ca * 0.015 + sway, -fringe_length * (0.85 + 0.25 * absf(sin(float(f_idx) * 1.9))), sa * 0.012)
		var mid_pt := root_pt.lerp(tip_pt, 0.5) + Vector3(sway * 0.5, 0.0, 0.003)
		add_ValidationBand(scarf_root, "ShawlFringe%d" % f_idx,
			PackedVector3Array([root_pt, mid_pt, tip_pt]), 0.0048, 0.0030,
			fringe_color.lightened(0.04 * sin(float(f_idx))))

	# 3. Flat-Folded Under-Chin Cloth Knot + Two Broad Square-Cornered Kerchief Tie Flaps (图2颌下平缓布结与左右两片宽大斜方垂角!)
	var knot_pos := Vector3(0.0, -0.022, 0.232)
	var k_grid := PackedVector3Array()
	var k_rows := 5
	var k_cols := 8
	for r in k_rows + 1:
		var vt := float(r) / k_rows
		var ky := knot_pos.y + lerpf(0.020, -0.022, vt)
		for c in k_cols + 1:
			var ut := float(c) / k_cols - 0.5
			var kx := ut * lerpf(0.072, 0.056, vt)
			var kz := knot_pos.z + 0.012 * cos(ut * PI) + 0.006 * sin(vt * PI)
			k_grid.append(Vector3(kx, ky, kz))
	_build_extruded_surface_strip(scarf_root, "ChinKnotFold", k_grid, k_rows, k_cols,
		0.0080, 0.0040, Vector3(0, 0.0, 0.0), scarf_color.darkened(0.05))

	for side_sign: float in [-1.0, 1.0]:
		var f_verts := PackedVector3Array()
		var fu_steps := 12
		var fv_steps := 12
		var len_here := flap_length * (0.96 if side_sign < 0 else 1.04)
		for iv in fv_steps + 1:
			var vt := float(iv) / fv_steps # 0 = gathered at chin knot, 1 = broad angled bottom edge
			# Broad trapezoidal/square-corner kerchief end: widens from 0.046 at knot to 0.148 * flap_spread at the bottom!
			var width_env := lerpf(0.046, 0.148 * flap_spread, pow(vt, 0.62))
			var spine_x := side_sign * (0.022 + 0.095 * flap_spread * pow(vt, 0.88))
			var spine_y := knot_pos.y - 0.008 - len_here * vt
			for iu in fu_steps + 1:
				var ut := float(iu) / fu_steps - 0.5 # -0.5 = left edge of flap, +0.5 = right edge of flap
				# Outer edge is slightly higher, inner edge extends slightly lower, forming the authentic angled square-scarf corner in Image 2!
				var px := spine_x + ut * width_env
				var corner_tilt := -side_sign * ut * 0.048 * pow(vt, 0.85)
				var bottom_v_point := -0.022 * vt * (1.0 - absf(ut * 2.0))
				var py := spine_y + corner_tilt + bottom_v_point
				# Keep flap cleanly in front of the shawl chest surface (+0.020m clearance) with natural cloth pleat waves
				var st := clampf((-0.052 - py) / maxf(0.08, shawl_drop), 0.0, 1.0)
				var sa_ang := atan2(0.24, px)
				var shawl_pt: Vector3 = eval_shawl_point.call(st, sa_ang)
				var pleat_z := 0.007 * cos(ut * PI * 2.0) * sin(vt * PI * 0.85)
				var pz := maxf(knot_pos.z + 0.016 * sin(vt * PI * 0.65), shawl_pt.z + 0.020) + pleat_z + (0.004 if side_sign < 0 else 0.0)
				f_verts.append(Vector3(px, py, pz))

		_build_extruded_surface_strip(scarf_root, "TriangularTieFlapL" if side_sign < 0 else "TriangularTieFlapR",
			f_verts, fv_steps, fu_steps, 0.0050, 0.0020, Vector3(0, -0.1, -0.2),
			scarf_color.lightened(0.04))

		# L-Shaped Gold Folk Corner Border along the bottom edge and outer edge of each broad tie flap (matching Image 2!)
		_extrude_uv_strip_from_grid(scarf_root, "FlapGoldBottomBorderL" if side_sign < 0 else "FlapGoldBottomBorderR",
			f_verts, fv_steps, fu_steps, 0.78, 0.90, 0.08, 0.92, 3, fu_steps,
			0.0062, 0.0010, Vector3(0, -0.1, -0.2), border_color)
		var u_outer0 := 0.08 if side_sign < 0 else 0.78
		var u_outer1 := 0.22 if side_sign < 0 else 0.92
		_extrude_uv_strip_from_grid(scarf_root, "FlapGoldSideBorderL" if side_sign < 0 else "FlapGoldSideBorderR",
			f_verts, fv_steps, fu_steps, 0.18, 0.90, u_outer0, u_outer1, fv_steps, 3,
			0.0062, 0.0010, Vector3(0, -0.1, -0.2), border_color)

	return scarf_root

static func front_x_lerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t)


# #19 帆布袋 (Parametric Gusseted Cotton Canvas Tote Bag — Standalone or Shoulder/Hand Mounted)
static func build_prop_19_canvas_tote_bag(parent: Node3D, params: Dictionary = {}) -> Node3D:
	var bag_root := Node3D.new()
	bag_root.name = params.get("node_name", "CanvasToteBag")
	parent.add_child(bag_root)

	var canvas_color: Color = params.get("color", Color(0.93, 0.89, 0.81)) # Natural unbleached ecru cotton canvas
	var strap_color: Color = params.get("strap_color", Color(0.24, 0.32, 0.28)) # Forest green / navy cotton webbing
	var bottom_color: Color = params.get("bottom_color", strap_color)
	var pocket_color: Color = params.get("pocket_color", canvas_color.darkened(0.05))
	var bag_width: float = params.get("bag_width", 0.34)
	var bag_height: float = params.get("bag_height", 0.38)
	var gusset_depth: float = params.get("gusset_depth", 0.115)
	var strap_drop: float = params.get("strap_drop", 0.26)
	var strap_width: float = params.get("strap_width", 0.028)
	var mouth_openness: float = params.get("mouth_openness", 0.85)
	var contrast_bottom_ratio: float = clampf(params.get("contrast_bottom_ratio", 0.24), 0.0, 0.55)

	var rings := 22
	var sides := 48
	var hw := bag_width * 0.5
	var hd := gusset_depth * 0.5

	# Helper to evaluate rounded-rectangle canvas tote cross-section with natural fabric slouch
	var eval_bag_point := func(t: float, s_idx: int, inset: float) -> Vector3:
		var a := TAU * float(s_idx) / float(sides)
		var ca := cos(a)
		var sa := sin(a)
		# Superellipse rounded-box profile (n = 3.2 at bottom gusset, softening to oval at open top mouth)
		var exp_pow := lerpf(0.32, 0.72, t)
		var sx := signf(ca) * pow(absf(ca), exp_pow)
		var sz := signf(sa) * pow(absf(sa), exp_pow)
		# Natural canvas belly bulge in lower-mid section + slight taper at top mouth
		var width_curve := 1.0 + 0.07 * sin(t * PI) - 0.04 * pow(t, 1.8)
		var depth_curve := lerpf(1.0, 0.78 * mouth_openness, pow(t, 1.1)) + 0.10 * sin(t * PI)
		var side_crease := -0.014 * sin(t * PI) * pow(absf(ca), 4.0) * (1.0 - absf(sa))
		var px := sx * maxf(0.01, hw * width_curve - inset)
		var pz := sz * maxf(0.01, hd * depth_curve - inset) + side_crease
		var py := t * bag_height - 0.010 * pow(t, 2.0) * (1.0 - absf(ca)) # gentle center mouth dip
		return Vector3(px, py, pz)

	# 1. Main Canvas Body (Lower Contrast Dipped Base + Upper Natural Ecru Canvas)
	var split_ring := clampi(int(round(contrast_bottom_ratio * rings)), 0, rings - 2)
	for part in 2:
		var r_start := 0 if part == 0 else split_ring
		var r_end := split_ring if part == 0 else rings
		if r_end <= r_start:
			continue
		var p_verts := PackedVector3Array()
		var p_inds := PackedInt32Array()
		var local_rings := r_end - r_start
		for i in local_rings + 1:
			var t := float(r_start + i) / float(rings)
			for s in sides + 1:
				p_verts.append(eval_bag_point.call(t, s, 0.0))
		for i in local_rings:
			for s in sides:
				var a := i * (sides + 1) + s
				var b := a + sides + 1
				emit_quad_outward(p_verts, p_inds, a, a + 1, b + 1, b, Vector3(0, bag_height * 0.5, 0))
		var col := bottom_color if part == 0 else canvas_color
		build_mesh_instance(bag_root, "CanvasBaseSection" if part == 0 else "CanvasUpperBody",
			p_verts, compute_welded_normals(p_verts, p_inds), p_inds, col, 0.90, 0.0005)

	# Flat Gusseted Bottom Floor Cap
	var bot_verts := PackedVector3Array([Vector3(0, 0, 0)])
	var bot_inds := PackedInt32Array()
	for s in sides + 1:
		bot_verts.append(eval_bag_point.call(0.0, s, 0.0))
	for s in sides:
		emit_triangle_outward(bot_verts, bot_inds, 0, s + 1, s + 2, Vector3(0, 0.1, 0))
	build_mesh_instance(bag_root, "CanvasBottomFloor", bot_verts,
		compute_welded_normals(bot_verts, bot_inds), bot_inds, bottom_color if split_ring > 0 else canvas_color.darkened(0.06), 0.90, 0.0004)

	# 2. Hollow Interior Lining & Top Double-Stitched Hem Facing
	var in_verts := PackedVector3Array()
	var in_inds := PackedInt32Array()
	var in_rings := 8
	for i in in_rings + 1:
		var t := lerpf(1.0, 0.35, float(i) / in_rings)
		for s in sides + 1:
			in_verts.append(eval_bag_point.call(t, s, 0.007))
	for i in in_rings:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			# Inward facing normals for interior cavity
			emit_quad_outward(in_verts, in_inds, a, b, b + 1, a + 1, Vector3(0, bag_height * 2.0, 0))
	build_mesh_instance(bag_root, "CanvasInteriorCavity", in_verts,
		compute_welded_normals(in_verts, in_inds), in_inds, canvas_color.darkened(0.16), 0.92, 0.0003)

	var rim_pts := PackedVector3Array()
	for s in sides + 1:
		rim_pts.append(eval_bag_point.call(0.985, s, -0.002))
	add_ValidationBand(bag_root, "TopStitchedHemBand", rim_pts, 0.026, 0.007, canvas_color.lightened(0.03))

	# 3. Front Stitched Patch Pocket + Woven Brand Label Tab
	var pocket_enabled: bool = bool(params.get("pocket_enabled", true))
	if pocket_enabled:
		var pk_y := bag_height * 0.48
		var pk_z := hd * 0.96 + 0.008
		var pk_w := bag_width * 0.24
		var pk_h := bag_height * 0.22
		var pk_verts := PackedVector3Array([
			Vector3(-pk_w, pk_y - pk_h, pk_z),
			Vector3(pk_w, pk_y - pk_h, pk_z),
			Vector3(pk_w, pk_y + pk_h, pk_z - 0.003),
			Vector3(-pk_w, pk_y + pk_h, pk_z - 0.003)
		])
		var pk_inds := PackedInt32Array([0, 1, 2, 0, 2, 3])
		build_mesh_instance(bag_root, "FrontPatchPocket", pk_verts,
			compute_welded_normals(pk_verts, pk_inds), pk_inds, pocket_color, 0.89, 0.0004)
		add_ValidationBand(bag_root, "PocketTopHem",
			PackedVector3Array([Vector3(-pk_w, pk_y + pk_h, pk_z), Vector3(0, pk_y + pk_h, pk_z + 0.002), Vector3(pk_w, pk_y + pk_h, pk_z)]),
			0.016, 0.006, strap_color)

	# 4. Dual Flat Cotton Webbing Shoulder Straps with Box-Stitch Anchor Tabs
	var strap_span_x := bag_width * 0.24
	for face_sign: float in [-1.0, 1.0]: # Front (+Z) and Back (-Z) straps
		var s_pts := PackedVector3Array()
		var s_steps := 24
		var base_z := face_sign * (hd * 0.78 * mouth_openness + 0.004)
		var anchor_y := bag_height * 0.84
		for k in s_steps + 1:
			var u := float(k) / s_steps
			var sx: float
			var sy: float
			var sz: float
			if u <= 0.14:
				var lt := u / 0.14
				sx = -strap_span_x
				sy = lerpf(anchor_y, bag_height, lt)
				sz = base_z + face_sign * 0.004
			elif u >= 0.86:
				var rt := (u - 0.86) / 0.14
				sx = strap_span_x
				sy = lerpf(bag_height, anchor_y, rt)
				sz = base_z + face_sign * 0.004
			else:
				var mt := (u - 0.14) / 0.72
				var ang := mt * PI
				sx = -cos(ang) * strap_span_x
				sy = bag_height + sin(ang) * strap_drop
				# Slight inward gather at top shoulder grip
				sz = lerpf(base_z, face_sign * 0.018, pow(sin(ang), 0.85))
			s_pts.append(Vector3(sx, sy, sz))
		add_ValidationBand(bag_root, "CanvasWebbingStrapF" if face_sign > 0 else "CanvasWebbingStrapB",
			s_pts, strap_width, 0.007, strap_color)

	return bag_root


# ============================================================================
# CATEGORY 5: MATRYOSHKA & SOUVENIR WOODEN DOLLS (#20 - #22)
# ============================================================================

# Helper to evaluate Russian Matryoshka outer radius at normalized height t in [0..1]
static func _eval_matryoshka_radius(t: float, max_r: float, base_ratio: float, belly_ratio: float,
		waist_height_ratio: float, neck_indent: float, head_ratio: float, shoulder_slope: float) -> float:
	if t <= 0.03:
		var bt := t / 0.03
		return max_r * lerpf(base_ratio * 0.90, base_ratio, sqrt(bt))
	elif t <= 0.42:
		# Lower turned wooden base swelling smoothly to maximum round belly
		var bt := (t - 0.03) / 0.39
		return max_r * lerpf(base_ratio, belly_ratio, sin(bt * PI * 0.5))
	elif t <= waist_height_ratio:
		# Upper belly tapering into traditional Matryoshka neck/chest cove
		var wt := (t - 0.42) / maxf(0.05, waist_height_ratio - 0.42)
		var s_curve := wt * wt * (3.0 - 2.0 * wt)
		return max_r * lerpf(belly_ratio, neck_indent, pow(s_curve, shoulder_slope))
	elif t <= 0.76:
		# Head swelling from neck cove to rounded cheeks/temples
		var ht := (t - waist_height_ratio) / maxf(0.04, 0.76 - waist_height_ratio)
		return max_r * lerpf(neck_indent, head_ratio, sin(ht * PI * 0.5))
	else:
		# Rounded spherical-ovoid wooden crown closure at top (t = 1.0)
		var ct := clampf((t - 0.76) / 0.24, 0.0, 1.0)
		return max_r * head_ratio * sqrt(maxf(0.0, 1.0 - ct * ct))


# Single Matryoshka shell builder (can be closed OR split open into upper + lower hollow halves with inner tenon lip!)
static func _build_single_matryoshka_shell(parent: Node3D, node_name: String, height: float, max_r: float,
		params: Dictionary, open_offset_y: float = 0.0, open_upper_shift_x: float = 0.0) -> Node3D:
	var doll_node := Node3D.new()
	doll_node.name = node_name
	parent.add_child(doll_node)

	var base_ratio: float = params.get("base_ratio", 0.58)
	var belly_ratio: float = params.get("belly_ratio", 1.0)
	var waist_height_ratio: float = clampf(params.get("waist_height_ratio", 0.64), 0.50, 0.72)
	var neck_indent: float = params.get("neck_indent", 0.72)
	var head_ratio: float = params.get("head_ratio", 0.80)
	var shoulder_slope: float = params.get("shoulder_slope", 1.0)
	var split_ratio: float = clampf(params.get("split_ratio", 0.44), 0.36, 0.54)

	var scarf_color: Color = params.get("scarf_color", Color(0.78, 0.18, 0.18))
	var body_color: Color = params.get("body_color", Color(0.16, 0.24, 0.42))
	var apron_color: Color = params.get("apron_color", Color(0.95, 0.89, 0.76))
	var wood_color: Color = params.get("wood_color", Color(0.92, 0.81, 0.66))
	var gold_color: Color = params.get("gold_color", Color(0.86, 0.68, 0.26))

	var lower_half := Node3D.new()
	lower_half.name = "LowerShell"
	doll_node.add_child(lower_half)

	var upper_half := Node3D.new()
	upper_half.name = "UpperShell"
	upper_half.position = Vector3(open_upper_shift_x, open_offset_y, 0.0)
	doll_node.add_child(upper_half)

	var sides := 44
	var wall_thick := max_r * 0.11

	# 1. Lower Shell (t = 0 .. split_ratio) + Turned Wooden Inner Tenon Lip (子母口内榫)
	var l_profile := PackedVector2Array([Vector2(0.0, 0.0)])
	var l_steps := 18
	for i in l_steps + 1:
		var t := lerpf(0.0, split_ratio, float(i) / l_steps)
		var r := _eval_matryoshka_radius(t, max_r, base_ratio, belly_ratio, waist_height_ratio, neck_indent, head_ratio, shoulder_slope)
		l_profile.append(Vector2(r, t * height))
	var split_r := _eval_matryoshka_radius(split_ratio, max_r, base_ratio, belly_ratio, waist_height_ratio, neck_indent, head_ratio, shoulder_slope)
	var split_y := split_ratio * height
	# Step inward to wooden tenon rim and hollow interior cavity
	var tenon_r := split_r - wall_thick * 0.48
	var inner_r := split_r - wall_thick
	var tenon_h := height * 0.045
	l_profile.append(Vector2(tenon_r, split_y))
	l_profile.append(Vector2(tenon_r, split_y + tenon_h))
	l_profile.append(Vector2(inner_r, split_y + tenon_h))
	l_profile.append(Vector2(inner_r * 0.78, height * 0.08))
	l_profile.append(Vector2(0.0, height * 0.08))
	build_lathe_mesh(lower_half, "LowerBodyMesh", l_profile, sides, body_color, 0.72, 0.0003)

	# Exposed natural birch wood tenon collar ring when shell is opened
	var tenon_profile := PackedVector2Array([
		Vector2(inner_r + 0.001, split_y + 0.001),
		Vector2(tenon_r + 0.001, split_y + 0.001),
		Vector2(tenon_r + 0.001, split_y + tenon_h + 0.001),
		Vector2(inner_r + 0.001, split_y + tenon_h + 0.001)
	])
	build_lathe_mesh(lower_half, "BirchWoodTenonCollar", tenon_profile, sides, wood_color, 0.78, 0.0002)

	# 2. Upper Shell (t = split_ratio .. 1.0) with Hollow Interior
	var u_profile := PackedVector2Array()
	u_profile.append(Vector2(inner_r, split_y + height * 0.25))
	u_profile.append(Vector2(tenon_r + 0.002, split_y))
	var u_steps := 24
	for i in u_steps + 1:
		var t := lerpf(split_ratio, 1.0, float(i) / u_steps)
		var r := _eval_matryoshka_radius(t, max_r, base_ratio, belly_ratio, waist_height_ratio, neck_indent, head_ratio, shoulder_slope)
		u_profile.append(Vector2(r, t * height))
	build_lathe_mesh(upper_half, "UpperHeadScarfMesh", u_profile, sides, scarf_color, 0.70, 0.0003)

	# Gold Split-Seam Trim Ring at Waist Division
	var seam_pts := PackedVector3Array()
	for s in sides + 1:
		var a := TAU * float(s) / sides
		seam_pts.append(Vector3(cos(a) * (split_r + 0.002), split_y, sin(a) * (split_r + 0.002)))
	add_ValidationBand(lower_half, "WaistSeamGoldBand", seam_pts, height * 0.018, 0.004, gold_color)

	# 3. Painted Wooden Face Oval + Bangs + Eyes + Rosy Cheeks on Upper Shell
	var face_center_t := lerpf(waist_height_ratio, 0.86, 0.46)
	var face_y := face_center_t * height
	var face_r := _eval_matryoshka_radius(face_center_t, max_r, base_ratio, belly_ratio, waist_height_ratio, neck_indent, head_ratio, shoulder_slope)
	add_ellipsoid(upper_half, "FaceWoodOval", Vector3(0, face_y, face_r * 0.76),
		Vector3(face_r * 0.56, height * 0.115, face_r * 0.30), wood_color.lightened(0.05))
	# Golden-brown parted bangs arc at top of face oval
	add_ellipsoid(upper_half, "PartedBangsL", Vector3(-face_r * 0.20, face_y + height * 0.078, face_r * 0.86),
		Vector3(face_r * 0.28, height * 0.032, face_r * 0.16), Color(0.56, 0.36, 0.18))
	add_ellipsoid(upper_half, "PartedBangsR", Vector3(face_r * 0.20, face_y + height * 0.078, face_r * 0.86),
		Vector3(face_r * 0.28, height * 0.032, face_r * 0.16), Color(0.56, 0.36, 0.18))
	# Eyes, rosy cheeks & tiny red smile dot
	for side_sign: float in [-1.0, 1.0]:
		add_ellipsoid(upper_half, "EyeL" if side_sign < 0 else "EyeR",
			Vector3(side_sign * face_r * 0.21, face_y + height * 0.012, face_r * 1.02),
			Vector3(max_r * 0.048, max_r * 0.052, max_r * 0.025), Color(0.12, 0.12, 0.14))
		add_ellipsoid(upper_half, "BlushL" if side_sign < 0 else "BlushR",
			Vector3(side_sign * face_r * 0.31, face_y - height * 0.020, face_r * 0.96),
			Vector3(max_r * 0.068, max_r * 0.045, max_r * 0.025), Color(0.86, 0.38, 0.36))
	add_ellipsoid(upper_half, "LipsDot", Vector3(0, face_y - height * 0.036, face_r * 1.02),
		Vector3(max_r * 0.048, max_r * 0.028, max_r * 0.022), Color(0.78, 0.18, 0.18))

	# Under-chin headscarf knot & decorative front apron oval on belly
	var knot_y := waist_height_ratio * height
	var knot_r := _eval_matryoshka_radius(waist_height_ratio, max_r, base_ratio, belly_ratio, waist_height_ratio, neck_indent, head_ratio, shoulder_slope)
	add_ellipsoid(upper_half, "ScarfKnot", Vector3(0, knot_y - height * 0.015, knot_r * 0.98),
		Vector3(max_r * 0.13, height * 0.026, max_r * 0.08), gold_color)

	var apron_y := height * 0.27
	var apron_r := _eval_matryoshka_radius(0.27, max_r, base_ratio, belly_ratio, waist_height_ratio, neck_indent, head_ratio, shoulder_slope)
	add_ellipsoid(lower_half, "FrontApronPanel", Vector3(0, apron_y, apron_r * 0.72),
		Vector3(apron_r * 0.58, height * 0.17, apron_r * 0.32), apron_color)
	# Simple folk flower medallion on apron
	add_ellipsoid(lower_half, "ApronFlowerCenter", Vector3(0, apron_y + height * 0.01, apron_r * 1.01),
		Vector3(max_r * 0.11, max_r * 0.11, max_r * 0.04), scarf_color)
	add_ellipsoid(lower_half, "ApronFlowerPistil", Vector3(0, apron_y + height * 0.01, apron_r * 1.04),
		Vector3(max_r * 0.045, max_r * 0.045, max_r * 0.03), gold_color)

	return doll_node


# #20 俄罗斯套娃 (Parametric Russian Matryoshka Nesting Dolls — Adjustable Shell Size, Proportions, Layer Count & Open/Nested State)
static func build_prop_20_matryoshka_set(parent: Node3D, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = params.get("node_name", "MatryoshkaSet")
	parent.add_child(root)

	var layer_count: int = clampi(int(params.get("layer_count", 5)), 1, 9)
	var outer_height: float = params.get("outer_height", 0.54)
	var outer_radius: float = params.get("outer_radius", 0.155)
	var layer_scale_decay: float = clampf(params.get("layer_scale_decay", 0.76), 0.62, 0.86)
	var open_first_shell: bool = params.get("open_first_shell", false)
	var spacing_factor: float = params.get("spacing_factor", 1.18)

	var scarf_palette: Array[Color] = [
		Color(0.78, 0.16, 0.16),
		Color(0.18, 0.42, 0.34),
		Color(0.82, 0.54, 0.18),
		Color(0.24, 0.32, 0.56),
		Color(0.64, 0.22, 0.42),
		Color(0.32, 0.52, 0.28),
		Color(0.74, 0.34, 0.20)
	]
	var body_palette: Array[Color] = [
		Color(0.16, 0.24, 0.44),
		Color(0.74, 0.22, 0.20),
		Color(0.18, 0.38, 0.32),
		Color(0.68, 0.46, 0.18),
		Color(0.28, 0.22, 0.42),
		Color(0.76, 0.32, 0.26),
		Color(0.20, 0.34, 0.46)
	]

	# Compute total width to center the lineup nicely
	var cursor_x := 0.0
	var positions_x: Array[float] = []
	for idx in layer_count:
		var r_here := outer_radius * pow(layer_scale_decay, float(idx))
		if idx > 0:
			var r_prev := outer_radius * pow(layer_scale_decay, float(idx - 1))
			cursor_x += (r_prev + r_here) * spacing_factor
		positions_x.append(cursor_x)
	var center_offset_x := cursor_x * 0.5

	for idx in layer_count:
		var scale_k := pow(layer_scale_decay, float(idx))
		var h_here := outer_height * scale_k
		var r_here := outer_radius * scale_k
		var shell_params := params.duplicate()
		shell_params["scarf_color"] = scarf_palette[idx % scarf_palette.size()]
		shell_params["body_color"] = body_palette[idx % body_palette.size()]

		var open_y := (h_here * 0.42 if (open_first_shell and idx == 0) else 0.0)
		var doll_shell := _build_single_matryoshka_shell(root, "MatryoshkaLayer%d" % (idx + 1),
			h_here, r_here, shell_params, open_y, 0.0)
		doll_shell.position = Vector3(positions_x[idx] - center_offset_x, 0.0, 0.0)

		# When outer shell #1 is opened, show a nested inner doll sitting right inside its lower shell cavity!
		if open_first_shell and idx == 0:
			var nested_params := params.duplicate()
			nested_params["scarf_color"] = scarf_palette[1]
			nested_params["body_color"] = body_palette[1]
			var nested_doll := _build_single_matryoshka_shell(doll_shell, "NestedInnerDoll",
				h_here * 0.72, r_here * 0.70, nested_params, 0.0, 0.0)
			nested_doll.position = Vector3(0.0, h_here * 0.08, 0.0)

	return root


# #21 纪念品娃娃 (Turned Wooden Folk Souvenir Doll with Sculpted Hair Buns, Collar, Sash & Flared Dress Base)
static func build_prop_21_souvenir_doll(parent: Node3D, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = params.get("node_name", "SouvenirFolkDoll")
	parent.add_child(root)

	var total_height: float = params.get("total_height", 0.52)
	var head_radius: float = params.get("head_radius", 0.115)
	var head_squash: float = params.get("head_squash", 0.94)
	var skirt_flare: float = params.get("skirt_flare", 0.145)
	var waist_ratio: float = params.get("waist_ratio", 0.56)
	var bun_size: float = params.get("bun_size", 0.044)
	var hair_style: int = int(params.get("hair_style", 0)) # 0 = twin side buns, 1 = high crown bun

	var wood_skin: Color = params.get("wood_skin", Color(0.93, 0.83, 0.70))
	var hair_color: Color = params.get("hair_color", Color(0.22, 0.16, 0.13))
	var dress_color: Color = params.get("dress_color", Color(0.76, 0.24, 0.24))
	var sash_color: Color = params.get("sash_color", Color(0.20, 0.34, 0.46))
	var collar_color: Color = params.get("collar_color", Color(0.96, 0.93, 0.86))
	var base_wood: Color = params.get("base_wood", Color(0.78, 0.62, 0.44))

	var body_h := total_height - head_radius * head_squash * 1.85
	var sides := 44

	# 1. Turned Wooden Pedestal Foot Base (0 .. 0.08 * body_h)
	var ped_profile := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(skirt_flare * 0.88, 0.0),
		Vector2(skirt_flare * 0.92, body_h * 0.04),
		Vector2(skirt_flare * 0.84, body_h * 0.08),
		Vector2(0.0, body_h * 0.08)
	])
	build_lathe_mesh(root, "WoodenPedestalBase", ped_profile, sides, base_wood, 0.80, 0.0003)

	# 2. Turned Bell/Tulip Dress Body + Bodice (0.08 * body_h .. body_h)
	var dress_profile := PackedVector2Array([Vector2(0.0, body_h * 0.075)])
	var d_steps := 24
	var waist_h := body_h * 0.66
	var waist_r := skirt_flare * waist_ratio
	for i in d_steps + 1:
		var t := float(i) / d_steps
		var y := lerpf(body_h * 0.075, body_h, t)
		var r: float
		if y <= waist_h:
			var st := (y - body_h * 0.075) / maxf(0.01, waist_h - body_h * 0.075)
			# Graceful bell skirt curve
			r = lerpf(skirt_flare, waist_r, pow(st, 0.82)) + 0.010 * sin(st * PI)
		else:
			var bt := (y - waist_h) / maxf(0.01, body_h - waist_h)
			# Rounded wooden bust/shoulder tapering into neck groove
			var bust_r := waist_r * 1.18
			r = lerpf(waist_r, bust_r, sin(bt * PI * 0.65)) * (1.0 - 0.46 * pow(bt, 2.2))
		dress_profile.append(Vector2(r, y))
	dress_profile.append(Vector2(0.0, body_h))
	build_lathe_mesh(root, "TurnedDressBody", dress_profile, sides, dress_color, 0.74, 0.0003)

	# 3. High Relief Waist Sash Belt + Scalloped Collar Ring — Shrinkwrapped & Extruded on TurnedDressBody
	var eval_dress_r := func(y: float) -> float:
		if y <= waist_h:
			var st := clampf((y - body_h * 0.075) / maxf(0.01, waist_h - body_h * 0.075), 0.0, 1.0)
			return lerpf(skirt_flare, waist_r, pow(st, 0.82)) + 0.010 * sin(st * PI)
		var bt := clampf((y - waist_h) / maxf(0.01, body_h - waist_h), 0.0, 1.0)
		var bust_r := waist_r * 1.18
		return lerpf(waist_r, bust_r, sin(bt * PI * 0.65)) * (1.0 - 0.46 * pow(bt, 2.2))

	var sash_grid := PackedVector3Array()
	for iv in 5:
		var vt := float(iv) / 4.0
		var sy := waist_h + (vt - 0.5) * body_h * 0.09
		var sr: float = eval_dress_r.call(sy)
		for s in sides + 1:
			var a := TAU * float(s) / sides
			sash_grid.append(Vector3(cos(a) * sr, sy, sin(a) * sr))
	_build_extruded_surface_strip(root, "WaistSashBand", sash_grid, 4, sides,
		0.0045, 0.0018, Vector3(0, waist_h, 0), sash_color)

	# Scalloped Collar Ring tilted naturally lower in front (+Z) and higher at back (-Z)
	var col_grid := PackedVector3Array()
	for iv in 5:
		var vt := float(iv) / 4.0 # 0 = neck root, 1 = outer scalloped collar edge
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var front_dip := 0.016 * (0.5 + 0.5 * sin(a)) # sin(a) = +1 at front (+Z), -1 at back (-Z)
			var wave := 0.006 * absf(cos(a * 6.0)) * vt
			var cy := body_h * lerpf(0.97, 0.89, vt) - front_dip - wave
			var cr: float = eval_dress_r.call(cy) + 0.003 * vt
			col_grid.append(Vector3(cos(a) * cr, cy, sin(a) * cr))
	_build_extruded_surface_strip(root, "ScallopedCollar", col_grid, 4, sides,
		0.0045, 0.0018, Vector3(0, body_h * 0.90, 0), collar_color)

	# Carved Wooden Side Arm Reliefs tucked neatly at sides of bodice
	for side_sign: float in [-1.0, 1.0]:
		var arm_pts := PackedVector3Array([
			Vector3(side_sign * (waist_r * 0.82), body_h * 0.91, 0.0),
			Vector3(side_sign * (waist_r * 1.14), body_h * 0.76, 0.018),
			Vector3(side_sign * (waist_r * 0.88), waist_h + 0.01, 0.042)
		])
		add_ValidationBand(root, "CarvedArmReliefL" if side_sign < 0 else "CarvedArmReliefR",
			arm_pts, 0.032, 0.016, collar_color)
		add_ellipsoid(root, "WoodenHandL" if side_sign < 0 else "WoodenHandR",
			Vector3(side_sign * (waist_r * 0.84), waist_h + 0.008, 0.048),
			Vector3(0.018, 0.016, 0.014), wood_skin)

	# 4. Turned Wooden Spherical-Ovoid Head + Sculpted Hair Cap + Cute Painted Face
	var head_center := Vector3(0.0, body_h + head_radius * head_squash * 0.88, 0.0)
	var head_r_vec := Vector3(head_radius, head_radius * head_squash, head_radius)
	add_ellipsoid(root, "WoodenHead", head_center, head_r_vec, wood_skin)

	# Sculpted Hair Cap + Rounded Fringe Bangs
	add_ellipsoid(root, "WoodenHairCap", head_center + Vector3(0, head_radius * 0.08, -head_radius * 0.06),
		head_r_vec * Vector3(1.03, 0.98, 1.02), hair_color)
	add_ellipsoid(root, "WoodenBangs", head_center + Vector3(0, head_radius * 0.34, head_radius * 0.56),
		Vector3(head_radius * 0.78, head_radius * 0.34, head_radius * 0.48), hair_color)

	if hair_style == 0:
		for side_sign: float in [-1.0, 1.0]:
			var bun_pos := head_center + Vector3(side_sign * head_radius * 0.92, head_radius * 0.32, -head_radius * 0.08)
			add_ellipsoid(root, "SideBunL" if side_sign < 0 else "SideBunR",
				bun_pos, Vector3(bun_size, bun_size, bun_size), hair_color)
			add_ellipsoid(root, "BunRibbonL" if side_sign < 0 else "BunRibbonR",
				bun_pos + Vector3(-side_sign * bun_size * 0.45, 0, 0),
				Vector3(bun_size * 0.35, bun_size * 0.85, bun_size * 0.85), dress_color)
	else:
		var top_bun_pos := head_center + Vector3(0, head_radius * head_squash * 1.02, -head_radius * 0.06)
		add_ellipsoid(root, "TopCrownBun", top_bun_pos, Vector3(bun_size * 1.25, bun_size * 1.05, bun_size * 1.25), hair_color)
		add_ellipsoid(root, "TopBunRibbon", top_bun_pos + Vector3(0, -bun_size * 0.5, 0),
			Vector3(bun_size * 1.05, bun_size * 0.35, bun_size * 1.05), sash_color)

	# Painted Face Eyes & Blush
	for side_sign: float in [-1.0, 1.0]:
		add_ellipsoid(root, "DollEyeL" if side_sign < 0 else "DollEyeR",
			head_center + Vector3(side_sign * head_radius * 0.32, -head_radius * 0.04, head_radius * 0.94),
			Vector3(head_radius * 0.09, head_radius * 0.11, head_radius * 0.04), Color(0.14, 0.12, 0.12))
		add_ellipsoid(root, "DollBlushL" if side_sign < 0 else "DollBlushR",
			head_center + Vector3(side_sign * head_radius * 0.48, -head_radius * 0.18, head_radius * 0.84),
			Vector3(head_radius * 0.14, head_radius * 0.09, head_radius * 0.04), Color(0.88, 0.44, 0.42))

	return root


# #22 纪念品球型脑袋+圆锥身体木偶 (Souvenir Spherical-Head + Cone-Body Turned Wooden Peg Doll)
# Adjustable: head_radius, cone_height, cone_base_radius, cone_top_radius, neck_groove_radius, neck_groove_height, base_chamfer, collar_ring_enabled
static func build_prop_22_sphere_cone_peg_doll(parent: Node3D, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = params.get("node_name", "SphereConePegDoll")
	parent.add_child(root)

	var head_radius: float = params.get("head_radius", 0.108)
	var cone_height: float = params.get("cone_height", 0.34)
	var cone_base_radius: float = params.get("cone_base_radius", 0.135)
	var cone_top_radius: float = params.get("cone_top_radius", 0.046)
	var neck_groove_radius: float = params.get("neck_groove_radius", 0.036)
	var neck_groove_height: float = params.get("neck_groove_height", 0.020)
	var base_chamfer: float = params.get("base_chamfer", 0.018)
	var collar_ring_enabled: bool = params.get("collar_ring_enabled", true)

	var head_wood_color: Color = params.get("head_color", Color(0.92, 0.81, 0.67)) # Natural maple/birch wood sphere head
	var cone_paint_color: Color = params.get("cone_color", Color(0.24, 0.42, 0.48)) # Painted or natural wooden cone body
	var accent_ring_color: Color = params.get("accent_color", Color(0.86, 0.66, 0.32))
	var base_wood_color: Color = params.get("base_wood_color", Color(0.84, 0.70, 0.54))

	var sides := 48

	# 1. Lower Chamfered Natural Wood Base Ring + Straight Conical Body Lathe
	var base_profile := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(maxf(0.01, cone_base_radius - base_chamfer), 0.0),
		Vector2(cone_base_radius, base_chamfer),
		Vector2(0.0, base_chamfer)
	])
	build_lathe_mesh(root, "PegBaseChamfer", base_profile, sides, base_wood_color, 0.80, 0.0002)

	var cone_profile := PackedVector2Array([Vector2(0.0, base_chamfer)])
	var c_steps := 16
	for i in c_steps + 1:
		var t := float(i) / c_steps
		var y := lerpf(base_chamfer, cone_height, t)
		var r := lerpf(cone_base_radius, cone_top_radius, t)
		cone_profile.append(Vector2(r, y))
	cone_profile.append(Vector2(0.0, cone_height))
	build_lathe_mesh(root, "ConicalBody", cone_profile, sides, cone_paint_color, 0.76, 0.0003)

	# 2. Turned Wooden Neck Groove Spigot (连接圆锥顶与球形脑袋的车削颈槽)
	var neck_profile := PackedVector2Array([
		Vector2(0.0, cone_height),
		Vector2(cone_top_radius, cone_height),
		Vector2(neck_groove_radius, cone_height + neck_groove_height * 0.5),
		Vector2(minf(head_radius * 0.55, neck_groove_radius * 1.15), cone_height + neck_groove_height),
		Vector2(0.0, cone_height + neck_groove_height)
	])
	build_lathe_mesh(root, "TurnedNeckGroove", neck_profile, sides, base_wood_color, 0.78, 0.0002)

	if collar_ring_enabled:
		var peg_col_grid := PackedVector3Array()
		for iv in 4:
			var vt := float(iv) / 3.0
			for s in sides + 1:
				var a := TAU * float(s) / sides
				var front_dip := 0.012 * (0.5 + 0.5 * sin(a))
				var ry := lerpf(cone_height - 0.004, cone_height - 0.024, vt) - front_dip
				var rr := lerpf(cone_base_radius, cone_top_radius, (ry - base_chamfer) / maxf(0.01, cone_height - base_chamfer))
				peg_col_grid.append(Vector3(cos(a) * rr, ry, sin(a) * rr))
		_build_extruded_surface_strip(root, "PegCollarStripe", peg_col_grid, 3, sides,
			0.0038, 0.0016, Vector3(0, cone_height * 0.9, 0), accent_ring_color)

	# 3. True Spherical Wooden Head (正球型木偶脑袋) sitting cleanly atop the neck groove
	# Overlap distance into sphere: dy = sqrt(R^2 - r_neck^2)
	var r_join := minf(head_radius * 0.75, neck_groove_radius * 1.1)
	var sphere_center_y := cone_height + neck_groove_height + sqrt(maxf(0.0001, head_radius * head_radius - r_join * r_join)) - 0.004
	var head_center := Vector3(0.0, sphere_center_y, 0.0)
	add_ellipsoid(root, "SphericalWoodenHead", head_center, Vector3(head_radius, head_radius, head_radius), head_wood_color, 36, 26)

	# 4. Parametric Carved & Painted Wooden Hair (木偶参数化木雕头发：支持齐刘海波波头/高丸子木髻/双圆木髻)
	var hair_color: Color = params.get("hair_color", Color(0.24, 0.16, 0.12)) # Warm walnut/chestnut carved wood hair
	var hair_style: int = int(params.get("hair_style", 0)) # 0 = sculpted wooden bob + bangs, 1 = topknot bun, 2 = twin side buns
	var bun_size: float = params.get("bun_size", head_radius * 0.38)

	# Sculpted 3D wooden hair cap dome wrapping the crown, back, and sides of the spherical wooden head
	var hc_rings := 18
	var hc_sides := 36
	var hc_verts := PackedVector3Array()
	var hc_inds := PackedInt32Array()
	for i in hc_rings + 1:
		var t := float(i) / hc_rings
		var phi := lerpf(0.0, PI * 0.76, t)
		var sp := sin(phi)
		var cp := cos(phi)
		for s in hc_sides + 1:
			var a := -PI * 0.5 + TAU * float(s) / hc_sides
			var ca := cos(a)
			var sa := sin(a)
			# Carve an arched face opening on the front (+Z, sa > 0) while wrapping low over the back & sides
			var face_cut := maxf(0.0, sa) * smoothstep(0.22, 0.92, t)
			var eff_phi := phi * (1.0 - 0.56 * face_cut)
			var bob_flare := (0.012 * pow(t, 1.6) * (1.0 - 0.65 * maxf(0.0, sa))) if hair_style == 0 else 0.003
			var r_shell := head_radius * (1.045 + 0.025 * sin(t * PI)) + bob_flare
			var px := ca * sin(eff_phi) * r_shell
			var py := cos(eff_phi) * r_shell
			var pz := sa * sin(eff_phi) * r_shell - head_radius * 0.02 * (1.0 - face_cut)
			hc_verts.append(head_center + Vector3(px, py, pz))
	for i in hc_rings:
		for s in hc_sides:
			var a := i * (hc_sides + 1) + s
			var b := a + hc_sides + 1
			emit_quad_outward(hc_verts, hc_inds, a, a + 1, b + 1, b, head_center)
	build_mesh_instance(root, "PegWoodenHairCap", hc_verts,
		compute_welded_normals(hc_verts, hc_inds), hc_inds, hair_color, 0.78, 0.0003)

	# Sculpted Curved Front Wooden Fringe Bangs (木雕弧形前刘海)
	var bg_verts := PackedVector3Array()
	var bg_inds := PackedInt32Array()
	var bu_steps := 18
	var bv_steps := 8
	for iv in bv_steps + 1:
		var vt := float(iv) / bv_steps
		var phi := lerpf(0.14 * PI, 0.42 * PI, vt)
		for iu in bu_steps + 1:
			var ut := float(iu) / bu_steps - 0.5
			var ang := PI * 0.5 + ut * 0.68 * PI
			var r_bang := head_radius * (1.055 + 0.025 * sin(vt * PI) * cos(ut * PI))
			# Subtle center/side carve groove in bangs
			if hair_style == 2:
				r_bang -= head_radius * 0.022 * exp(-pow(ut / 0.10, 2.0)) * pow(vt, 1.2)
			var px := cos(ang) * sin(phi) * r_bang
			var py := cos(phi) * r_bang + head_radius * 0.02 * (1.0 - vt)
			var pz := sin(ang) * sin(phi) * r_bang
			bg_verts.append(head_center + Vector3(px, py, pz))
	for iv in bv_steps:
		for iu in bu_steps:
			var a := iv * (bu_steps + 1) + iu
			var b := a + bu_steps + 1
			emit_quad_outward(bg_verts, bg_inds, a, a + 1, b + 1, b, head_center)
	build_mesh_instance(root, "PegWoodenBangs", bg_verts,
		compute_welded_normals(bg_verts, bg_inds), bg_inds, hair_color.lightened(0.03), 0.76, 0.0003)

	# Cheek-framing carved wooden side locks (木雕鬓角)
	for side_sign: float in [-1.0, 1.0]:
		var lock_pts := PackedVector3Array([
			head_center + Vector3(side_sign * head_radius * 0.78, head_radius * 0.36, head_radius * 0.54),
			head_center + Vector3(side_sign * head_radius * 0.94, head_radius * 0.06, head_radius * 0.44),
			head_center + Vector3(side_sign * head_radius * 0.84, -head_radius * 0.24, head_radius * 0.36)
		])
		add_ValidationBand(root, "PegSideLockL" if side_sign < 0 else "PegSideLockR",
			lock_pts, head_radius * 0.24, head_radius * 0.11, hair_color)

	if hair_style == 1:
		# Turned Wooden Topknot Crown Bun + Accent Ring
		var bun_pos := head_center + Vector3(0.0, head_radius * 1.04, -head_radius * 0.08)
		add_ellipsoid(root, "PegTopknotBun", bun_pos, Vector3(bun_size * 1.15, bun_size * 0.95, bun_size * 1.15), hair_color)
		add_ellipsoid(root, "PegBunTieRing", bun_pos + Vector3(0.0, -bun_size * 0.45, 0.0),
			Vector3(bun_size * 0.95, bun_size * 0.32, bun_size * 0.95), accent_ring_color)
	elif hair_style == 2:
		# Twin Carved Wooden Side Buns
		for side_sign: float in [-1.0, 1.0]:
			var sb_pos := head_center + Vector3(side_sign * head_radius * 0.92, head_radius * 0.46, -head_radius * 0.06)
			add_ellipsoid(root, "PegSideBunL" if side_sign < 0 else "PegSideBunR",
				sb_pos, Vector3(bun_size * 0.92, bun_size * 0.92, bun_size * 0.92), hair_color)
			add_ellipsoid(root, "PegSideBunRingL" if side_sign < 0 else "PegSideBunRingR",
				sb_pos + Vector3(-side_sign * bun_size * 0.42, 0.0, 0.0),
				Vector3(bun_size * 0.32, bun_size * 0.78, bun_size * 0.78), accent_ring_color)

	# Minimalist peg-doll burnt-wood dot eyes & warm blush dots
	for side_sign: float in [-1.0, 1.0]:
		add_ellipsoid(root, "PegEyeL" if side_sign < 0 else "PegEyeR",
			head_center + Vector3(side_sign * head_radius * 0.28, -head_radius * 0.04, head_radius * 0.96),
			Vector3(head_radius * 0.075, head_radius * 0.075, head_radius * 0.035), Color(0.18, 0.14, 0.11))
		add_ellipsoid(root, "PegBlushL" if side_sign < 0 else "PegBlushR",
			head_center + Vector3(side_sign * head_radius * 0.42, -head_radius * 0.16, head_radius * 0.89),
			Vector3(head_radius * 0.11, head_radius * 0.07, head_radius * 0.03), Color(0.86, 0.48, 0.44))

	return root


static func invoke(fn_name: String, target: Node3D, params: Dictionary = {}) -> Node3D:
	match fn_name:
		"build_hair_01_bob":
			build_hair_01_bob(target, params)
			return null
		"build_hair_02_high_ponytail":
			build_hair_02_high_ponytail(target, params)
			return null
		"build_hair_03_half_up_long":
			build_hair_03_half_up_long(target, params)
			return null
		"build_hair_04_topknot_bun":
			build_hair_04_topknot_bun(target, params)
			return null
		"build_hair_05_wavy_lob":
			build_hair_05_wavy_lob(target, params)
			return null
		"build_hair_06_twin_pigtails":
			build_hair_06_twin_pigtails(target, params)
			return null
		"build_garment_07_cuban_shirt_remake": return build_garment_07_cuban_shirt_remake(target, params)
		"build_garment_08_babydoll_remake": return build_garment_08_babydoll_remake(target, params)
		"build_garment_09_preppy_vest_remake": return build_garment_09_preppy_vest_remake(target, params)
		"build_garment_10_sailor_blouse": return build_garment_10_sailor_blouse(target, params)
		"build_garment_11_knit_cardigan": return build_garment_11_knit_cardigan(target, params)
		"build_garment_12_pinafore_dress": return build_garment_12_pinafore_dress(target, params)
		"build_garment_13_square_neck_top": return build_garment_13_square_neck_top(target, params)
		"build_garment_14_pleated_shorts": return build_garment_14_pleated_shorts(target, params)
		"build_garment_15_mock_neck_shift_dress": return build_garment_15_mock_neck_shift_dress(target, params)
		"build_hat_16_yi_liberation_cap": return build_hat_16_yi_liberation_cap(target, params)
		"build_hat_17_yi_adu_hat": return build_hat_17_yi_adu_hat(target, params)
		"build_hat_18_estonian_headscarf": return build_hat_18_estonian_headscarf(target, params)
		"build_prop_19_canvas_tote_bag": return build_prop_19_canvas_tote_bag(target, params)
		"build_prop_20_matryoshka_set": return build_prop_20_matryoshka_set(target, params)
		"build_prop_21_souvenir_doll": return build_prop_21_souvenir_doll(target, params)
		"build_prop_22_sphere_cone_peg_doll": return build_prop_22_sphere_cone_peg_doll(target, params)
	return null
