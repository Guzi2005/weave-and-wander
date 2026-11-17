class_name UkrainianCostume
extends RefCounted

## Procedural geometry for the ukrainian_photo_001 set (WW-UKR-001), rebuilt
## against assets/collections/ukrainian_photo_001/photo_landmarks.json.
##
## Evidence policy: only what the source photo shows is modelled as observed
## (white gathered blouse with bishop sleeves, burgundy neck ribbon, black and
## white bead strands, high mustard sash with two woven tails ending in yarn
## tassels, mauve front apron, teal overskirt with yellow warp stripes, white
## petticoat, white socks). Back views and hidden joins are production inference.
##
## The doll body is the shared VolumeDoll and is not modified. All heights are
## doll metres, taken from the photo landmarks (chin and shoe top anchors).
## Skirt shells follow Docs/PLEATED_SKIRT_CONTRACT.md (8 samples per pleat,
## 24 rows, sharpness blend, depth ramp/cap, real inner wall, seam at -Z).

const Mosuo = preload("res://components/mosuo_costume.gd")
const Stripe = preload("res://components/motifs/stripe_motif.gd")
const Tassel = preload("res://components/motifs/tassel_motif.gd")
const CLOTH_FIT = preload("res://assets/collections/ukrainian_photo_001/cloth_fit.tres")

static var stripe: Stripe = null
static var tassel: Tassel = null

const COLOR_SHIRT := Color("f1ece0")
const COLOR_PETTICOAT := Color("ebe6da")
const COLOR_SOCK := Color("f4f1e9")
const COLOR_RIBBON := Color("6a2038")
const COLOR_SASH := Color("a08622")
const COLOR_APRON := Color("8a5578")
const COLOR_BEAD_DARK := Color("232028")
const COLOR_BEAD_LIGHT := Color("ece7db")

## Landmarks, doll metres (photo_landmarks.json -> doll_targets_y).
## Realigned to the authentic high-waist doll anatomy:
## Sash wraps at the natural waist (1.30~1.48), leaving generous room
## for the billowy blouse above (1.48~1.93) and layered skirts below.
const Y_SASH_TOP := 1.48
const Y_SASH_BOTTOM := 1.30
const Y_SASH_CENTER := 1.39
const Y_TAIL_END := 0.98
const Y_OVERSKIRT_HEM := .37
const Y_APRON_HEM := .46
const Y_PETTICOAT_HEM := .335
const Y_SLEEVE_CUFF := 1.20

const OVERSKIRT_RINGS := [
	Vector4(1.64, .300, .236, 0.0), Vector4(1.50, .302, .240, 0.0),
	Vector4(1.30, .306, .246, 0.0), Vector4(1.12, .318, .258, 0.0),
	Vector4(.96, .366, .294, 0.0), Vector4(.78, .440, .352, 0.0),
	Vector4(.60, .530, .420, 0.0), Vector4(.37, .640, .510, 0.0)]

const UNDERSKIRT_RINGS := [
	Vector4(1.60, .280, .220, 0.0), Vector4(1.30, .285, .228, 0.0),
	Vector4(1.10, .295, .238, 0.0), Vector4(.90, .360, .288, 0.0),
	Vector4(.70, .430, .345, 0.0), Vector4(.50, .510, .405, 0.0),
	Vector4(.37, .565, .450, 0.0), Vector4(.335, .585, .465, 0.0)]

const OVERSKIRT_OPTS := {"pleat_count": 44, "depth_m": .017, "sharpness": .55,
	"thickness": .0012, "swell": .022, "swell_count": 7}

## Calf sock, in leg-node space (same z offset as the doll calf, +.045).
const SOCK_RINGS := [
	Vector3(-.96, .059, .066), Vector3(-.90, .0625, .0695), Vector3(-.82, .0685, .0765),
	Vector3(-.72, .0765, .0835), Vector3(-.70, .0775, .0845)]

