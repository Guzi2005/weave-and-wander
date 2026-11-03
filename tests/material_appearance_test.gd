extends SceneTree

const Appearance := preload("res://scripts/material_appearance.gd")
const Inventory := preload("res://scripts/shop_inventory.gd")
const Package := preload("res://components/material_package.gd")
const Flow := preload("res://scripts/production_flow.gd")

var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value and message not in errors:
		errors.append(message)
		push_error(message)


func _run() -> void:
	test_describe()
	test_make_material()
	test_chain("rose_check", "thread_rose", Color("bb7986"), 2, "cloth.check.v1", false)
	test_chain("gold_stripe", "thread_cream", Color("d2ae66"), 1, "cloth.stripe.v1", true)
	test_chain("opening_cloth", "thread_blue", Color("779ab1"), 0, "cloth.plain.v1", false)
	print("MATERIAL_APPEARANCE_TEST failures=", errors.size())
	quit(0 if errors.is_empty() else 1)


func test_describe() -> void:
	var described: Dictionary = Appearance.describe({"pigment": Color("bb7986"), "pattern": "check", "material": "cotton", "name": "蔷薇格纹棉布"})
	check(int(described.get("pattern_code", -1)) == 2, "describe lost pattern string mapping")
	check(str(described.get("pattern", "")) == "check" and str(described.get("pattern_id", "")) == "cloth.check.v1", "describe check id wrong")
	check(is_equal_approx(float(described.get("pattern_scale", 0.0)), 12.0), "describe default pattern_scale wrong")
	check(int(described.get("pattern_revision", 0)) == 1, "describe default pattern_revision wrong")
	check(described.get("source_ids") == ["procedural_cloth_v1"], "describe default source_ids wrong")
	check(str(described.get("material", "")) == "cotton" and str(described.get("name", "")) == "蔷薇格纹棉布", "describe dropped existing fields")
	var from_code: Dictionary = Appearance.describe({"pattern_code": 1})
	check(str(from_code.get("pattern", "")) == "stripe" and str(from_code.get("pattern_id", "")) == "cloth.stripe.v1", "describe code-only mapping wrong")
	var plain: Dictionary = Appearance.describe({})
	check(int(plain.get("pattern_code", -1)) == 0 and str(plain.get("pattern_id", "")) == "cloth.plain.v1", "describe empty input not plain")
	check(plain.get("pigment") == Color("779ab1") and str(plain.get("material", "")) == "cotton", "describe defaults wrong")
	var invalid: Dictionary = Appearance.describe({"pattern_code": 9, "pattern_scale": -3.0})
	check(int(invalid.get("pattern_code", -1)) == 0 and is_equal_approx(float(invalid.get("pattern_scale", 0.0)), 12.0), "describe did not repair invalid pattern fields")
	var source := {"pigment": Color("d2ae66"), "source_ids": ["mill_a"]}
	var copy: Dictionary = Appearance.describe(source)
	copy["pigment"] = Color.BLACK
	(copy["source_ids"] as Array).append("extra")
	check(source.pigment == Color("d2ae66") and (source["source_ids"] as Array).size() == 1, "describe did not deep copy")
	check(copy["source_ids"] == ["mill_a", "extra"], "describe overwrote existing source_ids")


func test_make_material() -> void:
	var linen := Appearance.make_material({"material": "linen", "pigment": Color("8ba28a")})
	check(is_equal_approx(float(linen.get_shader_parameter("weave_scale")), 125.0), "linen weave wrong")
	var wool := Appearance.make_material({"material": "wool"})
	check(is_equal_approx(float(wool.get_shader_parameter("weave_scale")), 75.0) and is_equal_approx(float(wool.get_shader_parameter("fiber_strength")), 0.09), "wool params wrong")
	var silk := Appearance.make_material({"material": "silk"})
	check(is_equal_approx(float(silk.get_shader_parameter("roughness")), 0.65), "silk roughness wrong")
	var cotton := Appearance.make_material({"material": "cotton"})
	check(is_equal_approx(float(cotton.get_shader_parameter("roughness")), 0.94) and is_equal_approx(float(cotton.get_shader_parameter("weave_scale")), 180.0) and is_equal_approx(float(cotton.get_shader_parameter("fiber_strength")), 0.055), "cotton params wrong")
	check(cotton.get_shader_parameter("use_material_uv") == null, "uv mode leaked into positional material")
	var uv := Appearance.make_material({}, true, Vector2(2.0, 1.3))
	check(uv.get_shader_parameter("use_material_uv") == true and uv.get_shader_parameter("uv_metres") == Vector2(2.0, 1.3), "uv parameters not applied")


