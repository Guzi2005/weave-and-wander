extends SceneTree

## Material state contract for the Mosuo photo garments (styles 14/15/16):
## the flat-ink source material (pigment map / vertex colours) must survive
## rack, folded, carried and worn presentations, and fold splitting must keep
## the source UVs while interpolating vertex colours across cut lines.

const Definition = preload("res://scripts/garment_definition.gd")
const Garment = preload("res://scripts/garment_item.gd")
const MosuoDollSource = preload("res://scripts/mosuo_doll.gd")
const Customer = preload("res://scripts/customer_doll.gd")
const Forms = preload("res://scripts/garment_forms.gd")
const ROOM_SHADER_PATH := "res://shaders/room_paper.gdshader"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func snapshot(material: Material) -> Dictionary:
	if material == null:
		return {"kind": "none"}
	if material is StandardMaterial3D:
		return {"kind": "standard", "name": material.resource_name}
	if not material is ShaderMaterial:
		return {"kind": "other"}
	return {
		"kind": "shader",
		"shader": material.shader.resource_path if material.shader != null else "",
		"pigment": material.get_shader_parameter("pigment"),
		"map": material.get_shader_parameter("pigment_map"),
		"use_map": material.get_shader_parameter("use_pigment_map") == true,
		"use_vertex_color": material.get_shader_parameter("use_vertex_color") == true,
	}


func carries_detail(snap: Dictionary) -> bool:
	if snap.get("kind") == "standard":
		return true
	return snap.get("use_map", false) or snap.get("map") != null or snap.get("use_vertex_color", false)


func same_material(actual: Dictionary, expected: Dictionary, label: String) -> void:
	check(actual.get("kind") == expected.get("kind"), "%s: material kind changed (%s -> %s)" % [label, expected.get("kind"), actual.get("kind")])
	if actual.get("kind") != "shader" or expected.get("kind") != "shader":
		return
	check(actual.shader == expected.shader, "%s: shader changed (%s -> %s)" % [label, expected.shader, actual.shader])
	check(actual.use_map == expected.use_map, "%s: use_pigment_map flag changed" % label)
	check((actual.map != null) == (expected.map != null), "%s: pigment_map texture lost" % label)
	check(actual.use_vertex_color == expected.use_vertex_color, "%s: use_vertex_color flag changed" % label)
	if actual.pigment != null and expected.pigment != null:
		check((actual.pigment as Color).is_equal_approx(expected.pigment), "%s: pigment changed (%s -> %s)" % [label, expected.pigment, actual.pigment])


func position_key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0)]


func expect_color_at(vertices: PackedVector3Array, colors: PackedColorArray, position: Vector3, expected: Color, label: String) -> void:
	var found := false
	for i in vertices.size():
		if vertices[i].distance_to(position) < 1e-4:
			found = true
			var c: Color = colors[i]
			check(absf(c.r - expected.r) < 2e-3 and absf(c.g - expected.g) < 2e-3 and absf(c.b - expected.b) < 2e-3,
				"%s: colour at %s is %s, expected %s" % [label, position, c, expected])
	check(found, "%s: no vertex at %s after fold split" % [label, position])


func assert_detail_live(item: Node3D, detail_indices: Array, state: String, worn: bool) -> void:
	for index in detail_indices:
		var part: MeshInstance3D = item.parts[index]
		var label := "%s / %s @ %s" % [item.item_id, part.name, state]
		var expected: Dictionary = snapshot(item.worn_materials[index] if worn else item.prop_materials[index])
		same_material(snapshot(part.material_override), expected, label)
		if expected.get("map") != null:
			check(part.material_override.get_shader_parameter("pigment_map") != null, "%s: live pigment map lost" % label)
		if expected.get("use_vertex_color", false):
			check(part.material_override.get_shader_parameter("use_vertex_color") == true, "%s: live vertex colour flag lost" % label)


