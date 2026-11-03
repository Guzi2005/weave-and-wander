extends SceneTree

## Headless acceptance test for the versioned pleated-skirt contract.
##
## Run with:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script tests/pleated_skirt_test.gd --log-file captures/pleated_skirt_test.log

const Design = preload("res://scripts/pleated_skirt_design.gd")
const Skirt = preload("res://components/pleated_skirt.gd")
const Dynamics = preload("res://scripts/pleated_skirt_dynamics.gd")
const VolumeDollScript = preload("res://scripts/volume_doll.gd")

const TEST_DIR := "res://.appdata"
const ROUNDTRIP_JSON := TEST_DIR + "/pleated_skirt_roundtrip.json"
const API_JSON := TEST_DIR + "/pleated_skirt_api.json"
const BAD_JSON := TEST_DIR + "/pleated_skirt_bad.json"
const EMPTY_JSON := TEST_DIR + "/pleated_skirt_empty.json"
const OVERSIZE_JSON := TEST_DIR + "/pleated_skirt_oversize.json"
const SIBLING_PNG := TEST_DIR + "/pleated_skirt_roundtrip.png"

var failures: Array[String] = []
var checks := 0
var _skirt = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	_test_validation()
	_test_roundtrip()
	_test_geometry()
	_test_parameters()
	_test_materials_and_texture()
	_test_public_api()
	_test_editor_export()
	_test_preview_scene()
	_test_toolkit_dynamics_and_doll_binding()
	print("PLEATED_SKIRT_CHECK checks=", checks, " failures=", failures.size(),
		" templates=", Design.TEMPLATE_IDS.size(), " generated_texture=true")
	_cleanup()
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)


