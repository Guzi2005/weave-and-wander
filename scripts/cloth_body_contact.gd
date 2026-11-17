extends RefCounted
## Game-scale post-skin contact, paired with the existing gravity/rest cloth morphs.
## Body margins + ordered garment contact. This is not a full cloth simulation.

var rig: RefCounted
var bone_names: Array[String] = ["Hips", "Spine"]
var ends_a := PackedVector4Array([Vector4(0, 1.12, -.014, .232), Vector4(0, 1.43, .015, .194)])
var ends_b := PackedVector4Array([Vector4(0, 1.20, -.01, .222), Vector4(0, 1.72, .02, .197)])
var settings := PackedVector4Array([Vector4(.73, 0, 0, 0), Vector4(.76, 0, 0, 0)])
var to_pose: Array[Transform3D] = []
var to_rest: Array[Transform3D] = []
var materials: Array[ShaderMaterial] = []
var _material_cache := {}
var rest_a := PackedVector4Array()
var rest_b := PackedVector4Array()
var profile: Resource
var _bone_transforms: Array[Transform3D] = []
var surface := preload("res://scripts/cloth_surface_proxy.gd").new()
var _owner: WeakRef
var _source_signature := ""
var motion := preload("res://scripts/garment_secondary_motion.gd").new()
var fabric: Resource
var motion_amount := 0.0


func setup(doll: Node3D) -> void:
	rig = doll.rig
	_owner = weakref(doll)
	profile = doll.cloth_contact
	fabric = doll.skirt_fabric
	build_rest_envelopes()
	_refresh_sources()
	_bind_materials()
	update()


func build_rest_envelopes() -> void:
	# Shared by bind-time contour fitting and post-skin contact, so a different
	# collision proxy does not introduce a fresh hip bump after the shape is fitted.
	bone_names = ["Hips", "Spine"]
	ends_a = PackedVector4Array([Vector4(0, 1.12, -.014, .232), Vector4(0, 1.43, .015, .194)])
	ends_b = PackedVector4Array([Vector4(0, 1.20, -.01, .222), Vector4(0, 1.72, .02, .197)])
	settings = PackedVector4Array([Vector4(.73, 0, 0, 0), Vector4(.76, 0, 0, 0)])
	to_pose.clear()
	to_rest.clear()
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0 else "R"
		bone_names.append_array(["arm" + suffix, "arm" + suffix, "arm" + suffix, "leg" + suffix, "leg" + suffix])
		ends_a.append_array(PackedVector4Array([
			Vector4(side * .16, 1.78, .018, .045), Vector4(side * .205, 1.59, .012, .072),
			Vector4(side * .263, 1.33, .020, .089),
			Vector4(side * .136, 1.08, -.01, .143), Vector4(side * .134, .69, .024, .101)]))
		ends_b.append_array(PackedVector4Array([
			Vector4(side * .205, 1.59, .012, .072), Vector4(side * .263, 1.33, .020, .089),
			Vector4(side * .295, 1.21, .026, .102),
			Vector4(side * .134, .72, .024, .104), Vector4(side * .132, .24, .034, .078)]))
		settings.append_array(PackedVector4Array([Vector4(1, 0, 0, 0), Vector4(1, 0, 0, 0), Vector4(1, 0, 0, 0), Vector4(1.04, 0, 0, 0), Vector4(1.04, 0, 0, 0)]))
	for side in [-1.0, 1.0]:
		bone_names.append("armL" if side < 0 else "armR")
		ends_a.append(Vector4(side * .30, 1.19, .028, .090))
		ends_b.append(Vector4(side * .30, 1.055, .030, .078))
		settings.append(Vector4(.92, 0, 0, 0))
	rest_a = ends_a.duplicate()
	rest_b = ends_b.duplicate()
	for i in bone_names.size():
		to_pose.append(Transform3D.IDENTITY)
		to_rest.append(Transform3D.IDENTITY)


