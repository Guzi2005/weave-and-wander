@tool
class_name ParametricFlower
extends Resource

## Upward-opening, layered fabric headflower. Units are model metres and the
## local frame is Y-up: the centre of the flower opens toward +Y, with broad
## cupped petals on several staggered layers and a raised, curled centre bud.
##
## Geometry is fully parametric and deterministic from `seed`. Every petal is
## a closed solid with real thickness: upper/lower faces, a rounded cross
## section and stitched root/tip caps. Normals are generated analytically from
## the petal surface and triangle winding follows Godot's clockwise front-face
## convention. `material()` is a matte cloth material with vertex colours.
##
## The dictionary returned by build_geometry() is the same contract used by the
## other headwear resources:
##   vertices, normals, indices, colors, uv, arm_weights, slot,
##   petal_count, layer_count
##
## Schema: ww-parametric-flower-v1.

const SCHEMA := "ww-parametric-flower-v1"

const PETAL_RING_SIDES := 10
const PETAL_ROWS := 19
const PETAL_T_START := 0.02
const PETAL_T_END := 0.995
const BUD_RING_SIDES := 10
const BUD_ROWS := 7
# Cross products of millimetre-scale surface derivatives are much smaller than
# positional tolerances. A 1e-6 squared-length threshold discarded valid normals.
const EPSILON := 1.0e-18

@export var petal_color := Color("e83547")
@export_range(0.03, 0.18, 0.001) var radius := 0.09
@export_range(1, 8, 1) var layers := 4
@export_range(3, 16, 1) var petals_per_layer := 7
@export_range(0.005, 0.12, 0.001) var cup_depth := 0.045
@export_range(0.0, 1.0, 0.01) var petal_roundness := 0.85
@export_range(0.0, 1.5, 0.01) var twist := 0.5
@export var orientation_degrees := Vector3.ZERO
@export var seed := 7


## JSON-compatible description of the design, suitable for saving beside a
## garment definition. No Godot value types leak into the result.
func parameters() -> Dictionary:
	return {
		"schema": SCHEMA,
		"petal_color": petal_color.to_html(),
		"radius": radius,
		"layers": layers,
		"petals_per_layer": petals_per_layer,
		"cup_depth": cup_depth,
		"petal_roundness": petal_roundness,
		"twist": twist,
		"orientation_degrees": [orientation_degrees.x, orientation_degrees.y, orientation_degrees.z],
		"seed": self.seed,
		"units": "model metres",
		"attachment": "HeadwearSlot",
	}


func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "ParametricFlower · scarlet cloth"
	# Vertex attributes are linear in Godot and glTF; colour-picker values are sRGB.
	# Convert the recipe colour when building vertices and keep a white base.
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.metallic = 0.0
	mat.metallic_specular = 0.28
	# A real cloth shell is closed, but disabling culling keeps the paper-thin
	# root/tip caps readable from every angle without a plastic-looking clear coat.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Slight anisotropy breaks up the specular highlight like a brushed weave.
	# The property is guarded because it is optional in some compatibility builds.
	if _has_property(mat, "anisotropy_enabled"):
		mat.set("anisotropy_enabled", true)
	if _has_property(mat, "anisotropy"):
		mat.set("anisotropy", 0.32)
	return mat


func build_geometry() -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()

	var specs := _layer_specs()
	for spec in specs:
		_append_petal(vertices, normals, indices, colors, uvs, spec)
	_append_bud(vertices, normals, indices, colors, uvs)

	var rotation := _orientation_basis()
	for index in vertices.size():
		vertices[index] = rotation * vertices[index]
		var normal := rotation * normals[index]
		if normal.length_squared() > EPSILON:
			normals[index] = normal.normalized()
		else:
			normals[index] = Vector3.UP

	# Keep the output contract safe even if a caller assigns a non-finite export.
	for index in vertices.size():
		if not _vector_is_finite(vertices[index]):
			vertices[index] = Vector3.ZERO
		if not _vector_is_finite(normals[index]) or normals[index].length_squared() <= EPSILON:
			normals[index] = Vector3.UP
		normals[index] = normals[index].normalized()

	return {
		"vertices": vertices,
		"normals": normals,
		"indices": indices,
		"colors": colors,
		"uv": uvs,
		"arm_weights": PackedFloat32Array(),
		"slot": "headwear",
		"petal_count": specs.size() + _bud_petal_count(),
		"layer_count": _layer_count(),
	}


