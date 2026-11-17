extends CanvasLayer
## The contents of the desk books; access is provided by physical desktop objects.
const SAVE = preload("res://scripts/game_save.gd")
const INK := Color("40392f")
const BLUE := Color("344f6c")
const RED := Color("994a3b")
const PAPER := Color("eee0bb")
const TITLES := {"magazine":"织物通信 · 创刊号", "catalog":"服饰与人物 · 藏册", "skills":"手艺人的成长", "strategy":"小铺经营手记", "ledger":"营业日账", "save":"保存这一天"}
var game: Node
var state: Node
var page := "magazine"
var curtain: ColorRect
var content: VBoxContainer
var left_content: VBoxContainer
var right_content: VBoxContainer
var _load_confirmation := ""
var heading: Label
var feedback: Label
var _return_speed := 1.0
var opened := false

func setup(controller: Node, model: Node) -> void:
	game = controller
	state = model
	layer = 40
	curtain = ColorRect.new()
	curtain.color = Color(.08,.065,.045,.64)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(curtain)
	var book := Control.new()
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	book.anchor_left = .04
	book.anchor_right = .96
	book.anchor_top = .02
	book.anchor_bottom = .98
	book.add_theme_font_override("font",load("res://assets/fonts/jiangcheng-500w.ttf"))
	curtain.add_child(book)
	var paper := TextureRect.new()
	paper.texture = load("res://assets/ui/manuscript/plain_book.png")
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(paper)
	heading = _text("",26,BLUE)
	book.add_child(heading)
	heading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	heading.anchor_left = .10
	heading.anchor_right = .46
	heading.anchor_top = .10
	heading.anchor_bottom = .17
	var close_button := _button(book,"合上书页 ×",close_page)
	close_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	close_button.anchor_left = .66
	close_button.anchor_right = .88
	close_button.anchor_top = .10
	close_button.anchor_bottom = .16
	for side in 2:
		var scroller := ScrollContainer.new()
		book.add_child(scroller)
		scroller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroller.anchor_left = .10 if side == 0 else .55
		scroller.anchor_right = .45 if side == 0 else .90
		scroller.anchor_top = .20
		scroller.anchor_bottom = .78
		scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",14)
		scroller.add_child(column)
		if side == 0: left_content = column
		else: right_content = column
	content = left_content
	feedback = _text("",16,RED)
	book.add_child(feedback)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feedback.anchor_left = .55
	feedback.anchor_right = .88
	feedback.anchor_top = .80
	feedback.anchor_bottom = .88
	curtain.hide()

func _text(value: String, size := 19, color := INK) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func _paragraph(value: String, size := 19, color := INK) -> void:
	content.add_child(_text(value,size,color))

