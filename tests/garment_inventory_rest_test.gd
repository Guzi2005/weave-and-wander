extends SceneTree

const Forms = preload("res://scripts/garment_forms.gd")
const Garment = preload("res://scripts/garment_item.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const Catalog = preload("res://scripts/catalog_doll.gd")
const Customer = preload("res://scripts/customer_doll.gd")
const EPS := .0002
var checks := 0
var completed := 0
var failures: Array[String] = []


class StateWearer extends Node:
	var rig := {"meshes": []}
	var _rest_blend := .5
	var rest_mode := "nap"
	var _nap_pose_weights := Vector4(.1, .2, .3, .4)


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		if failures.size() <= 20: push_error(message)


func mesh_bytes(mesh: ArrayMesh) -> PackedByteArray:
	var names: Array = []
	for i in mesh.get_blend_shape_count(): names.append(mesh.get_blend_shape_name(i))
	return var_to_bytes([mesh.blend_shape_mode, names, mesh.surface_get_arrays(0), mesh.surface_get_blend_shape_arrays(0)])


func find_part(parts: Array, label: String) -> MeshInstance3D:
	for part in parts:
		if str(part.name) == label: return part
	return null


func check_weights(item: Node3D, expected: PackedFloat32Array, context: String) -> void:
	var found := 0
	for part in item.parts:
		for i in part.mesh.get_blend_shape_count():
			var mode: int = Forms.REST_SHAPES.find(str(part.mesh.get_blend_shape_name(i)))
			if mode < 0: continue
			found += 1
			check(absf(part.get_blend_shape_value(i) - expected[mode]) < .00001, context + ": rest weight " + str(part.name))
	check(found > 0, context + ": no rest targets checked")


func test_subdivision(relative: bool, skinned: bool) -> void:
	var source := ArrayMesh.new()
	source.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE if relative else Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var names := ["RestDraped", "RestSit"]
	for label in names: source.add_blend_shape(label)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.6, .3, .2), Vector3(.6, .5, -.25), Vector3(.1, 1.8, .15)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(.9, 1), Vector2(.7, 1), Vector2(.1, 1)])
	if skinned:
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0])
		arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, .5, .5, 0, 0, 0, 1, 0, 0])
	var targets: Array[Array] = []
	for mode in names.size():
		var target := []
		target.resize(Mesh.ARRAY_MAX)
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		for i in 3:
			var delta := Vector3(.03 * (i + 1), .1 * (mode + 1), -.04 * i)
			var normal := Vector3(.2 * (i + 1), 1, .15 * (mode + 1)).normalized()
			positions.append(delta if relative else arrays[Mesh.ARRAY_VERTEX][i] + delta)
			normals.append(normal - Vector3.UP if relative else normal)
		target[Mesh.ARRAY_VERTEX] = positions
		target[Mesh.ARRAY_NORMAL] = normals
		targets.append(target)
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, targets)
	var before := mesh_bytes(source)
	var part := MeshInstance3D.new()
	part.mesh = source
	var shared := MeshInstance3D.new()
	shared.mesh = source
	var forms := Forms.new()
	var parts: Array[MeshInstance3D] = [part]
	forms.build(parts, Definition.create(0, 0), .2, 1.9)
	var context := "subdivision relative=%s skinned=%s" % [relative, skinned]
	check(part.mesh != source and shared.mesh == source, context + ": shared source replaced")
	check(mesh_bytes(source) == before, context + ": source arrays mutated")
	check(part.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED, context + ": output mode")
	check(part.mesh.get_blend_shape_count() == 6, context + ": appended target count")
	var original := source.surface_get_arrays(0)
	var originals := source.surface_get_blend_shape_arrays(0)
	var output := part.mesh.surface_get_arrays(0)
	var shaped := part.mesh.surface_get_blend_shape_arrays(0)
	check(output[Mesh.ARRAY_VERTEX].size() > 3, context + ": subdivision not exercised")
	for stage in Forms.SHAPES.size():
		check(str(part.mesh.get_blend_shape_name(stage)) == Forms.SHAPES[stage], context + ": fold index changed")
	for mode in names.size():
		check(str(part.mesh.get_blend_shape_name(4 + mode)) == names[mode], context + ": source target name/order lost")
	for i in output[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = output[Mesh.ARRAY_VERTEX][i]
		var bary := Geometry3D.get_triangle_barycentric_coords(p, original[Mesh.ARRAY_VERTEX][0], original[Mesh.ARRAY_VERTEX][1], original[Mesh.ARRAY_VERTEX][2])
		var uv := Vector2.ZERO
		for j in 3: uv += original[Mesh.ARRAY_TEX_UV2][j] * bary[j]
		check(output[Mesh.ARRAY_TEX_UV2][i].distance_to(uv) < EPS, context + ": UV2 interpolation")
		for mode in names.size():
			var target_p := Vector3.ZERO
			var target_n := Vector3.ZERO
			for j in 3:
				target_p += (originals[mode][Mesh.ARRAY_VERTEX][j] + (original[Mesh.ARRAY_VERTEX][j] if relative else Vector3.ZERO)) * bary[j]
				target_n += (originals[mode][Mesh.ARRAY_NORMAL][j] + (original[Mesh.ARRAY_NORMAL][j] if relative else Vector3.ZERO)) * bary[j]
			check(shaped[4 + mode][Mesh.ARRAY_VERTEX][i].distance_to(target_p) < EPS, context + ": target position interpolation")
			check(shaped[4 + mode][Mesh.ARRAY_NORMAL][i].normalized().distance_to(target_n.normalized()) < EPS, context + ": target normal interpolation")
		for stage in Forms.SHAPES.size():
			var folded := forms.deform(p, output[Mesh.ARRAY_NORMAL][i], stage)
			check(shaped[stage][Mesh.ARRAY_VERTEX][i].distance_to(folded[0]) < EPS, context + ": fold geometry changed")
	forms.blend_forms(parts, "Worn", "Folded", .4)
	check(absf(part.get_blend_shape_value(3) - .4) < .00001, context + ": fold blend index")
	for i in range(4, 6): check(part.get_blend_shape_value(i) == 0, context + ": blend retained rest")
	part.free()
	shared.free()
	completed += 1


func test_inventory(style: int) -> void:
	var stock := Node3D.new()
	root.add_child(stock)
	var customer := Customer.new()
	stock.add_child(customer)
	customer.customer_id = "rest-inventory-test"
	customer.configure({"outfit": 0, "palette": 0})
	customer.set_process(false)
	var source := Catalog.new()
	stock.add_child(source)
	source.catalog_style = style
	source.configure({"outfit": style, "palette": 0})
	source.set_process(false)
	var label := "Apron" if style == 1 else "LongSkirt"
	var source_skirt := find_part(source.rig.meshes, label)
	var source_before := mesh_bytes(source_skirt.mesh)
	var body_before := {}
	for part in customer.rig.meshes:
		if part.get_meta("is_underbody", false): body_before[part] = mesh_bytes(part.mesh)
	var item := Garment.new()
	stock.add_child(item)
	item.item_id = "rest-%d" % style
	item.definition = Definition.create(style, 0)
	item.build()
	item.set_process(false)
	item.place("rack", Transform3D.IDENTITY)
	check(item.reserve(customer) and customer.carry_item(item) and customer.put_on(item), "style %d: wear lifecycle" % style)
	var skirt := find_part(item.parts, label)
	check(skirt != null, "style %d: missing inventory garment" % style)
	if skirt == null:
		stock.free()
		return
	var snapshots := {}
	for part in item.parts:
		snapshots[part] = mesh_bytes(part.mesh)
		for i in mini(4, part.mesh.get_blend_shape_count()):
			check(str(part.mesh.get_blend_shape_name(i)) == Forms.SHAPES[i], "inventory fold indices")
		if part.material_override is ShaderMaterial and part.material_override.get_shader_parameter("cloth_secondary_enabled") == true:
			var arrays: Array = part.mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_TEX_UV2] != null, "inventory motion coordinates missing")
			for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV2]:
				check(uv.x >= 0 and uv.x <= 1 and absf(uv.y - 1) < EPS, "inventory motion coordinates invalid")
	# Original vertices must retain their exact correctives after fold-line subdivision.
	var original := source_skirt.mesh.surface_get_arrays(0)
	var output := skirt.mesh.surface_get_arrays(0)
	var targets := skirt.mesh.surface_get_blend_shape_arrays(0)
	var original_targets := source_skirt.mesh.surface_get_blend_shape_arrays(0)
	var bins := {}
	for i in output[Mesh.ARRAY_VERTEX].size():
		var key := Vector3i((output[Mesh.ARRAY_VERTEX][i] * 10000).round())
		if not bins.has(key): bins[key] = []
		bins[key].append(i)
	var pairs: Array[Vector2i] = []
	for i in original[Mesh.ARRAY_VERTEX].size():
		var key := Vector3i((original[Mesh.ARRAY_VERTEX][i] * 10000).round())
		var chosen := -1
		var best := INF
		for candidate: int in bins.get(key, []):
			if output[Mesh.ARRAY_NORMAL][candidate].distance_to(original[Mesh.ARRAY_NORMAL][i]) < EPS:
				# Layer seams can share rest positions/normals but have different correctives.
				var error := 0.0
				for mode in Forms.REST_SHAPES.size():
					error += targets[4 + mode][Mesh.ARRAY_VERTEX][candidate].distance_squared_to(original_targets[mode][Mesh.ARRAY_VERTEX][i])
					error += targets[4 + mode][Mesh.ARRAY_NORMAL][candidate].distance_squared_to(original_targets[mode][Mesh.ARRAY_NORMAL][i])
				if error < best:
					best = error
					chosen = candidate
		check(chosen >= 0, "inventory lost original skirt vertex")
		if chosen < 0: continue
		pairs.append(Vector2i(i, chosen))
		for mode in Forms.REST_SHAPES.size():
			check(str(skirt.mesh.get_blend_shape_name(4 + mode)) == Forms.REST_SHAPES[mode], "inventory rest shape names")
			check(targets[4 + mode][Mesh.ARRAY_VERTEX][chosen].distance_to(original_targets[mode][Mesh.ARRAY_VERTEX][i]) < EPS, "inventory source rest position changed")
			check(targets[4 + mode][Mesh.ARRAY_NORMAL][chosen].distance_to(original_targets[mode][Mesh.ARRAY_NORMAL][i]) < EPS, "inventory source rest normal changed")
	for mode in Forms.REST_SHAPES.size() + 1:
		var nap := mode > 0
		var nap_weights := Vector4(.1, .2, .3, .4) if mode == 5 else Vector4.ZERO
		if mode > 0 and mode < 5: nap_weights[mode - 1] = 1
		var amount := .65 if mode == 5 else 1.0
		for doll in [customer, source]:
			doll.rig.animate(0, 0, "idle", 0)
			doll.rig.pose_rest("nap" if nap else "sit", amount, 0, nap_weights)
		customer.body_contact.update()
		item.update_attachment()
		var expected := PackedFloat32Array([0, 0, 0, 0, 0])
		if nap:
			for variant in 4: expected[variant + 1] = nap_weights[variant] * amount
		else:
			expected[0] = amount
		check_weights(item, expected, "worn pose %d" % mode)
		var posed: PackedVector3Array = customer.rig.deformed_vertices(skirt)
		var reference: PackedVector3Array = source.rig.deformed_vertices(source_skirt)
		for pair in pairs:
			check(posed[pair.y].distance_to(reference[pair.x]) < EPS, "inventory posed skirt differs from accepted source")
		for form in ["Folded", "Hanging"]:
			item.set_presentation(form)
			item.update_attachment()
			check_weights(item, PackedFloat32Array([0, 0, 0, 0, 0]), form + " retained rest weights")
			item.set_presentation("Worn")
			item.update_attachment()
			check_weights(item, expected, form + " round trip")
	customer.rig.animate(0, 0, "idle", 0)
	item.update_attachment()
	check_weights(item, PackedFloat32Array([0, 0, 0, 0, 0]), "idle reset")
	var state_wearer := StateWearer.new()
	item._sync_rest_shapes(state_wearer)
	check_weights(item, PackedFloat32Array([0, .05, .1, .15, .2]), "rest state fallback")
	state_wearer.rest_mode = "sit"
	item._sync_rest_shapes(state_wearer)
	check_weights(item, PackedFloat32Array([.5, 0, 0, 0, 0]), "sit state fallback")
	state_wearer.free()
	check(customer.take_off(item), "take off")
	check_weights(item, PackedFloat32Array([0, 0, 0, 0, 0]), "carried reset")
	item.place("rack", Transform3D.IDENTITY)
	check_weights(item, PackedFloat32Array([0, 0, 0, 0, 0]), "rack reset")
	for part in item.parts:
		check(mesh_bytes(part.mesh) == snapshots[part], "fold/hang mutated inventory mesh targets")
	check(mesh_bytes(source_skirt.mesh) == source_before, "catalog source mutated")
	for part in body_before:
		check(mesh_bytes(part.mesh) == body_before[part], "accepted body mutated")
	stock.free()
	completed += 1


func _run() -> void:
	for relative in [false, true]:
		for skinned in [false, true]: test_subdivision(relative, skinned)
	for style in [0, 1]: test_inventory(style)
	check(completed == 6, "Not all test cases completed")
	print("GARMENT_INVENTORY_REST_TEST checks=", checks, " failures=", failures.size(), " ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
