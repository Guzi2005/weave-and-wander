extends PanelContainer

## Supply catalog + production queue panel. Rows are only rebuilt when the
## underlying list structure changes, so focused SpinBox/CheckButton controls
## are never recreated under the user's pointer.

const RECIPES = preload("res://scripts/garment_recipes.gd")

var game: Node
var catalog: Node
var tabs: TabContainer
var catalog_list: VBoxContainer
var queue_list: VBoxContainer
var queue_summary: Label
var hint_label: Label
var random_auto_switch: CheckButton
var _elapsed := 0.0
var _entries_rev := -1
var _queue_sig := ""


func setup(controller: Node) -> void:
	game = controller
	catalog = game._supply_catalog
	name = "OrderQueuePanel"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	anchor_bottom = 1.0
	offset_left = -372
	offset_right = -20
	offset_top = 82
	offset_bottom = -20
	var style: StyleBoxFlat = game._panel_style(Color("f2ead9"),Color("8ba28a"),1,8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(box)
	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	var title := Label.new()
	title.text = "供应目录与生产队列"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color",Color("445f56"))
	title.add_theme_font_size_override("font_size",20)
	title_row.add_child(title)
	var close_button: Button = game._make_text_button("收起",Vector2(72,30))
	close_button.pressed.connect(hide)
	title_row.add_child(close_button)
	tabs = TabContainer.new()
	tabs.add_theme_stylebox_override("panel", game._panel_style(Color("f2ead9"), Color("c3b091"), 1, 4))
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)

	var catalog_page := VBoxContainer.new()
	catalog_page.name = "供应目录"
	catalog_page.add_theme_constant_override("separation",6)
	tabs.add_child(catalog_page)
	var save_button: Button = game._make_text_button("将当前配方存入目录",Vector2(312,34))
	save_button.tooltip_text = "把制作面板当前选择的款式、布料、缝线与长度存为一条目录配方"
	save_button.pressed.connect(func() -> void:
		var entry: Dictionary = catalog.capture_current_recipe()
		if entry.is_empty():
			game._show_toast("当前配方无效，未存入目录")
		else:
			game._show_toast("已存入目录：%s（自动补货默认关闭）" % entry.name))
	catalog_page.add_child(save_button)
	hint_label = Label.new()
	hint_label.text = "新配方默认不自动补货；+1 立即排一件"
	hint_label.add_theme_font_size_override("font_size",12)
	hint_label.add_theme_color_override("font_color",Color("66554c"))
	catalog_page.add_child(hint_label)
	var catalog_scroll := ScrollContainer.new()
	catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog_page.add_child(catalog_scroll)
	catalog_list = VBoxContainer.new()
	catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_list.add_theme_constant_override("separation",6)
	catalog_scroll.add_child(catalog_list)

	var queue_page := VBoxContainer.new()
	queue_page.name = "生产队列"
	queue_page.add_theme_constant_override("separation",6)
	tabs.add_child(queue_page)
	queue_summary = Label.new()
	queue_summary.add_theme_font_size_override("font_size",13)
	queue_summary.add_theme_color_override("font_color",Color("446f65"))
	queue_page.add_child(queue_summary)
	random_auto_switch = _switch("随机自动排单", catalog.random_auto_enabled)
	random_auto_switch.tooltip_text = "排队为 0 时，随机组合现有布料、缝线和全部可制作版型（含胸花），长度随机、尺码沿用当前设置；耗材足够才排单 +1。无需存入目录；制作中的订单不算排队，目标补货优先。"
	random_auto_switch.toggled.connect(func(value: bool) -> void: catalog.set_random_auto_enabled(value))
	queue_page.add_child(random_auto_switch)
	var random_hint := Label.new()
	random_hint.text = "排队为 0：随机组合布料 × 缝线 × 版型 +1"
	random_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	random_hint.add_theme_font_size_override("font_size",12)
	random_hint.add_theme_color_override("font_color",Color("66554c"))
	queue_page.add_child(random_hint)
	var queue_scroll := ScrollContainer.new()
	queue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_page.add_child(queue_scroll)
	queue_list = VBoxContainer.new()
	queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_list.add_theme_constant_override("separation",6)
	queue_scroll.add_child(queue_list)
	refresh()
	hide()


