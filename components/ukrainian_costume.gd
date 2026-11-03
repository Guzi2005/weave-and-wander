class_name UkrainianCostume
extends RefCounted

## Procedural geometry for the ukrainian_photo_001 set, translated from the
## user-supplied reference (assets/collections/ukrainian_photo_001/source.jpg):
## ankle-length white undershirt-dress with puffed bishop sleeves and a
## center-front neck opening tied by a red ribbon, black/white beaded
## necklaces, a high wrapped yellow cloth sash with yarn-pompon tassels, a
## purple front apron, and a dark overskirt with yellow/purple/green warp
## stripes. The doll body is untouched; all parts sit outside the shared
## volume_doll silhouette. Waist stays HIGH: sash center y=1.42.
##
## Skirt geometry follows Docs/PLEATED_SKIRT_CONTRACT.md (8 samples/pleat,
## 24 rows, sharpness blend, depth ramp/cap, real inner wall, seam at -Z).
## Stripe fabric and tassels are parametric motif assets (StripeMotif /
## TasselMotif); assign `stripe` / `tassel` to override the defaults.

const Mosuo = preload("res://components/mosuo_costume.gd")
const Stripe = preload("res://components/motifs/stripe_motif.gd")
const Tassel = preload("res://components/motifs/tassel_motif.gd")

const CLOTH_FIT = preload("res://assets/collections/ukrainian_photo_001/cloth_fit.tres")

static var stripe: Stripe = null
static var tassel: Tassel = null

const COLOR_SHIRT := Color("f2ede2")
const COLOR_RIBBON := Color("572135")
const COLOR_SASH := Color("988024")
const COLOR_APRON := Color("784562")
const COLOR_SKIRT_BASE := Color("1f3a3c")
const COLOR_STRIPE_YELLOW := Color("c8a23a")
const COLOR_STRIPE_PURPLE := Color("6e4a86")
const COLOR_STRIPE_GREEN := Color("4a7a4a")
const COLOR_BEAD_DARK := Color("232028")
const COLOR_BEAD_LIGHT := Color("ece7db")

const OVERSKIRT_RINGS := [
	Vector4(1.44, .302, .230, 0.0), Vector4(1.30, .318, .242, 0.0),
	Vector4(1.10, .345, .262, 0.0), Vector4(0.88, .375, .285, 0.0),
	Vector4(0.66, .405, .308, 0.0), Vector4(0.46, .430, .330, 0.0),
	Vector4(0.26, .452, .352, 0.0)]

const UNDERSKIRT_RINGS := [
	Vector4(1.40, .292, .222, 0.0), Vector4(1.22, .305, .232, 0.0),
	Vector4(1.00, .325, .248, 0.0), Vector4(0.76, .348, .265, 0.0),
	Vector4(0.52, .332, .262, 0.0), Vector4(0.30, .336, .266, 0.0),
	Vector4(0.16, .338, .268, 0.0)]

const APRON_RINGS := [
	Vector4(1.42, .320, .250, 0.0), Vector4(1.24, .340, .266, 0.0),
	Vector4(1.02, .366, .286, 0.0), Vector4(0.80, .400, .312, 0.0),
	Vector4(0.35, .470, .365, 0.0)]

const OVERSKIRT_OPTS := {"pleat_count": 40, "depth_m": .018, "sharpness": .75, "thickness": .0012}


static func stripe_asset() -> Stripe:
	if stripe == null:
		stripe = preload("res://assets/collections/ukrainian_photo_001/stripe_overskirt.tres")
	return stripe


static func tassel_asset() -> Tassel:
	if tassel == null:
		tassel = preload("res://assets/collections/ukrainian_photo_001/tassel_sash.tres")
	return tassel


static func _pleat_wave(angle: float, count: int, sharpness: float) -> float:
	var phase := fposmod(angle * count / TAU, 1.0)
	var triangle := 1.0 - 4.0 * absf(phase - .5)
	return lerpf(cos(angle * count), triangle, sharpness)


static func _circumference(rx: float, rz: float) -> float:
	return PI * (3.0 * (rx + rz) - sqrt((3.0 * rx + rz) * (rx + 3.0 * rz)))


