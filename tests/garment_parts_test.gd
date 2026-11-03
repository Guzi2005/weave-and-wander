extends SceneTree

const Inventory = preload("res://scripts/shop_inventory.gd")
const Definition = preload("res://scripts/garment_definition.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func make_item(inventory: Node3D, style: int, fabric: String, thread_id: String) -> Node3D:
	var order: Dictionary = inventory.materials.reserve(fabric,thread_id,1.0,style)
	check(not order.is_empty(),"recipe reservation failed")
	if order.is_empty(): return null
	check(inventory.materials.cut(order.id),"cut failed")
	check(inventory.materials.advance_sewing(order.id,1.0),"sew failed")
	var item: Node3D = inventory.create_from_work_order(order)
	check(inventory.materials.complete(order.id,item.item_id),"complete failed")
	return item

func _run() -> void:
	var inventory := Inventory.new()
	root.add_child(inventory)
	var support := Node3D.new()
	root.add_child(support)
	var dress := make_item(inventory,0,"rose_check","thread_rose")
	inventory.store_produced(dress,support)
	check(not dress.parts.any(func(p: MeshInstance3D) -> bool: return Definition.is_flower(p)),"dress includes free flower")
	var button_colors := {}
	for part in dress.parts:
		if Definition.is_button(part): button_colors[str(part.name)] = part.material_override.get_shader_parameter("pigment")
	check(not button_colors.is_empty(),"dress has no buttons")
	dress.apply_material_data(inventory.materials.fabric("stock_teal_stripe"))
	for part in dress.parts:
		if Definition.is_button(part):
			check(part.material_override.get_shader_parameter("pigment") == button_colors[str(part.name)],"body dye recolored button")
	var before: float = inventory.materials.fabric("cream_roll").meters
	var flower := make_item(inventory,9,"cream_roll","thread_cream")
	inventory.store_produced(flower,support)
	check(flower.parts.size() == 6,"flower must contain five petals and one center")
	check(flower.location == "accessory","flower not independent inventory")
	check(inventory.materials.fabric("cream_roll").meters < before,"flower did not consume separate fabric")
	check(inventory.attach_flower_to(flower,dress.item_id),"cannot attach finished flower")
	check(not inventory.attach_flower_to(flower,dress.item_id),"flower applied twice")
	check(flower.location == "attached" and not flower.visible,"flower double-counted as loose stock")
	check(dress.definition.flower_material_data.pigment == inventory.materials.fabric("cream_roll").pigment,"flower source lost")
	for form in ["Hanging","Folded","Worn"]:
		dress.set_presentation(form)
		dress.apply_material_data(inventory.materials.fabric("rose_check"))
		for part in dress.parts:
			if Definition.is_flower(part):
				check(part.material_override.get_shader_parameter("pigment") == inventory.materials.fabric("cream_roll").pigment,"flower follows body dye")
				check(part.get_node(part.skeleton) == dress.skeleton,"flower not bound to target skeleton")
	for style in [0,5]:
		var skirt := make_item(inventory,style,"sage_linen","thread_sage")
		for part in skirt.parts:
			check(str(part.get_meta("semantic","")) not in ["legL","legR"],"skirt includes a leg/calf/trouser")
	check(inventory.materials.jobs.size() == 4,"body and accessory not separate orders")
	var vest := make_item(inventory,2,"stock_teal_stripe","thread_blue")
	for form in ["Hanging","Folded","Worn"]:
		vest.set_presentation(form)
		var worn_count := 0
		var prop_count := 0
		for part in vest.parts:
			var role: String = part.get_meta("presentation_only","")
			if role == "worn":
				worn_count += 1
				check(part.visible == (form == "Worn"),"worn waistcoat leaks into prop display")
			if role == "prop":
				prop_count += 1
				check(part.visible == (form != "Worn"),"armhole prop missing from standalone display")
		check(worn_count == 2 and prop_count == 2,"waistcoat does not have paired body/binding representations")
	print("GARMENT_PARTS_TEST failures=",failures.size())
	inventory.free()
	support.free()
	quit(0 if failures.is_empty() else 1)