func _test_validation() -> void:
	for template_id in Design.TEMPLATE_IDS:
		var template: Dictionary = Design.default_design(template_id)
		_check(not template.is_empty(), "Default template was not constructed: " + template_id)
		_check(Design.validate_design(template).is_empty(), "Default template is invalid: " + template_id)
		_check(template.get("template_id", "") == template_id, "Default template id changed: " + template_id)

	var base: Dictionary = Design.default_design("plain")
	_skirt = Skirt.new()
	root.add_child(_skirt)
	_check(not _skirt.design.is_empty(), "Scene-ready component did not build its default design.")
	_check(_skirt.configure(base) == OK, "Valid default design was rejected by configure().")
	var before_id := String(_skirt.design["design_id"])

	for silhouette in ["relaxed", "a_line", "bell", "trumpet"]:
		var shaped := base.duplicate(true)
		shaped["silhouette"] = silhouette
		var shape_result := Design.inspect_design(shaped)
		_check(shape_result["ok"], "Silhouette rejected: " + silhouette)
		if shape_result["ok"]:
			_check(shape_result["design"]["silhouette"] == silhouette, "Silhouette lost")
	_expect_invalid("silhouette invalid", _mutate(base, ["silhouette"], "invalid"))
	_expect_invalid("silhouette wrong type", _mutate(base, ["silhouette"], 2))
	var configured := base.duplicate(true)
	configured["shape"] = {
		"relaxed": {"fullness": 0.5, "taper": 0.5}, "a_line": {"flare": 0.5, "curve": 0.5},
		"bell": {"volume": 0.5, "peak": 0.6}, "trumpet": {"fit": 0.5, "flare_start": 0.5, "flare": 0.6},
		"hem": {"mode": "wide", "ratio": 0.7},
	}
	for hem_mode in ["body", "circle", "wide", "deep"]:
		configured["shape"]["hem"]["mode"] = hem_mode
		var encoded := Design.encode_design(configured)
		_check(encoded["ok"], "Shape settings rejected")
		if encoded["ok"]:
			var decoded := Design.inspect_json_text(encoded["text"])
			_check(decoded["ok"] and decoded["design"]["shape"] == configured["shape"], "Shape settings lost on roundtrip")
	_check(not Design.inspect_design(base)["design"].has("shape"), "Legacy design gained shape settings")
	_expect_invalid("shape wrong type", _mutate(base, ["shape"], null))
	_expect_invalid("shape unknown field", _mutate(configured, ["shape", "extra"], 1))
	_expect_invalid("shape missing profile", _drop(configured, ["shape", "bell"]))
	_expect_invalid("shape missing parameter", _drop(configured, ["shape", "trumpet", "flare_start"]))
	_expect_invalid("shape unknown parameter", _mutate(configured, ["shape", "a_line", "wrong"], 1))
	_expect_invalid("shape invalid number", _mutate(configured, ["shape", "relaxed", "fullness"], "0.5"))
	_expect_invalid("shape out of range", _mutate(configured, ["shape", "bell", "peak"], 1))
	_expect_invalid("hem invalid mode", _mutate(configured, ["shape", "hem", "mode"], "other"))
	_expect_invalid("hem invalid ratio", _mutate(configured, ["shape", "hem", "ratio"], 0.1))
	_expect_invalid("hem missing ratio", _drop(configured, ["shape", "hem", "ratio"]))
	configured["shape"]["hem"] = {"mode": "custom", "ratio": 0.53, "angle_deg": 37.0}
	var custom_roundtrip := Design.inspect_json_text(Design.encode_design(configured)["text"])
	_check(custom_roundtrip["ok"] and custom_roundtrip["design"]["shape"] == configured["shape"], "Rotated hem lost on roundtrip")
	_expect_invalid("hem angle out of range", _mutate(configured, ["shape", "hem", "angle_deg"], 181))
	_expect_invalid("hem angle wrong type", _mutate(configured, ["shape", "hem", "angle_deg"], "37"))
	var draped := base.duplicate(true)
	draped["drape"] = {"mode":"manual","weight":0.8,"bending":0.2,"opening":0.6}
	var inspected := Design.inspect_design(draped)
	_check(inspected["ok"], "Manual drape rejected")
	if inspected["ok"]:
		_check(inspected["design"]["drape"] == draped["drape"], "Manual drape lost during normalization")
	_expect_invalid("drape wrong type", _mutate(base, ["drape"], null))
	_expect_invalid("drape out of range", _mutate(draped, ["drape", "weight"], 2))
	_expect_invalid("drape bad mode", _mutate(draped, ["drape", "mode"], "bad"))
	_expect_invalid("drape missing field", _drop(draped, ["drape", "opening"]))
	_expect_invalid("drape unknown field", _mutate(draped, ["drape", "extra"], 1))
	var browser_file := "res://captures/skirt_revision/drape.json"
	if FileAccess.file_exists(browser_file):
		var browser: Variant = JSON.parse_string(FileAccess.get_file_as_string(browser_file))
		_check(Design.inspect_design(browser)["ok"], "Browser export with drape was rejected")

	_expect_invalid("empty dictionary", {})
	_expect_invalid("wrong schema", _mutate(base, ["schema"], "other-skirt"))
	_expect_invalid("wrong version", _mutate(base, ["version"], 2))
	_expect_invalid("string version", _mutate(base, ["version"], "1"))
	_expect_invalid("missing identity", _drop(base, ["collection_id"]))
	_expect_invalid("numeric identity", _mutate(base, ["design_id"], 42))
	_expect_invalid("empty identity", _mutate(base, ["item_id"], ""))
	_expect_invalid("unknown top-level field", _mutate(base, ["extra"], true))
	_expect_invalid("invalid template", _mutate(base, ["template_id"], "unknown"))
	_expect_invalid("invalid canvas view", _mutate(base, ["canvas_view"], "top"))
	_expect_invalid("missing source", _drop(base, ["source"]))
	_expect_invalid("source wrong type", _mutate(base, ["source"], "note"))
	_expect_invalid("source note wrong type", _mutate(base, ["source", "note"], 4))
	_expect_invalid("references wrong type", _mutate(base, ["source", "references"], {}))
	_expect_invalid("reference unknown field", _mutate(base, ["source", "references"],
		[{"title": "study", "path": "pleated_skirt_photo.jpg", "extra": 1}]))

	_expect_invalid("missing parameter", _drop(base, ["parameters", "length_cm"]))
	_expect_invalid("length too short", _mutate(base, ["parameters", "length_cm"], 39.9))
	_expect_invalid("length too long", _mutate(base, ["parameters", "length_cm"], 120.1))
	_expect_invalid("waist too narrow", _mutate(base, ["parameters", "waist_cm"], 49.9))
	_expect_invalid("hem too narrow", _mutate(base, ["parameters", "hem_cm"], 99.9))
	_expect_invalid("pleat count too low", _mutate(base, ["parameters", "pleat_count"], 15))
	_expect_invalid("fractional pleat count", _mutate(base, ["parameters", "pleat_count"], 32.5))
	_expect_invalid("pleat depth too large", _mutate(base, ["parameters", "pleat_depth_cm"], 4.1))
	_expect_invalid("sharpness below zero", _mutate(base, ["parameters", "sharpness"], -0.01))
	_expect_invalid("thickness too large", _mutate(base, ["parameters", "thickness_mm"], 3.01))
	_expect_invalid("parameter wrong type", _mutate(base, ["parameters", "waist_cm"], "70"))
	_expect_invalid("non-finite parameter", _mutate(base, ["parameters", "length_cm"], NAN))
	_expect_invalid("infinite parameter", _mutate(base, ["parameters", "hem_cm"], INF))
	_expect_invalid("invalid fabric", _mutate(base, ["parameters", "fabric"], "nylon"))
	_expect_invalid("short color", _mutate(base, ["parameters", "base_color"], "#FFF"))
	_expect_invalid("non-hex color", _mutate(base, ["parameters", "base_color"], "#GGGGGG"))

	_expect_invalid("bands wrong type", _mutate(base, ["bands"], {}))
	_expect_invalid("too many bands", _mutate(base, ["bands"], _many_bands(33)))
	_expect_invalid("band too short", _mutate(base, ["bands"],
		[_band("short", 0.4, 0.404, "#112233", "solid", 4)]))
	_expect_invalid("band reversed", _mutate(base, ["bands"],
		[_band("reversed", 0.8, 0.7, "#112233", "solid", 4)]))
	_expect_invalid("band bad pattern", _mutate(base, ["bands"],
		[_band("pattern", 0.1, 0.2, "#112233", "stripes", 4)]))
	_expect_invalid("band bad repeat", _mutate(base, ["bands"],
		[_band("repeat", 0.1, 0.2, "#112233", "solid", 3)]))
	_expect_invalid("band unknown field", _mutate(base, ["bands"],
		[{"id": "extra", "start": 0.1, "end": 0.2, "color": "#112233", "pattern": "solid", "repeat": 4, "extra": true}]))

	_expect_invalid("patches wrong type", _mutate(base, ["patches"], "patch"))
	_expect_invalid("too many patches", _mutate(base, ["patches"], _many_patches(65)))
	_expect_invalid("patch zero width", _mutate(base, ["patches"],
		[_patch("zero", 0.2, 0.2, 0.1, 0.2, "#112233", "solid", 4)]))
	_expect_invalid("patch outside UV", _mutate(base, ["patches"],
		[_patch("outside", 0.2, 1.2, 0.1, 0.2, "#112233", "solid", 4)]))
	_expect_invalid("strokes wrong type", _mutate(base, ["strokes"], {}))
	_expect_invalid("too many strokes", _mutate(base, ["strokes"], _many_strokes(257)))
	_expect_invalid("stroke too narrow", _mutate(base, ["strokes"],
		[_stroke("narrow", "#112233", 0.0005, [[0.0, 0.0], [1.0, 0.0]])]))
	_check(Design.validate_design(_mutate(base, ["strokes"], [_stroke("one", "#112233", 0.01, [[0.5, 0.5]])])).is_empty(), "A single brush dot must be valid.")
	_check(Design.validate_design(_mutate(base, ["strokes"], [_stroke("empty", "#112233", 0.01, [])])).is_empty(), "An empty vector stroke must round-trip.")
	var duplicate: Dictionary = base.duplicate(true)
	duplicate["bands"] = [_band("same", 0.1, 0.2, "#112233", "solid", 4)]
	duplicate["strokes"] = [_stroke("same", "#112233", 0.01, [[0.5, 0.5]])]
	_expect_invalid("duplicate decoration ID", duplicate)
	_expect_invalid("stroke malformed point", _mutate(base, ["strokes"],
		[_stroke("bad", "#112233", 0.01, [[0.5, 0.5, 0.5], [0.6, 0.6]])]))
	_expect_invalid("stroke outside UV", _mutate(base, ["strokes"],
		[_stroke("outside", "#112233", 0.01, [[-0.1, 0.5], [0.6, 0.6]])]))
	var too_many_points: Array = []
	for index in 40001:
		too_many_points.append([float(index % 101) / 100.0, float(index % 99) / 100.0])
	_expect_invalid("stroke point budget", _mutate(base, ["strokes"],
		[_stroke("budget", "#112233", 0.01, too_many_points)]))
	_expect_invalid("pattern_uv origin", _mutate(base, ["pattern_uv", "origin"], "hem"))
	_expect_invalid("pattern_uv seam", _mutate(base, ["pattern_uv", "seam"], "front"))

	_check(_skirt.design["design_id"] == before_id, "Rejected configuration replaced the active design.")
	_check(not _skirt.last_error.is_empty(), "Rejected configuration did not expose last_error.")
	_check(_skirt.last_error_code != OK, "Rejected configuration did not expose a non-OK error code.")
	_check(_skirt.configure(base) == OK, "Component did not recover after rejected configurations.")


