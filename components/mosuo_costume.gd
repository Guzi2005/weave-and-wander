class_name MosuoCostume
extends RefCounted

## Procedural geometry for the mosuo_photo_001 set (wiki record WW-MOS-001),
## translated from the user-uploaded photo
## Docs/wiki-concept-2026-10-28/mosuo-example/source-user-upload.png.
## Builders follow basic_garment.gd conventions: each returns a Dictionary of
## vertices/normals/indices, a per-vertex "arm_weights" array (all zero when
## the part carries no sleeve influence) and the generic "slot" metadata that
## Definition.part_slot surfaces as garment_slot. Colors are assigned by
## mosuo_doll.gd, not here. Ring rows are Vector4(height, radius_x, radius_z,
## center_x); tubes are open at both ends so collar, sleeve and hem openings
## stay hollow. The right bystander and the held item of the source photo are
## deliberately not modeled.

const SKIRT_FOLDS := 64
const SKIRT_SEGMENTS := SKIRT_FOLDS * 4


static func _sleeve_rings() -> Array:
	return [
		Vector4(1.86, .070, .080, .150), Vector4(1.78, .080, .090, .168),
		Vector4(1.68, .090, .100, .198), Vector4(1.58, .098, .108, .224),
		Vector4(1.48, .105, .114, .248), Vector4(1.38, .111, .120, .268),
		Vector4(1.28, .116, .124, .284), Vector4(1.18, .120, .127, .296),
		Vector4(1.13, .122, .129, .301)]


static func _pleat(angle: float) -> float:
	return .032 * cos(angle * SKIRT_FOLDS)


static func _torso_rings() -> Array:
	# Short blouse body: hem overlaps the skirt waistband, neck meets the collar.
	return [
		Vector4(1.24, .310, .224, 0.0), Vector4(1.32, .298, .213, 0.0),
		Vector4(1.42, .290, .207, 0.0), Vector4(1.52, .283, .201, 0.0),
		Vector4(1.61, .276, .196, 0.0), Vector4(1.70, .266, .189, 0.0),
		Vector4(1.78, .252, .176, 0.0), Vector4(1.85, .224, .160, 0.0),
		Vector4(1.90, .190, .140, 0.0), Vector4(1.935, .150, .120, 0.0)]


static func _skirt_rings() -> Array:
	# Ankle-length pleated skirt; waist sits at 1.34 under the blouse hem.
	return [
		Vector4(1.34, .270, .200, 0.0), Vector4(1.22, .295, .218, 0.0),
		Vector4(1.06, .325, .238, 0.0), Vector4(0.90, .355, .260, 0.0),
		Vector4(0.72, .370, .278, 0.0), Vector4(0.54, .390, .293, 0.0),
		Vector4(0.38, .408, .308, 0.0), Vector4(0.24, .426, .323, 0.0),
		Vector4(0.12, .438, .334, 0.0)]


static func _ring_at(rings: Array, y: float) -> Vector4:
	for index in rings.size() - 1:
		var a: Vector4 = rings[index]
		var b: Vector4 = rings[index + 1]
		if y >= minf(a.x, b.x) and y <= maxf(a.x, b.x):
			var t := (y - a.x) / (b.x - a.x)
			return a.lerp(b, t)
	var first: Vector4 = rings[0]
	var last: Vector4 = rings[rings.size() - 1]
	return first if absf(y - first.x) < absf(y - last.x) else last


static func blouse_body() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	_tube_part(_torso_rings(), 40, Callable(), Callable(), Callable(), vertices, indices, arm_weights)
	# Long sleeves reach the wrist like the base simple_garment shell; the
	# sleeve root tucks inside the torso and the same smoothstep ramp carries
	# the UpperArm/Forearm skinning influence.
	var sleeve := _sleeve_rings()
	for side in [-1.0, 1.0]:
		var sided := []
		for ring in sleeve:
			sided.append(Vector4(ring.x, ring.y, ring.z, side * ring.w))
		var weight := func(y: float, _angle: float) -> float:
			return side * (1.0 - smoothstep(1.63, 1.83, y))
		_tube_part(sided, 32, Callable(), Callable(), weight, vertices, indices, arm_weights)
	var result := _finish(vertices, indices, arm_weights, "top")
	var uv := PackedVector2Array()
	_append_uv(_torso_rings(),40,2.6,2.25,uv)
	for side in 2: _append_uv(sleeve,32,1.3,2.25,uv)
	result["uv"] = uv
	return result