## Shared parametric skirt shell (contract geometry). opts: pleat_count,
## depth_m, sharpness, thickness, patches, arc, rows, v_range (sub-section of
## the skirt for woven hem bands), lift (outward offset), only_troughs
## (shade panels confined to pleat valleys). role "solid" builds everything;
## otherwise only columns whose stripe role matches are emitted.
static func skirt_shell(rings: Array, opts: Dictionary, role: String) -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var count: int = opts.get("pleat_count", 40)
	var depth_m: float = opts.get("depth_m", .018)
	var sharpness: float = opts.get("sharpness", .75)
	var thickness: float = opts.get("thickness", .0012)
	var patches: Array = opts.get("patches", [])
	var arc: Vector2 = opts.get("arc", Vector2(0.0, 1.0))
	var rows: int = opts.get("rows", 24)
	var v_range: Vector2 = opts.get("v_range", Vector2(0.0, 1.0))
	var lift: float = opts.get("lift", 0.0)
	var only_troughs: bool = opts.get("only_troughs", false)
	var segments := count * (16 if not patches.is_empty() else 8)
	var span: float = arc.y - arc.x
	var columns := int(round(segments * span))
	var top_y: float = (rings[0] as Vector4).x
	var hem_y: float = (rings[rings.size() - 1] as Vector4).x
	var waist: Vector4 = rings[0]
	var depth_cap := _circumference(waist.y, waist.z) / count * .45
	var column_role := []
	var column_wave := []
	for column in columns + 1:
		var u: float = arc.x + span * float(column) / columns
		column_role.append("solid" if patches.is_empty() else stripe_role(fposmod(u, 1.0), patches))
		column_wave.append(_pleat_wave(PI + u * TAU, count, sharpness))
	var base := 0
	for wall in 2:
		base = vertices.size()
		var inward := float(wall) * thickness
		for row in rows + 1:
			var v := lerpf(v_range.x, v_range.y, float(row) / rows)
			var y := lerpf(top_y, hem_y, v)
			var ring := Mosuo._ring_at(rings, y)
			var depth := minf(depth_m * lerpf(.15, 1.0, v), depth_cap)
			for column in columns + 1:
				var u: float = arc.x + span * float(column) / columns
				var angle := PI + u * TAU
				var fold := depth * _pleat_wave(angle, count, sharpness)
				var rx := ring.y + fold + lift - inward
				var rz := ring.z + fold + lift - inward
				vertices.append(Vector3(sin(angle) * rx, y, cos(angle) * rz))
				arm_weights.append(0.0)
		for row in rows:
			for column in columns:
				if role != "solid" and column_role[column] != role:
					continue
				if only_troughs and column_wave[column] > -.15:
					continue
				var a := base + row * (columns + 1) + column
				var b := a + columns + 1
				if wall == 0:
					indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
				else:
					indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var wall_stride := (rows + 1) * (columns + 1)
	for end in 2:
		var row: int = 0 if end == 0 else rows
		for column in columns:
			if role != "solid" and column_role[column] != role:
				continue
			if only_troughs and column_wave[column] > -.15:
				continue
			var outer := row * (columns + 1) + column
			var inner := outer + wall_stride
			indices.append_array(PackedInt32Array([outer, inner, outer + 1, outer + 1, inner, inner + 1]))
	if span < .999:
		for side in 2:
			var column: int = 0 if side == 0 else columns
			if role != "solid" and column_role[column] != role:
				continue
			for row in rows:
				var outer := row * (columns + 1) + column
				var inner := outer + wall_stride
				var o2 := outer + columns + 1
				var i2 := inner + columns + 1
				indices.append_array(PackedInt32Array([outer, o2, inner, inner, o2, i2]))
	var result := Mosuo._finish(vertices, indices, arm_weights, "bottom")
	var uv := PackedVector2Array()
	uv.resize(vertices.size())
	for i in vertices.size():
		var p := vertices[i]
		var u := fposmod(atan2(p.x, p.z) / TAU - .5, 1.0)
		var v := inverse_lerp(top_y, hem_y, p.y)
		uv[i] = Vector2(u, v)
	result["uv"] = uv
	return result


static func stripe_role(u: float, patches: Array) -> String:
	for patch in patches:
		if u >= patch["u0"] and u < patch["u1"]:
			return patch["role"]
	return "base"