## Sleeve centre-line follows the shared doll arm: x = .150 at y = 1.86 to .301 at 1.13.
const SLEEVE_PROFILE := [
	Vector3(1.81, .070, .075), Vector3(1.76, .115, .112), Vector3(1.68, .155, .148),
	Vector3(1.58, .182, .172), Vector3(1.48, .186, .176), Vector3(1.38, .175, .165),
	Vector3(1.30, .145, .140), Vector3(1.24, .110, .108), Vector3(1.205, .084, .088),
	Vector3(1.195, .078, .082)]


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


static func stripe_role(u: float, patches: Array) -> String:
	for patch in patches:
		if u >= patch["u0"] and u < patch["u1"]:
			return patch["role"]
	return "base"


## Shared parametric skirt shell (contract geometry). opts: pleat_count,
## depth_m, sharpness, thickness, patches, arc, rows, v_range, lift, swell,
## swell_count. role "solid" builds everything; otherwise only columns whose
## stripe role matches are emitted.
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
	var swell: float = opts.get("swell", 0.0)
	var swell_count: int = opts.get("swell_count", 7)
	var segments := count * (16 if not patches.is_empty() else 8)
	var span: float = arc.y - arc.x
	var columns := int(round(segments * span))
	var top_y: float = (rings[0] as Vector4).x
	var hem_y: float = (rings[rings.size() - 1] as Vector4).x
	var waist: Vector4 = rings[0]
	var depth_cap := _circumference(waist.y, waist.z) / count * .45
	var column_role := []
	for column in columns + 1:
		var u: float = arc.x + span * float(column) / columns
		column_role.append("solid" if patches.is_empty() else stripe_role(fposmod(u, 1.0), patches))
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
				fold += swell * smoothstep(.10, .60, v) * sin(angle * swell_count + y * 2.3)
				var rx := ring.y + fold + lift - inward
				var rz := ring.z + fold + lift - inward
				vertices.append(Vector3(sin(angle) * rx, y, cos(angle) * rz))
				arm_weights.append(0.0)
		for row in rows:
			for column in columns:
				if role != "solid" and column_role[column] != role:
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
		uv[i] = Vector2(fposmod(atan2(p.x, p.z) / TAU - .5, 1.0), inverse_lerp(top_y, hem_y, p.y))
	result["uv"] = uv
	return result


static func overskirt(role: String) -> Dictionary:
	var opts := OVERSKIRT_OPTS.duplicate()
	opts["patches"] = stripe_asset().patches()
	return skirt_shell(OVERSKIRT_RINGS, opts, role)


static func overskirt_hem_band() -> Dictionary:
	# Continuous woven yellow edge along the overskirt hem.
	var opts := OVERSKIRT_OPTS.duplicate()
	opts["v_range"] = Vector2(.962, .990)
	opts["lift"] = .0015
	return skirt_shell(OVERSKIRT_RINGS, opts, "solid")


static func underskirt() -> Dictionary:
	return skirt_shell(UNDERSKIRT_RINGS, {
		"pleat_count": 22, "depth_m": .004, "sharpness": .5, "thickness": .0012, "swell": .008}, "solid")


static func _surface_z(rings: Array, x: float, y: float, lift: float) -> float:
	var ring: Vector4 = Mosuo._ring_at(rings, y)
	var k := clampf(1.0 - pow(x / ring.y, 2.0), 0.0, 1.0)
	return ring.z * sqrt(k) + lift