func _process(delta: float) -> void:
	_elapsed += delta
	if visible and _elapsed >= .2:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if catalog == null:
		return
	if catalog._entries_rev != _entries_rev:
		_rebuild_catalog()
	else:
		for row in catalog_list.get_children():
			var entry: Dictionary = catalog.find_entry(str(row.get_meta("entry_id","")))
			if entry.is_empty():
				continue
			row.get_meta("stock_label").text = _stock_text(entry)
	var sig := ""
	for job in catalog.queue:
		sig += "%s:%s:%s:%s;" % [job.id,job.state,job.blocked_reason,job.work_order_id]
	if sig != _queue_sig:
		_rebuild_queue(sig)
	else:
		for row in queue_list.get_children():
			var job: Dictionary = catalog.find_job(str(row.get_meta("job_id","")))
			if not job.is_empty():
				row.get_meta("state_label").text = catalog.state_text(job)
	_update_summary()


func _update_summary() -> void:
	random_auto_switch.set_pressed_no_signal(catalog.random_auto_enabled)
	var counts := {"waiting-material":0,"dyeing":0,"ready":0,"producing":0,"completed":0}
	for job in catalog.queue:
		counts[job.state] = int(counts.get(job.state,0))+1
	queue_summary.text = "待料 %d · 染色 %d · 待缝 %d · 缝制 %d · 完成 %d" % [counts["waiting-material"],counts["dyeing"],counts["ready"],counts["producing"],counts["completed"]]


func _rebuild_catalog() -> void:
	_entries_rev = catalog._entries_rev
	for child in catalog_list.get_children():
		child.free()
	for entry in catalog.entries:
		catalog_list.add_child(_catalog_row(entry))


func _rebuild_queue(sig: String) -> void:
	_queue_sig = sig
	for child in queue_list.get_children():
		child.free()
	if catalog.queue.is_empty():
		var empty := Label.new()
		empty.text = "队列空着。在目录页点 +1 安排制作。"
		empty.add_theme_font_size_override("font_size",13)
		empty.add_theme_color_override("font_color",Color("66554c"))
		queue_list.add_child(empty)
		return
	for job in catalog.queue:
		queue_list.add_child(_queue_row(job))


func _stock_text(entry: Dictionary) -> String:
	return "库存 %d · 排队 %d / 目标 %d" % [catalog.stock_count(catalog._snapshot(entry)),catalog.active_count(str(entry.id)),int(entry.target_stock)]


func _swatch(pigment: Color) -> ColorRect:
	var swatch := ColorRect.new()
	swatch.color = pigment
	swatch.custom_minimum_size = Vector2(26,26)
	swatch.tooltip_text = "#" + pigment.to_html()
	return swatch


func _spec_text(data: Dictionary) -> String:
	var text := "%s · %s/%s · 宽%.2f米" % [RECIPES.style_name(int(data.style)),catalog.MATERIAL_NAMES.get(str(data.material),str(data.material)),catalog.PATTERN_NAMES.get(int(data.pattern_code),str(data.pattern_code)),float(data.width_m)]
	if int(data.style) == 12:
		text += " · 裙长%.2f米" % float(data.skirt_length)
	if int(data.style) in [10,11,13]:
		text += " · 衣长%.2f米" % float(data.garment_length)
	return text


