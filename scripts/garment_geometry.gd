extends RefCounted

# Standalone (prop) geometry surgery for catalog garments.
# The worn meshes keep their original clipping; these helpers cut real openings
# into a copy for hanger/folded display while preserving every vertex channel,
# including the skeleton binding (BONES/WEIGHTS) and any rest-cloth blend shapes.

# Armhole capsules in catalog-doll model space (Y up, front +Z), mirrored in X.
# They follow the upper arm from the shoulder tip toward the underarm so the
# cutout lands exactly where the doll's arm exits the sleeveless shell.
const ARMHOLE_TOP := Vector3(0.185, 1.875, 0.0)
const ARMHOLE_BOTTOM := Vector3(0.255, 1.500, 0.008)
const ARMHOLE_RADIUS := 0.085
# Triangles closer than this to the cut curve are refined before clipping so
# the armhole boundary stays smooth instead of following source edges.
const SUBDIVIDE_MARGIN := 0.06
const SUBDIVISIONS := 8
const MIN_AREA := 1e-16


# Cut smooth armholes into a skinned garment mesh (e.g. the OpenWaistcoat or
# its FrontBinding before Forms.build). Returns a new ArrayMesh with the same
# channels, blend shapes and skeleton weights; open front and hem are kept.
static func standalone_waistcoat_mesh(source: ArrayMesh) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw_indices = arrays[Mesh.ARRAY_INDEX]
	var corner_count: int = positions.size() if raw_indices == null else raw_indices.size()
	var emitted_positions := PackedVector3Array()
	var emitted_bary := PackedVector3Array()
	var emitted_corner := PackedInt32Array()
	for face in range(0, corner_count, 3):
		var corners := PackedInt32Array()
		if raw_indices == null:
			corners = PackedInt32Array([face, face + 1, face + 2])
		else:
			corners = raw_indices.slice(face, face + 3)
		var distances := Vector3(
			_armhole_clearance(positions[corners[0]]),
			_armhole_clearance(positions[corners[1]]),
			_armhole_clearance(positions[corners[2]]))
		if minf(distances.x, minf(distances.y, distances.z)) >= SUBDIVIDE_MARGIN:
			_emit_triangle(corners, Vector3.RIGHT, Vector3.UP, Vector3.BACK, positions,
				emitted_positions, emitted_bary, emitted_corner)
		elif maxf(distances.x, maxf(distances.y, distances.z)) <= 0.0:
			continue
		else:
			_subdivide_clip(corners, positions, emitted_positions, emitted_bary, emitted_corner)
	var output := _materialize(source, arrays, emitted_positions, emitted_bary, emitted_corner)
	return output


static func _emit_triangle(corners: PackedInt32Array, b0: Vector3, b1: Vector3, b2: Vector3,
		positions: PackedVector3Array, emitted_positions: PackedVector3Array,
		emitted_bary: PackedVector3Array, emitted_corner: PackedInt32Array) -> void:
	var p0 := _bary_position(corners, b0, positions)
	var p1 := _bary_position(corners, b1, positions)
	var p2 := _bary_position(corners, b2, positions)
	if (p1 - p0).cross(p2 - p0).length_squared() < MIN_AREA:
		return
	if b0 == b1 or b1 == b2 or b0 == b2:
		return
	emitted_positions.append_array(PackedVector3Array([p0, p1, p2]))
	emitted_bary.append_array(PackedVector3Array([b0, b1, b2]))
	for i in 3: emitted_corner.append_array(corners)


static func _subdivide_clip(corners: PackedInt32Array, positions: PackedVector3Array,
		emitted_positions: PackedVector3Array, emitted_bary: PackedVector3Array,
		emitted_corner: PackedInt32Array) -> void:
	for step in SUBDIVISIONS:
		var row_count := SUBDIVISIONS - step
		for column in row_count:
			var k := SUBDIVISIONS - step - column
			var bary := Vector3(step, column, k) / SUBDIVISIONS
			var up := Vector3(step + 1, column, k - 1) / SUBDIVISIONS
			var across := Vector3(step, column + 1, k - 1) / SUBDIVISIONS
			_clip_subtriangle(corners, bary, up, across, positions, emitted_positions, emitted_bary, emitted_corner)
			if column < row_count - 1:
				var diagonal := Vector3(step + 1, column + 1, k - 2) / SUBDIVISIONS
				_clip_subtriangle(corners, up, diagonal, across, positions, emitted_positions, emitted_bary, emitted_corner)


static func _clip_subtriangle(corners: PackedInt32Array, b0: Vector3, b1: Vector3, b2: Vector3,
		positions: PackedVector3Array, emitted_positions: PackedVector3Array,
		emitted_bary: PackedVector3Array, emitted_corner: PackedInt32Array) -> void:
	var polygon: Array[Vector3] = [b0, b1, b2]
	var distances: Array[float] = [
		_armhole_clearance(_bary_position(corners, b0, positions)),
		_armhole_clearance(_bary_position(corners, b1, positions)),
		_armhole_clearance(_bary_position(corners, b2, positions))]
	var clipped: Array[Vector3] = []
	for i in polygon.size():
		var previous := polygon[(i + polygon.size() - 1) % polygon.size()]
		var before := distances[(i + polygon.size() - 1) % polygon.size()]
		var current := polygon[i]
		var after := distances[i]
		if (before >= 0.0) != (after >= 0.0):
			clipped.append(previous.lerp(current, before / (before - after)))
		if after >= 0.0:
			clipped.append(current)
	for fan in range(1, clipped.size() - 1):
		_emit_triangle(corners, clipped[0], clipped[fan], clipped[fan + 1], positions,
			emitted_positions, emitted_bary, emitted_corner)