func _layer_count() -> int:
	return clampi(layers, 1, 8)


func _petal_count() -> int:
	return clampi(petals_per_layer, 3, 16)


func _safe_radius() -> float:
	var value := radius if is_finite(radius) else 0.09
	return clampf(value, 0.03, 0.18)


func _safe_cup() -> float:
	var value := cup_depth if is_finite(cup_depth) else 0.045
	return clampf(value, 0.005, 0.12)


func _safe_roundness() -> float:
	var value := petal_roundness if is_finite(petal_roundness) else 0.85
	return clampf(value, 0.0, 1.0)


func _safe_twist() -> float:
	var value := twist if is_finite(twist) else 0.5
	return clampf(value, 0.0, 1.5)


func _orientation_basis() -> Basis:
	var value := orientation_degrees
	if not _vector_is_finite(value):
		value = Vector3.ZERO
	return Basis.from_euler(value * (PI / 180.0))


## Builds the specs for the visible outer whorl. Layer 0 is the broad, low
## outer petal ring; higher layers become shorter, steeper and more central.
func _layer_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var r := _safe_radius()
	var cup := _safe_cup()
	var layer_total := _layer_count()
	var petal_total := _petal_count()
	var rng := RandomNumberGenerator.new()
	rng.seed = self.seed
	for layer in layer_total:
		var layer_f := float(layer) / maxf(float(layer_total - 1), 1.0)
		var layer_offset := (float(layer) * 0.5 + _safe_twist() * 0.15 * float(layer)) * TAU / float(petal_total)
		for petal in petal_total:
			var angle := layer_offset + TAU * float(petal) / float(petal_total)
			angle += rng.randf_range(-0.035, 0.035)
			var length_jitter := rng.randf_range(0.965, 1.035)
			var width_jitter := rng.randf_range(0.95, 1.05)
			var phase := rng.randf_range(0.0, TAU)
			var base_radius := r * (0.075 + 0.085 * layer_f) * length_jitter
			var reach := r * (0.90 - 0.54 * layer_f) * length_jitter
			var base_y := 0.0025 + cup * (0.015 + 0.12 * layer_f) + rng.randf_range(0.0, 0.0012)
			var tip_y := 0.0025 + cup * (0.78 + 0.55 * layer_f) + r * 0.008
			tip_y += rng.randf_range(-0.0015, 0.0015)
			specs.append({
				"angle": angle,
				"base_radius": base_radius,
				"reach": reach,
				"curl": 0.0,
				"base_y": base_y,
				"tip_y": maxf(tip_y, base_y + 0.002),
				# Broad overlapping rose petals, measured across the entire petal.
				"width": r * (1.18 - 0.65 * layer_f) * width_jitter,
				"thickness": maxf(r * 0.028, 0.0015),
				"cup": cup * (0.24 - 0.08 * layer_f),
				"arch": cup * (0.12 - 0.02 * layer_f),
				"twist_curl": _safe_twist() * 0.35,
				"phase": phase,
				"undulation": 0.055,
			})
	return specs


func _bud_petal_count() -> int:
	return 8


