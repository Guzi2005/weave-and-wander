extends SceneTree

const GameScene = preload("res://main.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	if is_instance_valid(game._production.actor): game._production.suspend(game._production.actor)
	var inventory: Node3D = game._inventory
	var customer: Node3D = game.customers[0]
	var ledger: RefCounted = inventory.materials
	for index in 6:
		for old_item in inventory.slots[index]: inventory._store(old_item)
		inventory.slots[index].clear()
		inventory._sync_slot(index)
	# Remove the startup reservation, without consuming any stock.
	if not game._production.order.is_empty(): ledger.cancel(game._production.order.id)
	game._production.order = {}
	var panel: PanelContainer = game._production_panel
	panel.style_choice.select(0)
	panel.style_choice.item_selected.emit(0)
	panel.fabric_choice.select(1)
	panel.fabric_choice.item_selected.emit(1)
	check(game._production.selected_style == 0 and game._production.selected_fabric == "rose_check","UI selection not connected to production")
	check(panel.make_button.text == "安排一件连衣裙","UI action names wrong style")
	var ui_order: Dictionary = ledger.reserve("rose_check","thread_blue",1.0,0)
	game._production.order = ui_order
	game._production.selected_style = 5
	panel.refresh()
	check(panel.style_choice.disabled and panel.style_choice.selected == 0,"active order not locked to snapshot")
	ledger.cancel(ui_order.id)
	game._production.order = {}
	panel.refresh()
	check(not panel.style_choice.disabled and panel.style_choice.selected == 5,"next selection did not unlock")
	var fabrics := ["rose_check","gold_stripe","sage_linen","stock_blue_check","cream_roll","stock_teal_stripe"]
	for index in 4:
		var style: int = [10,11,12,13][index]
		var thread_id: String = ledger.thread_batches[index].id
		var order: Dictionary = ledger.reserve(fabrics[index],thread_id,1.0,style)
		check(not order.is_empty(),"reservation failed style %d" % style)
		if order.is_empty(): continue
		check(ledger.cut(order.id) and ledger.advance_sewing(order.id,1.0),"sewing failed")
		var item: Node3D = inventory.create_from_work_order(order)
		check(item != null,"output missing")
		if item == null: continue
		check(ledger.complete(order.id,item.item_id),"completion failed")
		inventory.store_produced(item,game._production.output_bin)
		check(item.presentation == "Folded" and item.visible,"stored item hidden or not folded")
		# Exercise the actual display mount / customer attachment operations.
		inventory._place_on_slot(item,index)
		check(item.presentation == "Hanging","display did not hang garment")
		check(item.reserve(customer) and item.carry(customer),"customer cannot carry made garment")
		inventory.slots[index].erase(item)
		inventory._sync_slot(index)
		check(item.wear(customer),"customer cannot wear made garment")
		item.update_attachment()
		check(item.presentation == "Worn" and item.definition.outfit_style == style,"wear changed garment style")
		for part in item.parts:
			if preload("res://scripts/garment_definition.gd").is_button(part): continue
			var mat: ShaderMaterial = part.material_override
			check(mat.get_shader_parameter("pigment") == order.material_snapshot.pigment,"wear lost pigment")
			check(int(mat.get_shader_parameter("pattern")) == int(order.material_snapshot.pattern_code),"wear lost pattern")
		inventory.service_authorizer = func() -> bool: return true
		var transaction_count: int = inventory.transactions.size()
		check(inventory.checkout(item,customer) == item.definition.price,"checkout price incorrect")
		check(inventory.transactions.size() == transaction_count + 1,"checkout transaction missing")
		check(inventory.checkout(item,customer) == 0,"duplicate checkout charged twice")
		item.collect()
		check(item.paid and not item.visible,"purchased garment returned to display")
	print("BASIC_GARMENT_SALES_TEST styles=4 failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