func _test_roundtrip() -> void:
	var design: Dictionary = Design.default_design("mosuo_reference")
	design["design_id"] = "design_roundtrip_001"
	design["item_id"] = "item_roundtrip_skirt"
	design["component_id"] = "component_roundtrip_skirt"
	design["collection_id"] = "collection_roundtrip_study"
	design["canvas_view"] = "ring"
	design["source"]["note"] = "Round-trip note kept verbatim: 蓝 / indigo stripes."
	design["source"]["references"] = [
		{"title": "local reference photo", "path": "references/pleated_skirt_roundtrip.jpg"},
	]
	design["strokes"].append(_stroke("roundtrip_diagonal", "#E9D9B8", 0.012,
		[[0.02, 0.08], [0.18, 0.22], [0.35, 0.19], [0.51, 0.4], [0.79, 0.38], [0.98, 0.55]]))

	var source := Skirt.new()
	root.add_child(source)
	_check(source.configure(design) == OK, "Round-trip design was rejected by configure().")
	var export_error = source.export_design(ROUNDTRIP_JSON)
	_check(export_error == OK, "export_design() failed: " + error_string(export_error))
	_check(FileAccess.file_exists(ROUNDTRIP_JSON), "export_design() did not create the JSON file.")

	var loaded := Skirt.new()
	root.add_child(loaded)
	var load_error = loaded.load_design(ROUNDTRIP_JSON)
	_check(load_error == OK, "load_design() failed: " + error_string(load_error))
	_check(loaded.design_path == ROUNDTRIP_JSON, "load_design() did not expose design_path.")
	_check(loaded.last_error.is_empty(), "Successful load left last_error populated.")
	for key in ["design_id", "item_id", "component_id", "collection_id", "template_id",
			"canvas_view", "source", "parameters", "bands", "patches", "strokes", "pattern_uv"]:
		_check(JSON.stringify(loaded.design[key], "", true) == JSON.stringify(design[key], "", true),
			"Round-trip changed field: " + key)
	_check(loaded.design["source"]["references"].size() == 1, "Round-trip lost source references.")
	_check(loaded.design["strokes"].size() == design["strokes"].size(), "Round-trip lost strokes.")
	_check(loaded.design["strokes"][-1]["points"].size() == 6, "Round-trip lost stroke points.")

	var encoded := Design.encode_design(loaded.design)
	_check(encoded["ok"], "encode_design() rejected a loaded design.")
	# JSON numbers parse as floats; the schema restores integer fields before comparison.
	_check(Design.inspect_design(JSON.parse_string(String(encoded["text"])))["design"] == design,
		"Exported JSON does not round-trip through JSON.parse_string().")

	# The text importer must preserve the same identities, source and strokes.
	var text_result := Design.inspect_json_text(String(encoded["text"]))
	_check(text_result["ok"], "inspect_json_text() rejected the exported text.")
	_check(text_result["design"]["design_id"] == design["design_id"], "Text import rebuilt design_id.")
	_check(text_result["design"]["source"]["note"] == design["source"]["note"], "Text import changed source note.")
	_check(JSON.stringify(text_result["design"]["strokes"], "", true)
		== JSON.stringify(design["strokes"], "", true), "Text import changed stroke vectors.")

	var before_id := String(loaded.design["design_id"])
	_check(loaded.configure({}) != OK, "Malformed configure() unexpectedly succeeded.")
	_check(loaded.design["design_id"] == before_id, "Malformed configure() replaced the loaded design.")