static func overskirt(role: String) -> Dictionary:
	var opts := OVERSKIRT_OPTS.duplicate()
	opts["patches"] = stripe_asset().patches()
	if role == "base_shade":
		# Woven shadow tone inside pleat valleys, just above the base cloth.
		opts["only_troughs"] = true
		opts["lift"] = .0007
		return skirt_shell(OVERSKIRT_RINGS, opts, "base")
	return skirt_shell(OVERSKIRT_RINGS, opts, role)


static func overskirt_hem_band() -> Dictionary:
	# Continuous woven yellow edge along the overskirt hem.
	var opts := OVERSKIRT_OPTS.duplicate()
	opts["v_range"] = Vector2(.955, .985)
	opts["lift"] = .0015
	return skirt_shell(OVERSKIRT_RINGS, opts, "solid")


static func overskirt_flecks(count: int = 220) -> Dictionary:
	# Sparse woven flecks on the dark base cloth only (never over stripes).
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var patches: Array = stripe_asset().patches()
	for index in count:
		var v := .06 + .88 * fposmod(float(index) * .6180339, 1.0)
		var y := lerpf(1.44, .26, v)
		var u := fposmod(float(index) * 2.3999632 / TAU, 1.0)
		if stripe_role(u, patches) != "base":
			continue
		var angle := PI + u * TAU
		var ring := Mosuo._ring_at(OVERSKIRT_RINGS, y)
		var depth := .018 * lerpf(.15, 1.0, v)
		var base := vertices.size()
		for offset in [Vector2(0, .010), Vector2(.009, .003), Vector2(0, -.010), Vector2(-.007, -.002)]:
			var py: float = y + offset.y
			var pv := inverse_lerp(1.44, .26, py)
			var pa: float = angle + offset.x
			var r := Mosuo._ring_at(OVERSKIRT_RINGS, py)
			var fold := .018 * lerpf(.15, 1.0, pv) * _pleat_wave(pa, 40, .75)
			vertices.append(Vector3(sin(pa) * (r.y + fold + .002), py, cos(pa) * (r.z + fold + .002)))
			arm_weights.append(0.0)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	return Mosuo._finish(vertices, indices, arm_weights, "bottom")


static func underskirt() -> Dictionary:
	return skirt_shell(UNDERSKIRT_RINGS, {
		"pleat_count": 20, "depth_m": .003, "sharpness": .6, "thickness": .0012}, "solid")


static func underskirt_hem_band(v0: float, v1: float) -> Dictionary:
	return skirt_shell(UNDERSKIRT_RINGS, {
		"pleat_count": 20, "depth_m": .003, "sharpness": .6, "thickness": .0012,
		"v_range": Vector2(v0, v1), "lift": .0015}, "solid")


static func apron() -> Dictionary:
	return skirt_shell(APRON_RINGS, {
		"pleat_count": 40, "depth_m": .010, "sharpness": .65,
		"thickness": .0012, "arc": Vector2(.35, .65)}, "solid")


static func apron_hem_band() -> Dictionary:
	return skirt_shell(APRON_RINGS, {
		"pleat_count": 40, "depth_m": .010, "sharpness": .65,
		"thickness": .0012, "arc": Vector2(.35, .65),
		"v_range": Vector2(.955, .98), "lift": .0015}, "solid")


static func _shirt_rings() -> Array:
	return [
		Vector4(1.30, .315, .235, 0.0), Vector4(1.40, .305, .228, 0.0),
		Vector4(1.52, .295, .220, 0.0), Vector4(1.64, .285, .210, 0.0),
		Vector4(1.76, .270, .196, 0.0), Vector4(1.85, .235, .170, 0.0),
		Vector4(1.889, .204, .150, 0.0), Vector4(1.90, .195, .145, 0.0), Vector4(1.916, .175, .138, 0.0)]


static func _puff_sleeve_rings() -> Array:
	# Bishop sleeve: full balloon at the upper arm, gathered to a narrow cuff.
	return [
		Vector4(1.86, .075, .085, .150), Vector4(1.80, .105, .118, .162),
		Vector4(1.72, .140, .155, .185), Vector4(1.64, .155, .172, .210),
		Vector4(1.56, .158, .175, .232), Vector4(1.48, .150, .166, .252),
		Vector4(1.40, .138, .152, .268), Vector4(1.32, .122, .136, .280),
		Vector4(1.24, .105, .118, .289), Vector4(1.18, .095, .108, .296),
		Vector4(1.13, .095, .105, .301)]