## A compact raised core plus two whorls of narrow petals that curl inward and
## upward over it. This is intentionally independent of the outer layer count so
## the centre reads as a bud rather than a hole.
func _append_bud(vertices: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray, uvs: PackedVector2Array) -> void:
	var r := _safe_radius()
	var cup := _safe_cup()
	# More whorls naturally mound the centre up a little, so changing `layers`
	# also changes the silhouette rather than only the triangle count.
	var stack_lift := maxf(float(_layer_count() - 1), 0.0) * 0.0008
	var core_radius := r * 0.085
	var core_base := 0.003 + cup * 0.10 + stack_lift
	var core_height := cup * 0.95 + r * 0.10
	_append_bud_core(vertices, normals, indices, colors, uvs, core_base, core_height, core_radius)

	var rng := RandomNumberGenerator.new()
	rng.seed = self.seed + 104729
	for ring in 2:
		var count := 5 if ring == 0 else 3
		var ring_f := float(ring)
		for petal in count:
			var angle := TAU * float(petal) / float(count) + 0.35 * _safe_twist() * (ring_f + 1.0)
			angle += rng.randf_range(-0.06, 0.06) + (0.7 if ring == 1 else 0.0)
			var base_radius := r * (0.05 - 0.015 * ring_f)
			var reach := r * (0.15 - 0.06 * ring_f) * rng.randf_range(0.94, 1.06)
			var curl := -r * (0.145 - 0.035 * ring_f) * rng.randf_range(0.94, 1.06)
			var phase := rng.randf_range(0.0, TAU)
			var base_y := 0.006 + cup * (0.22 + 0.10 * ring_f) + stack_lift
			var tip_y := 0.006 + cup * (1.25 + 0.23 * ring_f) + r * 0.03 + stack_lift
			tip_y += rng.randf_range(-0.001, 0.001)
			_append_petal(vertices, normals, indices, colors, uvs, {
				"angle": angle,
				"base_radius": base_radius,
				"reach": reach,
				"curl": curl,
				"base_y": base_y,
				"tip_y": maxf(tip_y, base_y + 0.004),
				"width": r * (0.16 - 0.05 * ring_f) * rng.randf_range(0.9, 1.08),
				"thickness": maxf(r * 0.026, 0.0014),
				"cup": cup * 0.05,
				"arch": cup * 0.06,
				"twist_curl": _safe_twist() * 0.95,
				"phase": phase,
				"undulation": 0.035,
			})


func _append_bud_core(vertices: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray, uvs: PackedVector2Array,
		base_y: float, height: float, max_radius: float) -> void:
	var start := vertices.size()
	for row in BUD_ROWS:
		var v := lerpf(0.08, 0.92, float(row) / float(BUD_ROWS - 1))
		var ring_radius := max_radius * pow(maxf(sin(PI * v), 0.0), 0.62)
		var y := base_y + height * v
		for side in BUD_RING_SIDES:
			var phi := TAU * float(side) / float(BUD_RING_SIDES)
			var point := Vector3(cos(phi) * ring_radius, y, sin(phi) * ring_radius)
			var normal := _bud_core_normal(v, phi, max_radius, height)
			vertices.append(point)
			normals.append(normal)
			colors.append(petal_color.srgb_to_linear())
			uvs.append(Vector2(float(side) / float(BUD_RING_SIDES), v))

	for row in BUD_ROWS - 1:
		for side in BUD_RING_SIDES:
			var a := start + row * BUD_RING_SIDES + side
			var b := start + (row + 1) * BUD_RING_SIDES + side
			var c := start + row * BUD_RING_SIDES + (side + 1) % BUD_RING_SIDES
			var d := start + (row + 1) * BUD_RING_SIDES + (side + 1) % BUD_RING_SIDES
			_append_oriented(indices, vertices, a, b, c, (normals[a] + normals[b] + normals[c]).normalized())
			_append_oriented(indices, vertices, b, d, c, (normals[b] + normals[d] + normals[c]).normalized())

	var bottom := vertices.size()
	vertices.append(Vector3(0.0, base_y, 0.0))
	normals.append(Vector3.DOWN)
	colors.append(petal_color.srgb_to_linear())
	uvs.append(Vector2(0.5, 0.0))
	var top := vertices.size()
	vertices.append(Vector3(0.0, base_y + height, 0.0))
	normals.append(Vector3.UP)
	colors.append(petal_color.srgb_to_linear())
	uvs.append(Vector2(0.5, 1.0))
	for side in BUD_RING_SIDES:
		var low_a := start + side
		var low_b := start + (side + 1) % BUD_RING_SIDES
		_append_oriented(indices, vertices, bottom, low_b, low_a, Vector3.DOWN)
		var high_base := start + (BUD_ROWS - 1) * BUD_RING_SIDES
		var high_a := high_base + side
		var high_b := high_base + (side + 1) % BUD_RING_SIDES
		_append_oriented(indices, vertices, top, high_a, high_b, Vector3.UP)