## Front panel hung from the high waist. It is not a wrap-around skirt: a flat
## cloth falls straight, widening a little, and lies on the overskirt surface.
static func _apron_panel(t0: float, t1: float, lift_extra: float) -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var uv := PackedVector2Array()
	var rows := maxi(2, int(round(24.0 * (t1 - t0))))
	var cols := 32
	for row in rows + 1:
		var t := lerpf(t0, t1, float(row) / rows)
		var y := lerpf(1.63, Y_APRON_HEM, t)
		var half := lerpf(.262, .395, pow(t, .9))
		for col in cols + 1:
			var s := float(col) / cols * 2.0 - 1.0
			var x := s * half
			var lift := lerpf(.006, .046, smoothstep(0.06, 0.22, t)) + .006 * t + lift_extra
			var gather := .006 * smoothstep(0.08, 0.22, t) * (1.0 - smoothstep(0.22, 0.70, t)) * cos(s * PI * 9.0)
			var drape := .008 * smoothstep(.15, .90, t) * (cos(s * PI * 4.0 + .6) + 1.0) * 0.5 \
				+ .004 * t * sin(s * PI * 8.0 + t * 4.0)
			var edge_curl := .006 * smoothstep(.75, 1.0, absf(s)) * smoothstep(0.08, 0.30, t)
			var sag := -.008 * (1.0 - s * s) * smoothstep(.85, 1.0, t)
			vertices.append(Vector3(x, y + sag, _surface_z(OVERSKIRT_RINGS, x, y, lift + gather + drape + edge_curl)))
			arm_weights.append(0.0)
			uv.append(Vector2(float(col) / cols * 2.6, (2.0 - y) * 2.25))
	for row in rows:
		for col in cols:
			var a := row * (cols + 1) + col
			var b := a + cols + 1
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var result := Mosuo._finish(vertices, indices, arm_weights, "bottom")
	result["uv"] = uv
	return result


static func apron() -> Dictionary:
	return _apron_panel(0.0, .955, 0.0)


static func apron_hem_band() -> Dictionary:
	return _apron_panel(.955, 1.0, .003)


static func _bodice_rings() -> Array:
	return [
		Vector4(1.28, .260, .200, 0.0), Vector4(1.38, .275, .215, 0.0),
		Vector4(1.48, .285, .222, 0.0), Vector4(1.58, .292, .228, 0.0),
		Vector4(1.68, .288, .224, 0.0), Vector4(1.76, .272, .208, 0.0),
		Vector4(1.82, .235, .175, 0.0), Vector4(1.86, .195, .145, 0.0),
		Vector4(1.90, .148, .122, 0.0), Vector4(1.93, .115, .098, 0.0)]


static func _sleeve_rings(side: float) -> Array:
	var rings := []
	for p: Vector3 in SLEEVE_PROFILE:
		var centre: float = side * (.155 + (1.81 - p.x) * .22)
		rings.append(Vector4(p.x, p.y, p.z, centre))
	return rings


static func _bodice_front_z(x: float, y: float) -> float:
	var ring: Vector4 = Mosuo._ring_at(_bodice_rings(), y)
	return ring.z * sqrt(clampf(1.0 - pow(x / ring.y, 2.0), 0.0, 1.0))


static func shirt_body() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var opening := func(y: float, angle: float) -> bool:
		return y > 1.875 and absf(wrapf(angle, -PI, PI)) < .034
	# Smooth linen with gathers only where the photo shows them: the neckline
	# and the cuffs. No vertical pleating down the bodice.
	var gathers := func(y: float, angle: float) -> float:
		var neck := smoothstep(1.78, 1.915, y)
		return neck * CLOTH_FIT.gather_depth * 4.0 * cos(CLOTH_FIT.gather_count * angle) \
			+ (1.0 - neck) * .006 * sin(angle * 3.0 + y * 5.0)
	Mosuo._tube_part(_bodice_rings(), 128, gathers, opening, Callable(), vertices, indices, arm_weights)
	for side in [-1.0, 1.0]:
		var drape := func(y: float, angle: float) -> float:
			var cuff := smoothstep(1.40, 1.22, y)
			var shoulder := smoothstep(1.78, 1.86, y)
			return .008 * cos(angle * 3.0 + y * 6.0) + .035 * cuff * cos(angle * 15.0) \
				+ .018 * shoulder * cos(angle * 12.0)
		var weight := func(y: float, _angle: float) -> float:
			return side * (1.0 - smoothstep(1.63, 1.83, y))
		Mosuo._tube_part(_sleeve_rings(side), 40, drape, Callable(), weight, vertices, indices, arm_weights)
	var result := Mosuo._finish(vertices, indices, arm_weights, "top")
	var uv := PackedVector2Array()
	Mosuo._append_uv(_bodice_rings(), 128, 2.6, 2.25, uv)
	for side in 2:
		Mosuo._append_uv(SLEEVE_PROFILE.map(func(p: Vector3) -> Vector4: return Vector4(p.x, 0, 0, 0)), 40, 1.3, 2.25, uv)
	result["uv"] = uv
	return result