func _bind_materials() -> void:
	for part: MeshInstance3D in rig.meshes:
		if part.get_meta("is_underbody", false): continue
		if str(part.name).begins_with("Button") or preload("res://scripts/garment_definition.gd").is_flower(part): continue
		if preload("res://scripts/garment_definition.gd").part_slot(part) in ["top", "bottom", "outer"]:
			var material := part.material_override as ShaderMaterial
			if material == null or not _supports_contact(material): continue
			# Body and garment can share a pigment material; opt in only the cloth copy.
			# Sleeves contact arms. Skirts must not balloon around hands resting on the lap.
			var arms: bool = preload("res://scripts/garment_definition.gd").part_slot(part) == "top"
			var layer: bool = part.has_meta("skin_layer_sources") and not str(part.name).begins_with("ApronStrap")
			var depth := _layer_depth(part)
			var skirt: bool = part.get_meta("semantic", "") in ["skirt", "apron"]
			if skirt: _bind_motion_coordinates(part)
			var lift: float = profile.layer_gap + profile.rendering_thickness * 2.0 if part.has_meta("skin_layer_sources") else 0.0
			lift *= depth
			if str(part.name).begins_with("ApronStrap"): lift = .004
			if str(part.name) in ["CuffBinding", "WaistRibbon"]: lift = .003
			var key := str(material.get_instance_id()) + ":" + str(_clearance(part)) + ":" + str(arms) + ":" + str(lift) + ":" + str(layer) + ":" + str(skirt)
			if not _material_cache.has(key):
				var copy := material.duplicate() as ShaderMaterial
				copy.set_shader_parameter("cloth_layer_clearance", _clearance(part))
				copy.set_shader_parameter("cloth_surface_lift", lift)
				copy.set_shader_parameter("cloth_contact_arms", arms)
				copy.set_shader_parameter("cloth_contact_enabled", true)
				copy.set_shader_parameter("cloth_outer_layer", layer)
				copy.set_shader_parameter("cloth_layer_depth", float(depth))
				copy.set_shader_parameter("cloth_skirt_side", skirt)
				copy.set_shader_parameter("cloth_secondary_enabled", skirt)
				_material_cache[key] = copy
				materials.append(copy)
			part.material_override = _material_cache[key]


func _bind_motion_coordinates(part: MeshInstance3D) -> void:
	# Stable root-to-hem coordinates survive skinning and garment folding.
	var arrays := part.mesh.surface_get_arrays(0)
	var uv := PackedVector2Array()
	for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		uv.append(Vector2(clampf((1.31 - point.y) / 1.11, 0, 1), 1.0))
	arrays[Mesh.ARRAY_TEX_UV2] = uv
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = part.mesh.blend_shape_mode
	for i in part.mesh.get_blend_shape_count(): mesh.add_blend_shape(part.mesh.get_blend_shape_name(i))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, part.mesh.surface_get_blend_shape_arrays(0))
	part.mesh = mesh
	# GPU displacement is outside the undeformed mesh bounds at the hem.
	part.extra_cull_margin = maxf(part.extra_cull_margin, .5)
	part.set_meta("cloth_motion_uv", true)


func advance(delta: float) -> void:
	var doll: Node3D = _owner.get_ref()
	if not is_instance_valid(doll): return
	var next_fabric: Resource = doll.skirt_fabric
	if "garments" in doll:
		for item in doll.garments:
			if is_instance_valid(item) and item.location == "worn" and "bottom" in item.definition.slots():
				if item.definition.fabric_physics != null: next_fabric = item.definition.fabric_physics
	if fabric != next_fabric:
		fabric = next_fabric
		motion.clear()
	motion.advance(delta, doll.body_rig.global_transform, fabric, doll._rest_blend)
	motion_amount = (1.0 - smoothstep(0.0, .35, doll._rest_blend)) if fabric.enabled and motion.is_active() else 0.0


func motion_point(point: Vector3, s: float) -> Vector3:
	return motion.deform(point, s, _bone_transforms[rig.bones.Hips], motion_amount, fabric.stretch_stiffness)


func motion_normal(point: Vector3, normal: Vector3, s: float) -> Vector3:
	return motion.deform_normal(point, normal, s, _bone_transforms[rig.bones.Hips], motion_amount, fabric.stretch_stiffness)


func _supports_contact(material: ShaderMaterial) -> bool:
	return material.shader != null and material.shader.resource_path in ["res://shaders/doll_volume.gdshader", "res://shaders/doll_costume.gdshader", "res://shaders/material_cloth.gdshader"]


func _clearance(part: MeshInstance3D) -> float:
	var gap: float = profile.layer_gap * _layer_depth(part) if part.has_meta("skin_layer_sources") else 0.0
	if str(part.name) in ["CuffBinding", "WaistRibbon"]: gap = .004
	return profile.body_clearance() + gap


func _layer_depth(part: MeshInstance3D, visited: Array = []) -> int:
	if not part.has_meta("skin_layer_sources") or part in visited: return 0
	var path := visited.duplicate()
	path.append(part)
	var depth := 0
	for source_path in part.get_meta("skin_layer_sources"):
		var source := part.get_node_or_null(NodePath(source_path)) as MeshInstance3D
		if source != null: depth = maxi(depth, _layer_depth(source, path))
	return mini(6, depth + 1)


