extends RefCounted
## REJECTED EXPERIMENT: centroid matching introduced self-intersecting rest shapes.
## Capture-only diagnostic; do not install in production dolls.

const RestCloth = preload("res://scripts/rest_cloth.gd")
const BodyFit = preload("res://scripts/accepted_body_fit.gd")


static func install(doll: Node3D) -> void:
	var rig: RefCounted = doll.rig
	var legs: Array = []
	var cloth: Array[MeshInstance3D] = []
	var layers: Array[MeshInstance3D] = []
	for part in rig.meshes:
		if str(part.name) == "LegMannequin": legs.append(_leg_rows(part))
		if part.has_meta("skin_layer_sources"): layers.append(part)
		elif part.get_meta("semantic", "") in ["skirt", "apron"] and part.mesh.get_blend_shape_count() == RestCloth.SHAPES.size():
			cloth.append(part)
	if legs.size() != 2 or cloth.is_empty(): return
	var knee_y := 0.0
	for side in ["L", "R"]:
		knee_y += rig.skeleton.get_bone_global_rest(rig.bones["Shin" + side]).origin.y * .5
	var hip_y: float = minf(legs[0].heights[-1], legs[1].heights[-1])
	for mode in RestCloth.SHAPES.size():
		rig.animate(0, 0, "idle", 0)
		var pose_weights := Vector4.ZERO
		pose_weights[maxi(0, mode - 1)] = 1
		rig.pose_rest("sit" if mode == 0 else "nap", 1, 0, pose_weights)
		var hip_skin: Transform3D = rig.global_pose(rig.bones.Hips) * rig.skeleton.get_bone_global_rest(rig.bones.Hips).affine_inverse()
		var guide: Array = []
		for leg in legs:
			var posed: PackedVector3Array = rig.deformed_vertices(leg.part)
			var centers := PackedVector3Array()
			for row in leg.rows:
				var center := Vector3.ZERO
				for id in row: center += posed[id]
				centers.append(hip_skin.affine_inverse() * (center / row.size()))
			guide.append({"heights": leg.heights, "centers": centers})
		for part in cloth: _retarget(part, mode, guide, knee_y, hip_y)
		var fitted := {}
		for layer in layers: _fit_layer(rig, layer, mode, fitted)
	# Building correctives must not leave the actor in a sleeping pose.
	rig.animate(0, 0, "idle", 0)


static func _leg_rows(part: MeshInstance3D) -> Dictionary:
	var points: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rows := {}
	var unique := {}
	for i in points.size():
		var key := Vector3i((points[i] * 100000).round())
		if unique.has(key): continue
		unique[key] = true
		if not rows.has(key.y): rows[key.y] = []
		rows[key.y].append(i)
	var heights := rows.keys()
	heights.sort()
	var ordered: Array = []
	var y := PackedFloat32Array()
	for height in heights:
		if rows[height].size() < 8: continue
		ordered.append(rows[height])
		y.append(float(height) / 100000)
	return {"part": part, "heights": y, "rows": ordered}


static func _sample(guide: Dictionary, y: float) -> Vector3:
	var heights: PackedFloat32Array = guide.heights
	var centers: PackedVector3Array = guide.centers
	if y <= heights[0]: return centers[0]
	for i in range(1, heights.size()):
		if y > heights[i]: continue
		return centers[i - 1].lerp(centers[i], inverse_lerp(heights[i - 1], heights[i], y))
	return centers[-1]


static func shift(y: float, mode: int, guide: Array, knee_y: float, hip_y: float) -> Vector3:
	var follow := 1.0 - smoothstep(knee_y, hip_y, y)
	if follow <= 0: return Vector3.ZERO
	var source := RestCloth.point(Vector3(0, y, 0), mode > 0, maxi(0, mode - 1), false)
	var target := (_sample(guide[0], y) + _sample(guide[1], y)) * .5
	# X carries the accepted cushion-side gravity compression; retain that drape.
	return Vector3(0, target.y - source.y, target.z - source.z) * follow


static func _retarget(part: MeshInstance3D, mode: int, guide: Array, knee_y: float, hip_y: float) -> void:
	var arrays: Array = part.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var shapes: Array = part.mesh.surface_get_blend_shape_arrays(0)
	var previous: PackedVector3Array = shapes[mode][Mesh.ARRAY_VERTEX]
	var moved := previous.duplicate()
	for i in rest.size():
		var p := rest[i]
		moved[i] += shift(p.y, mode, guide, knee_y, hip_y)
		if p.z < 0:
			# The legacy paper body flattened the back of the skirt. Retain its
			# standing ease around the full mannequin's seat, tapering toward knees.
			var center := RestCloth.point(Vector3(p.x, p.y, 0), mode > 0, maxi(0, mode - 1))
			var front := RestCloth.point(Vector3(p.x, p.y, -p.z), mode > 0, maxi(0, mode - 1))
			var back := RestCloth.point(p, mode > 0, maxi(0, mode - 1))
			var support := smoothstep(knee_y, hip_y - .10, p.y)
			var full_back := center * 2 - front
			moved[i] += Vector3(0, full_back.y - back.y, full_back.z - back.z) * support
	var temporary := arrays.duplicate()
	temporary[Mesh.ARRAY_VERTEX] = moved
	temporary[Mesh.ARRAY_NORMAL] = shapes[mode][Mesh.ARRAY_NORMAL]
	shapes[mode][Mesh.ARRAY_VERTEX] = moved
	shapes[mode][Mesh.ARRAY_NORMAL] = BodyFit.new()._normals(temporary, previous)
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = part.mesh.blend_shape_mode
	for i in part.mesh.get_blend_shape_count(): mesh.add_blend_shape(part.mesh.get_blend_shape_name(i))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	part.mesh = mesh
	part.set_meta("wearing_pose_binding", "shared-leg-guide-v1")
	part.set_blend_shape_value(mode, 1)


static func _fit_layer(rig: RefCounted, layer: MeshInstance3D, mode: int, fitted: Dictionary) -> void:
	if fitted.has(layer): return
	for path in layer.get_meta("skin_layer_sources"):
		var source: MeshInstance3D = layer.get_node(NodePath(path))
		if source.has_meta("skin_layer_sources"): _fit_layer(rig, source, mode, fitted)
	RestCloth.fit_layer(rig, layer, mode)
	fitted[layer] = true
