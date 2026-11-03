class_name BasicGarment
extends RefCounted

## Neutral modern everyday garment geometry for the catalog doll.
## Every builder returns a Dictionary with vertices/normals/indices, a
## per-vertex "arm_weights" array (empty when the part carries no sleeve
## influence) and the generic "slot" metadata ("top" / "bottom" / "outer")
## that Definition.part_slot surfaces as garment_slot.
## Ring rows are Vector4(height, radius_x, radius_z, center_x); tubes are
## open at both ends so neck, sleeve and hem openings stay hollow. The modern
## tops (cuban_shirt, babydoll_blouse) are built as connected shells instead:
## an analytic top-edge torso grid, sewn shoulder bridges, sleeves grown from
## the armhole boundary, and (for the camp shirt) flat camp-collar leaves
## welded onto the neck opening.

const SEGMENTS := 120


static func cuban_shirt(length: float = .80) -> Dictionary:
	# Relaxed camp/Cuban shirt: analytic top edge (open front V, high back neck,
	# armhole dips) so no quads are skipped and nothing stair-steps. Shoulder
	# bridges sew front to back over the shoulder, the short sleeves grow out of
	# the armhole boundary itself, and flat camp-collar leaves weld onto the
	# neck opening, so the whole garment is one connected shell.
	length = clampf(length, .55, 1.05)
	var hem := TOP_HEIGHT - length
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var top_edge := _top_grid(hem, _cuban_profile, _cuban_top, Callable(), vertices, indices, arm_weights)
	var bridges := _shoulder_bridges(top_edge, vertices, indices, arm_weights)
	for side in [-1.0, 1.0]:
		_sleeve(side, _armhole_loop(side, top_edge, bridges), CUBAN_SLEEVE, .95, .30,
			vertices, indices, arm_weights)
	var collar_start := vertices.size()
	var collar_indices_start := indices.size()
	var collar_edge := _camp_collar(top_edge, bridges, vertices, indices, arm_weights)
	var result := _finish(vertices, indices, arm_weights, "top")
	result["top_edge"] = top_edge
	result["hem_y"] = hem
	result["sleeve_hem_y"] = CUBAN_SLEEVE.back()[0]
	result["collar_edge"] = collar_edge
	var collar_indices := PackedInt32Array()
	for index in range(collar_indices_start,indices.size()): collar_indices.append(indices[index]-collar_start)
	result["collar_trim"] = _finish(vertices.slice(collar_start),collar_indices,arm_weights.slice(collar_start),"top")
	return result


static func babydoll_blouse(length: float = .80) -> Dictionary:
	# Babydoll blouse: fitted bust over a high empire seam, gathers releasing
	# into a flared hem below it, a smooth round neckline and short puff sleeves
	# cinched at the hem. Same connected-shell construction as the camp shirt.
	length = clampf(length, .55, 1.05)
	var hem := TOP_HEIGHT - length
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var top_edge := _top_grid(hem, _babydoll_profile, _babydoll_top, _babydoll_gathers,
		vertices, indices, arm_weights)
	var bridges := _shoulder_bridges(top_edge, vertices, indices, arm_weights)
	for side in [-1.0, 1.0]:
		_sleeve(side, _armhole_loop(side, top_edge, bridges), BABYDOLL_SLEEVE, .92, .30,
			vertices, indices, arm_weights)
	var result := _finish(vertices, indices, arm_weights, "top")
	result["top_edge"] = top_edge
	result["hem_y"] = hem
	result["sleeve_hem_y"] = BABYDOLL_SLEEVE.back()[0]
	return result


# Modern tops anchor every silhouette feature at an absolute height; the length
# parameter moves the hem only (hem = TOP_HEIGHT - length).
const TOP_HEIGHT := 1.905
const TOP_ROWS := 22
# Absolute-height torso profiles: [height, radius_x, radius_z].
const CUBAN_PROFILE := [
	[.85, .310, .226], [1.00, .302, .221], [1.15, .294, .214],
	[1.30, .286, .208], [1.45, .278, .201], [1.60, .267, .193],
	[1.70, .258, .186], [1.78, .246, .176], [1.84, .226, .162],
	[1.885, .198, .146], [1.905, .152, .118]]
