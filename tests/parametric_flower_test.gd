extends SceneTree

## Focused acceptance test for the new parametric headflower.
## Preloads the script directly so it does not depend on the editor's global
## class cache.
##
## Run with:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script tests/parametric_flower_test.gd

const Flower = preload("res://components/parametric_flower.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)


func _aabb(vertices: PackedVector3Array) -> AABB:
	var box := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		box = box.expand(vertex)
	return box


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _check_geometry(data: Dictionary, label: String) -> void:
	for key in ["vertices", "normals", "indices", "colors", "uv", "arm_weights", "slot"]:
		_check(data.has(key), "%s missing key %s" % [label, key])
	if not data.has("vertices"):
		return
	var vertices: PackedVector3Array = data["vertices"]
	var normals: PackedVector3Array = data["normals"]
	var indices: PackedInt32Array = data["indices"]
	var colors: PackedColorArray = data["colors"]
	var uvs: PackedVector2Array = data["uv"]
	_check(vertices.size() > 0, "%s has no vertices" % label)
	_check(normals.size() == vertices.size(), "%s normal count mismatch" % label)
	_check(colors.size() == vertices.size(), "%s color count mismatch" % label)
	_check(uvs.size() == vertices.size(), "%s uv count mismatch" % label)
	_check(indices.size() % 3 == 0, "%s indices are not triangles" % label)
	_check(data["arm_weights"].is_empty(), "%s arm_weights must be empty" % label)
	_check(String(data["slot"]) == "headwear", "%s slot is not headwear" % label)

	var vertex_errors := 0
	for vertex in vertices:
		if not _finite_vector(vertex):
			vertex_errors += 1
	_check(vertex_errors == 0, "%s has non-finite vertices" % label)

	var normal_errors := 0
	for normal in normals:
		if not _finite_vector(normal) or absf(normal.length() - 1.0) > 0.001:
			normal_errors += 1
	_check(normal_errors == 0, "%s normals are not finite unit vectors" % label)

	var uv_errors := 0
	for uv in uvs:
		if not is_finite(uv.x) or not is_finite(uv.y):
			uv_errors += 1
	_check(uv_errors == 0, "%s has non-finite uvs" % label)

	var index_errors := 0
	for index in indices:
		if index < 0 or index >= vertices.size():
			index_errors += 1
	_check(index_errors == 0, "%s has out-of-range indices" % label)

	# Godot front faces are clockwise: (c-a) x (b-a) points out of the surface.
	var winding_errors := 0
	for triangle in range(0, indices.size(), 3):
		var a := indices[triangle]
		var b := indices[triangle + 1]
		var c := indices[triangle + 2]
		var winding_normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		if winding_normal.length_squared() <= 0.000000000001:
			continue
		var averaged_normal := (normals[a] + normals[b] + normals[c]).normalized()
		# A loose threshold avoids flagging the tightly curved root/tip fans
		# where a triangle normal legitimately differs from the averaged smooth
		# normal, while still catching any globally reversed surface.
		if winding_normal.normalized().dot(averaged_normal) < -0.2:
			winding_errors += 1
	_check(winding_errors == 0, "%s has %d triangles wound against their normals" % [label, winding_errors])


func _run() -> void:
	var flower = Flower.new()
	_check(flower is Resource, "ParametricFlower must extend Resource")
	_check(flower.petal_color.is_equal_approx(Color("e83547")), "default petal colour is not deep scarlet")
	_check(is_equal_approx(flower.radius, 0.09), "default radius changed")
	_check(flower.layers == 4, "default layer count changed")
	_check(flower.petals_per_layer == 7, "default petals-per-layer changed")
	_check(is_equal_approx(flower.cup_depth, 0.045), "default cup depth changed")
	_check(is_equal_approx(flower.petal_roundness, 0.85), "default roundness changed")
	_check(is_equal_approx(flower.twist, 0.5), "default twist changed")
	_check(flower.orientation_degrees == Vector3.ZERO, "default orientation changed")
	_check(typeof(flower.seed) == TYPE_INT, "seed export must be an int")

	var geometry: Dictionary = flower.build_geometry()
	_check_geometry(geometry, "default")
	var vertices: PackedVector3Array = geometry["vertices"]
	var indices: PackedInt32Array = geometry["indices"]
	var box := _aabb(vertices)

	# Upward opening: a meaningful Y volume, a centred raised bud, and a radial
	# footprint rather than a forward-facing flat disk.
	_check(box.size.y > 0.045, "flower is too flat to open upward: %s" % box.size)
	_check(box.size.x > flower.radius * 1.2, "flower is narrow along X: %s" % box.size)
	_check(box.size.z > flower.radius * 1.2, "flower is narrow along Z: %s" % box.size)
	_check(box.position.y > -0.005, "flower extends implausibly far below its base: %s" % box.position)
	var apex := Vector3.ZERO
	for vertex in vertices:
		if vertex.y > apex.y:
			apex = vertex
	var apex_radial := Vector2(apex.x, apex.z).length()
	_check(apex.y > 0.05, "centre bud does not rise above the base")
	_check(apex_radial < flower.radius * 0.25, "highest point is not the centre bud")
	var max_radial := 0.0
	for vertex in vertices:
		max_radial = maxf(max_radial, Vector2(vertex.x, vertex.z).length())
	_check(max_radial <= flower.radius * 1.15, "flower exceeds its requested radius")
	_check(max_radial >= flower.radius * 0.65, "flower does not reach its requested radius")
	_check(geometry["petal_count"] == 4 * 7 + 8, "outer petals and centre bud are not all present")
	_check(indices.size() / 3 > 2000, "geometry is suspiciously low-resolution for layered petals")

	var first_color: Color = geometry["colors"][0]
	_check(first_color.is_equal_approx(flower.petal_color.srgb_to_linear()), "vertex colours do not carry the petal colour")

	# Same seed and parameters produce byte-identical mesh data.
	var repeat = Flower.new()
	var repeated: Dictionary = repeat.build_geometry()
	_check(repeated["vertices"] == geometry["vertices"], "flower geometry is not deterministic")
	_check(repeated["normals"] == geometry["normals"], "flower normals are not deterministic")
	_check(repeated["indices"] == geometry["indices"], "flower indices are not deterministic")
	_check(repeated["colors"] == geometry["colors"], "flower colours are not deterministic")

	var other_seed = Flower.new()
	other_seed.seed = flower.seed + 1
	var other_geometry: Dictionary = other_seed.build_geometry()
	_check_geometry(other_geometry, "other seed")
	_check(other_geometry["vertices"] != geometry["vertices"], "seed does not affect geometry")

	# Radius changes the actual footprint.
	var larger = Flower.new()
	larger.radius = 0.12
	var larger_geometry: Dictionary = larger.build_geometry()
	_check_geometry(larger_geometry, "larger radius")
	var larger_box := _aabb(larger_geometry["vertices"])
	_check(larger_box.size.x > box.size.x * 1.15, "radius does not change the X footprint")
	_check(larger_box.size.z > box.size.z * 1.15, "radius does not change the Z footprint")

	# Cup depth changes the real vertical curvature and silhouette.
	var deeper = Flower.new()
	deeper.cup_depth = 0.08
	var deeper_geometry: Dictionary = deeper.build_geometry()
	_check_geometry(deeper_geometry, "deeper cup")
	_check(deeper_geometry["vertices"] != geometry["vertices"], "cup depth does not affect geometry")
	_check(_aabb(deeper_geometry["vertices"]).size.y > box.size.y + 0.01, "cup depth does not deepen the flower")

	# Layer and petal counts add real petals.
	var layered = Flower.new()
	layered.layers = 6
	var layered_geometry: Dictionary = layered.build_geometry()
	_check_geometry(layered_geometry, "six layers")
	_check(layered_geometry["petal_count"] > geometry["petal_count"], "layers do not add petals")
	_check(layered_geometry["vertices"].size() > geometry["vertices"].size(), "layers do not add geometry")
	_check(_aabb(layered_geometry["vertices"]) != box, "layers do not change the flower silhouette")

	var denser = Flower.new()
	denser.petals_per_layer = 9
	var denser_geometry: Dictionary = denser.build_geometry()
	_check_geometry(denser_geometry, "nine petals")
	_check(denser_geometry["petal_count"] > geometry["petal_count"], "petals_per_layer does not add petals")
	_check(denser_geometry["vertices"].size() > geometry["vertices"].size(), "petals_per_layer does not add geometry")

	# Roundness and twist are real shape parameters, not metadata.
	var tapered = Flower.new()
	tapered.petal_roundness = 0.15
	var tapered_geometry: Dictionary = tapered.build_geometry()
	_check_geometry(tapered_geometry, "tapered petals")
	_check(tapered_geometry["vertices"] != geometry["vertices"], "petal_roundness does not affect geometry")

	var twisted = Flower.new()
	twisted.twist = 1.2
	var twisted_geometry: Dictionary = twisted.build_geometry()
	_check_geometry(twisted_geometry, "twisted petals")
	_check(twisted_geometry["vertices"] != geometry["vertices"], "twist does not affect geometry")

	# Orientation is baked into vertices and normals.
	var turned = Flower.new()
	turned.orientation_degrees = Vector3(90, 0, 0)
	var turned_geometry: Dictionary = turned.build_geometry()
	_check_geometry(turned_geometry, "rotated")
	_check(turned_geometry["vertices"] != geometry["vertices"], "orientation_degrees does not affect geometry")
	_check(_aabb(turned_geometry["vertices"]) != box, "orientation_degrees does not rotate bounds")

	# Material contract: matte cloth, white base and vertex-colour albedo.
	var mat: StandardMaterial3D = flower.material()
	_check(mat != null, "material() did not return a StandardMaterial3D")
	_check(is_equal_approx(mat.roughness, 0.45), "cloth roughness is not 0.45")
	_check(mat.vertex_color_use_as_albedo, "material does not use vertex colours as albedo")
	_check(mat.albedo_color.is_equal_approx(Color.WHITE), "material base colour must be white")
	_check(is_equal_approx(mat.metallic, 0.0), "cloth material must not be metallic")
	_check(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "small double-sided cloth faces must not be culled")

	# Parameter schema is JSON-safe and names the versioned contract.
	var params: Dictionary = flower.parameters()
	_check(params.get("schema", "") == "ww-parametric-flower-v1", "parameter schema changed")
	_check(params.get("petal_color", "") == flower.petal_color.to_html(), "parameters lost the petal colour")
	_check(params.get("layers", 0) == flower.layers, "parameters lost the layer count")
	_check(params.get("petals_per_layer", 0) == flower.petals_per_layer, "parameters lost petals_per_layer")
	_check(params.get("seed", 0) == flower.seed, "parameters lost the seed")
	_check(params.get("orientation_degrees") is Array, "orientation is not JSON-compatible")
	var encoded := JSON.stringify(params)
	_check(not encoded.is_empty(), "parameters could not be JSON-encoded")
	_check(JSON.parse_string(encoded) is Dictionary, "parameters did not survive a JSON round-trip")

	print("PARAMETRIC_FLOWER_TEST checks=", checks, " failures=", failures.size(),
		" vertices=", vertices.size(), " triangles=", indices.size() / 3,
		" bounds=", box.size)
	quit(0 if failures.is_empty() else 1)