func update() -> void:
	_refresh_sources()
	to_pose.clear()
	to_rest.clear()
	_bone_transforms.clear()
	for id in rig.skeleton.get_bone_count():
		_bone_transforms.append(rig.global_pose(id) * rig.skeleton.get_bone_global_rest(id).affine_inverse())
	for i in bone_names.size():
		var label := bone_names[i]
		var transform := Transform3D.IDENTITY
		if label.begins_with("arm") or label.begins_with("leg"):
			ends_a[i] = _posed_end(label, rest_a[i])
			ends_b[i] = _posed_end(label, rest_b[i])
		else:
			var id: int = rig.bones[label]
			transform = _bone_transforms[id]
		to_pose.append(transform)
		to_rest.append(transform.affine_inverse())
	surface.update(_bone_transforms, self)
	for material in materials: apply(material)


func _refresh_sources() -> void:
	var candidates: Array = rig.meshes.duplicate()
	var doll: Node3D = _owner.get_ref()
	if is_instance_valid(doll) and "garments" in doll:
		for item in doll.garments:
			if is_instance_valid(item) and item.location == "worn":
				# The contact cage and rendered inventory need the same frame's rest pose.
				item._sync_rest_shapes(doll)
				candidates.append_array(item.parts)
	var sources: Array = []
	for label in ["LongSkirt", "TailoredShell"]:
		var chosen: MeshInstance3D
		for part in candidates:
			if is_instance_valid(part) and part.visible and str(part.name) == label: chosen = part
		if chosen != null: sources.append(chosen)
	var signature := ""
	for part in sources: signature += "%d:%d;" % [part.get_instance_id(), part.mesh.get_instance_id()]
	if signature != _source_signature or surface.rings.is_empty():
		_source_signature = signature
		surface.setup(sources, rig.bones)


func _posed_end(semantic: String, end: Vector4) -> Vector4:
	var p := Vector3(end.x, end.y, end.z)
	var influences: Array = rig._weights(semantic, "ArmMannequin" if semantic.begins_with("arm") else "LegMannequin", p)
	var result := Vector3.ZERO
	for j in 4:
		var id: int = influences[0][j]
		var transform: Transform3D = _bone_transforms[id]
		result += (transform * p) * float(influences[1][j])
	return Vector4(result.x, result.y, result.z, end.w)


func apply(material: ShaderMaterial) -> void:
	if not _supports_contact(material) or material.get_shader_parameter("cloth_contact_enabled") != true: return
	material.set_shader_parameter("cloth_contact_a", ends_a)
	material.set_shader_parameter("cloth_contact_b", ends_b)
	material.set_shader_parameter("cloth_contact_settings", settings)
	material.set_shader_parameter("cloth_to_pose", to_pose)
	material.set_shader_parameter("cloth_to_rest", to_rest)
	material.set_shader_parameter("cloth_surface_centers", surface.centers)
	material.set_shader_parameter("cloth_surface_across", surface.across)
	material.set_shader_parameter("cloth_surface_depth", surface.depth)
	material.set_shader_parameter("cloth_arm_bones", Vector4(rig.bones.UpperArmL, rig.bones.ForearmL, rig.bones.UpperArmR, rig.bones.ForearmR))
	material.set_shader_parameter("cloth_fabric_gap", profile.layer_gap + profile.rendering_thickness)
	material.set_shader_parameter("cloth_sleeve_gap", profile.layer_gap * 3.0 + profile.rendering_thickness * 2.0)
	material.set_shader_parameter("cloth_collision_margin", profile.collision_thickness + fabric.collision_margin())
	material.set_shader_parameter("cloth_side_axis", _bone_transforms[rig.bones.Hips].basis.x.normalized())
	material.set_shader_parameter("cloth_motion_states", motion.states)
	material.set_shader_parameter("cloth_motion_amount", motion_amount)
	material.set_shader_parameter("cloth_motion_stretch", fabric.stretch_stiffness)