static func shirt_collar() -> Dictionary:
	# Small standing gathered frill around the neckline, open at the ribbon.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var opening := func(y: float, angle: float) -> bool:
		return y > 1.88 and absf(wrapf(angle, -PI, PI)) < .03
	var folds := func(_y: float, angle: float) -> float:
		return .045 * cos(26.0 * angle)
	var rings := [Vector4(1.895, .144, .122, 0.0), Vector4(1.920, .154, .130, 0.0),
		Vector4(1.947, .148, .124, 0.0)]
	Mosuo._tube_part(rings, 104, folds, opening, Callable(), vertices, indices, arm_weights)
	return Mosuo._finish(vertices, indices, arm_weights, "top")


static func shirt_cuffs() -> Dictionary:
	# Narrow gathered bands where the bishop sleeves close at the wrist.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	for side in [-1.0, 1.0]:
		var rings := [
			Vector4(1.205, .091, .095, side * (.150 + (1.86 - 1.205) * .2068)),
			Vector4(1.150, .089, .093, side * (.150 + (1.86 - 1.150) * .2068))]
		var folds := func(_y: float, angle: float) -> float:
			return .045 * cos(16.0 * angle)
		var weight := func(_y: float, _angle: float) -> float:
			return side * .95
		Mosuo._tube_part(rings, 40, folds, Callable(), weight, vertices, indices, arm_weights)
	return Mosuo._finish(vertices, indices, arm_weights, "top")


static func neck_bow() -> Dictionary:
	# Burgundy ribbon: small tie at the front opening, two long unequal tails
	# lying on the bodice (the photo shows them reaching just above the sash).
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var bow_y := 1.888
	var zf := _bodice_front_z(0.0, bow_y) + .014
	Mosuo._append_sphere(vertices, indices, arm_weights, Vector3(0, bow_y, zf), .0125)
	for side in [-1.0, 1.0]:
		var loop := PackedVector3Array([
			Vector3(side * .004, bow_y, zf), Vector3(side * .030, bow_y + .020, zf + .002),
			Vector3(side * .052, bow_y + .002, zf), Vector3(side * .030, bow_y - .018, zf + .002),
			Vector3(side * .004, bow_y, zf)])
		Mosuo._ribbon(loop, .008, .0, vertices, indices, arm_weights)
	for tail in [[.006, .018, 1.745], [-.006, -.020, 1.768]]:
		var controls := PackedVector3Array()
		for step in 6:
			var t := float(step) / 5.0
			var y := lerpf(bow_y - .008, tail[2], t)
			var x: float = lerpf(tail[0], tail[1], t) + .006 * sin(t * PI * 1.5)
			controls.append(Vector3(x, y, _bodice_front_z(x, y) + .010))
		Mosuo._ribbon(controls, .0065, .0, vertices, indices, arm_weights)
	return Mosuo._finish(vertices, indices, arm_weights, "top")