func _test_geometry() -> void:
	var design: Dictionary = Design.default_design("plain")
	_check(_skirt.configure(design) == OK, "Geometry fixture was rejected.")
	var arrays := _arrays(_skirt)
	var vertices: PackedVector3Array = arrays["vertices"]
	var normals: PackedVector3Array = arrays["normals"]
	var uvs: PackedVector2Array = arrays["uvs"]
	var indices: PackedInt32Array = arrays["indices"]
	_check(vertices.size() > 0, "Mesh is empty.")
	_check(indices.size() > 0, "Mesh has no triangles.")
	_check(indices.size() % 3 == 0, "Mesh index count is not triangular.")

	var finite_vertices := true
	var finite_normals := true
	var finite_uvs := true
	var valid_uvs := true
	for index in vertices.size():
		if not _finite_vector(vertices[index]):
			finite_vertices = false
		if not _finite_vector(normals[index]) or normals[index].length_squared() < 0.5:
			finite_normals = false
		if not is_finite(uvs[index].x) or not is_finite(uvs[index].y):
			finite_uvs = false
		if uvs[index].x < -0.000001 or uvs[index].x > 1.000001 or uvs[index].y < -0.000001 or uvs[index].y > 1.000001:
			valid_uvs = false
	_check(finite_vertices, "Mesh contains non-finite vertices.")
	_check(finite_normals, "Mesh contains non-finite or zero-length normals.")
	_check(finite_uvs, "Mesh contains non-finite UVs.")
	_check(valid_uvs, "Mesh UVs escaped [0, 1].")

	var valid_indices := true
	for index in indices.size():
		if indices[index] < 0 or indices[index] >= vertices.size():
			valid_indices = false
	_check(valid_indices, "Mesh index buffer references an out-of-range vertex.")

	var degenerate := 0
	var wrong_winding := 0
	for index in range(0, indices.size(), 3):
		var a := indices[index]
		var b := indices[index + 1]
		var c := indices[index + 2]
		var face := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		if face.length_squared() < 0.000000000000000001:
			degenerate += 1
			continue
		var normal_sum := normals[a] + normals[b] + normals[c]
		if face.normalized().dot(normal_sum.normalized()) <= 0.0:
			wrong_winding += 1
	_check(degenerate == 0, "Mesh contains degenerate triangles: %d" % degenerate)
	_check(wrong_winding == 0, "Triangle winding opposes vertex normals: %d" % wrong_winding)

	var outer_count := int(_skirt.get_mesh_instance().get_meta("outer_vertex_count"))
	var inner_count := int(_skirt.get_mesh_instance().get_meta("inner_vertex_count"))
	var columns := int(_skirt.get_mesh_instance().get_meta("columns"))
	var rows := int(_skirt.get_mesh_instance().get_meta("vertical_rows"))
	_check(outer_count == (columns + 1) * (rows + 1), "Outer shell vertex count is not 24 rows x 8 samples per pleat.")
	_check(rows == 24 and columns == int(design["parameters"]["pleat_count"]) * 8,
		"Mesh does not use 24 rows and 8 circumferential samples per pleat.")
	_check(inner_count == outer_count, "Inner and outer shells have different resolutions.")
	_check(vertices[int(columns / 4)].x > 0.0, "Circumferential UV orientation differs from the 2D editor.")
	_check(normals[0].z < 0.0, "Outer normal at the back seam points into the skirt.")

	var seam_error := 0.0
	for row in range(rows + 1):
		var first := row * (columns + 1)
		var last := first + columns
		seam_error = maxf(seam_error, vertices[first].distance_to(vertices[last]))
		if absf(uvs[first].x) > 0.000001 or absf(uvs[last].x - 1.0) > 0.000001:
			_check(false, "UV seam columns are not mapped to 0 and 1.")
		if absf(vertices[first].x) > 0.000001 or vertices[first].z >= 0.0:
			_check(false, "UV seam is not on the -Z back axis.")
	_check(seam_error < 0.000001, "u=0 and u=1 seam vertices do not coincide: %s" % str(seam_error))

	var waist_error := 0.0
	var hem_error := 0.0
	var waist_radius := float(design["parameters"]["waist_cm"]) / 100.0 / TAU
	for column in range(columns + 1):
		var waist_mid := (vertices[column] + vertices[column + outer_count]) * 0.5
		var hem_index := rows * (columns + 1) + column
		var hem_mid := (vertices[hem_index] + vertices[hem_index + outer_count]) * 0.5
		waist_error = maxf(waist_error, absf(waist_mid.y - float(design["parameters"]["length_cm"]) / 100.0))
		hem_error = maxf(hem_error, absf(hem_mid.y))
	_check(waist_error < 0.000001, "v=0 row is not at y=length.")
	_check(hem_error < 0.000001, "v=1 row is not at y=0.")

	# A through-hole is absent if a cap vertex sits on the axis or if the shell
	# is topologically a sphere rather than a tube (Euler characteristic 2).
	var minimum_radius := INF
	for index in outer_count:
		minimum_radius = minf(minimum_radius, Vector2(vertices[index].x, vertices[index].z).length())
	_check(minimum_radius > waist_radius * 0.5, "A cap vertex was inserted into the waist/hem hole.")
	_check(vertices.size() == outer_count + inner_count + 4 * (columns + 1),
		"Waist/hem rims are missing or an unexpected cap surface was generated.")
	_check_closed_hollow_shell(vertices, indices)

	var aabb: AABB = _skirt.get_mesh_instance().mesh.get_aabb()
	_check(aabb.size.y > 0.6 and aabb.size.x > 0.1 and aabb.size.z > 0.1, "Mesh bounds are collapsed.")

	# Rebuilding the same design must be byte-for-byte deterministic.
	_check(_skirt.configure(design) == OK, "Determinism rebuild was rejected.")
	var rebuilt := _arrays(_skirt)
	_check(rebuilt["vertices"] == vertices and rebuilt["indices"] == indices,
		"Rebuilding the same design produced different geometry.")


