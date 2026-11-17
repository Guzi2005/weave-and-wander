extends RefCounted
## A small, pose-aware collision cage sampled from the actual inner garments.
## It follows the same skin and gravity morphs, without evaluating full meshes each frame.

const RING_COUNT := 12
static var _sample_cache := {}
var centers := PackedVector4Array()
var across := PackedVector4Array()
var depth := PackedVector4Array()
var rings: Array = []


func setup(meshes: Array, bones: Dictionary) -> void:
	rings.clear()
	centers.resize(RING_COUNT)
	across.resize(RING_COUNT)
	depth.resize(RING_COUNT)
	for specification in [["LongSkirt", [.24, .43, .64, .85, 1.06, 1.29]],
		["TailoredShell", [1.31, 1.43, 1.56, 1.70, 1.82, 1.92]]]:
		var part: MeshInstance3D
		for candidate in meshes:
			if str(candidate.name) == specification[0] and candidate.visible: part = candidate
		var arrays: Array = part.mesh.surface_get_arrays(0) if part != null else []
		var shapes: Array = part.mesh.surface_get_blend_shape_arrays(0) if part != null else []
		var key := ""
		var eligible: Array[int] = []
		if part != null:
			var hasher := HashingContext.new()
			hasher.start(HashingContext.HASH_SHA256)
			hasher.update(var_to_bytes([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_BONES], arrays[Mesh.ARRAY_WEIGHTS], shapes, specification]))
			key = hasher.finish().hex_encode()
			if _sample_cache.has(key):
				for samples in _sample_cache[key]: rings.append({"part": weakref(part), "samples": samples})
				continue
			for i in arrays[Mesh.ARRAY_VERTEX].size():
				var sleeve := 0.0
				for j in 4:
					if arrays[Mesh.ARRAY_BONES][i * 4 + j] in [bones.UpperArmL, bones.ForearmL, bones.UpperArmR, bones.ForearmR]:
						sleeve += arrays[Mesh.ARRAY_WEIGHTS][i * 4 + j]
				if sleeve <= .001: eligible.append(i)
		var cached_rings: Array = []
		for height in specification[1]:
			if part == null:
				rings.append({})
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var samples: Array = []
			for direction in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
				var best := INF
				var chosen := -1
				for i in eligible:
					var radial := Vector3(vertices[i].x, 0, vertices[i].z).normalized()
					var score := pow(vertices[i].y - float(height), 2) * 8.0 + (1.0 - radial.dot(direction)) * .1
					if score < best:
						best = score
						chosen = i
				if chosen < 0: continue
				var targets: Array[Vector3] = []
				var normal_targets: Array[Vector3] = []
				for shape in shapes:
					targets.append(shape[Mesh.ARRAY_VERTEX][chosen] - vertices[chosen])
					normal_targets.append(shape[Mesh.ARRAY_NORMAL][chosen] - arrays[Mesh.ARRAY_NORMAL][chosen])
				samples.append({"p": vertices[chosen], "ids": ids.slice(chosen * 4, chosen * 4 + 4),
					"weights": weights.slice(chosen * 4, chosen * 4 + 4), "targets": targets,
					"n": arrays[Mesh.ARRAY_NORMAL][chosen], "normal_targets": normal_targets})
			rings.append({"part": weakref(part), "samples": samples})
			cached_rings.append(samples)
		if not key.is_empty():
			if _sample_cache.size() >= 128: _sample_cache.clear()
			_sample_cache[key] = cached_rings


func update(transforms: Array[Transform3D], contact: RefCounted) -> void:
	for i in rings.size():
		var ring: Dictionary = rings[i]
		centers[i] = Vector4.ZERO
		if ring.is_empty(): continue
		var part: MeshInstance3D = ring.part.get_ref()
		if not is_instance_valid(part) or ring.samples.size() != 4: continue
		var points := PackedVector3Array()
		for sample in ring.samples:
			var p: Vector3 = sample.p
			var n: Vector3 = sample.n
			for shape in sample.targets.size():
				p += sample.targets[shape] * part.get_blend_shape_value(shape)
				n += sample.normal_targets[shape] * part.get_blend_shape_value(shape)
			var posed := Vector3.ZERO
			var normal := Vector3.ZERO
			for j in 4:
				posed += (transforms[sample.ids[j]] * p) * sample.weights[j]
				normal += (transforms[sample.ids[j]].basis * n) * sample.weights[j]
			if i < 6:
				var s := clampf((1.31 - sample.p.y) / 1.11, 0, 1)
				normal = contact.motion_normal(posed, normal, s)
				posed = contact.motion_point(posed, s)
				posed = contact.project_skirt(posed)
			points.append(contact.project(posed, contact.profile.body_clearance(), false, normal.normalized() if i < 6 else Vector3.ZERO))
		var center := (points[0] + points[1] + points[2] + points[3]) * .25
		var u := (points[0] - points[2]) * .5
		var v := (points[1] - points[3]) * .5
		centers[i] = Vector4(center.x, center.y, center.z, 1.0 if i < 6 else 2.0)
		across[i] = Vector4(u.x, u.y, u.z, 0)
		depth[i] = Vector4(v.x, v.y, v.z, 0)


func project(point: Vector3, gap: float) -> Vector3:
	for i in RING_COUNT - 1:
		if centers[i].w == 0 or centers[i].w != centers[i + 1].w: continue
		var a := Vector3(centers[i].x, centers[i].y, centers[i].z)
		var b := Vector3(centers[i + 1].x, centers[i + 1].y, centers[i + 1].z)
		var axis := b - a
		var t := (point - a).dot(axis) / maxf(axis.length_squared(), .000001)
		if t < 0 or t > 1: continue
		var center := a.lerp(b, t)
		var u4 := across[i].lerp(across[i + 1], t)
		var v4 := depth[i].lerp(depth[i + 1], t)
		var u := Vector3(u4.x, u4.y, u4.z)
		var v := Vector3(v4.x, v4.y, v4.z)
		var n := u.cross(v).normalized()
		var basis := Basis(u, n, v)
		if absf(basis.determinant()) < .000001: continue
		var local := basis.inverse() * (point - center)
		var radius := Vector2(local.x, local.z).length()
		if radius < .00001: continue
		var surface := (u * local.x + v * local.z) / radius
		var required := 1.0 + gap / maxf(surface.length(), .001)
		if radius < required: point = center + surface * required + n * local.y
	return point