static func neck_beads() -> Dictionary:
	# Authentic Ukrainian neck adornment with natural gravity-draped catenary hanging:
	# 1. Choker (Sylianka): tight collar band hugging the neck column at Y=1.98.
	# 2. Layered Hanging Beads (Namysto): 3 cascading strands anchored high at the nape (Y=1.94),
	#    draping gracefully forward under gravity across the clavicle and chest (U-shaped catenary).
	var groups := {"dark": [PackedVector3Array(), PackedInt32Array(), PackedFloat32Array()],
		"light": [PackedVector3Array(), PackedInt32Array(), PackedFloat32Array()]}
	var bead_radius := .0058

	# Strand 0: Sylianka choker band around neck column
	var choker_count := 26
	for i in choker_count:
		var angle := TAU * i / choker_count
		var y := 1.98 - .010 * cos(angle)
		var center := Vector3(sin(angle) * .098, y, cos(angle) * .090 + .004)
		var key := "dark" if i % 4 < 3 else "light"
		Mosuo._append_sphere(groups[key][0], groups[key][1], groups[key][2], center, bead_radius)

	# Strands 1, 2, 3: Gravitational Hanging Beads (Namysto)
	# Each strand hangs from back nape (Y=1.94, Z=-0.075) and loops forward across chest.
	var hanging_strands := [
		{"y_dip": 1.88, "z_front": .138, "count": 28, "rx": .105}, # sits on clavicle frill
		{"y_dip": 1.82, "z_front": .170, "count": 32, "rx": .118}, # drapes across upper chest
		{"y_dip": 1.76, "z_front": .198, "count": 36, "rx": .132}, # cascades over mid chest
	]

	for s_idx in hanging_strands.size():
		var s: Dictionary = hanging_strands[s_idx]
		var count: int = s.count
		var y_front: float = s.y_dip
		var z_front: float = s.z_front
		var rx: float = s.rx
		for i in count:
			var angle := TAU * i / count
			var front_factor := .5 * (1.0 + cos(angle)) # 0 at back, 1 at front
			var y := lerpf(1.94, y_front, pow(front_factor, 1.3))
			var z := lerpf(-.075, z_front, front_factor)
			var x := sin(angle) * lerpf(.092, rx, front_factor)
			var center := Vector3(x, y, z)
			var key := "light" if (i + s_idx) % 2 == 0 else "dark"
			Mosuo._append_sphere(groups[key][0], groups[key][1], groups[key][2], center, bead_radius)

	return {"dark": Mosuo._finish(groups["dark"][0], groups["dark"][1], groups["dark"][2], "top"),
		"light": Mosuo._finish(groups["light"][0], groups["light"][1], groups["light"][2], "top")}


static func _waist_ring(y: float) -> Vector2:
	var skirt: Vector4 = Mosuo._ring_at(OVERSKIRT_RINGS, y)
	var bodice: Vector4 = Mosuo._ring_at(_bodice_rings(), y)
	return Vector2(maxf(skirt.y, bodice.y), maxf(skirt.z, bodice.z))


## One wide folded cloth band (photo: a flat band about as tall as the bust
## gap, not a stack of rolls). Soft crease rows and a gently tilted edge.
static func sash_wrap() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var colors := PackedColorArray()
	var segments := 96
	var rows := 12
	for row in rows + 1:
		var t := float(row) / rows
		for column in segments + 1:
			var angle := TAU * column / segments
			var y := lerpf(Y_SASH_TOP, Y_SASH_BOTTOM, t) + .006 * sin(angle + 1.1) * (1.0 - .6 * absf(t - .5))
			var fit := _waist_ring(y)
			var front_bias: float = maxf(0.0, cos(angle))
			var bulge := .004 * sin(PI * t) + .002 * cos(angle * 6.0 + t * 3.0)
			var radial := .008 + .005 * front_bias + bulge
			vertices.append(Vector3(sin(angle) * (fit.x + radial), y, cos(angle) * (fit.y + radial)))
			arm_weights.append(0.0)
			var shade := 1.0
			if t < .07 or t > .93:
				shade = .90
			elif absf(t - .34) < .035 or absf(t - .68) < .035:
				shade = .86
			colors.append(Color(shade, shade, shade))
	for row in rows:
		for column in segments:
			var a := row * (segments + 1) + column
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var result := Mosuo._finish(vertices, indices, arm_weights, "bottom")
	result["colors"] = colors
	return result