const BABYDOLL_PROFILE := [
	[.85, .368, .268], [1.00, .348, .256], [1.10, .332, .244],
	[1.25, .318, .232], [1.38, .312, .228], [1.47, .308, .224],
	[1.52, .258, .190], [1.58, .278, .203], [1.66, .284, .208],
	[1.74, .272, .199], [1.82, .238, .172], [1.885, .196, .146],
	[1.905, .152, .118]]
# Sleeve morph rings after the armhole root: [height, center_x, radius_x,
# radius_z, morph]. The babydoll set bulges then cinches for the puff.
const CUBAN_SLEEVE := [
	[1.745, .205, .132, .126, .42], [1.665, .222, .127, .120, .72],
	[1.590, .238, .124, .116, 1.0]]
const BABYDOLL_SLEEVE := [
	[1.750, .200, .140, .132, .42], [1.690, .214, .158, .144, .72],
	[1.648, .222, .112, .104, 1.0]]


static func _cuban_profile(y: float) -> Vector2:
	return _profile_at(CUBAN_PROFILE, y)


static func _babydoll_profile(y: float) -> Vector2:
	return _profile_at(BABYDOLL_PROFILE, y)


static func _profile_at(table: Array, y: float) -> Vector2:
	if y <= table[0][0]:
		return Vector2(table[0][1], table[0][2])
	for span in table.size() - 1:
		var a: Array = table[span]
		var b: Array = table[span + 1]
		if y <= b[0]:
			var t := (y - float(a[0])) / (float(b[0]) - float(a[0]))
			return Vector2(lerpf(float(a[1]), float(b[1]), t), lerpf(float(a[2]), float(b[2]), t))
	return Vector2(table.back()[1], table.back()[2])


# Camp-shirt top edge: open V at the front, high back neck, smooth armhole
# dips under the shoulder bridges.
static func _cuban_top(angle: float) -> float:
	var f := absf(wrapf(angle, -PI, PI))
	var top := 1.855
	if f < .46:
		top = lerpf(1.705, 1.855, smoothstep(0.0, .46, f))
	elif PI - f < .62:
		top = lerpf(1.888, 1.855, smoothstep(0.0, .62, PI - f))
	var side := absf(f - PI * .5)
	if side < PI / 6.0:
		top = minf(top, lerpf(1.70, 1.855, smoothstep(0.0, PI / 6.0, side)))
	return top


# Babydoll top edge: round front scoop, high back neck, smooth armhole dips.
static func _babydoll_top(angle: float) -> float:
	var f := absf(wrapf(angle, -PI, PI))
	var top := 1.848
	if f < .72:
		top = lerpf(1.775, 1.848, smoothstep(0.0, .72, f))
	elif PI - f < .62:
		top = lerpf(1.878, 1.848, smoothstep(0.0, .62, PI - f))
	var side := absf(f - PI * .5)
	if side < PI / 6.0:
		top = minf(top, lerpf(1.68, 1.848, smoothstep(0.0, PI / 6.0, side)))
	return top


# Empire gathers: ripple strongest just under the seam, releasing into the flare.
static func _babydoll_gathers(y: float, angle: float) -> float:
	return .06 * smoothstep(1.58, 1.50, y) * (1.0 - .4 * smoothstep(1.44, 1.12, y)) * cos(angle * 9.0)


static func _top_torso_weight(angle: float, y: float) -> float:
	# Shoulders and armhole rims follow the upper arm just a little.
	return signf(sin(angle)) * .22 * smoothstep(1.58, 1.86, y) * smoothstep(.45, .95, absf(sin(angle)))