static func _append_uv(rings: Array, segments: int, repeats_x: float, repeats_y: float, uv: PackedVector2Array) -> void:
	for ring in rings:
		for column in segments+1:
			uv.append(Vector2(float(column)/segments*repeats_x,(2.0-ring.x)*repeats_y))


static func blouse_collar() -> Dictionary:
	# Light standing collar band above the blouse neck ring.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := [
		Vector4(1.922, .165, .130, 0.0), Vector4(1.955, .150, .120, 0.0),
		Vector4(1.985, .127, .105, 0.0)]
	_tube_part(rings, 40, Callable(), Callable(), Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "top")

static func blouse_neckband() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := [Vector4(1.895,.192,.145,0.0),Vector4(1.925,.175,.134,0.0)]
	_tube_part(rings,40,Callable(),Callable(),Callable(),vertices,indices,arm_weights)
	return _finish(vertices,indices,arm_weights,"top")

static func blouse_collar_base() -> Dictionary:
	var data := blouse_collar()
	var vertices: PackedVector3Array = data.vertices
	for i in vertices.size():
		var p := vertices[i]
		var radial := Vector2(p.x,p.z).normalized()
		vertices[i] = p + Vector3(radial.x*.009,0,radial.y*.009)
	data.vertices = vertices
	data.normals = _recalculate_normals(vertices,data.indices)
	return data


static func blouse_hem_band() -> Dictionary:
	# Light band along the blouse hem, matching the collar/front edging.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := [
		Vector4(1.235, .313, .227, 0.0), Vector4(1.275, .305, .219, 0.0)]
	_tube_part(rings, 40, Callable(), Callable(), Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "top")


static func blouse_front_trim() -> Dictionary:
	# Light wrap-front edging: one continuous band from the collar bone down
	# across the chest to the waist side, following the torso surface.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var controls := PackedVector3Array([
		Vector3(-.055, 1.945, .132), Vector3(-.010, 1.830, .178),
		Vector3(.050, 1.700, .200), Vector3(.110, 1.550, .208),
		Vector3(.150, 1.400, .202), Vector3(.160, 1.270, .206)])
	_ribbon(controls, .011, .008, vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "top")


static func blouse_cuffs() -> Dictionary:
	# Light cuff bands at both wrists; they ride the forearm like the sleeve hem.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	for side in [-1.0, 1.0]:
		var rings := [
			Vector4(1.195, .133, .139, side * .295), Vector4(1.145, .135, .141, side * .300)]
		var weight := func(_y: float, _angle: float) -> float:
			return side * .95
		_tube_part(rings, 32, Callable(), Callable(), weight, vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "top")


static func blouse_motifs(variant: int) -> Dictionary:
	# Small organic color patches suggest the visible multicolor floral pattern.
	# This is a game-scale reading, not a reconstruction of a named motif or craft.
	# Each color is merged; sleeve patches carry the same weights as their shell.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	for patch in 80:
		if patch % 4 != variant:
			continue
		var y := 1.30 + .53 * fposmod(float(patch) * .6180339, 1.0)
		var angle := patch * 2.3999632
		_pattern_patch(_torso_rings(), y, angle, 0.0, .035, .016, float(patch), vertices, indices, arm_weights)
	for side in [-1.0, 1.0]:
		for patch in 36:
			if patch % 4 != variant:
				continue
			var y := 1.22 + .56 * fposmod(float(patch) * .6180339, 1.0)
			var angle: float = patch * 2.3999632 + side * .8
			_pattern_patch(_sleeve_rings(), y, angle, side, .033, .013, float(patch + 91), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "top")


