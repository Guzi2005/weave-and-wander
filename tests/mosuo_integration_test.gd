extends SceneTree

const Definition = preload("res://scripts/garment_definition.gd")
const Garment = preload("res://scripts/garment_item.gd")
const Customer = preload("res://scripts/customer_doll.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var stock := Node3D.new()
	root.add_child(stock)
	var wearer := Customer.new()
	root.add_child(wearer)
	wearer.customer_id = "mosuo-test-wearer"
	wearer.configure({"outfit":0,"palette":0})
	var suit: Array[Node3D] = []
	for style in 17:
		if style == 9: continue # Flower is built through accessory_kind, not an independent outfit.
		var definition: Resource = Definition.create(style, 2)
		check(definition.design_id == Definition.DESIGN_IDS[style],"Design ID mismatch for %d" % style)
		var item := Garment.new()
		item.item_id = "test-%d" % style
		item.definition = definition
		stock.add_child(item)
		item.build()
		check(not item.parts.is_empty(),"Empty item for style %d" % style)
		check(item.rest_bounds.size.length() > .01,"Empty bounds for style %d" % style)
		if style < 14:
			check(not definition.is_mosuo_photo_set(),"Legacy style changed collection")
			item.free()
			continue
		suit.append(item)
		check(definition.collection_id == "mosuo_photo_001","Missing suite membership")
		check(definition.wiki_record_id == "WW-MOS-001-C%02d" % (style - 13),"Wrong component record")
		check(definition.source_record_id == "WW-MOS-001","Missing source record")
		check(definition.display_name().contains("照片001套装"),"Suite not visible in item name")
		for part in item.parts:
			check(Definition.part_slot(part) in definition.slots(),"Wrong mesh extracted into garment")
			check(str(part.name).begins_with("Mosuo"),"Generic body leaked into photo garment")
			check(part.skin != null and part.get_node(part.skeleton) == item.skeleton,"Broken garment skin")
		for form in ["Worn","Hanging","Folded"]:
			item.set_presentation(form)
			check(item.presentation == ("Worn" if style == 14 else form),"Wrong presentation")
		check(item.reserve(wearer),"Cannot reserve garment")
		check(wearer.carry_item(item),"Cannot carry garment")
		check(wearer.put_on(item),"Cannot wear garment")
	check(suit[0].parts.any(func(p: MeshInstance3D) -> bool: return str(p.name) == "MosuoBeadStrands"),"Purple beads missing from headwear")
	check(suit[0].definition.is_hat(),"Headwear not using hat display pipeline")
	check(suit[2].definition.long_bottom(),"Long skirt not using long-garment gait")
	for a in suit:
		for b in suit:
			check(a.definition.compatible(b.definition) == (a != b),"Suite slot compatibility wrong")
	wearer.rig.animate(1.2,1.0,"idle",1.0)
	for item in suit:
		item.update_attachment()
		for bone in item.skeleton.get_bone_count():
			check(item.skeleton.get_bone_pose(bone).is_equal_approx(wearer.rig.skeleton.get_bone_pose(bone)),"Worn animation not copied")
	var shoe_count := 0
	for part in wearer.rig.meshes:
		if str(part.name) in ["ShoeUpper","FlatSole"]:
			shoe_count += 1
			check(part.get_meta("culture_attribution","unexpected") == "","Generic shoe gained cultural attribution")
			check(part.get_meta("wiki_record_id","") == "WW-GEN-001","Generic shoe missing independent record")
	check(shoe_count == 4,"Shoe pair missing")
	check(wearer.take_off(),"Cannot remove suite")
	for item in suit: item.collect()
	stock.free()
	wearer.free()
	print("MOSUO_INTEGRATION_TEST failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
