@tool
class_name ProceduralGarment3D
extends MeshInstance3D

signal geometry_rebuilt

@export_range(1.05, 1.30, 0.005) var waist_height := 1.13:
	set(value):
		waist_height = clampf(value, 1.05, 1.30)
		_queue_rebuild()
@export_range(0.85, 1.20, 0.01) var body_width := 1.0:
	set(value):
		body_width = clampf(value, 0.85, 1.20)
		_queue_rebuild()
@export_range(0.85, 1.15, 0.01) var sleeve_length := 1.0:
	set(value):
		sleeve_length = clampf(value, 0.85, 1.15)
		_queue_rebuild()
@export_range(0.70, 1.35, 0.01) var cuff_width := 1.0:
	set(value):
		cuff_width = clampf(value, 0.70, 1.35)
		_queue_rebuild()

var _pending := false


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if is_inside_tree() and not _pending:
		_pending = true
		rebuild.call_deferred()


func rebuild() -> void:
	_pending = false
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := [Vector3(waist_height, 0.285, 0.202), Vector3(1.52, 0.263, 0.194),
		Vector3(1.67, 0.254, 0.187), Vector3(1.6925, 0.253, 0.186),
		Vector3(1.715, 0.252, 0.184), Vector3(1.7375, 0.247, 0.179),
		Vector3(1.76, 0.230, 0.171), Vector3(1.7825, 0.216, 0.163),
		Vector3(1.805, 0.202, 0.151), Vector3(1.8275, 0.192, 0.141),
		Vector3(1.85, 0.185, 0.132), Vector3(1.90, 0.170, 0.107),
		Vector3(1.93, 0.105, 0.095)]
	const SEGMENTS := 32
	const HOLE_BOTTOM := 2
	const HOLE_TOP := 10
	for ring in rings:
		for column in SEGMENTS:
			var angle := TAU * column / SEGMENTS
			vertices.append(Vector3(sin(angle) * ring.y * body_width, ring.x, cos(angle) * ring.z))
			arm_weights.append(0.0)
	for row in rings.size() - 1:
		for column in SEGMENTS:
			var armhole := (column >= 4 and column < 12) or (column >= 20 and column < 28)
			if armhole and row >= HOLE_BOTTOM and row < HOLE_TOP:
				continue
			var a := row * SEGMENTS + column
			var b := (row + 1) * SEGMENTS + column
			var c := row * SEGMENTS + (column + 1) % SEGMENTS
			var d := (row + 1) * SEGMENTS + (column + 1) % SEGMENTS
			indices.append_array(PackedInt32Array([a, b, c, c, b, d]))
	var smooth_vertices: Array[int] = []
	for side in [-1.0, 1.0]:
		var start := 4 if side > 0 else 28
		var direction := 1 if side > 0 else -1
		var boundary: Array[int] = []
		# Reuse the torso's armhole vertices, never an overlapping sleeve cap.
		for i in 8:
			boundary.append(HOLE_TOP * SEGMENTS + start + direction * i)
		for i in 8:
			boundary.append((HOLE_TOP - i) * SEGMENTS + start + direction * 8)
		for i in 8:
			boundary.append(HOLE_BOTTOM * SEGMENTS + start + direction * (8 - i))
		for i in 8:
			boundary.append((HOLE_BOTTOM + i) * SEGMENTS + start)
		smooth_vertices.append_array(boundary)
		for i in boundary:
			arm_weights[i] = side * 0.2
		var previous := boundary.duplicate()
		var sections := [Vector3(1.54, 0.35, 0.084), Vector3(1.43, 0.38, 0.112),
			Vector3(1.34, 0.405, 0.14), Vector3(1.23, 0.425, 0.171), Vector3(1.195, 0.43, 0.178)]
		var depths := [0.112, 0.116, 0.128, 0.151, 0.160]
		for step in 7:
			var loop: Array[int] = []
			for i in SEGMENTS:
				var angle := PI * 0.25 + TAU * i / SEGMENTS
				var section_index := maxi(step - 2, 0)
				var section: Vector3 = sections[section_index]
				var flare := lerpf(1.0, cuff_width, float(section_index) / 4.0)
				var point := Vector3(side * (section.y * body_width + sin(angle) * section.z * flare),
					1.619 - (1.54 - section.x) * (0.424 / 0.345) * sleeve_length, cos(angle) * depths[section_index] * flare)
				if step <= 2:
					point.y += sin(angle) * 0.033
				if step < 2:
					point = vertices[boundary[i]].lerp(point, (step + 1) / 3.0)
				loop.append(vertices.size())
				if step < 3:
					smooth_vertices.append(vertices.size())
				vertices.append(point)
				arm_weights.append(side * (lerpf(0.2, 1.0, (step + 1) / 3.0) if step < 2 else 1.0))
			for i in SEGMENTS:
				var a: int = previous[i]
				var b: int = previous[(i + 1) % SEGMENTS]
				var c: int = loop[i]
				var d: int = loop[(i + 1) % SEGMENTS]
				if side > 0:
					indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
				else:
					indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
			previous = loop
	_smooth_junction(vertices, indices, smooth_vertices, arm_weights)
	for i in vertices.size():
		vertices[i] = fit_reference_point(vertices[i])
	# Remove unused armhole-interior vertices so the shell is one connected surface.
	var compact := PackedVector3Array()
	var remap: Dictionary = {}
	var compact_weights := PackedFloat32Array()
	for i in indices.size():
		var old := indices[i]
		if not remap.has(old):
			remap[old] = compact.size()
			compact.append(vertices[old])
			compact_weights.append(arm_weights[old])
		indices[i] = remap[old]
	var normals := PackedVector3Array()
	normals.resize(compact.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var normal := (compact[c] - compact[a]).cross(compact[b] - compact[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in normals.size():
		normals[i] = normals[i].normalized()
		var point := compact[i]
		var front_fill := smoothstep(0.065, 0.15, absf(point.z)) * smoothstep(1.42, 1.58, point.y)
		front_fill *= 1.0 - smoothstep(1.85, 1.94, point.y)
		var print_normal := Vector3(normals[i].x * 0.35, normals[i].y * 0.65, normals[i].z).normalized()
		normals[i] = normals[i].lerp(print_normal, front_fill * 0.8).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = compact
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = result
	set_meta("garment_component", "continuous_shell")
	set_meta("garment_arm_weights", compact_weights)
	geometry_rebuilt.emit()


func _smooth_junction(vertices: PackedVector3Array, indices: PackedInt32Array, selected: Array[int], arm_weights: PackedFloat32Array) -> void:
	var neighbors: Dictionary = {}
	for i in vertices.size():
		neighbors[i] = []
	for i in range(0, indices.size(), 3):
		for corner in 3:
			var a := indices[i + corner]
			if not neighbors.has(a):
				continue
			for offset in [1, 2]:
				var b := indices[i + (corner + offset) % 3]
				if not neighbors[a].has(b):
					neighbors[a].append(b)
	for iteration in 4:
		var source := vertices.duplicate()
		for i in selected:
			var average := Vector3.ZERO
			for adjacent in neighbors[i]:
				average += source[adjacent]
			vertices[i] = source[i].lerp(average / neighbors[i].size(), 0.38)
	var weight_region := selected.duplicate()
	for i in selected:
		for adjacent in neighbors[i]:
			if absf(arm_weights[adjacent]) < 1.0 and not weight_region.has(adjacent):
				weight_region.append(adjacent)
	# Blend the attachment into one extra torso ring, while locking the cuffs to the arms.
	for iteration in 18:
		var source_weights := arm_weights.duplicate()
		for i in weight_region:
			var weight := 0.0
			for adjacent in neighbors[i]:
				weight += source_weights[adjacent]
			arm_weights[i] = lerpf(source_weights[i], weight / neighbors[i].size(), 0.5)


static func fit_reference_point(point: Vector3) -> Vector3:
	# A monotone silhouette cage keeps the armhole intact while narrowing the sleeves.
	var outside := maxf(absf(point.x) - 0.25, 0.0)
	var compression := lerpf(0.50, 0.67, smoothstep(1.20, 1.57, point.y))
	point.x -= signf(point.x) * compression * outside * outside / (outside + 0.03)
	return point


static func fit_reference_normal(point: Vector3, normal: Vector3) -> Vector3:
	const STEP := 0.0001
	var origin := fit_reference_point(point)
	var jacobian := Basis((fit_reference_point(point + Vector3.RIGHT * STEP) - origin) / STEP,
		(fit_reference_point(point + Vector3.UP * STEP) - origin) / STEP,
		Vector3.BACK)
	return (jacobian.inverse().transposed() * normal).normalized()