func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size",18)
	button.add_theme_color_override("font_color",BLUE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e2cea1")
	style.border_color = Color("ad9470")
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	button.add_theme_stylebox_override("normal",style)
	var hover := style.duplicate()
	hover.bg_color = Color("f5eaca")
	button.add_theme_stylebox_override("hover",hover)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func open_page(kind: String) -> void:
	if not TITLES.has(kind): return
	if not opened: _return_speed = game._speed
	opened = true
	game._speed = 0.0
	page = kind
	_load_confirmation = ""
	curtain.show()
	feedback.text = ""
	_render()

func close_page() -> void:
	if not opened: return
	opened = false
	curtain.hide()
	game._speed = _return_speed

func _unhandled_key_input(event: InputEvent) -> void:
	if opened and event.is_action_pressed("ui_cancel"):
		close_page()
		get_viewport().set_input_as_handled()

func _result(result: Dictionary) -> void:
	_render()
	feedback.text = str(result.get("message",""))

func _render() -> void:
	for column in [left_content,right_content]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	content = left_content
	heading.text = TITLES[page]
	match page:
		"magazine": _magazine()
		"catalog": _catalog()
		"skills": _skills()
		"strategy": _strategy()
		"ledger": _ledger()
		"save": _save()

func _magazine() -> void:
	_paragraph("第一期  /  一块布的旅程",22,RED)
	_paragraph("从布柜到裁剪台，再到缝纫机，每一批布都带着自己的颜色与纹样。同一张纸样，用蓝格棉做来轻快，用米色麻做来素净。认衣服，也要认得做成它的那块布。")
	content = right_content
	_paragraph("店铺观察题 · 如果两件同款衣服使用了不同颜色的布料，试穿时应该看到什么？",21,BLUE)
	var answers := ["纸样相同，颜色与纹样也相同", "各自保留所用布料的颜色与纹样", "换布只影响手感，不影响外观"]
	for index in answers.size():
		var button := _button(content,"%s  %s" % [char(65+index),answers[index]],func() -> void: _result(state.answer_quiz(index)))
		button.disabled = state.quiz_answers.has(state.ISSUE_ID)
	if state.quiz_answers.has(state.ISSUE_ID):
		var answer: Dictionary = state.quiz_answers[state.ISSUE_ID]
		_paragraph("已作答 · " + ("答对，奖金已领取" if answer.correct else "本期无奖金；知识照常收录"),20,RED)
		_paragraph("答案 B。纸样决定衣形，布料带来颜色和纹样。衣物售出后，关于它的观察与制作心得仍可以留在手记里。")
	_paragraph("来信竞答：自愿参加，答对可领取 20 枚奖金，每期一次。",16)

func _catalog() -> void:
	_paragraph("实物会旅行，资料留在这里。",22,RED)
	_paragraph("摩梭 · 照片 001\n现有案例：彩饰头饰与紫色米珠串、红底花纹上衣、浅蓝长褶裙。文化归属来自用户提供的照片标注，待考证。拍摄地点、年代、作者与授权信息尚待补全。",19)
	content = right_content
	_paragraph("乌克兰 · 照片 001\n现有复原资产包括白色长衬衣、条纹罩裙、围裙、腰带和珠串。这是一张具体照片的建模案例，不能据此概括所有地区或年代的服饰。材料工艺与照片来源细节待补。",19)
	_paragraph("基础款 · 工坊练习\n围裙、衬衣、半裙与帽饰用于学习材料和服务流程，不作民族归属。",19)
	if state.knowledge.get("material_identity",false): _paragraph("✓ 剪报已归档：款式资料与单件实物的区别",19,BLUE)
	else: _button(content,"翻到《织物通信》学习材料与实物",func() -> void: open_page("magazine"))

func _skills() -> void:
	_paragraph("亲手做过的工序，才成为自己的本领。工作经验属于个人，知识属于小铺。",18)
	var person_index := 0
	for id in state.people:
		content = left_content if person_index == 0 else right_content
		person_index += 1
		var person: Dictionary = state.people[id]
		_paragraph("%s · 制作经验 %.1f / 服务经验 %.1f" % [person.name,person.craft,person.service],22,RED)
		for key in state.SKILLS:
			var spec: Dictionary = state.SKILLS[key]
			var learned: bool = key in person.learned
			_paragraph("%s%s · %s\n需要 %d 工作经验，培训费 %d%s" % ["✓ " if learned else "",spec.name,spec.description,spec.xp,spec.cost,"；先学“"+state.SKILLS[spec.requires].name+"”" if not str(spec.requires).is_empty() else ""],17)
			var button := _button(content,"已掌握" if learned else "安排培训 · " + spec.name,func() -> void: _result(state.learn_skill(id,key)))
			button.disabled = learned

func _strategy() -> void:
	_paragraph("钱、时间与人员都有限。可以同时投入，也可以暂歇一条业务；重新启用不重复付解锁费。",18)
	var branch_index := 0
	for key in state.STRATEGIES:
		content = left_content if branch_index == 0 else right_content
		branch_index += 1
		var spec: Dictionary = state.STRATEGIES[key]
		var unlocked: bool = state.strategies.has(key)
		var active: bool = state.strategies.get(key,{}).get("active",false)
		_paragraph(spec.name + (" · 营业中" if active else (" · 暂歇" if unlocked else " · 待开辟")),24,RED)
		_paragraph(spec.description + "\n首次投入 %d，首日运营费 %d。余额不足时次日自动暂歇。" % [spec.cost,spec.daily],18)
		_button(content,"暂歇业务" if active else ("重新启用" if unlocked else "开辟业务"),func() -> void: _result(state.toggle_strategy(key)))
		for child_key in state.STRATEGY_NODES:
			var child_spec: Dictionary = state.STRATEGY_NODES[child_key]
			if child_spec.branch != key: continue
			_paragraph("↓ " + child_spec.name + "\n" + child_spec.description,18,BLUE)
			var learned: bool = child_key in state.strategy_nodes
			var button := _button(content,"已解锁" if learned else "投入 %d · 解锁" % child_spec.cost,func() -> void: _result(state.unlock_strategy_node(child_key)))
			button.disabled = learned
			if child_key == "batch_orders" and learned and active:
				for entry in game._supply_catalog.entries:
					_button(content,"制作三件 · " + str(entry.get("name",entry.id)),func() -> void: _result(state.enqueue_batch(str(entry.id))))

func _ledger() -> void:
	state.tick(0)
	for key in state.journals:
		var day: Dictionary = state.journals[key]
		_paragraph("第 %d 日 · %s" % [day.day,"已打烊" if day.closed else "进行中"],23,RED)
		_paragraph("开日现金 %d\n售出 %d 件，营业收入 +%d\n新制成衣 %d 件\n用电支出 −%d\n其他现金变动 %+d（采购、培训、竞答与经营投入）\n当前现金 %d" % [day.opening_cash,day.sold,day.sales,day.crafted,day.electricity,day.other_cash,day.closing_cash],19)
		_paragraph("核对：%d + %d − %d %+d = %d" % [day.opening_cash,day.sales,day.electricity,day.other_cash,day.closing_cash],17,BLUE)
	_paragraph("本簿记录现金进出。材料和库存还有成本，账面结余请勿直接当作利润。",16)
	content = right_content
	_paragraph("采购存根",23,RED)
	var found := false
	if is_instance_valid(game.get("_vendor")):
		for receipt in game._vendor.receipts:
			found = true
			var title := str(receipt.offer)
			for goods in game._vendor.GOODS:
				if goods.id == receipt.offer: title = goods.name
			_paragraph("第 %d 日 · %s\n%s  %.1f 米 · 支出 %d" % [receipt.day,receipt.id,title,receipt.amount,receipt.cost],18)
	if not found: _paragraph("还没有采购记录。后街奶奶每天带来一批布与线，买下后会进入材料柜。",18)

func _save() -> void:
	var reason := SAVE.stable_reason(game)
	_paragraph("把忙碌的一天夹进书页",23,RED)
	_paragraph("保存包含日期、现金、逐件库存、材料余量、家具布局、人物外观与体力、杂志答案、技能和经营方针。先完成收店及手上的制作，让物品归位。",18)
	_paragraph("现在可以保存。" if reason.is_empty() else reason,19,BLUE)
	content = right_content
	_button(content,"保存当前进度",func() -> void: _result(SAVE.save_game(game,state)))
	_button(content,"读取上次进度",func() -> void: _load(SAVE.DEFAULT_PATH))
	_button(content,"从上一份备份恢复",func() -> void: _load(SAVE.DEFAULT_PATH+".bak"))
	if game._business_state == "open":
		_button(content,"准备收店，让顾客完成购物",func() -> void:
			game._begin_closing()
			close_page()
			if game._desktop.active: game._desktop.leave_desktop()
			game._speed = 1.0)
	_paragraph("进行中的生产订单不会被静默删除。若队列阻止保存，请回到订单簿完成或取消订单。",16)

func _load(path: String) -> void:
	var result: Dictionary = SAVE.load_game(game,state,path,_load_confirmation == path)
	if result.get("confirm",false): _load_confirmation = path
	else: _load_confirmation = ""
	_result(result)