func _test_parameters() -> void:
	var sparse: Dictionary = Design.default_design("plain")
	sparse["parameters"]["pleat_count"] = 16
	sparse["parameters"]["thickness_mm"] = 0.6
	_check(_skirt.configure(sparse) == OK, "Sparse-density fixture was rejected.")
	var sparse_count := int(_skirt.get_mesh_instance().get_meta("outer_vertex_count"))
	var dense: Dictionary = sparse.duplicate(true)
	dense["parameters"]["pleat_count"] = 32
	_check(_skirt.configure(dense) == OK, "Dense-density fixture was rejected.")
	var dense_count := int(_skirt.get_mesh_instance().get_meta("outer_vertex_count"))
	_check(dense_count > sparse_count, "More pleats did not increase vertex density.")

	var sharp_design: Dictionary = Design.default_design("plain")
	sharp_design["parameters"]["pleat_count"] = 16
	sharp_design["parameters"]["pleat_depth_cm"] = 4.0
	sharp_design["parameters"]["length_cm"] = 80.0
	sharp_design["parameters"]["hem_cm"] = 260.0
	sharp_design["parameters"]["sharpness"] = 0.0
	_check(_skirt.configure(sharp_design) == OK, "Soft-pleat fixture was rejected.")
	var soft_vertices: PackedVector3Array = _arrays(_skirt)["vertices"]
	var sharp: Dictionary = sharp_design.duplicate(true)
	sharp["parameters"]["sharpness"] = 1.0
	_check(_skirt.configure(sharp) == OK, "Sharp-pleat fixture was rejected.")
	var sharp_vertices: PackedVector3Array = _arrays(_skirt)["vertices"]
	var sharpness_delta := 0.0
	for index in soft_vertices.size():
		sharpness_delta = maxf(sharpness_delta, soft_vertices[index].distance_to(sharp_vertices[index]))
	_check(sharpness_delta > 0.002, "Sharpness did not move the radial pleat profile.")

	var thin: Dictionary = Design.default_design("plain")
	thin["parameters"]["pleat_count"] = 24
	thin["parameters"]["thickness_mm"] = 0.4
	_check(_skirt.configure(thin) == OK, "Thin-shell fixture was rejected.")
	var thin_arrays := _arrays(_skirt)
	var thin_outer := int(_skirt.get_mesh_instance().get_meta("outer_vertex_count"))
	var thick: Dictionary = thin.duplicate(true)
	thick["parameters"]["thickness_mm"] = 2.8
	_check(_skirt.configure(thick) == OK, "Thick-shell fixture was rejected.")
	var thick_arrays := _arrays(_skirt)
	var thick_outer := int(_skirt.get_mesh_instance().get_meta("outer_vertex_count"))
	var thin_mean := _shell_separation(thin_arrays["vertices"], thin_outer)
	var thick_mean := _shell_separation(thick_arrays["vertices"], thick_outer)
	_check(absf(thin_mean - 0.0004) < 0.00002, "Thin shell is not 0.4 mm thick.")
	_check(absf(thick_mean - 0.0028) < 0.00005, "Thick shell is not 2.8 mm thick.")
	_check(thick_mean > thin_mean * 6.0, "Thickness parameter did not change shell separation.")
	_check(absf(float(_skirt.get_mesh_instance().get_meta("thickness_m")) - 0.0028) < 0.0000001,
		"Thickness metadata is not in metres.")


func _test_materials_and_texture() -> void:
	var design: Dictionary = Design.default_design("plain")
	design["bands"] = [_band("test_band", 0.9, 1.0, "#B9AA91", "solid", 8)]
	var roughness: Dictionary = {}
	for fabric in Design.FABRICS:
		var variant: Dictionary = design.duplicate(true)
		variant["parameters"]["fabric"] = fabric
		_check(_skirt.configure(variant) == OK, "Fabric fixture was rejected: " + fabric)
		var material: StandardMaterial3D = _skirt.get_active_material()
		_check(material != null, "No material was created for " + fabric)
		if material == null:
			continue
		roughness[fabric] = material.roughness
		_check(absf(material.roughness - Skirt.fabric_roughness(fabric)) < 0.000001,
			"Fabric roughness does not match the component table: " + fabric)
		_check(material.albedo_texture != null, "Material has no generated texture: " + fabric)
		if material.albedo_texture != null:
			_check(material.albedo_texture.get_width() == 512, "Generated texture width is not 512: " + fabric)
	_check(roughness.size() == 4, "Not all four fabrics produced a material.")
	var distinct := {}
	for fabric in roughness:
		distinct[snappedf(roughness[fabric], 0.001)] = true
	_check(distinct.size() == 4, "Cotton/linen/silk/wool do not visibly differ in roughness.")

	_check(_skirt.configure(design) == OK, "Texture fixture was rejected.")
	var texture: Texture2D = _skirt.get_active_material().albedo_texture
	_check(_skirt.get_texture_source() == "generated", "Default design did not use a generated texture.")
	if texture != null:
		var image := texture.get_image()
		_check(image != null and image.get_width() == 512, "Generated texture image is unavailable.")
		if image != null:
			var band_color := image.get_pixel(256, 500)
			_check(_color_close(band_color, Color("#B9AA91"), 0.02),
				"Band start/end/color did not reach the generated texture.")

	var patterned: Dictionary = Design.default_design("mosuo_reference")
	patterned["strokes"] = [_stroke("test_dot", "#E1C27A", 0.02, [[0.5, 0.31]])]
	_check(_skirt.configure(patterned) == OK, "Patterned texture fixture was rejected.")
	var patterned_image: Image = _skirt.get_active_material().albedo_texture.get_image()
	var stroke_color := patterned_image.get_pixel(256, 159)
	_check(_color_close(stroke_color, Color("#E1C27A"), 0.03),
		"Stroke vector data did not reach the generated texture.")
	var plain_design: Dictionary = Design.default_design("plain")
	_check(_skirt.configure(plain_design) == OK, "Plain texture comparison fixture was rejected.")
	var plain_bytes: PackedByteArray = _skirt.get_active_material().albedo_texture.get_image().get_data()
	_check(plain_bytes != patterned_image.get_data(), "Different band/patch/stroke data produced identical textures.")