func _run() -> void:
	var stock := Node3D.new()
	root.add_child(stock)
	# Independent source of truth: the doll pipeline that garment extraction samples.
	var reference := MosuoDollSource.new()
	reference.configure({"outfit": 0, "palette": 0})
	var source_parts := {}
	for part: MeshInstance3D in reference.rig.meshes:
		source_parts[str(part.name)] = part

	var items := {}
	for style in Definition.MOSUO_STYLES:
		var definition: Resource = Definition.create(style, 0)
		var item := Garment.new()
		item.item_id = "material-test-%d" % style
		item.definition = definition
		stock.add_child(item)
		item.build()
		items[style] = item
		check(not item.parts.is_empty(), "Style %d: empty garment" % style)
		var textured := 0
		var vertex_colored := 0
		for index in item.parts.size():
			var part := item.parts[index]
			var label := "Style %d / %s" % [style, part.name]
			check(source_parts.has(str(part.name)), "%s: no source counterpart" % label)
			if not source_parts.has(str(part.name)):
				continue
			var expected: Dictionary = snapshot(source_parts[str(part.name)].material_override)
			# Worn presentation must be the untouched source material.
			same_material(snapshot(item.worn_materials[index]), expected, label + " worn")
			var prop: Dictionary = snapshot(item.prop_materials[index])
			if carries_detail(expected):
				# Prop presentations (rack/folded/carried) keep texture and vertex colour.
				same_material(prop, expected, label + " prop")
				if prop.get("map") != null:
					textured += 1
				if prop.get("use_vertex_color", false):
					vertex_colored += 1
			else:
				# Plain pigment legacy parts keep the room-paper display material.
				check(prop.get("shader") == ROOM_SHADER_PATH, "%s: legacy prop material changed" % label)
		if style in [15, 16]:
			check(textured > 0, "Style %d: no textured prop material survived" % style)
		if style == 14:
			check(vertex_colored > 0, "Style 14: no vertex-coloured prop material survived")

	# Fold splitting must preserve the authored fabric UVs per vertex.
	for style in [15, 16]:
		var item: Node3D = items[style]
		var uv_parts := 0
		for part: MeshInstance3D in item.parts:
			if not part.has_meta("preserve_fabric_uv"):
				continue
			uv_parts += 1
			var label := "Style %d / %s UV" % [style, part.name]
			var source: MeshInstance3D = source_parts.get(str(part.name))
			check(source != null, "%s: no source mesh" % label)
			if source == null:
				continue
			var source_arrays := source.mesh.surface_get_arrays(0)
			var rebuilt := part.mesh.surface_get_arrays(0)
			var uvs = rebuilt[Mesh.ARRAY_TEX_UV]
			check(uvs != null, "%s: UVs dropped by fold splitting" % label)
			if uvs == null:
				continue
			var vertices: PackedVector3Array = rebuilt[Mesh.ARRAY_VERTEX]
			check(uvs.size() == vertices.size(), "%s: UV/vertex count mismatch" % label)
			var expected_uvs := {}
			var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
			var source_uvs: PackedVector2Array = source_arrays[Mesh.ARRAY_TEX_UV]
			for i in source_vertices.size():
				var key := position_key(source_vertices[i])
				if not expected_uvs.has(key):
					expected_uvs[key] = []
				expected_uvs[key].append(source_uvs[i])
			var found := 0
			for i in vertices.size():
				var key := position_key(vertices[i])
				if not expected_uvs.has(key):
					continue
				found += 1
				var ok := false
				for expected_uv: Vector2 in expected_uvs[key]:
					if uvs[i].distance_to(expected_uv) < 1e-4:
						ok = true
						break
				check(ok, "%s: UV %s no longer matches source at %s" % [label, uvs[i], key])
			check(found >= expected_uvs.size(), "%s: only %d of %d source positions survive the split" % [label, found, expected_uvs.size()])
		check(uv_parts > 0, "Style %d: no fabric-UV part to verify" % style)

	# Rack -> carried -> worn -> carried -> rack keeps detail materials live in every state.
	var wearer := Customer.new()
	root.add_child(wearer)
	wearer.customer_id = "material-test-wearer"
	wearer.configure({"outfit": 0, "palette": 0})
	for style in Definition.MOSUO_STYLES:
		var item: Node3D = items[style]
		var detail_indices: Array = []
		for index in item.parts.size():
			if carries_detail(snapshot(item.worn_materials[index])):
				detail_indices.append(index)
		assert_detail_live(item, detail_indices, "rack", false)
		check(item.reserve(wearer), "Style %d: cannot reserve" % style)
		check(wearer.carry_item(item), "Style %d: cannot carry" % style)
		assert_detail_live(item, detail_indices, "carried", false)
		check(wearer.put_on(item), "Style %d: cannot wear" % style)
		assert_detail_live(item, detail_indices, "worn", true)
		check(wearer.take_off(item), "Style %d: cannot remove" % style)
		assert_detail_live(item, detail_indices, "carried-again", false)
		item.place("rack", Transform3D.IDENTITY)
		assert_detail_live(item, detail_indices, "rack-again", false)

	# Legacy pigment-only garments still fall back to the room-paper prop material.
	var legacy := Garment.new()
	legacy.item_id = "material-test-legacy"
	legacy.definition = Definition.create(3, 1)
	stock.add_child(legacy)
	legacy.build()
	for index in legacy.parts.size():
		var worn_snap: Dictionary = snapshot(legacy.worn_materials[index])
		var prop_snap: Dictionary = snapshot(legacy.prop_materials[index])
		var label := "Legacy / %s" % legacy.parts[index].name
		if carries_detail(worn_snap):
			same_material(prop_snap, worn_snap, label)
		else:
			check(prop_snap.get("shader") == ROOM_SHADER_PATH, "%s: legacy prop material changed" % label)
			if prop_snap.get("pigment") != null and worn_snap.get("pigment") != null:
				check((prop_snap.pigment as Color).is_equal_approx(worn_snap.pigment), "%s: legacy pigment changed" % label)

	# Fold splitting keeps the vertex-colour channel and interpolates across cut lines.
	var colored_part := MeshInstance3D.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.3, 0, .1), Vector3(.3, 0, .1), Vector3(0, 1, .1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var colored_mesh := ArrayMesh.new()
	colored_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	colored_part.mesh = colored_mesh
	var forms := Forms.new()
	forms.build([colored_part], Definition.create(15, 0), 0.0, 1.0)
	var rebuilt := colored_part.mesh.surface_get_arrays(0)
	var colors = rebuilt[Mesh.ARRAY_COLOR]
	check(colors != null, "Fold split dropped the vertex-colour channel")
	if colors != null:
		var rebuilt_vertices: PackedVector3Array = rebuilt[Mesh.ARRAY_VERTEX]
		check(colors.size() == rebuilt_vertices.size(), "Colour/vertex count mismatch after fold split")
		expect_color_at(rebuilt_vertices, colors, Vector3(-.3, 0, .1), Color.RED, "corner A")
		expect_color_at(rebuilt_vertices, colors, Vector3(.3, 0, .1), Color.GREEN, "corner B")
		expect_color_at(rebuilt_vertices, colors, Vector3(0, 1, .1), Color.BLUE, "corner C")
		expect_color_at(rebuilt_vertices, colors, Vector3(.2, 0, .1), Color.RED.lerp(Color.GREEN, 5.0 / 6.0), "x=+half_width cut")
		expect_color_at(rebuilt_vertices, colors, Vector3(-.2, 0, .1), Color.RED.lerp(Color.GREEN, 1.0 / 6.0), "x=-half_width cut")
		expect_color_at(rebuilt_vertices, colors, Vector3(.15, .5, .1), Color.GREEN.lerp(Color.BLUE, .5), "y=half_y cut B-C")
		expect_color_at(rebuilt_vertices, colors, Vector3(-.15, .5, .1), Color.RED.lerp(Color.BLUE, .5), "y=half_y cut A-C")

	colored_part.free()
	reference.free()
	stock.free()
	wearer.free()
	print("GARMENT_MATERIAL_STATE_TEST failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