func _bud_core_normal(v: float, phi: float, max_radius: float, height: float) -> Vector3:
	var exponent := 0.62
	var sin_pi := maxf(sin(PI * v), EPSILON)
	var ring_radius := max_radius * pow(sin_pi, exponent)
	var dr := max_radius * exponent * pow(sin_pi, exponent - 1.0) * PI * cos(PI * v)
	var dp_dv := Vector3(dr * cos(phi), height, dr * sin(phi))
	var dp_dphi := Vector3(-ring_radius * sin(phi), 0.0, ring_radius * cos(phi))
	var normal := dp_dv.cross(dp_dphi)
	if normal.length_squared() <= EPSILON:
		normal = Vector3(cos(phi), 0.0, sin(phi))
	return normal.normalized()


## One closed, thick petal. The centreline is a radial/vertical curve; each
## cross-section is a flattened, edge-cupped lens. A root fan and a tip fan close
## the solid.
func _append_petal(vertices: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, colors: PackedColorArray, uvs: PackedVector2Array,
		spec: Dictionary) -> void:
	var start := vertices.size()
	for row in PETAL_ROWS:
		var row_f := float(row) / float(PETAL_ROWS - 1)
		var t := lerpf(PETAL_T_START, PETAL_T_END, row_f)
		for side in PETAL_RING_SIDES:
			var phi := TAU * float(side) / float(PETAL_RING_SIDES)
			vertices.append(_petal_point(spec, t, phi))
			normals.append(_petal_normal(spec, t, phi))
			colors.append(petal_color.srgb_to_linear())
			uvs.append(Vector2(float(side) / float(PETAL_RING_SIDES), row_f))

	for row in PETAL_ROWS - 1:
		for side in PETAL_RING_SIDES:
			var a := start + row * PETAL_RING_SIDES + side
			var b := start + (row + 1) * PETAL_RING_SIDES + side
			var c := start + row * PETAL_RING_SIDES + (side + 1) % PETAL_RING_SIDES
			var d := start + (row + 1) * PETAL_RING_SIDES + (side + 1) % PETAL_RING_SIDES
			_append_oriented(indices, vertices, a, b, c, (normals[a] + normals[b] + normals[c]).normalized())
			_append_oriented(indices, vertices, b, d, c, (normals[b] + normals[d] + normals[c]).normalized())

	var root_center := vertices.size()
	var root_tangent := _petal_tangent(spec, 0.0)
	vertices.append(_petal_center(spec, 0.0))
	normals.append(-root_tangent)
	colors.append(petal_color.srgb_to_linear())
	uvs.append(Vector2(0.5, 0.0))
	for side in PETAL_RING_SIDES:
		var a := start + side
		var b := start + (side + 1) % PETAL_RING_SIDES
		_append_oriented(indices, vertices, root_center, a, b, -root_tangent)

	var tip_center := vertices.size()
	var tip_tangent := _petal_tangent(spec, 1.0)
	vertices.append(_petal_center(spec, 1.0))
	normals.append(tip_tangent)
	colors.append(petal_color.srgb_to_linear())
	uvs.append(Vector2(0.5, 1.0))
	var last_base := start + (PETAL_ROWS - 1) * PETAL_RING_SIDES
	for side in PETAL_RING_SIDES:
		var a := last_base + side
		var b := last_base + (side + 1) % PETAL_RING_SIDES
		_append_oriented(indices, vertices, tip_center, a, b, tip_tangent)


func _petal_center(spec: Dictionary, t: float) -> Vector3:
	var clamped_t := clampf(t, 0.0, 1.0)
	var theta := float(spec["angle"]) + float(spec["twist_curl"]) * pow(clamped_t, 1.35)
	# Ease into the outer rim so the closed petal tip describes a rounded lobe.
	var radial_distance := float(spec["base_radius"]) + float(spec["reach"]) * sin(clamped_t*PI*.5)
	radial_distance += float(spec["curl"]) * clamped_t * clamped_t
	var y := float(spec["base_y"]) + (float(spec["tip_y"]) - float(spec["base_y"])) * clamped_t
	y += float(spec["arch"]) * sin(PI * clamped_t)
	return Vector3(cos(theta) * radial_distance, y, sin(theta) * radial_distance)