func _catalog_row(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",game._panel_style(Color("e9dfca"),Color("c3b091"),1,6))
	card.set_meta("entry_id",str(entry.id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	card.add_child(row)
	row.add_child(_swatch(entry.pigment))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = str(entry.name)
	name_label.add_theme_color_override("font_color",Color("5a4038"))
	name_label.add_theme_font_size_override("font_size",15)
	info.add_child(name_label)
	var spec := Label.new()
	spec.text = _spec_text(entry)
	spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spec.add_theme_font_size_override("font_size",12)
	spec.add_theme_color_override("font_color",Color("66554c"))
	info.add_child(spec)
	var stock := Label.new()
	stock.text = _stock_text(entry)
	stock.add_theme_font_size_override("font_size",12)
	stock.add_theme_color_override("font_color",Color("446f65"))
	info.add_child(stock)
	card.set_meta("stock_label",stock)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation",4)
	row.add_child(controls)
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation",4)
	controls.add_child(target_row)
	var target_label := Label.new()
	target_label.text = "目标"
	target_label.add_theme_font_size_override("font_size",12)
	target_label.add_theme_color_override("font_color",Color("66554c"))
	target_row.add_child(target_label)
	var target := SpinBox.new()
	target.min_value = 0
	target.max_value = catalog.MAX_TARGET
	target.step = 1
	target.value = int(entry.target_stock)
	target.custom_minimum_size = Vector2(76,0)
	target.value_changed.connect(func(value: float) -> void: catalog.update_entry(str(entry.id),{"target_stock":int(value)}))
	target_row.add_child(target)
	var switches := HBoxContainer.new()
	switches.add_theme_constant_override("separation",6)
	controls.add_child(switches)
	var auto := _switch("自动",bool(entry.auto_enabled))
	auto.toggled.connect(func(value: bool) -> void: catalog.update_entry(str(entry.id),{"auto_enabled":value}))
	switches.add_child(auto)
	var dye_switch := _switch("可染",bool(entry.allow_dye))
	dye_switch.tooltip_text = "缺料时允许用同材质同纹样的异色布先染后缝"
	dye_switch.toggled.connect(func(value: bool) -> void: catalog.update_entry(str(entry.id),{"allow_dye":value}))
	switches.add_child(dye_switch)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",6)
	controls.add_child(actions)
	var order_button: Button = game._make_text_button("+1",Vector2(56,28))
	order_button.tooltip_text = "立即排入队列一件（配方快照此刻冻结）"
	order_button.pressed.connect(func() -> void:
		var job: Dictionary = catalog.enqueue_manual(str(entry.id))
		if not job.is_empty():
			game._show_toast("已排入队列：%s" % entry.name))
	actions.add_child(order_button)
	var remove_button: Button = game._make_text_button("删除",Vector2(56,28))
	remove_button.tooltip_text = "只影响以后的订单；已排队的不变"
	remove_button.pressed.connect(func() -> void: catalog.remove_entry(str(entry.id)))
	actions.add_child(remove_button)
	return card


func _switch(label: String, pressed: bool) -> CheckButton:
	var button := CheckButton.new()
	button.text = label
	button.button_pressed = pressed
	for state in ["font_color","font_pressed_color","font_hover_color","font_hover_pressed_color","font_focus_color"]:
		button.add_theme_color_override(state,Color("66554c"))
	button.add_theme_font_size_override("font_size",12)
	return button


func _queue_row(job: Dictionary) -> PanelContainer:
	var snapshot: Dictionary = job.snapshot
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",game._panel_style(Color("e9dfca"),Color("c3b091"),1,6))
	card.set_meta("job_id",str(job.id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	card.add_child(row)
	row.add_child(_swatch(snapshot.pigment))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = ("%s · %s" % [str(snapshot.name),"手动" if bool(job.manual) else ("随机自动" if job.get("random_auto", false) else "自动补货")])
	name_label.add_theme_color_override("font_color",Color("5a4038"))
	name_label.add_theme_font_size_override("font_size",14)
	info.add_child(name_label)
	var spec := Label.new()
	spec.text = _spec_text(snapshot)
	spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spec.add_theme_font_size_override("font_size",12)
	spec.add_theme_color_override("font_color",Color("66554c"))
	info.add_child(spec)
	var state := Label.new()
	state.text = catalog.state_text(job)
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_theme_font_size_override("font_size",12)
	state.add_theme_color_override("font_color",Color("446f65"))
	info.add_child(state)
	card.set_meta("state_label",state)
	if job.state in catalog.PENDING_STATES:
		var actions := VBoxContainer.new()
		actions.add_theme_constant_override("separation",3)
		row.add_child(actions)
		var up: Button = game._make_text_button("↑",Vector2(26,20))
		up.pressed.connect(func() -> void: catalog.move_job(str(job.id),-1))
		actions.add_child(up)
		var down: Button = game._make_text_button("↓",Vector2(26,20))
		down.pressed.connect(func() -> void: catalog.move_job(str(job.id),1))
		actions.add_child(down)
		var cancel: Button = game._make_text_button("取消",Vector2(50,44))
		cancel.pressed.connect(func() -> void: catalog.cancel_job(str(job.id)))
		row.add_child(cancel)
	return card
