@tool
class_name PleatedSkirtDynamics
extends RefCounted

## Game-side implementation of the Toolkit pleated-skirt bone/cage binding,
## silhouette/hem shape, inextensible longitudinal drape, seated/lying support,
## 120Hz centrifugal spin inertia, and display grasp.
##
## Directly mirrors D:/CodexWorkspace/papercut-editor/src/pleatedSkirt/*.ts
## so the in-game PleatedSkirt matches the Toolkit preview 1:1.

const CAGE_ROWS := [0.20, 0.24, 0.30, 0.48, 0.70, 0.99, 1.22, 1.31]
const CAGE_COLUMNS := 40
const SILHOUETTES := ["relaxed", "a_line", "bell", "trumpet"]
const HEM_SHAPES := ["body", "circle", "wide", "deep", "custom"]

const DEFAULT_SHAPE := {
	"relaxed": {"fullness": 0.5, "taper": 0.5},
	"a_line": {"flare": 0.5, "curve": 0.5},
	"bell": {"volume": 0.5, "peak": 0.6},
	"trumpet": {"fit": 0.5, "flare_start": 0.5, "flare": 0.6},
	"hem": {"mode": "body", "ratio": 0.7},
}

const DEFAULT_MOTION := {
	"arm_angle": 45.0,
	"spread": 90.0,
	"speed": 0.4,
	"uniformity": 0.35,
}


static func smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _round_cent(v: float) -> float:
	return roundf(clampf(v, 0.0, 1.0) * 100.0) / 100.0


static func default_drape(parameters: Dictionary) -> Dictionary:
	var fabric_table := {
		"cotton": [0.48, 0.44, 0.55],
		"linen": [0.55, 0.72, 0.35],
		"silk": [0.28, 0.16, 0.86],
		"wool": [0.78, 0.65, 0.38],
	}
	var f: Array = fabric_table.get(String(parameters.get("fabric", "cotton")), fabric_table["cotton"])
	var thickness := maxf(0.01, float(parameters.get("thickness_mm", 0.7)) / 0.7)
	var fullness := float(parameters.get("hem_cm", 240.0)) / maxf(1.0, float(parameters.get("waist_cm", 68.0)))
	var length_cm := float(parameters.get("length_cm", 88.0))
	var sharpness := float(parameters.get("sharpness", 0.5))
	return {
		"weight": _round_cent(float(f[0]) * sqrt(thickness) * sqrt(length_cm / 88.0)),
		"bending": _round_cent(float(f[1]) + (log(thickness) / log(2.0)) * 0.12 + sharpness * 0.08),
		"opening": _round_cent(float(f[2]) + (fullness - 3.4) * 0.055 - sharpness * 0.12),
	}


static func effective_drape(design: Dictionary) -> Dictionary:
	if design.has("drape") and typeof(design["drape"]) == TYPE_DICTIONARY:
		var d: Dictionary = design["drape"]
		if String(d.get("mode", "auto")) == "manual":
			return {
				"weight": clampf(float(d.get("weight", 0.5)), 0.0, 1.0),
				"bending": clampf(float(d.get("bending", 0.5)), 0.0, 1.0),
				"opening": clampf(float(d.get("opening", 0.5)), 0.0, 1.0),
			}
	return default_drape(design.get("parameters", {}))


static func effective_shape(design: Dictionary) -> Dictionary:
	if design.has("shape") and typeof(design["shape"]) == TYPE_DICTIONARY:
		return (design["shape"] as Dictionary).duplicate(true)
	return DEFAULT_SHAPE.duplicate(true)


static func effective_hem(design: Dictionary) -> Dictionary:
	var shape := effective_shape(design)
	var hem: Dictionary = shape.get("hem", DEFAULT_SHAPE["hem"])
	var mode := String(hem.get("mode", "body"))
	var ratio := float(hem.get("ratio", 0.7))
	if mode == "body":
		ratio = 1.87 / 2.59
	elif mode == "circle":
		ratio = 1.0
	var angle_deg := 0.0
	if mode == "deep":
		angle_deg = 90.0
	elif mode == "custom":
		angle_deg = fposmod(float(hem.get("angle_deg", 0.0)), 180.0)
	return {"mode": mode, "ratio": clampf(ratio, 0.35, 1.0), "angle_deg": angle_deg}


static func ellipse_perimeter(a: float, b: float) -> float:
	var sum := maxf(0.000001, a + b)
	var h := pow((a - b) / sum, 2.0)
	return PI * sum * (1.0 + 3.0 * h / (10.0 + sqrt(maxf(0.0001, 4.0 - 3.0 * h))))


static func rest_opening(design: Dictionary, v: float) -> float:
	var d := effective_drape(design)
	var fabric := 0.40 + 0.28 * float(d["bending"]) - 0.12 * float(d["weight"]) + 0.10 * float(d["opening"])
	var s := effective_shape(design)
	var silhouette := String(design.get("silhouette", "relaxed"))
	match silhouette:
		"a_line":
			var a_line: Dictionary = s["a_line"]
			return clampf((fabric + 0.12 + (float(a_line["flare"]) - 0.5) * 0.6) * pow(maxf(v, 1.0 / 24.0), (0.5 - float(a_line["curve"])) * 0.9), 0.16, 0.95)
		"bell":
			var bell: Dictionary = s["bell"]
			var peak := clampf(float(bell["peak"]), 0.2, 0.85)
			var bump := smooth(v / peak) if v <= peak else 1.0 - 0.55 * smooth((v - peak) / maxf(0.001, 1.0 - peak))
			return clampf(fabric + 0.64 * float(bell["volume"]) * bump, 0.2, 0.98)
		"trumpet":
			var trumpet: Dictionary = s["trumpet"]
			var flare_start := clampf(float(trumpet["flare_start"]), 0.2, 0.85)
			return clampf(fabric * (0.3 + 0.5 * float(trumpet["fit"])) + 0.8 * float(trumpet["flare"]) * smooth((v - flare_start) / maxf(0.001, 1.0 - flare_start)), 0.14, 0.98)
		_:
			var relaxed: Dictionary = s["relaxed"]
			return clampf(fabric + (float(relaxed["fullness"]) - 0.5) * 0.4 - (float(relaxed["taper"]) - 0.5) * 0.25 * v, 0.16, 0.9)