static func _bary_position(corners: PackedInt32Array, bary: Vector3, positions: PackedVector3Array) -> Vector3:
	return positions[corners[0]] * bary.x + positions[corners[1]] * bary.y + positions[corners[2]] * bary.z


static func _armhole_clearance(point: Vector3) -> float:
	# Side-facing oval leaves a continuous shoulder strap above the opening.
	var ellipse := Vector2((point.y-1.64)/.165,point.z/.145).length()-1.0
	return maxf(ellipse*.145,.14-absf(point.x))


static func _materialize(source: ArrayMesh, arrays: Array, positions: PackedVector3Array,
		bary: PackedVector3Array, corners: PackedInt32Array) -> ArrayMesh:
	var source_positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var count := positions.size()
	var output := []
	output.resize(Mesh.ARRAY_MAX)
	output[Mesh.ARRAY_VERTEX] = positions
	for channel in Mesh.ARRAY_MAX:
		if channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX]:
			continue
		var data = arrays[channel]
		if data == null:
			continue
		match channel:
			Mesh.ARRAY_NORMAL:
				var values := PackedVector3Array()
				values.resize(count)
				for i in count:
					values[i] = (data[corners[i * 3]] * bary[i].x + data[corners[i * 3 + 1]] * bary[i].y
						+ data[corners[i * 3 + 2]] * bary[i].z).normalized()
				output[channel] = values
			Mesh.ARRAY_TANGENT:
				var values := PackedFloat32Array()
				values.resize(count * 4)
				for i in count:
					var blended := Vector3.ZERO
					for corner in 3:
						var index: int = corners[i * 3 + corner] * 4
						blended += Vector3(data[index], data[index + 1], data[index + 2]) * bary[i][corner]
					blended = blended.normalized()
					var anchor: int = corners[i * 3] * 4
					values[i * 4] = blended.x
					values[i * 4 + 1] = blended.y
					values[i * 4 + 2] = blended.z
					values[i * 4 + 3] = data[anchor + 3]
				output[channel] = values
			Mesh.ARRAY_COLOR:
				var values := PackedColorArray()
				values.resize(count)
				for i in count:
					values[i] = data[corners[i * 3]] * bary[i].x + data[corners[i * 3 + 1]] * bary[i].y + data[corners[i * 3 + 2]] * bary[i].z
				output[channel] = values
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				var values := PackedVector2Array()
				values.resize(count)
				for i in count:
					values[i] = data[corners[i * 3]] * bary[i].x + data[corners[i * 3 + 1]] * bary[i].y + data[corners[i * 3 + 2]] * bary[i].z
				output[channel] = values
			Mesh.ARRAY_BONES:
				var merged := _merge_weights(arrays[Mesh.ARRAY_BONES], arrays[Mesh.ARRAY_WEIGHTS], corners, bary, count)
				output[Mesh.ARRAY_BONES] = merged[0]
				output[Mesh.ARRAY_WEIGHTS] = merged[1]
			Mesh.ARRAY_WEIGHTS:
				pass
			_:
				output[channel] = null
	var shape_count := source.get_blend_shape_count()
	var shapes: Array[Array] = []
	for shape in shape_count:
		var shape_arrays: Array = source.surface_get_blend_shape_arrays(0)[shape]
		var shaped := []
		shaped.resize(Mesh.ARRAY_MAX)
		for channel in Mesh.ARRAY_MAX:
			var data = shape_arrays[channel]
			if data == null or data is not PackedVector3Array:
				continue
			var values := PackedVector3Array()
			values.resize(count)
			for i in count:
				values[i] = data[corners[i * 3]] * bary[i].x + data[corners[i * 3 + 1]] * bary[i].y + data[corners[i * 3 + 2]] * bary[i].z
			shaped[channel] = values
		shapes.append(shaped)
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = source.blend_shape_mode
	for shape in shape_count:
		mesh.add_blend_shape(source.get_blend_shape_name(shape))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output, shapes)
	return mesh


static func _merge_weights(bones: PackedInt32Array, weights: PackedFloat32Array,
		corners: PackedInt32Array, bary: PackedVector3Array, count: int) -> Array:
	var out_bones := PackedInt32Array()
	var out_weights := PackedFloat32Array()
	out_bones.resize(count * 4)
	out_weights.resize(count * 4)
	for i in count:
		var influences := {}
		for corner in 3:
			var share: float = bary[i][corner]
			if share <= 0.0:
				continue
			var index: int = corners[i * 3 + corner] * 4
			for slot in 4:
				var bone: int = bones[index + slot]
				influences[bone] = influences.get(bone, 0.0) + weights[index + slot] * share
		var ranked := influences.keys()
		ranked.sort_custom(func(a: int, b: int) -> bool:
			return a < b if is_equal_approx(influences[a], influences[b]) else influences[a] > influences[b])
		var total := 0.0
		for slot in mini(4, ranked.size()):
			total += influences[ranked[slot]]
		for slot in 4:
			if slot < ranked.size():
				out_bones[i * 4 + slot] = ranked[slot]
				out_weights[i * 4 + slot] = influences[ranked[slot]] / maxf(total, 0.000001)
			else:
				out_bones[i * 4 + slot] = 0
				out_weights[i * 4 + slot] = 0.0
	return [out_bones, out_weights]