static func shirt_body() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var opening := func(y: float, angle: float) -> bool:
		return y > 1.889 and absf(wrapf(angle, -PI, PI)) < .028
	var gathers := func(y: float, angle: float) -> float:
		var slack := sin(PI * clampf((y - 1.42) / .50, 0, 1))
		return slack * CLOTH_FIT.blouse_fullness + CLOTH_FIT.gather_depth * cos(CLOTH_FIT.gather_count * angle + y * 3.0) * slack
	Mosuo._tube_part(_shirt_rings(), 128, gathers, opening, Callable(), vertices, indices, arm_weights)
	var sleeve := _puff_sleeve_rings()
	var drape := func(y: float, angle: float) -> float:
		return .006 * cos(angle * 10.0 + y * 4.0)
	for side in [-1.0, 1.0]:
		var sided := []
		for ring in sleeve:
			sided.append(Vector4(ring.x, ring.y, ring.z, side * ring.w))
		var weight := func(y: float, _angle: float) -> float:
			return side * (1.0 - smoothstep(1.63, 1.83, y))
		Mosuo._tube_part(sided, 32, drape, Callable(), weight, vertices, indices, arm_weights)
	var result := Mosuo._finish(vertices, indices, arm_weights, "top")
	var uv := PackedVector2Array()
	Mosuo._append_uv(_shirt_rings(), 128, 2.6, 2.25, uv)
	for side in 2:
		Mosuo._append_uv(sleeve, 32, 1.3, 2.25, uv)
	result["uv"] = uv
	return result


static func shirt_collar() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var opening := func(y: float, angle: float) -> bool:
		return y > 1.889 and absf(wrapf(angle, -PI, PI)) < .028
	var rings := [Vector4(1.906, .183, .145, 0.0), Vector4(1.920, .173, .139, 0.0)]
	Mosuo._tube_part(rings, 128, Callable(), opening, Callable(), vertices, indices, arm_weights)
	return Mosuo._finish(vertices, indices, arm_weights, "top")


static func shirt_cuffs() -> Dictionary:
	# Narrow gathered white bands at the puffed sleeve ends.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	for side in [-1.0, 1.0]:
		var rings := [
			Vector4(1.185, .102, .112, side * .294), Vector4(1.145, .100, .110, side * .297)]
		var weight := func(_y: float, _angle: float) -> float:
			return side * .95
		Mosuo._tube_part(rings, 32, Callable(), Callable(), weight, vertices, indices, arm_weights)
	return Mosuo._finish(vertices, indices, arm_weights, "top")


static func neck_bow() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	Mosuo._append_sphere(vertices, indices, arm_weights, Vector3(0, 1.862, .168), .014)
	for side in [-1.0, 1.0]:
		var loop := PackedVector3Array([
			Vector3(side * .005, 1.862, .170), Vector3(side * .045, 1.885, .175),
			Vector3(side * .062, 1.862, .172), Vector3(side * .045, 1.845, .170),
			Vector3(side * .005, 1.862, .170)])
		Mosuo._ribbon(loop, .009, .002, vertices, indices, arm_weights)
	Mosuo._ribbon(PackedVector3Array([
		Vector3(.008, 1.855, .172), Vector3(.020, 1.79, .205),
		Vector3(.030, 1.72, .215), Vector3(.032, 1.66, .222)]), .007, .004, vertices, indices, arm_weights)
	Mosuo._ribbon(PackedVector3Array([
		Vector3(-.006, 1.855, .172), Vector3(-.016, 1.80, .208),
		Vector3(-.020, 1.74, .218)]), .007, .004, vertices, indices, arm_weights)
	for i in vertices.size():
		vertices[i].y += .049
		vertices[i].z -= .024 * smoothstep(1.80, 1.91, vertices[i].y)
	return Mosuo._finish(vertices, indices, arm_weights, "top")