func test_chain(fabric_id: String, thread_id: String, pigment: Color, code: int, pattern_id: String, mutate_after_reserve: bool) -> void:
	var inventory: Node3D = Inventory.new()
	root.add_child(inventory)
	var ledger: RefCounted = inventory.materials
	var record: Dictionary = ledger.fabric(fabric_id)
	check(not record.is_empty(), fabric_id + " missing from opening stock")
	if record.is_empty():
		inventory.free()
		return
	check(str(record.get("id", "")) == fabric_id, fabric_id + " normalization lost record identity")
	check(str(record.get("pattern_id", "")) == pattern_id, fabric_id + " ledger pattern_id wrong")
	check(is_equal_approx(float(record.get("pattern_scale", 0.0)), 12.0) and int(record.get("pattern_revision", 0)) == 1, fabric_id + " ledger scale/revision wrong")
	check(record.get("source_ids") == ["procedural_cloth_v1"], fabric_id + " ledger provenance missing")
	var meters_before := float(record.get("meters", 0.0))

	var package := Package.new()
	root.add_child(package)
	package.configure(record, "book")
	_check_cloth(package.cloth_material, pigment, code, fabric_id + " package")
	package.free()

	var flow := Flow.new()
	_check_cloth(flow.cloth_material(record), pigment, code, fabric_id + " helper")
	flow.free()

	var order: Dictionary = ledger.reserve(fabric_id, thread_id)
	check(not order.is_empty(), fabric_id + " reservation failed")
	if order.is_empty():
		inventory.free()
		return
	var snapshot: Dictionary = order.material_snapshot
	check(snapshot.get("source_ids") == ["procedural_cloth_v1"] and str(snapshot.get("pattern_id", "")) == pattern_id, fabric_id + " snapshot lost provenance")
	if mutate_after_reserve:
		record.pigment = Color(1.0, 0.0, 0.0)
		record.pattern_code = 2 if code != 2 else 0
		check(ledger.fabric(fabric_id).get("pigment") == Color(1.0, 0.0, 0.0), fabric_id + " source mutation did not take")
	check(ledger.cut(order.id), fabric_id + " cut failed")
	check(ledger.advance_sewing(order.id, 1.0), fabric_id + " sewing failed")

	var remnant: Dictionary = ledger.remnants.back() if not ledger.remnants.is_empty() else {}
	check(not remnant.is_empty(), fabric_id + " remnant missing")
	check(str(remnant.get("source_fabric_id", "")) == fabric_id and remnant.get("source_ids") == ["procedural_cloth_v1"], fabric_id + " remnant lost provenance")
	check(not str(remnant.get("pattern_id", "")).is_empty(), fabric_id + " remnant pattern_id missing")
	if not mutate_after_reserve:
		check(str(remnant.get("pattern_id", "")) == pattern_id, fabric_id + " remnant pattern_id wrong")
		check(remnant.get("pigment") == pigment and int(remnant.get("pattern_code", -1)) == code, fabric_id + " remnant lost appearance")
		check(is_equal_approx(float(remnant.get("pattern_scale", 0.0)), 12.0), fabric_id + " remnant lost pattern scale")

	var item: Node3D = inventory.create_from_work_order(order)
	check(item != null, fabric_id + " garment not created")
	if item == null:
		inventory.free()
		return
	var data: Dictionary = item.definition.material_data
	check(data.get("pigment") == pigment, fabric_id + " garment repainted from mutated source" if mutate_after_reserve else fabric_id + " garment lost pigment")
	check(int(data.get("pattern_code", -1)) == code and str(data.get("pattern", "")) == str(Appearance.PATTERN_NAMES[code]), fabric_id + " garment lost pattern")
	check(str(data.get("pattern_id", "")) == pattern_id and int(data.get("pattern_revision", 0)) == 1, fabric_id + " garment lost pattern identity")
	check(is_equal_approx(float(data.get("pattern_scale", 0.0)), 12.0), fabric_id + " garment lost pattern scale")
	check(data.get("source_ids") == ["procedural_cloth_v1"], fabric_id + " garment lost provenance")
	check(is_equal_approx(float(ledger.fabric(fabric_id).get("meters", 0.0)), meters_before - float(order.estimate.cut_m)), fabric_id + " normalization touched stock")

	var expected_uv := Vector2(2.08, item.hang_height - item.bottom_height)
	for index in item.parts.size():
		var worn := item.worn_materials[index] as ShaderMaterial
		var prop := item.prop_materials[index] as ShaderMaterial
		check(worn != null and worn == prop, "%s part %d worn/folded materials diverge" % [fabric_id, index])
		_check_cloth(worn, pigment, code, "%s part %d" % [fabric_id, index])
		check(worn.get_shader_parameter("use_material_uv") == true, "%s part %d lost material uv mode" % [fabric_id, index])
		check((worn.get_shader_parameter("uv_metres") as Vector2).distance_to(expected_uv) < 0.001, "%s part %d uv metre scale wrong" % [fabric_id, index])
	# Worn and folded presentations resolve to the same propagated material.
	item._set_worn_materials(true)
	for index in item.parts.size():
		check(item.parts[index].material_override == item.worn_materials[index], "%s part %d worn form not applied" % [fabric_id, index])
	item._set_worn_materials(false)
	for index in item.parts.size():
		check(item.parts[index].material_override == item.prop_materials[index], "%s part %d folded form not applied" % [fabric_id, index])
	inventory.free()


func _check_cloth(mat: ShaderMaterial, pigment: Color, code: int, label: String) -> void:
	check(mat != null and mat.shader == Appearance.SHADER, label + " wrong shader")
	check(mat.get_shader_parameter("pigment") == pigment, label + " pigment mismatch")
	check(is_equal_approx(float(mat.get_shader_parameter("pattern")), float(code)), label + " pattern mismatch")
	check(is_equal_approx(float(mat.get_shader_parameter("pattern_scale")), 12.0), label + " pattern_scale mismatch")
	check(is_equal_approx(float(mat.get_shader_parameter("weave_scale")), 180.0), label + " weave mismatch")
	check(is_equal_approx(float(mat.get_shader_parameter("roughness")), 0.94), label + " roughness mismatch")