static func _append_ellipsoid(vertices: PackedVector3Array, indices: PackedInt32Array,
		arm_weights: PackedFloat32Array, center: Vector3, radii: Vector3, basis: Basis) -> void:
	var base := vertices.size()
	var rings := 6
	var segments := 12
	for ring in rings + 1:
		var phi := PI * ring / rings
		for column in segments + 1:
			var theta := TAU * column / segments
			var local := Vector3(sin(phi) * sin(theta) * radii.x, cos(phi) * radii.y, sin(phi) * cos(theta) * radii.z)
			vertices.append(center + basis * local)
			arm_weights.append(0.0)
	for ring in rings:
		for column in segments:
			var a := base + ring * (segments + 1) + column
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))


static func sash_knot() -> Dictionary:
	# Compact folded cloth knot at the front centre with folded loops either side.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var front: float = _waist_ring(Y_SASH_CENTER).y + .018
	_append_ellipsoid(vertices, indices, arm_weights, Vector3(0, Y_SASH_CENTER, front + .010),
		Vector3(.044, .034, .014), Basis.IDENTITY)
	for side in [-1.0, 1.0]:
		_append_ellipsoid(vertices, indices, arm_weights,
			Vector3(side * .036, Y_SASH_CENTER + side * .004, front + .006),
			Vector3(.030, .022, .012), Basis(Vector3.BACK, side * -.28))
	return Mosuo._finish(vertices, indices, arm_weights, "bottom")


static func _tail_points(side: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var steps := 14
	for step in steps + 1:
		var t := float(step) / steps
		var y := lerpf(1.575, Y_TAIL_END, t)
		var x := side * (.030 + .050 * t + .010 * sin(t * PI * 1.3))
		var apron_t := clampf((1.63 - y) / (1.63 - Y_APRON_HEM), 0.0, 1.0)
		var apron_lift := lerpf(.006, .046, smoothstep(0.06, 0.22, apron_t)) + .006 * apron_t
		var z := _surface_z(OVERSKIRT_RINGS, x, y, apron_lift + .006)
		points.append(Vector3(x, y, z))
	return points


## Flat woven tail: darker selvedge bands along both edges and a faint weft
## ladder, as visible on the photo's sash ends.
static func sash_tail(side: float) -> Dictionary:
	var path := _tail_points(side)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var arm_weights := PackedFloat32Array()
	var colors := PackedColorArray()
	var half := .046
	var offsets := [-1.0, -.80, -.80, .80, .80, 1.0]
	var shades := [.74, .74, 1.0, 1.0, .74, .74]
	for index in path.size():
		var tangent := (path[mini(index + 1, path.size() - 1)] - path[maxi(index - 1, 0)]).normalized()
		var width := Vector3(0, 0, 1).cross(tangent).normalized()
		var weft := .94 if index % 2 == 0 else 1.0
		for column in offsets.size():
			vertices.append(path[index] + width * half * offsets[column])
			arm_weights.append(0.0)
			var shade: float = shades[column] * weft
			colors.append(Color(shade, shade, shade))
	var stride := offsets.size()
	for index in path.size() - 1:
		for column in [0, 2, 4]:
			var a: int = index * stride + column
			var b := a + stride
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var result := Mosuo._finish(vertices, indices, arm_weights, "bottom")
	result["colors"] = colors
	return result


static func sash_tassels(side: float) -> Dictionary:
	# Yarn-pompon tassel from the parametric motif, one geometry per colour.
	var path := _tail_points(side)
	var end: Vector3 = path[path.size() - 1]
	return tassel_asset().build(Vector3(end.x, end.y - .004, end.z + .004))