func _test_public_api() -> void:
	var design: Dictionary = Design.default_design("wax_reference")
	design["design_id"] = "design_api_001"
	_check(Design.save_design_file(API_JSON, design)["ok"], "Could not write the public-API design fixture.")

	var preload_skirt := Skirt.new()
	preload_skirt.design_path = API_JSON
	root.add_child(preload_skirt)
	_check(preload_skirt.design.get("design_id", "") == "design_api_001",
		"Setting design_path before entering the tree did not load the design.")
	_check(preload_skirt.get_mesh_instance().mesh != null, "Path-loaded component has no mesh.")

	var live_skirt := Skirt.new()
	root.add_child(live_skirt)
	var initial_id := String(live_skirt.design["design_id"])
	live_skirt.design_path = API_JSON
	_check(live_skirt.design.get("design_id", "") == "design_api_001",
		"Setting design_path after entering the tree did not reload the design.")
	_check(live_skirt.design["design_id"] != initial_id, "design_path reload did not replace the design.")

	var missing_error = live_skirt.load_design(TEST_DIR + "/pleated_skirt_missing.json")
	_check(missing_error == ERR_FILE_NOT_FOUND, "Missing design file did not return ERR_FILE_NOT_FOUND.")
	_check(live_skirt.design["design_id"] == "design_api_001", "Missing file replaced the active design.")
	var before_mesh: Mesh = live_skirt.get_mesh_instance().mesh
	live_skirt.design_path = TEST_DIR + "/pleated_skirt_missing.json"
	_check(live_skirt.design_path == API_JSON, "An invalid Inspector path replaced the last valid design path.")
	_check(live_skirt.get_mesh_instance().mesh == before_mesh, "A rejected import replaced the live mesh.")

	_write_text(BAD_JSON, "{\"schema\": \"weave-pleated-skirt\", \"version\": 1,")
	var malformed_error = live_skirt.load_design(BAD_JSON)
	_check(malformed_error == ERR_PARSE_ERROR, "Malformed JSON did not return ERR_PARSE_ERROR.")
	_check(live_skirt.design["design_id"] == "design_api_001", "Malformed JSON replaced the active design.")

	_write_text(EMPTY_JSON, "[]")
	var wrong_root_error = live_skirt.load_design(EMPTY_JSON)
	_check(wrong_root_error == ERR_INVALID_DATA, "Non-object JSON root did not return ERR_INVALID_DATA.")

	var oversize := FileAccess.open(OVERSIZE_JSON, FileAccess.WRITE)
	_check(oversize != null, "Could not create the oversize-file fixture.")
	if oversize != null:
		oversize.store_string("x".repeat(8 * 1024 * 1024 + 1))
		oversize.close()
	var oversize_error = live_skirt.load_design(OVERSIZE_JSON)
	_check(oversize_error == ERR_FILE_CANT_READ, "Oversize design file did not fail before parsing.")

	var never_configured := Skirt.new()
	_check(never_configured.export_design(TEST_DIR + "/pleated_skirt_unconfigured.json") == ERR_UNCONFIGURED,
		"Exporting an unconfigured component did not return ERR_UNCONFIGURED.")
	never_configured.free()

	# A sibling unwrapped PNG is preferred when it is present.
	var sibling_image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	sibling_image.fill(Color("#3D6A63"))
	_check(sibling_image.save_png(SIBLING_PNG) == OK, "Could not write the sibling PNG fixture.")
	var sibling_skirt := Skirt.new()
	root.add_child(sibling_skirt)
	var sibling_error = sibling_skirt.load_design(ROUNDTRIP_JSON)
	_check(sibling_error == OK, "Loading a design with a sibling PNG failed.")
	_check(sibling_skirt.get_texture_source() == "sibling_png", "Sibling PNG was not preferred over the generated texture.")
	_check(sibling_skirt.get_active_material().albedo_texture.get_width() == 8, "Sibling PNG dimensions were not used.")


func _test_preview_scene() -> void:
	var packed := load("res://scenes/pleated_skirt_preview.tscn")
	_check(packed != null, "Preview scene does not parse or load.")
	if packed == null:
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	var preview_skirt = scene.get_node_or_null("Skirt")
	_check(preview_skirt != null, "Preview scene is missing its Skirt component.")
	if preview_skirt != null:
		_check(preview_skirt.get_mesh_instance().mesh != null, "Preview scene did not build a mesh.")
		_check(preview_skirt.design.get("template_id", "") == "mosuo_reference",
			"Preview scene does not show the mosuo_reference starting design.")
	var camera = scene.get_node_or_null("Camera3D")
	_check(camera != null and camera.current, "Preview scene has no current camera.")
	_check(scene.get_node_or_null("WorldEnvironment") != null, "Preview scene has no neutral environment.")
	_check(scene.get_node_or_null("KeyLight") != null, "Preview scene has no key light.")
	scene.free()