# Torso shell on a full grid: every column runs from the hem to the analytic
# top edge, radii sampled at absolute heights so only the hem moves with the
# length parameter. Returns the top edge points (SEGMENTS + 1 entries).
static func _top_grid(hem: float, profile: Callable, top: Callable, folds: Callable,
		vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> PackedVector3Array:
	var top_edge := PackedVector3Array()
	for row in TOP_ROWS:
		for column in SEGMENTS + 1:
			var angle := TAU * column / SEGMENTS
			var y := lerpf(hem, float(top.call(angle)), float(row) / (TOP_ROWS - 1))
			var radii: Vector2 = profile.call(y)
			var fold := 1.0 + (float(folds.call(y, angle)) if folds.is_valid() else 0.0)
			var point := Vector3(sin(angle) * radii.x * fold, y, cos(angle) * radii.y * fold)
			vertices.append(point)
			if row == TOP_ROWS - 1:
				top_edge.append(point)
			arm_weights.append(_top_torso_weight(angle, y))
	for row in TOP_ROWS - 1:
		for column in SEGMENTS:
			var a := row * (SEGMENTS + 1) + column
			var b := a + SEGMENTS + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	return top_edge


# Shoulder panels sewn between the front and back top edges, separating the
# neck opening from the two armholes. Returns the bridge inner (neck side) and
# outer (armhole side) chains per side for the collar and sleeve attachments.
static func _shoulder_bridges(top_edge: PackedVector3Array,
		vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> Dictionary:
	var chains := {"inner": {1: PackedVector3Array(), -1: PackedVector3Array()},
		"outer": {1: PackedVector3Array(), -1: PackedVector3Array()}}
	for side in [-1, 1]:
		var start := vertices.size()
		for depth in 9:
			for column in range(10, 21):
				var front_index: int = column if side == 1 else SEGMENTS - column
				var back_index: int = SEGMENTS / 2 - column if side == 1 else SEGMENTS / 2 + column
				var t := depth / 8.0
				var point: Vector3 = top_edge[front_index].lerp(top_edge[back_index], t)
				point.y += .014 * sin(PI * t)
				vertices.append(point)
				arm_weights.append(_top_torso_weight(TAU * front_index / SEGMENTS, point.y))
				if column == 10:
					chains["inner"][side].append(point)
				elif column == 20:
					chains["outer"][side].append(point)
		for depth in 8:
			for column in 10:
				var a := start + depth * 11 + column
				if side == 1:
					indices.append_array(PackedInt32Array([a, a + 1, a + 11, a + 1, a + 12, a + 11]))
				else:
					indices.append_array(PackedInt32Array([a, a + 11, a + 1, a + 1, a + 11, a + 12]))
	return chains


# Closed armhole boundary: over the bridge outer edge, then down the back top
# edge to the underarm and back up the front. Loop angles around its centre
# increase monotonically so the sleeve morph never twists.
static func _armhole_loop(side: float, top_edge: PackedVector3Array, bridges: Dictionary) -> PackedVector3Array:
	var loop: PackedVector3Array = bridges["outer"][int(side)].duplicate()
	if side > 0.0:
		for column in range(39, 20, -1):
			loop.append(top_edge[column])
	else:
		for column in range(81, 100):
			loop.append(top_edge[column])
	return loop


# Sleeve grown from the armhole boundary itself: ring 0 welds into the shell,
# the following rings morph the boundary loop onto sloped ellipses hugging the
# arm, so shoulder and sleeve read as one continuous surface.
static func _sleeve(side: float, loop: PackedVector3Array, rings: Array, hem_weight: float, root_weight: float,
		vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> void:
	var count := loop.size()
	var centre := Vector3.ZERO
	for point in loop:
		centre += point
	centre /= count
	# Distribute the morph targets evenly around the ring, anchored so the
	# bridge crown lands on the outer shoulder. Even spacing keeps the hem ring
	# free of sliver quads where the boundary sampling is uneven.
	var top_index := 0
	for i in count:
		if loop[i].y > loop[top_index].y:
			top_index = i
	var angles := PackedFloat32Array()
	for i in count:
		angles.append(PI * .5 + TAU * float(i - top_index) / count)
	var start := vertices.size()
	for point in loop:
		vertices.append(point)
		arm_weights.append(side * root_weight)
	var previous_centre := centre
	for ring in rings.size():
		var spec: Array = rings[ring]
		var y: float = spec[0]
		var cx: float = spec[1]
		var rx: float = spec[2]
		var rz: float = spec[3]
		var morph: float = spec[4]
		var ring_centre := Vector3(side * cx, y, 0.0)
		var weight := lerpf(root_weight, hem_weight, float(ring + 1) / rings.size())
		for i in count:
			var target := Vector3(side * (cx + sin(angles[i]) * rx), y, cos(angles[i]) * rz)
			vertices.append(loop[i].lerp(target, morph))
			arm_weights.append(side * weight)
		var axis := previous_centre.lerp(ring_centre, .5)
		for i in count:
			var j := (i + 1) % count
			_emit_quad(vertices, indices, start + ring * count + i, start + ring * count + j,
				start + (ring + 1) * count + j, start + (ring + 1) * count + i, axis)
		previous_centre = ring_centre


# Flat camp collar: one-piece leaves welded along the whole neck opening
# (front V, bridge inner edges, back neck) that lie directly on the shirt
# shell, the way a real camp/Cuban collar folds open. No stand and no rolled
# rim: the free edge rests one leaf-height below the neck seam, sampled from
# the same torso profile as the shell so the fabric stays flush. The two
# front leaves taper to a shared point at the V notch, reading as the paired
# pointed turnovers of the open camp collar. Returns the free outer edge.
static func _camp_collar(top_edge: PackedVector3Array, bridges: Dictionary,
		vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> PackedVector3Array:
	var loop := PackedVector3Array()
	for column in range(110, 131):
		loop.append(top_edge[column % SEGMENTS])
	var inner_right: PackedVector3Array = bridges["inner"][1]
	for depth in range(1, 9):
		loop.append(inner_right[depth])
	for column in range(51, 71):
		loop.append(top_edge[column])
	var inner_left: PackedVector3Array = bridges["inner"][-1]
	for depth in range(7, 0, -1):
		loop.append(inner_left[depth])
	var count := loop.size()
	var start := vertices.size()
	var edge := PackedVector3Array()
	for i in count:
		var point := loop[i]
		var angle := atan2(point.x, point.z)
		var f := absf(angle)
		# Leaf height: a point at the V notch, widening over the chest,
		# a steady flat band over the shoulders and across the back.
		var leaf := .058
		if f < .46:
			leaf = lerpf(.030, .098, smoothstep(.02, .16, f))
			leaf = lerpf(leaf, .058, smoothstep(.30, .46, f))
		elif PI - f < .62:
			leaf = lerpf(.070, .058, smoothstep(.10, .50, PI - f))
		var y := point.y - leaf
		var radii := _cuban_profile(y)
		var outer := Vector3(sin(angle) * (radii.x + .004), y, cos(angle) * (radii.y + .004))
		if f < .53:
			# Independent pointed leaves fold away from the open centre V.
			var x: float
			if f < .24:
				x = lerpf(.008,.155,f/.24)
				y = lerpf(1.705,1.665,f/.24)
			else:
				x = lerpf(.155,.175,(f-.24)/.29)
				y = lerpf(1.665,1.805,(f-.24)/.29)
			radii = _cuban_profile(y)
			outer = Vector3((-1.0 if point.x < 0 else 1.0)*x,y,radii.y*sqrt(maxf(0,1.0-pow(x/radii.x,2)))+.008)
		edge.append(outer)
		for step in 7:
			var weight := step/6.0
			var folded := point.lerp(outer,weight)
			if step > 0 and point.z > .08:
				var shell := _cuban_profile(folded.y)
				folded.z = maxf(folded.z,shell.y*sqrt(maxf(0,1-pow(folded.x/shell.x,2)))+.004*weight)
			vertices.append(folded)
			arm_weights.append(0.0)
	for i in count:
		var j := (i + 1) % count
		var mid := (loop[i] + loop[j]) * .5
		var outward := Vector3(mid.x, 0.0, mid.z)
		outward = outward.normalized() if outward.length_squared() > .0001 else Vector3(0.0, 0.0, 1.0)
		for step in 6:
			_emit_quad(vertices,indices,start+i*7+step,start+j*7+step,start+j*7+step+1,start+i*7+step+1,mid-outward-Vector3.UP*.5)
	return edge


# Emits one quad with the winding that faces away from the given axis point,
# so sleeves and collar keep outward normals on both sides of the body.
static func _emit_quad(vertices: PackedVector3Array, indices: PackedInt32Array,
		q0: int, q1: int, q2: int, q3: int, axis: Vector3) -> void:
	var centre := (vertices[q0] + vertices[q1] + vertices[q2] + vertices[q3]) * .25
	var normal := (vertices[q3] - vertices[q0]).cross(vertices[q1] - vertices[q0])
	if normal.dot(centre - axis) >= 0.0:
		indices.append_array(PackedInt32Array([q0, q1, q3, q1, q2, q3]))
	else:
		indices.append_array(PackedInt32Array([q0, q3, q1, q1, q3, q2]))


static func sweater_vest(length: float = .80) -> Dictionary:
	# Academic V-neck sweater vest worn over a shirt. Shoulder bridges join the
	# shell: every column runs from the hem to an analytic top-edge curve
	# (front V, sloped shoulders, side armholes, high back neck), so no quads
	# are skipped and the neck/armhole boundaries stay smooth instead of
	# stair-stepping along the ring grid. "trim" carries the ribbed bands that
	# hug the neck/armhole edge and the hem.
	length = clampf(length, .55, 1.05)
	const TOP := 1.90
	const ROWS := 24
	var hem := TOP - length
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var top_edge := PackedVector3Array()
	for row in ROWS:
		for column in SEGMENTS + 1:
			var angle := TAU * column / SEGMENTS
			var top := _vest_top(angle)
			var y := lerpf(hem, top, float(row) / (ROWS - 1))
			var radii := _vest_radii(y)
			var point := Vector3(sin(angle) * radii.x, y, cos(angle) * radii.y)
			vertices.append(point)
			if row == ROWS - 1:
				top_edge.append(point)
			arm_weights.append(_vest_arm_weight(angle, y))
	for row in ROWS - 1:
		for column in SEGMENTS:
			var a := row * (SEGMENTS + 1) + column
			var b := a + SEGMENTS + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	# Sew broad front/back shoulder panels together. These bridges separate
	# the neckline from the two armholes (four openings including the hem).
	for side in [-1, 1]:
		var start := vertices.size()
		for depth in 9:
			for column in range(10, 21):
				var front_index := column if side == 1 else SEGMENTS - column
				var back_index := SEGMENTS / 2 - column if side == 1 else SEGMENTS / 2 + column
				var t := depth / 8.0
				var point := top_edge[front_index].lerp(top_edge[back_index], t)
				point.y += .012 * sin(PI * t)
				vertices.append(point)
				arm_weights.append(_vest_arm_weight(TAU * front_index / SEGMENTS, point.y))
		for depth in 8:
			for column in 10:
				var a := start + depth * 11 + column
				if side == 1:
					indices.append_array(PackedInt32Array([a, a + 1, a + 11, a + 1, a + 12, a + 11]))
				else:
					indices.append_array(PackedInt32Array([a, a + 11, a + 1, a + 1, a + 11, a + 12]))
	var result := _finish(vertices, indices, arm_weights, "outer")
	result["top_edge"] = top_edge
	result["hem_y"] = hem
	result["row_count"] = ROWS
	result["trim"] = _vest_ribbing(hem)
	return result


static func _vest_top(angle: float) -> float:
	var f := absf(wrapf(angle, -PI, PI))
	var near_front := minf(f, PI - f)
	if near_front <= PI / 6.0:
		if f < PI * .5:
			# Straight V sides, with no flat-bottom scoop.
			return lerpf(1.66, 1.905, sin(f) / .5)
		return lerpf(1.865, 1.905, sin(f) / .5)
	if near_front <= PI / 3.0:
		return lerpf(1.905, 1.865, (near_front - PI / 6.0) / (PI / 6.0))
	return lerpf(1.865, 1.565, smoothstep(PI / 3.0, PI * .5, near_front))


static func _vest_radii(y: float) -> Vector2:
	# Absolute-height torso profile, eased ~1.5cm out of the shirt silhouette so
	# the vest layers over a top without swallowing its sleeves or collar.
	const PROFILE := [
		[0.85, .330, .240], [1.00, .322, .233], [1.15, .314, .226],
		[1.30, .305, .219], [1.45, .296, .211], [1.58, .287, .203],
		[1.70, .276, .194], [1.80, .262, .183], [1.87, .240, .166],
		[1.905, .208, .142]]
	if y <= PROFILE[0][0]:
		return Vector2(PROFILE[0][1], PROFILE[0][2])
	for span in PROFILE.size() - 1:
		var a: Array = PROFILE[span]
		var b: Array = PROFILE[span + 1]
		if y <= b[0]:
			var t := (y - float(a[0])) / (float(b[0]) - float(a[0]))
			return Vector2(lerpf(float(a[1]), float(b[1]), t), lerpf(float(a[2]), float(b[2]), t))
	return Vector2(PROFILE.back()[1], PROFILE.back()[2])


static func _vest_arm_weight(angle: float, y: float) -> float:
	# Shoulder straps and armhole rims follow the upper arm just a little.
	return signf(sin(angle)) * .22 * smoothstep(1.58, 1.86, y) * smoothstep(.45, .95, absf(sin(angle)))


static func _vest_ribbing(hem: float) -> Dictionary:
	# Knit rib bands: one hugs the whole top edge (neck + both armholes), one
	# wraps the hem. Fine angular ripple reads as rib wales, and the slight
	# radius lift keeps the bands proud of the vest body.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	const BAND_ROWS := 3
	for band in 2:
		var start := vertices.size()
		for row in BAND_ROWS:
			for column in SEGMENTS + 1:
				var angle := TAU * column / SEGMENTS
				var top := _vest_top(angle)
				var y := lerpf(top - .07, top, float(row) / (BAND_ROWS - 1)) if band == 0 \
					else lerpf(hem, hem + .075, float(row) / (BAND_ROWS - 1))
				var radii := _vest_radii(y) * (1.018 + .004 * cos(angle * 84.0))
				vertices.append(Vector3(sin(angle) * radii.x, y, cos(angle) * radii.y))
				arm_weights.append(_vest_arm_weight(angle, y))
		for row in BAND_ROWS - 1:
			for column in SEGMENTS:
				# Front/back shoulder seams are sewn, not exposed openings.
				# Never put a raised rib strip across those seams.
				var quarter_column := column % (SEGMENTS / 2)
				var mirrored := mini(quarter_column, SEGMENTS / 2 - 1 - quarter_column)
				if band == 0 and mirrored >= 10 and mirrored < 20:
					continue
				var a := start + row * (SEGMENTS + 1) + column
				var b := a + SEGMENTS + 1
				indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	return {"vertices": vertices, "normals": _welded_normals(vertices, indices),
		"indices": indices, "arm_weights": arm_weights}


static func simple_skirt(length: float) -> Dictionary:
	# Waist sits at 1.30; only the hem moves with the length parameter.
	length = clampf(length, .35, 1.05)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := []
	var rows := 7
	for row in rows:
		var drop := length * row / (rows - 1.0)
		rings.append(Vector4(1.30 - drop, .285 + .150 * drop, .208 + .105 * drop, 0.0))
	_tube_part(rings, Callable(), Callable(), Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "bottom")


static func bare_arm(side: float) -> Dictionary:
	# Skin tube under short or absent sleeves, in ArmLeft/ArmRight local space.
	# The bone line hides inside the torso shell, so the tube exits the armhole
	# and hangs just outside the garment silhouette down to the mitten.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := [
		Vector4(-.02, .094, .090, side * .02), Vector4(-.10, .096, .091, side * .055),
		Vector4(-.22, .095, .090, side * .10), Vector4(-.34, .092, .088, side * .145),
		Vector4(-.48, .089, .086, side * .15), Vector4(-.60, .088, .085, side * .148),
		Vector4(-.66, .087, .084, side * .145)]
	_tube_part(rings, Callable(), Callable(), Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "")


static func apron_strap(side: float, shell: Mesh = null) -> Dictionary:
	# One continuous band: up the front bib, over the shoulder, crossing the
	# back at the spine and down to the waist tie on the opposite side.
	# Every control point sits on the dressed torso surface measured from the
	# TailoredShell ring profile (rings 1.52/1.72/1.83/1.90/1.93, radii
	# .263/.252/.21/.15/.105): the shoulder crown at the strap's lateral
	# offset tops out at y~1.894, so the crest rides at 1.905 — not up in
	# the air. Front points carry an extra .014 to clear the bib strap
	# panels (shell + .018 offset, plus cloth clearance); back points rest
	# .008 off the bare shell; the last point lands on the waist tie.
	var controls := PackedVector3Array([
		Vector3(side * .145, 1.70, .176), Vector3(side * .150, 1.78, .144),
		Vector3(side * .155, 1.84, .111), Vector3(side * .158, 1.905, .0),
		Vector3(side * .160, 1.85, -.083), Vector3(side * .130, 1.78, -.145),
		Vector3(side * .095, 1.72, -.173), Vector3(0.0, 1.56, -.199),
		Vector3(-side * .085, 1.42, -.190), Vector3(-side * .145, 1.30, -.196)])
	# The right strap rides slightly above the left where they cross.
	var lift := .007 * (.5 + .5 * side)
	var path := _sample_path(controls, 5)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in path.size():
		var p: Vector3 = path[i]
		var tangent: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		# Frame from the true torso surface normal, so the band lies flat
		# against the body everywhere — front, shoulder crown and back —
		# instead of standing on edge at the crest.
		var normal := _torso_normal(p)
		p += normal * lift
		var width := normal.cross(tangent).normalized()
		if tangent.cross(width).dot(normal) < 0.0:
			width = -width
		vertices.append(p - width * .028)
		vertices.append(p + width * .028)
	for i in path.size() - 1:
		var a := i * 2
		indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	if shell != null:
		var surface := shell.surface_get_arrays(0)
		var source: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
		var triangles: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array = surface[Mesh.ARRAY_NORMAL]
		for index in vertices.size():
			var point := vertices[index]
			var closest := point
			var outward := Vector3.UP
			var best := INF
			for face in range(0,triangles.size(),3):
				var a := triangles[face]
				var b := triangles[face+1]
				var c := triangles[face+2]
				var hit := _closest_on_triangle(point,source[a],source[b],source[c])
				var distance := point.distance_squared_to(hit)
				if distance < best:
					best = distance
					closest = hit
					outward = (normals[a]+normals[b]+normals[c]).normalized()
			vertices[index] = closest+outward*(.003+lift*.45)
	return _finish(vertices, indices, PackedFloat32Array(), "outer")


# TailoredShell torso rings [height, radius_x, radius_z], mirrored from
# SimpleDollGarment3D so the apron straps can hug the same surface.
const TORSO_PROFILE := [
	[1.285, .285, .202], [1.52, .263, .194], [1.72, .252, .180],
	[1.83, .210, .145], [1.90, .150, .110], [1.93, .105, .095]]


# Outward normal of the dressed torso at p, from the implicit ellipse
# F = (x/rx(y))² + (z/rz(y))² - 1 of the interpolated ring profile.
static func _torso_normal(p: Vector3) -> Vector3:
	var rx: float = TORSO_PROFILE[0][1]
	var rz: float = TORSO_PROFILE[0][2]
	var drx := 0.0
	var drz := 0.0
	for span in TORSO_PROFILE.size() - 1:
		var a: Array = TORSO_PROFILE[span]
		var b: Array = TORSO_PROFILE[span + 1]
		if p.y <= b[0] or span == TORSO_PROFILE.size() - 2:
			var t := clampf((p.y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
			rx = lerpf(float(a[1]), float(b[1]), t)
			rz = lerpf(float(a[2]), float(b[2]), t)
			drx = (float(b[1]) - float(a[1])) / (float(b[0]) - float(a[0]))
			drz = (float(b[2]) - float(a[2])) / (float(b[0]) - float(a[0]))
			break
	var sx: float = p.x / (rx * rx)
	var sz: float = p.z / (rz * rz)
	var normal := Vector3(sx, -(p.x * sx * drx / rx + p.z * sz * drz / rz), sz)
	return normal.normalized() if normal.length_squared() > .0001 else Vector3.UP


static func _tube_part(rings: Array, folds: Callable, skip: Callable, weight: Callable,
		vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> void:
	if skip.is_valid():
		var refined := []
		for row in rings.size()-1:
			for step in 8:
				refined.append((rings[row] as Vector4).lerp(rings[row+1],step/8.0))
		refined.append(rings.back())
		rings = refined
	var start := vertices.size()
	for row in rings.size():
		var ring: Vector4 = rings[row]
		for column in SEGMENTS + 1:
			var angle := TAU * column / SEGMENTS
			var fold := 1.0 + (float(folds.call(ring.x, angle)) if folds.is_valid() else 0.0)
			vertices.append(Vector3(ring.w + sin(angle) * ring.y * fold, ring.x, cos(angle) * ring.z * fold))
			arm_weights.append(float(weight.call(ring.x, angle)) if weight.is_valid() else 0.0)
	for row in rings.size() - 1:
		var y_mid: float = (rings[row].x + rings[row + 1].x) * .5
		for column in SEGMENTS:
			if skip.is_valid() and skip.call(y_mid, TAU * (column + .5) / SEGMENTS):
				continue
			var a := start + row * (SEGMENTS + 1) + column
			var b := a + SEGMENTS + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))


static func _sample_path(controls: PackedVector3Array, per_span: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for span in controls.size() - 1:
		var p0: Vector3 = controls[maxi(span - 1, 0)]
		var p1: Vector3 = controls[span]
		var p2: Vector3 = controls[span + 1]
		var p3: Vector3 = controls[mini(span + 2, controls.size() - 1)]
		for step in per_span:
			var t := float(step) / per_span
			points.append(.5 * ((2.0 * p1) + (p2 - p0) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	points.append(controls[controls.size() - 1])
	return points


static func _welded_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	# Weld the duplicated seam column so the tube shades as one surface.
	var first := {}
	for i in vertices.size():
		var key := str(snappedf(vertices[i].x, .0005)) + "," + str(snappedf(vertices[i].y, .0005)) \
			+ "," + str(snappedf(vertices[i].z, .0005))
		if first.has(key):
			normals[first[key]] += normals[i]
		else:
			first[key] = i
	for i in vertices.size():
		var key := str(snappedf(vertices[i].x, .0005)) + "," + str(snappedf(vertices[i].y, .0005)) \
			+ "," + str(snappedf(vertices[i].z, .0005))
		normals[i] = normals[first[key]]
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > .000000000001 else Vector3.UP
	return normals


static func _finish(vertices: PackedVector3Array, indices: PackedInt32Array,
		arm_weights: PackedFloat32Array, slot: String) -> Dictionary:
	var normals := _welded_normals(vertices, indices)
	# All-zero weights must not install the garment_arm_weights metadata at
	# all, or the rig would class the part as a sleeved garment.
	var any_weight := false
	for value in arm_weights:
		if value != 0.0:
			any_weight = true
			break
	if not any_weight:
		arm_weights = PackedFloat32Array()
	return {"vertices": vertices, "normals": normals, "indices": indices,
		"arm_weights": arm_weights, "slot": slot}


static func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)