func evaluate_vertices(part: MeshInstance3D) -> PackedVector3Array:
	var points: PackedVector3Array = rig.deformed_vertices(part)
	var material := part.material_override as ShaderMaterial
	if material == null or material.get_shader_parameter("cloth_contact_enabled") != true: return points
	var arrays := part.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for shape in part.mesh.get_blend_shape_count():
		var amount := part.get_blend_shape_value(shape)
		if is_zero_approx(amount): continue
		var target: PackedVector3Array = part.mesh.surface_get_blend_shape_arrays(0)[shape][Mesh.ARRAY_NORMAL]
		for index in normals.size(): normals[index] += (target[index] - arrays[Mesh.ARRAY_NORMAL][index]) * amount
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var arm_ids: Array = [rig.bones.UpperArmL, rig.bones.ForearmL, rig.bones.UpperArmR, rig.bones.ForearmR]
	var clearance: float = material.get_shader_parameter("cloth_layer_clearance")
	var lift: float = material.get_shader_parameter("cloth_surface_lift")
	for i in points.size():
		var normal := Vector3.ZERO
		var sleeve := 0.0
		var forearm := 0.0
		for j in 4:
			var id: int = ids[i * 4 + j]
			var weight: float = weights[i * 4 + j]
			normal += (_bone_transforms[id].basis * normals[i]) * weight
			if id in arm_ids: sleeve += weight
			if id in [rig.bones.ForearmL, rig.bones.ForearmR]: forearm += weight
		var arms: bool = material.get_shader_parameter("cloth_contact_arms") and sleeve > .2
		var skirt: bool = material.get_shader_parameter("cloth_skirt_side")
		if material.get_shader_parameter("cloth_secondary_enabled") == true and arrays[Mesh.ARRAY_TEX_UV2] != null:
			var s: float = arrays[Mesh.ARRAY_TEX_UV2][i].x
			normal = motion_normal(points[i], normal, s)
			points[i] = motion_point(points[i], s)
		points[i] = project(points[i], clearance, arms, normal.normalized() if skirt else Vector3.ZERO)
		if skirt:
			points[i] = project(project_skirt(points[i]), clearance, false, normal.normalized())
		points[i] += normal.normalized() * lift
		var contact_weight := smoothstep(.35, .85, sleeve) * smoothstep(.04, .35, forearm) if arms else 0.0
		if material.get_shader_parameter("cloth_outer_layer"): contact_weight = 1.0
		if contact_weight > 0:
			var depth: float = maxf(1.0, material.get_shader_parameter("cloth_layer_depth"))
			var gap: float = (profile.layer_gap * 3.0 + profile.rendering_thickness * 2.0) if arms else (profile.layer_gap + profile.rendering_thickness) * depth
			points[i] = points[i].lerp(surface.project(points[i], gap), contact_weight)
	return points


func project_skirt(point: Vector3) -> Vector3:
	# The skirt is inside the relaxed arm. Compress its side underneath the hand,
	# rather than choosing the outward capsule exit and wrapping cloth over fingers.
	var axis: Vector3 = _bone_transforms[rig.bones.Hips].basis.x.normalized()
	for i in bone_names.size():
		if not bone_names[i].begins_with("arm"): continue
		var a := Vector3(ends_a[i].x, ends_a[i].y, ends_a[i].z)
		var b := Vector3(ends_b[i].x, ends_b[i].y, ends_b[i].z)
		var span := b - a
		var t := clampf((point - a).dot(span) / maxf(span.length_squared(), .000001), 0, 1)
		var radial := point - a.lerp(b, t)
		var radius: float = lerpf(ends_a[i].w, ends_b[i].w, t) + profile.collision_thickness + fabric.collision_margin()
		if radial.length_squared() >= radius * radius: continue
		var direction := axis * (1.0 if bone_names[i].ends_with("L") else -1.0)
		var dot := radial.dot(direction)
		var distance := -dot + sqrt(maxf(0, dot * dot + radius * radius - radial.length_squared()))
		point += direction * minf(distance, .14)
	return point


func project(point: Vector3, clearance := .025, include_arms := true, direction := Vector3.ZERO) -> Vector3:
	for pass_index in 2:
		for i in bone_names.size():
			if not include_arms and bone_names[i].begins_with("arm"): continue
			var p := to_rest[i] * point
			var a := Vector3(ends_a[i].x, ends_a[i].y, ends_a[i].z)
			var b := Vector3(ends_b[i].x, ends_b[i].y, ends_b[i].z)
			p.z /= settings[i].x
			a.z /= settings[i].x
			b.z /= settings[i].x
			var span := b - a
			var t := clampf((p - a).dot(span) / maxf(span.length_squared(), .000001), 0, 1)
			var center := a.lerp(b, t)
			var radial := p - center
			var radius := lerpf(ends_a[i].w, ends_b[i].w, t) + clearance
			if radial.length() < radius:
				if direction.length_squared() > .1 and not bone_names[i].begins_with("arm"):
					var ray: Vector3 = to_rest[i].basis * direction
					ray.z /= settings[i].x
					ray = ray.normalized()
					var dot := radial.dot(ray)
					p += ray * (-dot + sqrt(maxf(0, dot * dot + radius * radius - radial.length_squared())))
				else:
					p = center + (radial.normalized() if radial.length() > .00001 else Vector3.BACK) * radius
				p.z *= settings[i].x
				point = to_pose[i] * p
	return point