func _test_toolkit_dynamics_and_doll_binding() -> void:
	var draped_skirt = Skirt.new()
	root.add_child(draped_skirt)
	var design: Dictionary = Design.default_design("mosuo_reference")
	_check(draped_skirt.configure(design) == OK, "Toolkit dynamics fixture was rejected.")
	for silhouette in Dynamics.SILHOUETTES:
		for hem_shape in Dynamics.HEM_SHAPES:
			draped_skirt.design["parameters"]["silhouette"] = silhouette
			draped_skirt.design["shape"] = Dynamics.DEFAULT_SHAPE.duplicate(true)
			draped_skirt.design["shape"]["hem"] = {
				"mode": hem_shape,
				"ratio": 0.75,
				"angle_deg": 25.0,
			}
			var warp_err: float = draped_skirt.apply_standalone_drape(0.0)
			_check(warp_err < 0.0005,
				"Standalone drape longitudinal arc-length error exceeded tolerance for %s/%s: %s" % [
					silhouette, hem_shape, str(warp_err)])
	# Spin inertia check
	for step in range(1, 13):
		draped_skirt.apply_standalone_drape(float(step) * 0.12)
	var inertia = draped_skirt.get_inertia()
	_check(inertia != null and absf(inertia.lag[24]) > 0.0001 and inertia.opening[24] > 0.0001,
		"Toolkit 120Hz SkirtInertia did not accumulate centrifugal opening and angular lag during spin.")
	draped_skirt.free()

	# VolumeDoll cage binding and multi-pose physics check
	var doll = VolumeDollScript.new()
	root.add_child(doll)
	doll.configure({"name": "SkirtTester", "outfit_style": 0})
	var worn = doll.equip_pleated_skirt(Design.default_design("yi_reference"))
	_check(worn != null and is_instance_valid(worn), "VolumeDoll.equip_pleated_skirt() did not return a valid PleatedSkirt.")
	if worn != null:
		for motion in ["stand", "walk", "sit", "lie", "display", "spin"]:
			var pose_info: Dictionary = worn.pose_on_doll(motion, 0.55, 1.2)
			_check(bool(pose_info.get("ok", false)), "pose_on_doll failed for motion: " + motion)
			var arrays := _arrays(worn)
			var verts: PackedVector3Array = arrays["vertices"]
			_check(verts.size() > 1000, "Worn skirt vertices collapsed in motion: " + motion)
			var all_finite := true
			for v in verts:
				if not _finite_vector(v):
					all_finite = false
					break
			_check(all_finite, "Worn skirt produced non-finite vertices in motion: " + motion)
			_check(worn.get_last_warp_error() < 0.001,
				"Worn skirt warp arc-length constraint failed in motion %s: %s" % [motion, str(worn.get_last_warp_error())])
			if motion == "display":
				_check(bool(pose_info.get("grip", false)) and int(pose_info.get("grip_row", 0)) > 0,
					"Display motion did not engage hand grasp on the skirt.")
			if motion == "spin":
				_check(absf(float(pose_info.get("hem_lag", 0.0))) > 0.0001 and float(pose_info.get("hem_opening", 0.0)) > 0.0001,
					"Spin motion on VolumeDoll did not report hem_lag and hem_opening.")
	doll.unequip_pleated_skirt()
	_check(doll.pleated_skirt == null and doll._skirt.visible, "unequip_pleated_skirt() did not restore default VolumeDoll skirt.")
	doll.free()


func _test_editor_export() -> void:
	for name in ["plain", "mosuo_reference", "yi_reference", "wax_reference", "painted", "native_painted"]:
		_test_editor_fixture("res://assets/designs/pleated_skirt/%s/skirt.json" % name)


func _test_editor_fixture(fixture: String) -> void:
	_check(FileAccess.file_exists(fixture), "Browser-exported design fixture is missing.")
	if not FileAccess.file_exists(fixture):
		return
	var expected := Design.load_design_file(fixture)
	_check(expected["ok"], "Browser-exported JSON does not satisfy the shared contract.")
	if not expected["ok"]:
		return
	var imported := Skirt.new()
	root.add_child(imported)
	_check(imported.load_design(fixture) == OK, "Browser-exported JSON and PNG failed to load.")
	_check(imported.design == expected["design"], "Import changed browser identities, provenance, patches or strokes.")
	_check(imported.get_texture_source() == "sibling_png", "Browser PNG was replaced by the procedural fallback.")
	var png := Image.load_from_file(fixture.get_basename() + ".png")
	var texture_image: Image = imported.get_active_material().albedo_texture.get_image()
	_check(png != null and texture_image != null, "Browser texture is unavailable after importing.")
	if png != null and texture_image != null:
		_check(texture_image.get_size() == png.get_size(), "Browser texture resolution changed.")
		var matching := true
		for y in range(0, png.get_height(), 29):
			for x in range(0, png.get_width(), 31):
				if not _color_close(png.get_pixel(x, y), texture_image.get_pixel(x, y), 0.001):
					matching = false
		_check(matching, "Imported pixels differ from the 2D editor PNG (including the painting layer).")
	_check(imported.export_design(ROUNDTRIP_JSON) == OK, "Could not re-export the browser design.")
	var roundtrip := Design.load_design_file(ROUNDTRIP_JSON)
	_check(roundtrip["ok"] and roundtrip["design"] == expected["design"], "Godot re-export lost browser design data.")
	imported.free()