static func ellipse_transform(rx: float, rz: float, v: float, design: Dictionary) -> Vector3:
	var shape := effective_shape(design)
	if String(shape["hem"].get("mode", "body")) == "body":
		return Vector3(rx, 0.0, rz)
	var hem := effective_hem(design)
	var angle := deg_to_rad(float(hem["angle_deg"]))
	var c := cos(angle)
	var s := sin(angle)
	var perimeter := ellipse_perimeter(rx, rz)
	var ratio := float(hem["ratio"])
	var a := perimeter / ellipse_perimeter(1.0, ratio)
	var b := a * ratio
	var blend := smooth(v)
	var xx := rx + (a * c * c + b * s * s - rx) * blend
	var xz := (a - b) * c * s * blend
	var zz := rz + (a * s * s + b * c * c - rz) * blend
	var center := (xx + zz) * 0.5
	var spread := hypot(xx - zz, 2.0 * xz) * 0.5
	var correction := perimeter / maxf(0.000001, ellipse_perimeter(center + spread, maxf(0.0001, center - spread)))
	return Vector3(xx * correction, xz * correction, zz * correction)


static func hypot(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


class SkirtInertia extends RefCounted:
	var tick := 0
	var key := ""
	var previous_omega := 0.0
	var angle := 0.0
	var omega := 0.0
	var lag := PackedFloat64Array()
	var lag_velocity := PackedFloat64Array()
	var opening := PackedFloat64Array()
	var opening_velocity := PackedFloat64Array()

	func _init() -> void:
		lag.resize(25)
		lag_velocity.resize(25)
		opening.resize(25)
		opening_velocity.resize(25)
		reset()

	func reset() -> void:
		tick = 0
		angle = 0.0
		omega = 0.0
		previous_omega = 0.0
		lag.fill(0.0)
		lag_velocity.fill(0.0)
		opening.fill(0.0)
		opening_velocity.fill(0.0)

	func sample(time: float, design: Dictionary, motion: Dictionary = DEFAULT_MOTION) -> SkirtInertia:
		var p: Dictionary = design.get("parameters", {})
		var d: Dictionary = {}
		if design.has("drape") and typeof(design["drape"]) == TYPE_DICTIONARY and String(design["drape"].get("mode", "auto")) == "manual":
			d = {
				"weight": clampf(float(design["drape"].get("weight", 0.5)), 0.0, 1.0),
				"bending": clampf(float(design["drape"].get("bending", 0.5)), 0.0, 1.0),
				"opening": clampf(float(design["drape"].get("opening", 0.5)), 0.0, 1.0),
			}
		else:
			var fabric_table := {
				"cotton": [0.48, 0.44, 0.55],
				"linen": [0.55, 0.72, 0.35],
				"silk": [0.28, 0.16, 0.86],
				"wool": [0.78, 0.65, 0.38],
			}
			var f: Array = fabric_table.get(String(p.get("fabric", "cotton")), fabric_table["cotton"])
			var th := maxf(0.01, float(p.get("thickness_mm", 0.7)) / 0.7)
			var full := float(p.get("hem_cm", 240.0)) / maxf(1.0, float(p.get("waist_cm", 68.0)))
			var l_cm := float(p.get("length_cm", 88.0))
			var sh := float(p.get("sharpness", 0.5))
			d = {
				"weight": roundf(clampf(float(f[0]) * sqrt(th) * sqrt(l_cm / 88.0), 0.0, 1.0) * 100.0) / 100.0,
				"bending": roundf(clampf(float(f[1]) + (log(th) / log(2.0)) * 0.12 + sh * 0.08, 0.0, 1.0) * 100.0) / 100.0,
				"opening": roundf(clampf(float(f[2]) + (full - 3.4) * 0.055 - sh * 0.12, 0.0, 1.0) * 100.0) / 100.0,
			}
		var next_key := JSON.stringify([p, design.get("silhouette", "relaxed"), design.get("shape", {}), d])
		var goal := maxi(0, int(floor(time * 120.0 + 1e-7)))
		if next_key != key or goal < tick:
			key = next_key
			reset()
		var dt := 1.0 / 120.0
		var weight := float(d["weight"])
		var bending := float(d["bending"])
		var open_param := float(d["opening"])
		var length_cm := float(p.get("length_cm", 88.0))
		var waist_cm := float(p.get("waist_cm", 68.0))
		var hem_cm := float(p.get("hem_cm", 240.0))
		var thickness_mm := float(p.get("thickness_mm", 0.7))
		var mass := 0.65 + weight + thickness_mm * 0.12
		var stiffness := (10.0 + 26.0 * bending) / mass * (88.0 / maxf(1.0, length_cm))
		var speed := clampf(float(motion.get("speed", 0.4)), 0.1, 1.5)
		var uniformity := clampf(float(motion.get("uniformity", 0.35)), 0.0, 1.0)
		while tick < goal:
			tick += 1
			var t := float(tick) * dt
			var phase := t * speed
			var a := 0.85 * (1.0 - uniformity)
			var ramp := clampf(t / 0.8, 0.0, 1.0)
			var smooth_ramp := ramp * ramp * (3.0 - 2.0 * ramp)
			omega = TAU * speed * (1.0 - a * cos(TAU * phase)) * smooth_ramp
			var acceleration := (omega - previous_omega) / dt
			angle += (omega + previous_omega) * 0.5 * dt
			previous_omega = omega
			for row in range(1, 25):
				var v := float(row) / 24.0
				var k := stiffness / (0.4 + 0.6 * v)
				var damping := 2.0 * sqrt(k) * (0.35 + 0.35 * bending)
				var torque := -acceleration * v * 0.65 - omega * v * (0.15 + 0.2 * weight)
				lag_velocity[row] += (-k * lag[row] - damping * lag_velocity[row] + torque) * dt
				lag[row] = clampf(lag[row] + lag_velocity[row] * dt, -0.85, 0.85)
				var radius := (waist_cm + (hem_cm - waist_cm) * v) / TAU / 100.0
				var centrifugal := omega * omega * radius
				var equilibrium := clampf(centrifugal / (9.81 * (0.65 + weight * 0.35) + centrifugal) * (1.2 - 0.55 * bending) * (0.6 + 0.4 * open_param), 0.0, 0.92)
				var radial_k := (14.0 + 12.0 * bending) / mass
				opening_velocity[row] += (radial_k * (equilibrium - opening[row]) - 2.0 * sqrt(radial_k) * 0.65 * opening_velocity[row]) * dt
				opening[row] = clampf(opening[row] + opening_velocity[row] * dt, 0.0, 0.96)
		return self


static func natural_envelope(p: PackedVector3Array, rest: PackedVector3Array, design: Dictionary, width: int, inertia: SkirtInertia = null) -> void:
	var columns := width - 1
	var capacity := PackedFloat64Array()
	capacity.resize(25)
	capacity.fill(0.0)
	for row in range(25):
		for col in range(columns):
			var a := row * width + col
			var b := row * width + ((col + 1) % columns)
			capacity[row] += rest[a].distance_to(rest[b]) / TAU
	var length_m := float(design.get("parameters", {}).get("length_cm", 88.0)) / 100.0
	var side_col := int(round(float(columns) * 0.25))
	for row in range(1, 25):
		var v := float(row) / 24.0
		var open := inertia.opening[row] if inertia != null else 0.0
		var fraction := rest_opening(design, v) * (1.0 - open) + open
		var rx := maxf(0.001, absf(rest[side_col].x + (rest[row * width + side_col].x - rest[side_col].x) * fraction))
		var rz := maxf(0.001, absf(rest[0].z + (rest[row * width].z - rest[0].z) * fraction))
		var et := ellipse_transform(rx, rz, v, design)
		var xx := et.x
		var xz := et.y
		var zz := et.z
		var mean_radius := (absf(rest[row * width + side_col].x) + absf(rest[row * width].z)) * 0.5
		var circular := maxf(sqrt(maxf(0.0, xx * zz - xz * xz)), mean_radius * fraction + (capacity[row] - mean_radius) * open)
		var lag := inertia.lag[row] if inertia != null else 0.0
		var c := cos(lag)
		var s := sin(lag)
		for col in range(columns):
			var at := row * width + col
			var waist := col
			var qx := (rest[waist].x + (rest[at].x - rest[waist].x) * fraction) / rx
			var qz := (rest[waist].z + (rest[at].z - rest[waist].z) * fraction) / rz
			var x := xx * qx + xz * qz
			var z := xz * qx + zz * qz
			var angle := float(col) / float(columns) * TAU
			x = x * (1.0 - open) + sin(angle) * circular * open
			z = z * (1.0 - open) - cos(angle) * circular * open
			p[at] = Vector3(
				x * c + z * s,
				rest[at].y + open * v * length_m * 0.8,
				-x * s + z * c
			)


static func project_ellipsoid(p: PackedVector3Array, at: int, center: Vector3, radii: Vector3, strength: float = 1.0) -> float:
	var k := clampf(strength, 0.0, 1.0)
	if k <= 0.0 or at < 0 or at >= p.size() or radii.x <= 0.0 or radii.y <= 0.0 or radii.z <= 0.0:
		return 0.0
	var pt := p[at]
	var x := (pt.x - center.x) / radii.x
	var y := (pt.y - center.y) / radii.y
	var z := (pt.z - center.z) / radii.z
	var d2 := x * x + y * y + z * z
	if d2 >= 1.0:
		return 0.0
	var surface: Vector3
	if d2 <= 0.0:
		surface = Vector3(center.x, center.y + radii.y, center.z)
	else:
		var inv := 1.0 / sqrt(d2)
		surface = Vector3(center.x + x * inv * radii.x, center.y + y * inv * radii.y, center.z + z * inv * radii.z)
	var delta := (surface - pt) * k
	p[at] = pt + delta
	return delta.length()


static func project_capsule(p: PackedVector3Array, at: int, a: Vector3, b: Vector3, radius: float, strength: float = 1.0) -> float:
	var k := clampf(strength, 0.0, 1.0)
	if k <= 0.0 or at < 0 or at >= p.size() or radius <= 0.0:
		return 0.0
	var pt := p[at]
	var e := b - a
	var len2 := e.length_squared()
	var t := clampf((pt - a).dot(e) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
	var closest := a + e * t
	var d := pt - closest
	var d2 := d.length_squared()
	if d2 >= radius * radius:
		return 0.0
	var offset := d * (radius / sqrt(d2)) if d2 > 0.0 else Vector3(0.0, radius, 0.0)
	var move := (offset - d) * k
	p[at] = pt + move
	return move.length()


static func _eval_path(points: Array[Vector3], distance: float) -> Vector3:
	var rem := distance
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		if rem <= seg:
			var t := rem / seg if seg > 0.0 else 0.0
			return a.lerp(b, t)
		rem -= seg
	var last := points[points.size() - 1]
	return Vector3(last.x, last.y - rem, last.z)


static func seated_envelope(p: PackedVector3Array, rest: PackedVector3Array, width: int, rows: int, d: Dictionary, blend: float, knee_drop: float = 0.0) -> void:
	var cols := width - 1
	var bending := float(d["bending"])
	for col in range(cols):
		var u := float(col) / float(cols)
		var angle := u * TAU
		var front := (1.0 - cos(angle)) * 0.5
		var rear := 1.0 - front
		var side := sin(angle)
		var waist := p[col]
		var radial := absf(rest[rows * width + col].x) / maxf(0.001, absf(side))
		var side_room := minf(0.21, maxf(0.0, radial - 0.28)) * (0.3 + 0.4 * bending)
		var hip_x := side * (0.29 + side_room * 0.3)
		var knee_x := side * (0.29 + side_room)
		var seat := 1.04
		var front_path: Array[Vector3] = [
			waist,
			Vector3(hip_x, 1.255 - knee_drop * 0.45, 0.29),
			Vector3(knee_x, 1.255 - knee_drop, 0.50),
			Vector3(knee_x, 1.18 - knee_drop, 0.66),
			Vector3(knee_x, 1.05 - knee_drop, 0.69),
		]
		var fold := 0.025 + 0.055 * bending
		var back_x := side * (0.30 + side_room)
		var rear_path: Array[Vector3] = [
			waist,
			Vector3(hip_x, 1.12, -0.23),
			Vector3(back_x, seat + fold, -0.27),
			Vector3(back_x, seat + fold * 0.45, -0.12),
			Vector3(back_x, seat + fold, -0.34),
			Vector3(back_x, seat + 0.025, -0.23),
			Vector3(back_x, seat + 0.015, -0.38),
			Vector3(back_x, seat - 0.10, -0.39),
		]
		var lateral_path: Array[Vector3] = [
			waist,
			Vector3(hip_x, 1.13, 0.01),
			Vector3(back_x, seat + 0.04, 0.03),
			Vector3(back_x, seat - 0.10, 0.04),
		]
		var side_w := pow(absf(side), 4.0)
		var front_w := front * front
		var rear_w := rear * rear
		var total := maxf(0.000001, side_w + front_w + rear_w)
		var material := 0.0
		for row in range(1, rows + 1):
			var at := row * width + col
			var prior := (row - 1) * width + col
			material += rest[at].distance_to(rest[prior])
			var f := _eval_path(front_path, material)
			var b := _eval_path(rear_path, material)
			var s := _eval_path(lateral_path, material)
			var v := float(row) / float(rows)
			var fullness := minf(0.17, maxf(0.0, radial - 0.3)) * v
			var target := (f * front_w + b * rear_w + s * side_w) / total
			target.x += side * fullness
			target.z += (front - rear) * fullness * 0.35
			p[at] = p[at].lerp(target, blend)


static func support_seated_body(p: PackedVector3Array, width: int, rows: int, strength: float, knee_drop: float = 0.0) -> void:
	var cols := width - 1
	for row in range(1, rows + 1):
		for col in range(cols):
			var at := row * width + col
			project_ellipsoid(p, at, Vector3(0.0, 1.17, -0.015), Vector3(0.295, 0.15, 0.245), strength)
			for side in [-1.0, 1.0]:
				project_capsule(p, at, Vector3(side * 0.15, 1.14, 0.035), Vector3(side * 0.15, 1.14 - knee_drop, 0.52), 0.135, strength)
				project_capsule(p, at, Vector3(side * 0.15, 1.12 - knee_drop, 0.52), Vector3(side * 0.15, 0.66 - knee_drop, 0.52), 0.107, strength)


static func rest_frame_from_doll(doll: Node3D) -> Dictionary:
	if doll == null or doll.get("rig") == null:
		return {"hip": Vector3(0.0, 1.14, 0.0), "angle": 0.0}
	var rig = doll.rig
	var hip_index: int = rig.bones.get("Hips", 0)
	var hip_pose: Transform3D = rig.global_pose(hip_index)
	var hip_skin: Transform3D = hip_pose * rig.skeleton.get_bone_global_rest(hip_index).affine_inverse()
	var hip := hip_pose.origin
	var waist := hip_skin * Vector3(0.0, 1.31, 0.0)
	return {
		"hip": hip,
		"angle": atan2(-(waist.x - hip.x), waist.y - hip.y),
	}


static func transform_rest_cloth(p: PackedVector3Array, frame: Dictionary, count: int, inverse: bool = false) -> void:
	var hip: Vector3 = frame.get("hip", Vector3(0.0, 1.14, 0.0))
	var angle: float = float(frame.get("angle", 0.0))
	var c := cos(angle)
	var s := sin(angle)
	var limit := mini(count, p.size())
	for i in range(limit):
		var pt := p[i]
		if inverse:
			var x := pt.x - hip.x
			var y := pt.y - hip.y
			p[i] = Vector3(c * x + s * y, -s * x + c * y + 1.14, pt.z - hip.z)
		else:
			var x := pt.x
			var y := pt.y - 1.14
			p[i] = Vector3(c * x - s * y + hip.x, s * x + c * y + hip.y, pt.z + hip.z)


static func settle_reclining_cloth(p: PackedVector3Array, width: int, rows: int, angle: float, weight: float, constraint: DrapeConstraint) -> void:
	var recline := pow(sin(angle), 2.0)
	if recline < 1e-6:
		return
	var cols := width - 1
	for row in range(1, rows + 1):
		var v := float(row) / float(rows)
		for col in range(cols):
			var at := row * width + col
			p[at].y -= recline * v * v * (0.55 + 0.5 * weight)
	for _pass in range(8):
		constraint.project_lengths(p)
		for row in range(1, rows + 1):
			for col in range(cols):
				var at := row * width + col
				if absf(p[at].x) < 1.84 and p[at].z > -0.79 and p[at].z < 0.205:
					p[at].y = maxf(0.735, p[at].y)
	constraint.project_lengths(p)


class DrapeConstraint extends RefCounted:
	var width: int
	var rows: int
	var shell: int
	var rest: PackedVector3Array
	var warp: PackedFloat32Array
	var thickness: PackedFloat32Array

	func _init(columns: int, vertical_rows: int, rest_positions: PackedVector3Array) -> void:
		width = columns + 1
		rows = vertical_rows
		shell = width * (rows + 1)
		rest = rest_positions.duplicate()
		warp.resize(shell)
		thickness.resize(shell)
		for j in range(rows + 1):
			for i in range(width):
				var at := j * width + i
				if j > 0:
					warp[at] = rest[at].distance_to(rest[at - width])
				if at + shell < rest.size():
					thickness[at] = rest[at].distance_to(rest[at + shell])
				else:
					thickness[at] = 0.0007

	func apply(p: PackedVector3Array, n: PackedVector3Array, d: Dictionary, amount: float, action: String = "stand", shape_rest: PackedVector3Array = PackedVector3Array(), knee_drop: float = 0.0) -> void:
		if amount <= 0.0:
			return
		var ref_rest := shape_rest if not shape_rest.is_empty() else rest
		var w := width
		var cols := w - 1
		var source := p.slice(0, shell)
		var blend := amount * amount * (3.0 - 2.0 * amount)
		if action == "sit":
			_seated_envelope_internal(p, ref_rest, w, rows, d, blend, knee_drop)
		elif action == "lie":
			for row in range(1, rows + 1):
				var v := float(row) / float(rows)
				for col in range(cols):
					var at := row * w + col
					var r := ref_rest[at]
					var target := Vector3(-1.31 + (1.31 - r.y), r.x * (1.0 - 0.75 * v) - 0.10 * v, r.z * (1.0 - 0.40 * v) + 0.24 * v)
					p[at] = source[at].lerp(target, blend)

		var envelope := p.slice(0, shell)
		var open_val := float(d["opening"])
		var weight_val := float(d["weight"])
		var bend_val := float(d["bending"])
		for row in range(1, rows + 1):
			var v := float(row) / float(rows)
			var open := open_val * amount * v * 0.65
			var drop := weight_val * (1.0 - bend_val * 0.75) * amount * v * v * 0.22
			for col in range(cols):
				var at := row * w + col
				var lo := row * w + ((col + cols - 4) % cols)
				var hi := row * w + ((col + 4) % cols)
				var avg := (envelope[lo] + envelope[hi]) * 0.5
				p[at] = envelope[at].lerp(avg, open)
				p[at].y -= drop

		if action == "sit" or action == "lie":
			var seated := blend if action == "sit" else blend * (1.0 - blend)
			var gathered := p.slice(0, shell)
			var softness := 1.0 - bend_val * 0.7
			for row in range(1, rows):
				var v := float(row) / float(rows)
				var band := pow(sin(PI * v), 2.0)
				for col in range(cols):
					var index := row * w + col
					var u := float(col) / float(cols)
					var span := warp[index]
					var actual := gathered[index].distance_to(gathered[index - w])
					var slack := clampf(1.0 - actual / maxf(span, 1e-8), 0.0, 0.8)
					var side := pow(absf(sin(u * TAU)), 2.0)
					var amplitude := minf(0.065, sqrt(slack) * (0.025 + 0.045 * side) * softness) * band * seated
					var phase := v * PI * (4.0 + 2.0 * (1.0 - bend_val)) + 0.65 * cos(u * PI * 4.0)
					p[index].y += amplitude * sin(phase) - side * band * seated * weight_val * softness * 0.09
					p[index].z += amplitude * 0.65 * cos(phase)

		if action == "sit":
			for _i in range(3):
				_support_seated_body_internal(p, w, rows, blend, knee_drop)
				project_lengths(p)
		else:
			project_lengths(p)
		finish_surface(p, n)

	static func _eval_path_internal(points: Array[Vector3], distance: float) -> Vector3:
		var rem := distance
		for i in range(1, points.size()):
			var a := points[i - 1]
			var b := points[i]
			var seg := a.distance_to(b)
			if rem <= seg:
				var t := rem / seg if seg > 0.0 else 0.0
				return a.lerp(b, t)
			rem -= seg
		var last := points[points.size() - 1]
		return Vector3(last.x, last.y - rem, last.z)

	static func _seated_envelope_internal(p: PackedVector3Array, rest_arr: PackedVector3Array, w: int, r_count: int, d: Dictionary, blend: float, knee_drop: float = 0.0) -> void:
		var cols := w - 1
		var bending := float(d["bending"])
		for col in range(cols):
			var u := float(col) / float(cols)
			var angle := u * TAU
			var front := (1.0 - cos(angle)) * 0.5
			var rear := 1.0 - front
			var side := sin(angle)
			var waist := p[col]
			var radial := absf(rest_arr[r_count * w + col].x) / maxf(0.001, absf(side))
			var side_room := minf(0.21, maxf(0.0, radial - 0.28)) * (0.3 + 0.4 * bending)
			var hip_x := side * (0.29 + side_room * 0.3)
			var knee_x := side * (0.29 + side_room)
			var seat := 1.04
			var front_path: Array[Vector3] = [
				waist,
				Vector3(hip_x, 1.255 - knee_drop * 0.45, 0.29),
				Vector3(knee_x, 1.255 - knee_drop, 0.50),
				Vector3(knee_x, 1.18 - knee_drop, 0.66),
				Vector3(knee_x, 1.05 - knee_drop, 0.69),
			]
			var fold := 0.025 + 0.055 * bending
			var back_x := side * (0.30 + side_room)
			var rear_path: Array[Vector3] = [
				waist,
				Vector3(hip_x, 1.12, -0.23),
				Vector3(back_x, seat + fold, -0.27),
				Vector3(back_x, seat + fold * 0.45, -0.12),
				Vector3(back_x, seat + fold, -0.34),
				Vector3(back_x, seat + 0.025, -0.23),
				Vector3(back_x, seat + 0.015, -0.38),
				Vector3(back_x, seat - 0.10, -0.39),
			]
			var lateral_path: Array[Vector3] = [
				waist,
				Vector3(hip_x, 1.13, 0.01),
				Vector3(back_x, seat + 0.04, 0.03),
				Vector3(back_x, seat - 0.10, 0.04),
			]
			var side_w := pow(absf(side), 4.0)
			var front_w := front * front
			var rear_w := rear * rear
			var total := maxf(0.000001, side_w + front_w + rear_w)
			var material := 0.0
			for row in range(1, r_count + 1):
				var at := row * w + col
				var prior := (row - 1) * w + col
				material += rest_arr[at].distance_to(rest_arr[prior])
				var f := _eval_path_internal(front_path, material)
				var b := _eval_path_internal(rear_path, material)
				var s := _eval_path_internal(lateral_path, material)
				var v := float(row) / float(r_count)
				var fullness := minf(0.17, maxf(0.0, radial - 0.3)) * v
				var target := (f * front_w + b * rear_w + s * side_w) / total
				target.x += side * fullness
				target.z += (front - rear) * fullness * 0.35
				p[at] = p[at].lerp(target, blend)

	static func _project_ellipsoid_internal(p: PackedVector3Array, at: int, center: Vector3, radii: Vector3, strength: float = 1.0) -> void:
		var k := clampf(strength, 0.0, 1.0)
		if k <= 0.0 or at < 0 or at >= p.size() or radii.x <= 0.0 or radii.y <= 0.0 or radii.z <= 0.0:
			return
		var pt := p[at]
		var x := (pt.x - center.x) / radii.x
		var y := (pt.y - center.y) / radii.y
		var z := (pt.z - center.z) / radii.z
		var d2 := x * x + y * y + z * z
		if d2 >= 1.0:
			return
		var surface: Vector3
		if d2 <= 0.0:
			surface = Vector3(center.x, center.y + radii.y, center.z)
		else:
			var inv := 1.0 / sqrt(d2)
			surface = Vector3(center.x + x * inv * radii.x, center.y + y * inv * radii.y, center.z + z * inv * radii.z)
		p[at] = pt + (surface - pt) * k

	static func _project_capsule_internal(p: PackedVector3Array, at: int, a: Vector3, b: Vector3, radius: float, strength: float = 1.0) -> void:
		var k := clampf(strength, 0.0, 1.0)
		if k <= 0.0 or at < 0 or at >= p.size() or radius <= 0.0:
			return
		var pt := p[at]
		var e := b - a
		var len2 := e.length_squared()
		var t := clampf((pt - a).dot(e) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
		var closest := a + e * t
		var d := pt - closest
		var d2 := d.length_squared()
		if d2 >= radius * radius:
			return
		var offset := d * (radius / sqrt(d2)) if d2 > 0.0 else Vector3(0.0, radius, 0.0)
		p[at] = pt + (offset - d) * k

	static func _support_seated_body_internal(p: PackedVector3Array, w: int, r_count: int, strength: float, knee_drop: float = 0.0) -> void:
		var cols := w - 1
		for row in range(1, r_count + 1):
			for col in range(cols):
				var at := row * w + col
				_project_ellipsoid_internal(p, at, Vector3(0.0, 1.17, -0.015), Vector3(0.295, 0.15, 0.245), strength)
				for side in [-1.0, 1.0]:
					_project_capsule_internal(p, at, Vector3(side * 0.15, 1.14, 0.035), Vector3(side * 0.15, 1.14 - knee_drop, 0.52), 0.135, strength)
					_project_capsule_internal(p, at, Vector3(side * 0.15, 1.12 - knee_drop, 0.52), Vector3(side * 0.15, 0.66 - knee_drop, 0.52), 0.107, strength)

	func project_lengths(p: PackedVector3Array) -> void:
		var w := width
		var cols := w - 1
		var target := p.slice(0, shell)
		for row in range(1, rows + 1):
			for col in range(cols):
				var a := (row - 1) * w + col
				var b := row * w + col
				var delta := target[b] - target[a]
				var len_val := delta.length()
				if len_val < 1e-8:
					delta = rest[b] - rest[a]
					len_val = maxf(1e-8, delta.length())
				p[b] = p[a] + delta * (warp[b] / len_val)

	func finish_surface(p: PackedVector3Array, n: PackedVector3Array) -> void:
		var w := width
		var cols := w - 1
		for row in range(rows + 1):
			p[row * w + cols] = p[row * w]
		var has_inner := p.size() >= shell * 2
		for row in range(rows + 1):
			for col in range(w):
				var c := col % cols
				var at := row * w + col
				var left := row * w + ((c + cols - 1) % cols)
				var right := row * w + ((c + 1) % cols)
				var up := maxi(0, row - 1) * w + c
				var down := mini(rows, row + 1) * w + c
				var du := p[right] - p[left]
				var dv := p[down] - p[up]
				var normal := du.cross(dv).normalized()
				if normal.length_squared() < 0.25:
					normal = Vector3(p[at].x, 0.0, p[at].z).normalized()
					if normal.length_squared() < 0.25:
						normal = Vector3.UP
				n[at] = normal
				if has_inner:
					var inner := at + shell
					var t := thickness[at]
					p[inner] = p[at] - normal * t
					n[inner] = -normal
		if p.size() >= shell * 2 + 4 * w:
			var rim_base := shell * 2
			for col in range(w):
				p[rim_base + col] = p[col]
				p[rim_base + w + col] = p[shell + col]
				p[rim_base + w * 2 + col] = p[rows * w + col]
				p[rim_base + w * 3 + col] = p[shell + rows * w + col]

	func max_warp_error(p: PackedVector3Array) -> float:
		var error := 0.0
		for row in range(1, rows + 1):
			for col in range(width - 1):
				var at := row * width + col
				var d := p[at].distance_to(p[at - width])
				error = maxf(error, absf(d / maxf(1e-8, warp[at]) - 1.0))
		return error


static func grasp_phase(t: float) -> Dictionary:
	var release := 1.0 if t < 0.65 else exp(-9.0 * (t - 0.65) * 5.0) * (1.0 + 9.0 * (t - 0.65) * 5.0) * (1.0 - smooth((t - 0.9) / 0.1))
	return {
		"reach": smooth(t / 0.18),
		"lift": smooth((t - 0.22) / 0.22),
		"held": t >= 0.18 and t < 0.65,
		"recovery": smooth((t - 0.70) / 0.22),
		"release": release,
	}


static func grasp_skirt(p: PackedVector3Array, rest: PackedVector3Array, width: int, t: float, options: Dictionary = DEFAULT_MOTION) -> Array[Dictionary]:
	var phase := grasp_phase(t)
	var columns := width - 1
	var hands: Array[Dictionary] = []
	var spread := deg_to_rad(float(options.get("spread", 90.0)) * 0.5)
	var angle := deg_to_rad(float(options.get("arm_angle", 45.0)))
	for side in [-1.0, 1.0]:
		var col := int(round((0.25 if side > 0.0 else 0.75) * float(columns)))
		var shoulder := Vector3(side * 0.24, 1.66, 0.0)
		var rest_hand := Vector3(side * 0.30, 1.17, 0.025)
		var grip_row := 1
		var nearest := INF
		for row in range(1, 25):
			var at := row * width + col
			var pt := rest[at]
			var dist := rest_hand.distance_to(pt)
			if dist < nearest and shoulder.distance_to(pt) <= 0.55:
				nearest = dist
				grip_row = row
		var grip_at := grip_row * width + col
		var grip := rest[grip_at]
		var lift := float(phase["lift"]) * float(phase["release"])
		var delta := Vector3(
			side * 0.18 * sin(angle) * sin(spread) * lift,
			0.07 * sin(angle) * lift,
			0.08 * sin(angle) * cos(spread) * lift
		)
		if t >= 0.22 and lift > 1e-8:
			var source := p.duplicate()
			for column in range(columns):
				var diff := absi(column - col)
				var du := float(mini(diff, columns - diff)) / float(columns)
				var w := exp(-du * du / 0.012)
				var chain := PackedVector3Array()
				var sizes := PackedFloat32Array()
				chain.resize(grip_row + 1)
				sizes.resize(grip_row)
				for row in range(grip_row + 1):
					chain[row] = source[row * width + column]
					if row > 0:
						sizes[row - 1] = chain[row - 1].distance_to(chain[row])
				var root_pt := chain[0]
				var end_pt := chain[grip_row] + delta * w
				var total := 0.0
				for s in sizes:
					total += s
				var dist := root_pt.distance_to(end_pt)
				if dist > total * (1.0 - 1e-8):
					end_pt = root_pt + (end_pt - root_pt) * (total * (1.0 - 1e-8) / dist)
				for _pass in range(32):
					chain[grip_row] = end_pt
					for row in range(grip_row - 1, -1, -1):
						var d := maxf(1e-8, chain[row].distance_to(chain[row + 1]))
						chain[row] = chain[row + 1] + (chain[row] - chain[row + 1]) * (sizes[row] / d)
					chain[0] = root_pt
					for row in range(1, grip_row + 1):
						var d := maxf(1e-8, chain[row].distance_to(chain[row - 1]))
						chain[row] = chain[row - 1] + (chain[row] - chain[row - 1]) * (sizes[row - 1] / d)
				for row in range(1, grip_row + 1):
					p[row * width + column] = chain[row]
				var shift := chain[grip_row] - source[grip_row * width + column]
				for row in range(grip_row + 1, 25):
					p[row * width + column] = source[row * width + column] + shift
		var actual := p[grip_at]
		var target := rest_hand.lerp(grip, float(phase["reach"])) if t < 0.22 else actual
		if t >= 0.65:
			var release_hand := actual + Vector3(side * 0.04 * smooth((t - 0.65) / 0.05), 0.0, 0.0)
			target = release_hand.lerp(rest_hand, float(phase["recovery"]))
		hands.append({
			"side": side,
			"target": target,
			"row": grip_row,
			"column": col,
			"contact": bool(phase["held"]),
		})
	for hand in hands:
		if bool(hand["contact"]):
			var at := int(hand["row"]) * width + int(hand["column"])
			hand["target"] = p[at]
	return hands


class GarmentBinding extends RefCounted:
	var positions: PackedVector3Array
	var normals: PackedVector3Array
	var _corners: PackedInt32Array
	var _weights: PackedFloat32Array
	var _local: PackedVector3Array
	var _normal_local: PackedVector3Array
	var _radial_scale: PackedFloat32Array
	var _columns: int
	var _rows: int
	var _shell_count: int

	func _init(shell_positions: PackedVector3Array, shell_normals: PackedVector3Array, shell_uvs: PackedVector2Array, cage_rest: PackedVector3Array, length_cm: float, cage_columns: int = CAGE_COLUMNS, cage_rows_y: Array = CAGE_ROWS) -> void:
		_shell_count = shell_positions.size()
		positions = shell_positions.duplicate()
		normals = shell_normals.duplicate()
		_corners.resize(_shell_count * 4)
		_weights.resize(_shell_count * 4)
		_local.resize(_shell_count)
		_normal_local.resize(_shell_count)
		_radial_scale.resize(_shell_count)
		_columns = cage_columns
		_rows = cage_rows_y.size()
		var basis := _frames_for_grid(cage_rest, _columns, _rows)
		var top := float(cage_rows_y[_rows - 1])
		var bottom := float(cage_rows_y[0])
		var vertical := (top - bottom) / 0.88
		var sx := 0.28 / (0.68 / TAU)
		var sz := 0.202 / (0.68 / TAU)
		var stride := _columns + 1
		for i in range(_shell_count):
			var pos := shell_positions[i]
			var x := pos.x * sx
			var y := top - (length_cm / 100.0) * vertical + pos.y * vertical
			var z := pos.z * sz
			var u := shell_uvs[i].x
			var col_f := fposmod(0.5 - u, 1.0) * float(_columns)
			var c0 := mini(_columns - 1, int(floor(col_f)))
			var cu := col_f - float(c0)
			var r := 0
			while r < _rows - 2 and y > float(cage_rows_y[r + 1]):
				r += 1
			var r_span := maxf(1e-6, float(cage_rows_y[r + 1]) - float(cage_rows_y[r]))
			var v := clampf((y - float(cage_rows_y[r])) / r_span, 0.0, 1.0)
			var i4 := i * 4
			_corners[i4] = r * stride + c0
			_corners[i4 + 1] = r * stride + c0 + 1
			_corners[i4 + 2] = (r + 1) * stride + c0
			_corners[i4 + 3] = (r + 1) * stride + c0 + 1
			_weights[i4] = (1.0 - cu) * (1.0 - v)
			_weights[i4 + 1] = cu * (1.0 - v)
			_weights[i4 + 2] = (1.0 - cu) * v
			_weights[i4 + 3] = cu * v
			var frame := _interpolate_basis(basis, i)
			var p := _interpolate_vec3(cage_rest, i)
			var denom := maxf(1e-8, p.x * p.x + p.z * p.z)
			var scale := (x * p.x + z * p.z) / denom
			_radial_scale[i] = scale
			var delta := Vector3(x - p.x * scale, y - p.y, z - p.z * scale)
			var nrm := Vector3(shell_normals[i].x / sx, shell_normals[i].y / vertical, shell_normals[i].z / sz)
			_local[i] = _solve(frame, delta)
			_normal_local[i] = _solve(frame, nrm)

	static func _frames_for_grid(grid: PackedVector3Array, columns: int, rows: int) -> Array[Basis]:
		var stride := columns + 1
		var result: Array[Basis] = []
		result.resize(grid.size())
		for row in range(rows):
			for col in range(stride):
				var c := col % columns
				var left := row * stride + ((c + columns - 1) % columns)
				var right := row * stride + ((c + 1) % columns)
				var low := maxi(0, row - 1) * stride + c
				var high := mini(rows - 1, row + 1) * stride + c
				var u_axis := (grid[right] - grid[left]).normalized()
				if u_axis.length_squared() < 0.25:
					u_axis = Vector3.RIGHT
				var d := grid[high] - grid[low]
				var v_axis := (d - u_axis * u_axis.dot(d)).normalized()
				if v_axis.length_squared() < 0.25:
					v_axis = Vector3.UP
				var n_axis := u_axis.cross(v_axis).normalized()
				result[row * stride + col] = Basis(u_axis, v_axis, n_axis)
		return result

	func _interpolate_vec3(data: PackedVector3Array, index: int) -> Vector3:
		var i4 := index * 4
		return (
			data[_corners[i4]] * _weights[i4]
			+ data[_corners[i4 + 1]] * _weights[i4 + 1]
			+ data[_corners[i4 + 2]] * _weights[i4 + 2]
			+ data[_corners[i4 + 3]] * _weights[i4 + 3]
		)

	func _interpolate_basis(data: Array[Basis], index: int) -> Basis:
		var i4 := index * 4
		var b0 := data[_corners[i4]]
		var b1 := data[_corners[i4 + 1]]
		var b2 := data[_corners[i4 + 2]]
		var b3 := data[_corners[i4 + 3]]
		var w0 := _weights[i4]
		var w1 := _weights[i4 + 1]
		var w2 := _weights[i4 + 2]
		var w3 := _weights[i4 + 3]
		return Basis(
			b0.x * w0 + b1.x * w1 + b2.x * w2 + b3.x * w3,
			b0.y * w0 + b1.y * w1 + b2.y * w2 + b3.y * w3,
			b0.z * w0 + b1.z * w1 + b2.z * w2 + b3.z * w3
		)

	static func _solve(frame: Basis, p: Vector3) -> Vector3:
		var a := frame.x
		var b := frame.y
		var c := frame.z
		var bc := b.cross(c)
		var det := a.dot(bc)
		if absf(det) < 1e-8:
			return Vector3.ZERO
		return Vector3(p.dot(bc) / det, p.dot(c.cross(a)) / det, p.dot(a.cross(b)) / det)

	func deform(cage_positions: PackedVector3Array) -> GarmentBinding:
		var basis := _frames_for_grid(cage_positions, _columns, _rows)
		var centers := PackedVector3Array()
		centers.resize(cage_positions.size())
		var stride := _columns + 1
		for row in range(_rows):
			var mean := Vector3.ZERO
			for col in range(_columns):
				mean += cage_positions[row * stride + col]
			mean /= float(_columns)
			for col in range(stride):
				centers[row * stride + col] = mean
		for i in range(_shell_count):
			var frame := _interpolate_basis(basis, i)
			var p := _interpolate_vec3(cage_positions, i)
			var center := _interpolate_vec3(centers, i)
			var scale := _radial_scale[i]
			var loc := _local[i]
			var nloc := _normal_local[i]
			positions[i] = center + (p - center) * scale + frame.x * loc.x + frame.y * loc.y + frame.z * loc.z
			var nrm := frame.x * nloc.x + frame.y * nloc.y + frame.z * nloc.z
			normals[i] = nrm.normalized() if nrm.length_squared() > 1e-12 else Vector3.UP
		return self
