extends PanelContainer
var game: Node
var flow: Node3D
var fabric: OptionButton
var dye: OptionButton
var note: Label
var start_button: Button
var preview: ColorRect
var elapsed := 0.0

func setup(controller: Node) -> void:
	game = controller
	flow = game._dye
	name = "DyePanel"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -326
	offset_right = -20
	offset_top = 82
	var style: StyleBoxFlat = game._panel_style(Color("f2ead9"),Color("8ba28a"),1,8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	add_child(box)
	var title := Label.new()
	title.text = "染缸 · 配色与浸染"
	title.add_theme_color_override("font_color",Color("445f56"))
	title.add_theme_font_size_override("font_size",20)
	box.add_child(title)
	fabric = OptionButton.new()
	fabric.fit_to_longest_item = false
	fabric.clip_text = true
	box.add_child(fabric)
	for batch in flow.ledger.fabric_batches:
		if not flow.production.packages.has(batch.id): continue
		fabric.add_item(str(batch.get("name",batch.id)))
		fabric.set_item_metadata(fabric.item_count-1,batch.id)
	fabric.item_selected.connect(func(_index: int) -> void: refresh())
	dye = OptionButton.new()
	box.add_child(dye)
	for color_name in flow.NAMES: dye.add_item(color_name)
	dye.item_selected.connect(func(_index: int) -> void: refresh())
	preview = ColorRect.new()
	preview.custom_minimum_size = Vector2(270,28)
	box.add_child(preview)
	note = Label.new()
	note.custom_minimum_size = Vector2(270,140)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color",Color("66554c"))
	box.add_child(note)
	start_button = game._make_text_button("安排整匹染色",Vector2(270,36))
	start_button.pressed.connect(func() -> void:
		if flow.start(str(fabric.get_selected_metadata()),dye.selected):
			for worker in game.staff:
				if worker.energy > .35 and worker != game._production.actor:
					game._assign_staff(worker,game._facility_index("dye"),true)
					break
		refresh())
	box.add_child(start_button)
	var close: Button = game._make_text_button("收起",Vector2(270,30))
	close.pressed.connect(hide)
	box.add_child(close)
	hide()
	refresh()

func _process(delta: float) -> void:
	elapsed += delta
	if visible and elapsed > .25:
		elapsed = 0
		refresh()

func refresh() -> void:
	var id := str(fabric.get_selected_metadata())
	var batch: Dictionary = flow.ledger.fabric(id)
	if batch.is_empty(): return
	for index in fabric.item_count:
		var current: Dictionary = flow.ledger.fabric(str(fabric.get_item_metadata(index)))
		fabric.set_item_text(index,str(current.get("name",current.id)))
	var target: Color = (batch.pigment as Color).lerp(flow.COLORS[dye.selected],.8)
	preview.color = target
	var busy: bool = not flow.order.is_empty()
	fabric.disabled = busy
	dye.disabled = busy
	start_button.disabled = not flow.can_start(id,dye.selected)
	note.text = "整匹 %.2f / 容量 %.0f 米\n染料 %.2f 份 · 余量 %.2f 份\n叠染保留格纹与条纹；色块为预计色。\n取料 → 浸染 → 漂洗 → 晾干 → 归库\n%s" % [batch.meters,flow.CAPACITY_M,float(batch.meters)*.1,flow.dyes[dye.selected],flow.LABELS.get(flow.phase,flow.phase)]
	if busy and not is_instance_valid(flow.actor): note.text += " · 等待员工接手"
	if not busy and start_button.disabled: note.text += "\n需空闲棉、麻或羊毛布匹及足量染料。"
	size.y = get_combined_minimum_size().y