func _petal_tangent(spec: Dictionary, t: float) -> Vector3:
	var before := _petal_center(spec, maxf(t - 0.002, 0.0))
	var after := _petal_center(spec, minf(t + 0.002, 1.0))
	var tangent := after - before
	if tangent.length_squared() <= EPSILON:
		return Vector3.UP
	return tangent.normalized()


func _petal_point(spec: Dictionary, t: float, phi: float) -> Vector3:
	var clamped_t := clampf(t, 0.0, 1.0)
	var center := _petal_center(spec, clamped_t)
	var tangent := _petal_tangent(spec, clamped_t)
	var theta := float(spec["angle"]) + float(spec["twist_curl"]) * pow(clamped_t, 1.35)
	var side := Vector3(-sin(theta), 0.0, cos(theta))
	side -= tangent * side.dot(tangent)
	if side.length_squared() <= EPSILON:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(tangent)
	if up.dot(Vector3.UP) < 0.0:
		up = -up
	if up.length_squared() <= EPSILON:
		up = Vector3.UP
	up = up.normalized()

	# A low-amplitude, seed-driven ripple keeps the rims from reading as rigid
	# extruded cut-outs while preserving the broad petal silhouette.
	var ripple := float(spec["undulation"]) * sin(clamped_t * PI * 2.2 + float(spec["phase"]))
	ripple *= clamped_t * (1.0 - clamped_t) * 4.0
	var width_factor := _petal_width_factor(clamped_t) * (1.0 + ripple)
	var half_width := float(spec["width"]) * width_factor * 0.5
	var cup_shift := float(spec["cup"]) * width_factor * cos(phi) * cos(phi)
	var offset := side * (cos(phi) * half_width)
	offset += up * (sin(phi) * float(spec["thickness"]) * 0.5 + cup_shift)
	return center + offset


func _petal_normal(spec: Dictionary, t: float, phi: float) -> Vector3:
	var dt := 0.0012
	var dp := 0.003
	var before_t := maxf(t - dt, 0.0)
	var after_t := minf(t + dt, 1.0)
	var along := _petal_point(spec, after_t, phi) - _petal_point(spec, before_t, phi)
	var across := _petal_point(spec, t, phi + dp) - _petal_point(spec, t, phi - dp)
	var normal := along.cross(across)
	var center := _petal_center(spec, t)
	var offset := _petal_point(spec, t, phi) - center
	if normal.length_squared() > EPSILON:
		normal = normal.normalized()
		if offset.length_squared() > EPSILON and normal.dot(offset) < 0.0:
			normal = -normal
		return normal
	if offset.length_squared() > EPSILON:
		return offset.normalized()
	return Vector3.UP


## Broad, full middle with a rounded tip. Lower roundness raises the exponent
## and gives a narrower, more tapered petal; the default is deliberately rounded.
func _petal_width_factor(t: float) -> float:
	var clamped_t := clampf(t, 0.0, 1.0)
	var roundness := _safe_roundness()
	var exponent := lerpf(1.02, 0.55, roundness)
	var bell := pow(maxf(sin(PI * clamped_t), 0.0), exponent)
	var root := smoothstep(0.0, 0.20, clamped_t)
	return bell * lerpf(0.20, 1.0, root)


## Appends a triangle in Godot's clockwise front-face order. For a triangle
## (a, b, c), (c - a) x (b - a) points along the visible front normal.
func _append_oriented(indices: PackedInt32Array, vertices: PackedVector3Array,
		a: int, b: int, c: int, outward: Vector3) -> void:
	var winding_normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
	if winding_normal.dot(outward) >= 0.0:
		indices.append(a)
		indices.append(b)
		indices.append(c)
	else:
		indices.append(a)
		indices.append(c)
		indices.append(b)

func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property["name"]) == property_name:
			return true
	return false

func _vector_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