static func neck_beads() -> Dictionary:
	# Four black/white beaded strands (namysto) resting on collar and chest;
	# each ring sits OUTSIDE the shirt at its own height, dipping at the front.
	var groups := {"dark": [PackedVector3Array(), PackedInt32Array(), PackedFloat32Array()],
		"light": [PackedVector3Array(), PackedInt32Array(), PackedFloat32Array()]}
	var rows := [
		[1.962, .143, .120, .003], [1.949, .152, .130, .008],
		[1.936, .171, .145, .012]]
	var bead_radius := .0068
	for row in rows:
		var count := maxi(12, int(round(_circumference(row[1], row[2]) / (bead_radius * 2.15))))
		for index in count:
			var angle := TAU * index / count
			var drop: float = row[3] * pow(maxf(0.0, cos(angle)), 2.0)
			var center := Vector3(sin(angle) * row[1], row[0] - drop, cos(angle) * row[2])
			var key := "dark" if row == rows[0] and index % 4 < 3 else "light"
			var group: Array = groups[key]
			Mosuo._append_sphere(group[0], group[1], group[2], center, bead_radius)
	return {"dark": Mosuo._finish(groups["dark"][0], groups["dark"][1], groups["dark"][2], "top"),
		"light": Mosuo._finish(groups["light"][0], groups["light"][1], groups["light"][2], "top")}


static func _sash_fit(y: float) -> Vector2:
	# The sash hugs the dressed silhouette: shirt and overskirt waist,
	# whichever is wider at each height.
	var shirt := Mosuo._ring_at(_shirt_rings(), y)
	var skirt := Mosuo._ring_at(OVERSKIRT_RINGS, y)
	var apron_ring := Mosuo._ring_at(APRON_RINGS, y)
	return Vector2(maxf(apron_ring.y, maxf(shirt.y, skirt.y)), maxf(apron_ring.z, maxf(shirt.z, skirt.z)))


static func sash_wrap() -> Dictionary:
	# Three overlapping cloth turns wrapping the high waist. Each turn tilts
	# and wrinkles around the body instead of being a rigid ellipse band.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var segments := 96
	for wrap in 3:
		var center_y := 1.388 + wrap * .033
		var phase := wrap * 1.7
		var start := vertices.size()
		for row in 7:
			var edge := (row - 3) * .0093
			for column in segments + 1:
				var angle := TAU * column / segments
				var tilt := .012 * sin(angle) + .007 * sin(angle + phase)
				var y := center_y + edge + tilt
				var fit := _sash_fit(y)
				var wrinkle := .0035 * sin(PI * row / 6.0) + .0018 * cos(PI * row) + .0025 * cos(angle * 7.0 + phase * 2.0) + .0015 * cos(angle * 13.0 + phase)
				vertices.append(Vector3(sin(angle) * (fit.x + .010 + wrap * .004 + wrinkle), y,
					cos(angle) * (fit.y + .010 + wrap * .004 + wrinkle)))
				arm_weights.append(0.0)
		for row in 6:
			for column in segments:
				var a := start + row * (segments + 1) + column
				var b := a + segments + 1
				indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	return Mosuo._finish(vertices, indices, arm_weights, "bottom")


static func sash_knot() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	Mosuo._append_sphere(vertices, indices, arm_weights, Vector3( .075, 1.415, .280), .018)
	for side in [-1.0, 1.0]:
		var loop := PackedVector3Array([
			Vector3( .075 + side * .010, 1.415, .282), Vector3( .075 + side * .058, 1.442, .288),
			Vector3( .075 + side * .078, 1.415, .280), Vector3( .075 + side * .058, 1.392, .285),
			Vector3( .075 + side * .010, 1.415, .282)])
		Mosuo._ribbon(loop, .013, .003, vertices, indices, arm_weights)
	return Mosuo._finish(vertices, indices, arm_weights, "bottom")


static func sash_tail(side: float) -> Dictionary:
	var controls := PackedVector3Array([
		Vector3(side * .128, 1.400, .262), Vector3(side * .145, 1.240, .272),
		Vector3(side * .163, 1.160, .292), Vector3(side * .178, 1.035, .318)])
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	Mosuo._ribbon(controls, .047, .003, vertices, indices, arm_weights)
	return Mosuo._finish(vertices, indices, arm_weights, "bottom")


static func sash_tassels(side: float) -> Dictionary:
	# Yarn-pompon tassels from the parametric motif, one geometry per color.
	return tassel_asset().build(Vector3(side * .178, 1.035, .318))