static func _pattern_patch(rings: Array, y: float, angle: float, side: float, height: float, width: float,
		seed: float, vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> void:
	var ring := _ring_at(rings, y)
	var angular_width := width / maxf(.05, ring.y)
	var base := vertices.size()
	# A triangle fan around a three-lobed oval; every vertex is projected onto
	# the curved garment so motifs neither float above nor cut through sleeves.
	for point in 13:
		var theta := TAU * (point - 1) / 12.0
		var radial := 0.0 if point == 0 else .82 + .18 * cos(theta * 3.0 + seed)
		var py := y + cos(theta + seed) * height * radial
		var pa := angle + sin(theta + seed) * angular_width * radial
		var surface := _ring_at(rings, py)
		vertices.append(Vector3(side * surface.w + sin(pa) * (surface.y + .0025), py, cos(pa) * (surface.z + .0025)))
		arm_weights.append(side * (1.0 - smoothstep(1.63, 1.83, py)))
	for triangle in 12:
		indices.append_array(PackedInt32Array([base, base + 1 + triangle, base + 1 + (triangle + 1) % 12]))


static func pleated_skirt() -> Dictionary:
	# Dense vertical pleats; fold count is a game adaptation, not a measured fact.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var folds := func(_y: float, angle: float) -> float:
		return _pleat(angle)
	_tube_part(_skirt_rings(), SKIRT_SEGMENTS, folds, Callable(), Callable(), vertices, indices, arm_weights)
	var result := _finish(vertices, indices, arm_weights, "bottom")
	var uv := PackedVector2Array()
	_append_uv(_skirt_rings(),SKIRT_SEGMENTS,2.2,1.25,uv)
	result["uv"] = uv
	return result


static func skirt_pleat_tones(light_side: bool) -> Dictionary:
	# Thin, merged color planes keep the folds legible with the game's flat-ink
	# shader and in the exported GLB. They share the skirt's actual fold surface.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := []
	for original in _skirt_rings():
		var ring: Vector4 = original
		ring.y += .0008
		ring.z += .0008
		rings.append(ring)
	var folds := func(_y: float, angle: float) -> float: return _pleat(angle)
	var skip := func(_y: float, angle: float) -> bool:
		var quarter := int(floor(fposmod(angle * SKIRT_FOLDS / TAU, 1.0) * 4.0))
		return quarter != (3 if light_side else 1)
	_tube_part(rings, SKIRT_SEGMENTS, folds, skip, Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "bottom")


static func skirt_waistband() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := [
		Vector4(1.30, .284, .211, 0.0), Vector4(1.36, .279, .207, 0.0)]
	_tube_part(rings, 40, Callable(), Callable(), Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "bottom")


static func skirt_stripe() -> Dictionary:
	# The single fine red-purple line circling the lower skirt, riding the
	# pleat crests just above them.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := []
	for y in [.485, .494]:
		var ring := _ring_at(_skirt_rings(), y)
		ring.y += .003
		ring.z += .003
		rings.append(ring)
	var folds := func(_y: float, angle: float) -> float: return _pleat(angle)
	_tube_part(rings, SKIRT_SEGMENTS, folds, Callable(), Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "bottom")


static func skirt_flecks() -> Dictionary:
	# Merged pale flecks scattered over the skirt surface, on the pleat crests.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	for index in 360:
		var y := .17 + 1.1 * fposmod(float(index) * .6180339, 1.0)
		var angle := float(index) * 2.3999632
		var base := vertices.size()
		for offset in [Vector2(0,.016),Vector2(.016,.004),Vector2(0,-.016),Vector2(-.010,-.003)]:
			var py: float = y + offset.y
			var pa: float = angle + offset.x
			var ring := _ring_at(_skirt_rings(), py)
			var fold := 1.0 + _pleat(pa)
			vertices.append(Vector3(sin(pa) * (ring.y * fold + .002), py, cos(pa) * (ring.z * fold + .002)))
			arm_weights.append(0.0)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	return _finish(vertices, indices, arm_weights, "bottom")


static func headwear_base() -> Dictionary:
	# Black crown wrapping the hair cap; sits in HeadRig/HeadwearSlot space.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var rings := [
		Vector4(.44, .352, .366, 0.0), Vector4(.50, .362, .376, 0.0),
		Vector4(.56, .358, .372, 0.0), Vector4(.62, .344, .358, 0.0),
		Vector4(.68, .316, .330, 0.0), Vector4(.735, .252, .266, 0.0),
		Vector4(.775, .120, .130, 0.0), Vector4(.79, .008, .010, 0.0)]
	_tube_part(rings, 48, Callable(), Callable(), Callable(), vertices, indices, arm_weights)
	return _finish(vertices, indices, arm_weights, "headwear")


