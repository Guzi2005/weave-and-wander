extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var inventory: Node3D = game._inventory
	var ledger: RefCounted = inventory.materials
	var customer: Node3D = game.customers[0]
	for existing in inventory.slots[0]: inventory._store(existing)
	inventory.slots[0].clear()
	inventory._sync_slot(0)
	if not game._production.order.is_empty(): ledger.cancel(game._production.order.id)
	game._production.order = {}
	for record in ledger.fabric_batches: record.meters = 50.0
	for record in ledger.thread_batches: record.meters = 500.0
	var short_plan: Dictionary = ledger.estimate("rose_check",1.0,12,.35)
	var long_plan: Dictionary = ledger.estimate("rose_check",1.0,12,1.05)
	check(short_plan.ok and long_plan.ok and long_plan.cut_m > short_plan.cut_m,"skirt length must change material consumption")
	for invalid in [.1,1.2,NAN,INF]:
		check(not ledger.estimate("rose_check",1.0,12,invalid).ok,"illegal skirt length accepted")
	for style in [10,11,12,13]:
		var order: Dictionary = ledger.reserve("rose_check","thread_rose",1.0,style,.45)
		check(not order.is_empty(),"cannot reserve basic style %d" % style)
		if order.is_empty(): continue
		ledger.estimate("rose_check",1.0,12,1.05)
		check(ledger.cut(order.id) and ledger.advance_sewing(order.id,1.0),"cannot consume basic recipe")
		var item: Node3D = inventory.create_from_work_order(order)
		check(item != null,"missing output")
		if item == null: continue
		check(not item.definition.is_hat(),"basic garment classified as hat")
		check(item.parts.size() > 0,"empty garment")
		if style == 12:
			check(is_equal_approx(item.definition.skirt_length,.45),"order length overwritten")
			check(absf(item.bottom_height-.85) < .01,"skirt mesh does not match order length")
		check(ledger.complete(order.id,item.item_id),"cannot complete basic recipe")
		for state in ["Folded","Hanging","Worn"]:
			item.set_presentation(state)
			for part in item.parts:
				check(not part.has_meta("everyday_skin") and not str(part.name).contains("Skin"),"wearer skin leaked into garment")
				check(part.material_override.get_shader_parameter("pigment") == order.material_snapshot.pigment,"garment lost pigment")
				check(part.material_override.get_shader_parameter("pattern") == 2,"garment lost check pattern")
		inventory._place_on_slot(item,0)
		check(item.reserve(customer) and customer.carry_item(item) and customer.put_on(item),"customer cannot wear basic style")
		var visible_skin := 0
		for part in customer.rig.meshes:
			if part.has_meta("everyday_skin") and part.visible: visible_skin += 1
		if style == 13:
			check(visible_skin == 0,"vest layers over the shirt; no skin overlay expected")
		else:
			check(visible_skin >= 2,"short garment leaves missing wearer limbs")
		customer.take_off(item)
		for part in customer.rig.meshes:
			if part.has_meta("everyday_skin"): check(not part.visible,"skin overlay not restored after takeoff")
		customer.garments.erase(item)
		inventory.slots[0].erase(item)
		inventory._store(item)
	# garment_length is a real order parameter: it scales the estimate, rides
	# the ledger snapshot and lands on the produced definition and mesh.
	var short_top: Dictionary = ledger.estimate("rose_check",1.0,13,.70,.55)
	var long_top: Dictionary = ledger.estimate("rose_check",1.0,13,.70,1.05)
	check(short_top.ok and long_top.ok and long_top.cut_m > short_top.cut_m,"garment length must change material consumption")
	for invalid in [.3,1.2,NAN,INF]:
		check(not ledger.estimate("rose_check",1.0,13,.70,invalid).ok,"illegal garment length accepted")
	for bad_style in [0,1]:
		var untouched: Dictionary = ledger.estimate("rose_check",1.0,bad_style,.70,.55)
		var baseline: Dictionary = ledger.estimate("rose_check",1.0,bad_style,.70,1.05)
		check(is_equal_approx(untouched.cut_m,baseline.cut_m),"garment length must not affect non-top styles")
	var vest_order: Dictionary = ledger.reserve("rose_check","thread_rose",1.0,13,.70,.62)
	check(not vest_order.is_empty(),"cannot reserve vest with garment length")
	check(is_equal_approx(float(vest_order.get("garment_length",0.0)),.62),"order snapshot lost garment length")
	if not vest_order.is_empty():
		check(ledger.cut(vest_order.id) and ledger.advance_sewing(vest_order.id,1.0),"cannot consume vest recipe")
		var vest_item: Node3D = inventory.create_from_work_order(vest_order)
		check(vest_item != null,"missing vest output")
		if vest_item != null:
			check(is_equal_approx(vest_item.definition.garment_length,.62),"order garment length overwritten")
			check(absf(vest_item.bottom_height-1.28) < .01,"vest mesh does not match order length")
			check(vest_item.definition.slots() == ["outer"],"vest must occupy the outer slot")
			check(ledger.complete(vest_order.id,vest_item.item_id),"cannot complete vest recipe")
			inventory._store(vest_item)
	# A produced vest layers over a produced shirt on the customer.
	var shirt_order: Dictionary = ledger.reserve("sage_linen","thread_sage",1.0,10,.70,.80)
	var vest_order2: Dictionary = ledger.reserve("cream_roll","thread_cream",1.0,13,.70,.80)
	ledger.cut(shirt_order.id)
	ledger.advance_sewing(shirt_order.id,1.0)
	ledger.cut(vest_order2.id)
	ledger.advance_sewing(vest_order2.id,1.0)
	var shirt: Node3D = inventory.create_from_work_order(shirt_order)
	var vest: Node3D = inventory.create_from_work_order(vest_order2)
	check(shirt != null and vest != null,"layering outputs missing")
	if shirt != null and vest != null:
		check(shirt.definition.compatible(vest.definition) and vest.definition.compatible(shirt.definition),"shirt and vest must be layer-compatible")
		inventory._place_on_slot(shirt,0)
		inventory._place_on_slot(vest,0)
		check(shirt.slot == 0 and vest.slot == 0,"compatible shoulder garments must share a hanger")
		check(shirt.reserve(customer) and customer.carry_item(shirt) and customer.put_on(shirt),"customer cannot wear shirt")
		check(vest.reserve(customer) and customer.carry_item(vest) and customer.put_on(vest),"customer cannot layer vest over shirt")
		var shirt_visible := false
		var vest_visible := false
		for part in shirt.parts: shirt_visible = shirt_visible or part.visible
		for part in vest.parts: vest_visible = vest_visible or part.visible
		check(shirt_visible and vest_visible,"layered shirt and vest must both render")
		var shell_sleeves := 0
		for part in shirt.parts:
			if str(part.name) == "CubanShirt" and part.visible: shell_sleeves += 1
		check(shell_sleeves == 1,"vest must not hide the shirt (sleeves included)")
		for part in customer.rig.meshes:
			if str(part.name) in ["TailoredShell","OpenWaistcoat"]:
				check(not part.visible,"customer's own top/outer must yield to the worn layers")
		customer.take_off(vest)
		customer.take_off(shirt)
		for worn in [vest,shirt]:
			customer.garments.erase(worn)
			inventory.slots[0].erase(worn)
			inventory._store(worn)
		ledger.complete(shirt_order.id,shirt.item_id)
		ledger.complete(vest_order2.id,vest.item_id)
	# Selection uses stable style metadata, including non-contiguous style IDs.
	var panel: PanelContainer = game._production_panel
	for index in panel.style_choice.item_count:
		if panel.style_choice.get_item_metadata(index) == 12:
			panel.style_choice.select(index)
			panel.style_choice.item_selected.emit(index)
	panel.skirt_length.value = .56
	check(game._production.selected_style == 12 and is_equal_approx(game._production.selected_skirt_length,.56),"skirt UI disconnected")
	game._production.order = ledger.reserve("rose_check","thread_rose",1.0,12,.56)
	game._production.selected_skirt_length = .98
	panel.refresh()
	check(not panel.skirt_length.editable and is_equal_approx(panel.skirt_length.value,.56),"locked UI lost order length")
	ledger.cancel(game._production.order.id)
	game._production.order = {}
	for index in panel.style_choice.item_count:
		if panel.style_choice.get_item_metadata(index) == 13:
			panel.style_choice.select(index)
			panel.style_choice.item_selected.emit(index)
	panel.top_length.value = .62
	check(game._production.selected_style == 13 and is_equal_approx(game._production.selected_garment_length,.62),"garment length UI disconnected")
	panel.refresh()
	check(panel.top_controls.visible,"top length control must show for the vest style")
	check(not panel.skirt_controls.visible,"skirt length control must hide for the vest style")
	game._production.order = ledger.reserve("rose_check","thread_rose",1.0,13,.70,.62)
	game._production.selected_garment_length = .99
	panel.refresh()
	check(not panel.top_length.editable and is_equal_approx(panel.top_length.value,.62),"locked UI lost order garment length")
	print("BASIC_GARMENT_PRODUCTION_TEST failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
