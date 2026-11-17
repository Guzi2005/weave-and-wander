extends Control
var vendor: Node
var game: Node
var _return_speed := 1.0
var _rows: VBoxContainer
var _message: Label
var _wallet: Label

func setup(source: Node, controller: Node) -> void:
	vendor = source
	game = controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.09,.08,.07,.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620,490)
	panel.add_theme_stylebox_override("panel",game._panel_style(Color("f2ead9"),Color("5a4038"),2,5))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "巷口推车 · 奶奶的针线摊"
	title.add_theme_font_size_override("font_size",25)
	title.add_theme_color_override("font_color",Color("5a4038"))
	column.add_child(title)
	var description := Label.new()
	description.text = "清晨出摊 · 黄昏归家\n每天一车新货，售完便等明日。布料每份 2 米，棉线每份 20 米。"
	description.add_theme_color_override("font_color",Color("5a4038"))
	column.add_child(description)
	_wallet = Label.new()
	_wallet.add_theme_color_override("font_color",Color("5a4038"))
	column.add_child(_wallet)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation",10)
	column.add_child(_rows)
	_message = Label.new()
	_message.custom_minimum_size.y = 45
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color",Color("733f45"))
	column.add_child(_message)
	var close: Button = game._make_text_button("收好零钱 · 返回后街",Vector2(260,42))
	close.pressed.connect(close_panel)
	column.add_child(close)
	hide()

func open() -> void:
	if not visible: _return_speed = game._speed
	game._speed = 0.0
	_message.text = "奶奶：布和线都在这里，慢慢挑。" if vendor.is_trading() else "奶奶还没摆好摊，等她停稳了再来。"
	_refresh()
	show()

func _refresh() -> void:
	for child in _rows.get_children(): child.queue_free()
	_wallet.text = "荷包：%d    ·    第 %d 天" % [game._money,game._day_index]
	for offer in vendor.GOODS:
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = Color(offer.color)
		swatch.custom_minimum_size = Vector2(24,32)
		row.add_child(swatch)
		var label := Label.new()
		label.text = "%s · 余 %d 份" % [offer.name,int(vendor.stock.get(offer.id,0))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color",Color("5a4038"))
		row.add_child(label)
		var buy: Button = game._make_text_button("买一份 · %d" % offer.price,Vector2(150,40))
		buy.disabled = not vendor.is_trading() or int(vendor.stock.get(offer.id,0)) <= 0 or game._money < offer.price
		buy.pressed.connect(func() -> void:
			var result: Dictionary = vendor.purchase(offer.id)
			_message.text = result.reason
			_refresh())
		row.add_child(buy)

func close_panel() -> void:
	hide()
	game._speed = _return_speed

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