static func headwear_cords() -> Array:
	# Colorful wrapped cord rings around the black base; one band per level,
	# the doll assigns the ring colors.
	var levels := [
		[.505, .368, .382], [.560, .364, .378], [.620, .350, .364], [.675, .322, .336]]
	var result := []
	for level in levels:
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		var arm_weights := PackedFloat32Array()
		var rings := [
			Vector4(level[0] - .016, level[1], level[2], 0.0),
			Vector4(level[0] + .016, level[1] - .005, level[2] - .005, 0.0)]
		var braid_wave := func(_y: float, angle: float) -> float:
			return .017 * sin(angle * 20.0 + level[0] * 95.0)
		_tube_part(rings, 96, braid_wave, Callable(), Callable(), vertices, indices, arm_weights)
		result.append(_finish(vertices, indices, arm_weights, "headwear"))
	return result


static func headwear_pompom() -> Dictionary:
	# Merged red cluster at the top viewer-right of the crown.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var center := Vector3(.145, .745, .070)
	var offsets := PackedVector3Array([
		Vector3.ZERO, Vector3(.042, .018, .012), Vector3(-.040, .022, -.008),
		Vector3(.012, .048, -.020), Vector3(-.014, .050, .024), Vector3(.024, -.020, .034),
		Vector3(-.036, -.014, .026), Vector3(.008, .022, .046), Vector3(-.008, .010, -.042)])
	for offset in offsets:
		_append_sphere(vertices, indices, arm_weights, center + offset, .034)
	return _finish(vertices, indices, arm_weights, "headwear")

static func headwear_flower() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var center := Vector3(.155,.775,.075)
	_append_sphere(vertices,indices,arm_weights,center,.025)
	for petal in 11:
		var angle := TAU*petal/11.0
		var direction := Vector3(cos(angle)*.052,.085+(.035 if petal%3==0 else 0),sin(angle)*.052)
		var side := Vector3(-sin(angle),0,cos(angle)).normalized()
		var base := vertices.size()
		vertices.append(center + side*.007)
		vertices.append(center - side*.007)
		vertices.append(center + direction + side*.027)
		vertices.append(center + direction*1.06 - side*.027)
		arm_weights.append(0.0); arm_weights.append(0.0); arm_weights.append(0.0); arm_weights.append(0.0)
		indices.append_array(PackedInt32Array([base,base+1,base+2,base+1,base+3,base+2]))
	return _finish(vertices,indices,arm_weights,"headwear")


static func headwear_beads() -> Dictionary:
	# Dense purple seed-bead strands hanging from the viewer-right rim of the
	# headwear down the skirt side, as clarified by the user. Every bead merges into this
	# single mesh so the whole fringe costs one draw call.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var strands := 16
	for strand in strands:
		var t := float(strand) / (strands - 1)
		var rim_angle := PI * .5 + (t - .5) * .52
		var anchor := Vector3(sin(rim_angle) * .357, .47, cos(rim_angle) * .371)
		var length := 2.02 + .12 * sin(t * 9.0)
		var bead_count := int(length / .016)
		for bead in bead_count:
			var u := (float(bead) + .5) / bead_count
			var point := Vector3(
				anchor.x + .12 * sin(PI * u * .75),
				anchor.y - u * length,
				anchor.z + .19 * sin(u * PI * .6))
			_append_bead(vertices, indices, arm_weights, point, .007)
	return _finish(vertices, indices, arm_weights, "headwear")


static func _append_sphere(vertices: PackedVector3Array, indices: PackedInt32Array,
		arm_weights: PackedFloat32Array, center: Vector3, radius: float) -> void:
	var base := vertices.size()
	var rings := 4
	var segments := 8
	for ring in rings + 1:
		var phi := PI * ring / rings
		for column in segments + 1:
			var theta := TAU * column / segments
			vertices.append(center + radius * Vector3(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta)))
			arm_weights.append(0.0)
	for ring in rings:
		for column in segments:
			var a := base + ring * (segments + 1) + column
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))


