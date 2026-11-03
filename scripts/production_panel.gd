extends PanelContainer

const RECIPES = preload("res://scripts/garment_recipes.gd")

var game: Node
var flow: Node3D
var style_choice: OptionButton
var fabric_choice: OptionButton
var thread_choice: OptionButton
var estimate_label: Label
var progress_label: Label
var make_button: Button
var flower_box: VBoxContainer
var flower_target: OptionButton
var loose_flower: OptionButton
var attach_button: Button
var skirt_controls: HBoxContainer
var skirt_length: SpinBox
var top_controls: HBoxContainer
var top_length: SpinBox
var _elapsed := 0.0

func setup(controller: Node) -> void:
	game = controller
	flow = game._production
	name = "ProductionPanel"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -326
	offset_right = -20
	offset_top = 82
	offset_bottom = 428
	var style: StyleBoxFlat = game._panel_style(Color("f2ead9"),Color("8ba28a"),1,8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	add_child(box)
	var title := Label.new()
	title.text = "成衣与小物制作"
	title.add_theme_color_override("font_color",Color("445f56"))
	title.add_theme_font_size_override("font_size",20)
	box.add_child(title)
	var stock_note := Label.new()
	stock_note.text = "实物收纳 · 布料 %d 匹 / 缝线 %d 轴 / 毛线 %d 团" % [flow.ledger.fabric_batches.size(),flow.ledger.thread_batches.size(),flow.ledger.yarn_batches.size()]
	stock_note.add_theme_font_size_override("font_size",12)
	stock_note.add_theme_color_override("font_color",Color("66554c"))
	box.add_child(stock_note)
	style_choice = OptionButton.new()
	_style_choice(style_choice)
	box.add_child(style_choice)
	for outfit_style in RECIPES.PRODUCTION_STYLES:
		style_choice.add_item(RECIPES.style_name(outfit_style))
		style_choice.set_item_metadata(style_choice.item_count-1,outfit_style)
	style_choice.add_item("小物 · 胸花（单独选料）")
	style_choice.set_item_metadata(style_choice.item_count-1,RECIPES.FLOWER_STYLE)
	_select_by_metadata(style_choice,flow.selected_style)
	style_choice.item_selected.connect(func(index: int) -> void: flow.selected_style = int(style_choice.get_item_metadata(index)); refresh())
	skirt_controls = HBoxContainer.new()
	box.add_child(skirt_controls)
	var length_label := Label.new()
	length_label.text = "裙长（米）"
	length_label.add_theme_color_override("font_color",Color("66554c"))
	skirt_controls.add_child(length_label)
	skirt_length = SpinBox.new()
	skirt_length.min_value = .35
	skirt_length.max_value = 1.05
	skirt_length.step = .01
	skirt_length.value = flow.selected_skirt_length
	skirt_length.value_changed.connect(func(value: float) -> void: flow.selected_skirt_length = value; refresh())
	skirt_controls.add_child(skirt_length)
	top_controls = HBoxContainer.new()
	box.add_child(top_controls)
	var top_label := Label.new()
	top_label.text = "衣长（米）"
	top_label.add_theme_color_override("font_color",Color("66554c"))
	top_controls.add_child(top_label)
	top_length = SpinBox.new()
	top_length.min_value = .55
	top_length.max_value = 1.05
	top_length.step = .01
	top_length.value = flow.selected_garment_length
	top_length.value_changed.connect(func(value: float) -> void: flow.selected_garment_length = value; refresh())
	top_controls.add_child(top_length)
	fabric_choice = OptionButton.new()
	_style_choice(fabric_choice)
	box.add_child(fabric_choice)
	for record in flow.ledger.fabric_batches:
		if not flow.packages.has(record.id): continue
		fabric_choice.add_item(str(record.get("name",record.id)))
		fabric_choice.set_item_metadata(fabric_choice.item_count-1,record.id)
	fabric_choice.item_selected.connect(func(index: int) -> void: flow.selected_fabric = str(fabric_choice.get_item_metadata(index)); refresh())
	thread_choice = OptionButton.new()
	_style_choice(thread_choice)
	box.add_child(thread_choice)
	for record in flow.ledger.thread_batches:
		thread_choice.add_item(str(record.get("name",record.id)))
		thread_choice.set_item_metadata(thread_choice.item_count-1,record.id)
	thread_choice.item_selected.connect(func(index: int) -> void: flow.selected_thread = str(thread_choice.get_item_metadata(index)); refresh())
	flower_box = VBoxContainer.new()
	box.add_child(flower_box)
	flower_target = OptionButton.new()
	_style_choice(flower_target)
	flower_box.add_child(flower_target)
	flower_target.item_selected.connect(func(index: int) -> void: flow.selected_flower_target = str(flower_target.get_item_metadata(index)); refresh())
	loose_flower = OptionButton.new()
	_style_choice(loose_flower)
	flower_box.add_child(loose_flower)
	loose_flower.item_selected.connect(func(_index: int) -> void: refresh())
	attach_button = game._make_text_button("将库存胸花装到所选成衣",Vector2(270,32))
	flower_box.add_child(attach_button)
	attach_button.pressed.connect(func() -> void:
		for item in game._inventory.in_location("accessory"):
			if item.item_id == str(loose_flower.get_selected_metadata()):
				game._inventory.attach_flower_to(item,flow.selected_flower_target)
				break
		refresh())
	estimate_label = Label.new()
	estimate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	estimate_label.custom_minimum_size = Vector2(270,78)
	estimate_label.add_theme_color_override("font_color",Color("66554c"))
	box.add_child(estimate_label)
	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color",Color("446f65"))
	box.add_child(progress_label)
	make_button = game._make_text_button("安排一件%s" % RECIPES.style_name(flow.selected_style),Vector2(270,38))
	make_button.pressed.connect(_start)
	box.add_child(make_button)
	var catalog_button: Button = game._make_text_button("供应目录与队列",Vector2(270,32))
	catalog_button.tooltip_text = "保存配方、自动补货与生产队列"
	catalog_button.pressed.connect(func() -> void:
		game._order_queue_panel.visible = not game._order_queue_panel.visible
		if game._order_queue_panel.visible:
			hide()
			game._order_queue_panel.refresh())
	box.add_child(catalog_button)
	var auto := CheckButton.new()
	auto.text = "缺货时自动补制"
	auto.button_pressed = flow.auto_restock
	auto.add_theme_color_override("font_color",Color("66554c"))
	for state in ["font_pressed_color","font_hover_color","font_hover_pressed_color","font_focus_color"]:
		auto.add_theme_color_override(state,Color("66554c"))
	auto.toggled.connect(func(value: bool) -> void: flow.auto_restock = value)
	box.add_child(auto)
	var close_button: Button = game._make_text_button("收起",Vector2(270,30))
	close_button.pressed.connect(hide)
	box.add_child(close_button)
	refresh()
	hide()

func _style_choice(choice: OptionButton) -> void:
	choice.fit_to_longest_item = false
	choice.clip_text = true
	for state in ["font_color","font_disabled_color","font_hover_color","font_pressed_color","font_focus_color"]:
		choice.add_theme_color_override(state,Color("66554c"))
	for state in ["normal","hover","pressed","focus","disabled"]:
		var background := Color("e3dac8") if state == "disabled" else Color("fff9ed")
		var style: StyleBoxFlat = game._panel_style(background,Color("b9a68b"),1,5)
		style.content_margin_left = 10
		style.content_margin_right = 24
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		choice.add_theme_stylebox_override(state,style)
	var popup := choice.get_popup()
	popup.add_theme_color_override("font_color",Color("66554c"))
	popup.add_theme_color_override("font_hover_color",Color("304e45"))
	popup.add_theme_stylebox_override("panel",game._panel_style(Color("fff9ed"),Color("b9a68b"),1,5))
	popup.add_theme_stylebox_override("hover",game._panel_style(Color("dae5d7"),Color("8ba28a"),0,3))

func _select_by_metadata(choice: OptionButton, value: Variant) -> void:
	for index in choice.item_count:
		if choice.get_item_metadata(index) == value:
			choice.select(index)
			return

func _process(delta: float) -> void:
	_elapsed += delta
	if visible and _elapsed >= .15:
		_elapsed = 0
		refresh()

func refresh() -> void:
	# The editable recipe is the next order, never the in-flight material snapshot.
	var locked := false
	style_choice.disabled = locked
	fabric_choice.disabled = locked
	thread_choice.disabled = locked
	var outfit_style: int = int(flow.order.get("outfit_style",flow.selected_style)) if locked else flow.selected_style
	skirt_controls.visible = outfit_style == 12
	skirt_length.editable = not locked
	skirt_length.set_value_no_signal(float(flow.order.get("skirt_length",flow.selected_skirt_length)) if locked else flow.selected_skirt_length)
	top_controls.visible = outfit_style in [10,11,13]
	top_length.editable = not locked
	top_length.set_value_no_signal(float(flow.order.get("garment_length",flow.selected_garment_length)) if locked else flow.selected_garment_length)
	flower_box.visible = outfit_style == RECIPES.FLOWER_STYLE
	if flower_box.visible: _refresh_flowers(locked)
	_select_by_metadata(style_choice,outfit_style)
	var fabric_id: String = flow.order.fabric_id if locked else flow.selected_fabric
	var thread_id: String = flow.order.thread_id if locked else flow.selected_thread
	_select_by_metadata(fabric_choice,fabric_id)
	_select_by_metadata(thread_choice,thread_id)
	var plan: Dictionary = flow.order.estimate if locked else flow.ledger.estimate(flow.selected_fabric,flow.size_factor,flow.selected_style,flow.selected_skirt_length,flow.selected_garment_length)
	var fabric: Dictionary = flow.ledger.fabric(fabric_id)
	var thread: Dictionary = flow.ledger.thread(thread_id)
	if plan.get("ok",false):
		estimate_label.text = "余布 %.2f 米 · 余线 %.1f 米\n预计取布 %.2f 米 · 用线 %.1f 米\n可用余料 %.2f 米 · 损耗 %.2f 米" % [fabric.meters,thread.meters,plan.cut_m,plan.thread_m,plan.remnant_m,plan.waste_m]
	else:
		estimate_label.text = "所选材料不足，请选择另一匹布。"
	progress_label.text = flow.status_text()
	var style_name := RECIPES.style_name(outfit_style)
	make_button.text = "加入队列 · %s" % style_name
	make_button.disabled = fabric.is_empty() or thread.is_empty()
	size.y = get_combined_minimum_size().y


func _refresh_flowers(locked: bool) -> void:
	var target_entries: Array = [["","只制作胸花，单独入库"]]
	for item in game._inventory.flower_targets():
		target_entries.append([item.item_id,"装到："+item.definition.display_name()+" · "+item.item_id.trim_prefix("garment_")])
	_sync_entries(flower_target,target_entries)
	var target_id: String = str(flow.order.get("flower_target_id","")) if locked else flow.selected_flower_target
	if not locked and not target_entries.any(func(entry: Array) -> bool: return entry[0] == target_id):
		target_id = ""
		flow.selected_flower_target = ""
	_select_by_metadata(flower_target,target_id)
	flower_target.disabled = locked
	var entries: Array = [["","或选择已制好的胸花"]]
	for item in game._inventory.in_location("accessory"):
		entries.append([item.item_id,item.definition.display_name()+" · "+item.item_id.trim_prefix("garment_")])
	_sync_entries(loose_flower,entries)
	attach_button.disabled = locked or target_id.is_empty() or str(loose_flower.get_selected_metadata()).is_empty()
	loose_flower.disabled = locked


func _sync_entries(choice: OptionButton, entries: Array) -> void:
	if choice.get_meta("entries",[]) == entries: return
	var previous: String = str(choice.get_selected_metadata()) if choice.selected >= 0 else ""
	choice.clear()
	for entry in entries:
		choice.add_item(entry[1])
		choice.set_item_metadata(choice.item_count-1,entry[0])
	choice.set_meta("entries",entries.duplicate(true))
	_select_by_metadata(choice,previous)

func _start() -> void:
	var queued: Dictionary = game._supply_catalog.enqueue_current_recipe()
	if queued.is_empty():
		game._show_toast("配方无效，请先选择布料与缝线")
		return
	game._show_toast("已加入生产队列；当前制作不受影响")
	game._supply_catalog.tick(0.0)
	refresh()


func _resume_worker() -> void:
	var worker: Node3D
	for person in game.staff:
		if person.energy <= .25: continue
		var job: Dictionary = game._staff_jobs.get(person.get_instance_id(),{})
		if job.get("facility",-1) == game._facility_index("counter"): continue
		if worker == null or person.energy > worker.energy: worker = person
	if worker == null:
		game._show_toast("员工正在休息或接待，请稍后安排")
		return
	game._assign_staff(worker,game._facility_index("sewing"),true)
	game._switch_room("workshop")
	refresh()