func _expect_invalid(label: String, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		_check(false, "Invalid fixture was not a dictionary: " + label)
		return
	var validation := Design.validate_design(data)
	_check(not validation.is_empty(), "Invalid design accepted: " + label)
	var before_id := String(_skirt.design["design_id"])
	var error = _skirt.configure(data)
	_check(error != OK, "configure() accepted invalid design: " + label)
	_check(not _skirt.last_error.is_empty(), "Invalid design did not set last_error: " + label)
	_check(String(_skirt.design["design_id"]) == before_id, "Invalid design replaced the active design: " + label)


func _mutate(base: Dictionary, keys: Array, value: Variant) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	var target: Dictionary = result
	for index in range(keys.size() - 1):
		target = target[keys[index]]
	target[keys[keys.size() - 1]] = value
	return result


func _drop(base: Dictionary, keys: Array) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	var target: Dictionary = result
	for index in range(keys.size() - 1):
		target = target[keys[index]]
	target.erase(keys[keys.size() - 1])
	return result


func _many_bands(count: int) -> Array:
	var bands: Array = []
	for index in count:
		bands.append(_band("band_%d" % index, 0.0, 0.01, "#112233", "solid", 4))
	return bands


func _many_patches(count: int) -> Array:
	var patches: Array = []
	for index in count:
		patches.append(_patch("patch_%d" % index, 0.0, 0.5, 0.0, 0.5, "#112233", "solid", 4))
	return patches


func _many_strokes(count: int) -> Array:
	var strokes: Array = []
	for index in count:
		strokes.append(_stroke("stroke_%d" % index, "#112233", 0.01, [[0.0, 0.0], [1.0, 1.0]]))
	return strokes


func _band(id: String, start: float, end: float, color: String, pattern: String, repeat_count: int) -> Dictionary:
	return {"id": id, "start": start, "end": end, "color": color, "pattern": pattern, "repeat": repeat_count}


func _patch(id: String, u0: float, u1: float, v0: float, v1: float, color: String, pattern: String, repeat_count: int) -> Dictionary:
	return {"id": id, "u0": u0, "u1": u1, "v0": v0, "v1": v1, "color": color, "pattern": pattern, "repeat": repeat_count}


func _stroke(id: String, color: String, width: float, points: Array) -> Dictionary:
	return {"id": id, "color": color, "width": width, "points": points}


func _arrays(skirt) -> Dictionary:
	var mesh: ArrayMesh = skirt.get_mesh_instance().mesh
	_check(mesh != null and mesh.get_surface_count() == 1, "Component did not produce one mesh surface.")
	if mesh == null or mesh.get_surface_count() != 1:
		return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(),
			"uvs": PackedVector2Array(), "indices": PackedInt32Array()}
	var arrays: Array = mesh.surface_get_arrays(0)
	return {
		"vertices": arrays[Mesh.ARRAY_VERTEX],
		"normals": arrays[Mesh.ARRAY_NORMAL],
		"uvs": arrays[Mesh.ARRAY_TEX_UV],
		"indices": arrays[Mesh.ARRAY_INDEX],
	}


func _shell_separation(vertices: PackedVector3Array, outer_count: int) -> float:
	var total := 0.0
	var samples := 0
	for index in outer_count:
		total += vertices[index].distance_to(vertices[index + outer_count])
		samples += 1
	return total / float(samples)


func _check_closed_hollow_shell(vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	var unique: Dictionary = {}
	var remap := PackedInt32Array()
	remap.resize(vertices.size())
	for index in vertices.size():
		var key := vertices[index].snapped(Vector3.ONE * 0.000001)
		if not unique.has(key):
			unique[key] = unique.size()
		remap[index] = int(unique[key])
	var edges: Dictionary = {}
	for index in range(0, indices.size(), 3):
		var triangle := [remap[indices[index]], remap[indices[index + 1]], remap[indices[index + 2]]]
		for corner in 3:
			var a: int = triangle[corner]
			var b: int = triangle[(corner + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edges.has(key):
				edges[key] = [0, 0]
			edges[key][0] += 1
			edges[key][1] += 1 if a < b else -1
	var boundary_edges := 0
	var non_manifold_edges := 0
	var flipped_edges := 0
	for key in edges:
		var uses: Array = edges[key]
		if uses[0] == 1:
			boundary_edges += 1
		elif uses[0] > 2:
			non_manifold_edges += 1
		elif uses[1] != 0:
			flipped_edges += 1
	var euler := unique.size() - edges.size() + int(indices.size() / 3)
	_check(boundary_edges == 0, "Thick shell has %d boundary edges instead of connected rims." % boundary_edges)
	_check(non_manifold_edges == 0, "Thick shell has %d non-manifold edges." % non_manifold_edges)
	_check(flipped_edges == 0, "Adjacent shell triangles use inconsistent winding: %d" % flipped_edges)
	_check(euler == 0, "Waist/hem through-hole topology is not a closed hollow tube (Euler=%d)." % euler)


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _color_close(actual: Color, expected: Color, tolerance: float) -> bool:
	return (absf(actual.r - expected.r) <= tolerance
		and absf(actual.g - expected.g) <= tolerance
		and absf(actual.b - expected.b) <= tolerance
		and absf(actual.a - expected.a) <= tolerance)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Could not write test fixture: " + path)
		return
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	for path in [ROUNDTRIP_JSON, API_JSON, BAD_JSON, EMPTY_JSON, OVERSIZE_JSON, SIBLING_PNG,
			TEST_DIR + "/pleated_skirt_unconfigured.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