static func _append_bead(vertices: PackedVector3Array, indices: PackedInt32Array,
		arm_weights: PackedFloat32Array, center: Vector3, radius: float) -> void:
	# Seed bead as a small octahedron: six vertices, eight triangles.
	var base := vertices.size()
	for direction in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		vertices.append(center + direction * radius)
		arm_weights.append(0.0)
	indices.append_array(PackedInt32Array([
		base + 0, base + 2, base + 4, base + 0, base + 4, base + 3,
		base + 0, base + 3, base + 5, base + 0, base + 5, base + 2,
		base + 1, base + 4, base + 2, base + 1, base + 3, base + 4,
		base + 1, base + 5, base + 3, base + 1, base + 2, base + 5]))


static func _ribbon(controls: PackedVector3Array, half_width: float, lift: float,
		vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> void:
	var base := vertices.size()
	var path := _sample_path(controls, 5)
	for index in path.size():
		var point: Vector3 = path[index]
		var tangent: Vector3 = (path[mini(index + 1, path.size() - 1)] - path[maxi(index - 1, 0)]).normalized()
		var outward := Vector3(point.x, 0.0, point.z)
		if outward.length_squared() < .0001:
			outward = Vector3(0.0, 0.0, 1.0)
		outward = outward.normalized()
		point += outward * lift
		var width := outward.cross(tangent).normalized()
		vertices.append(point - width * half_width)
		vertices.append(point + width * half_width)
		arm_weights.append(0.0)
		arm_weights.append(0.0)
	for index in path.size() - 1:
		var a := base + index * 2
		indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))


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


static func _tube_part(rings: Array, segments: int, folds: Callable, skip: Callable, weight: Callable,
		vertices: PackedVector3Array, indices: PackedInt32Array, arm_weights: PackedFloat32Array) -> void:
	var start := vertices.size()
	for row in rings.size():
		var ring: Vector4 = rings[row]
		for column in segments + 1:
			var angle := TAU * column / segments
			var fold := 1.0 + (float(folds.call(ring.x, angle)) if folds.is_valid() else 0.0)
			vertices.append(Vector3(ring.w + sin(angle) * ring.y * fold, ring.x, cos(angle) * ring.z * fold))
			arm_weights.append(float(weight.call(ring.x, angle)) if weight.is_valid() else 0.0)
	for row in rings.size() - 1:
		var y_mid: float = ((rings[row] as Vector4).x + (rings[row + 1] as Vector4).x) * .5
		for column in segments:
			if skip.is_valid() and skip.call(y_mid, TAU * (column + .5) / segments):
				continue
			var a := start + row * (segments + 1) + column
			var b := a + segments + 1
			if (rings[row + 1] as Vector4).x < (rings[row] as Vector4).x:
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
			else:
				indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))


static func _finish(vertices: PackedVector3Array, indices: PackedInt32Array,
		arm_weights: PackedFloat32Array, slot: String) -> Dictionary:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for index in range(0, indices.size(), 3):
		var a := indices[index]
		var b := indices[index + 1]
		var c := indices[index + 2]
		var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	# Weld the duplicated seam column so tubes shade as one surface.
	var first := {}
	for index in vertices.size():
		var key := str(snappedf(vertices[index].x, .0005)) + "," + str(snappedf(vertices[index].y, .0005)) \
			+ "," + str(snappedf(vertices[index].z, .0005))
		if first.has(key):
			normals[first[key]] += normals[index]
		else:
			first[key] = index
	for index in vertices.size():
		var key := str(snappedf(vertices[index].x, .0005)) + "," + str(snappedf(vertices[index].y, .0005)) \
			+ "," + str(snappedf(vertices[index].z, .0005))
		normals[index] = normals[first[key]]
	for index in normals.size():
		normals[index] = normals[index].normalized() if normals[index].length_squared() > .000000000001 else Vector3.UP
	return {"vertices": vertices, "normals": normals, "indices": indices,
		"arm_weights": arm_weights, "slot": slot}

static func _recalculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array(); normals.resize(vertices.size())
	for index in range(0,indices.size(),3):
		var a := indices[index]; var b := indices[index+1]; var c := indices[index+2]
		var n := (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a])
		normals[a]+=n; normals[b]+=n; normals[c]+=n
	for i in normals.size(): normals[i]=normals[i].normalized() if normals[i].length_squared()>0.000001 else Vector3.UP
	return normals
