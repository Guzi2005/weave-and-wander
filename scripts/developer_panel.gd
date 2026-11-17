extends CanvasLayer

var game: Node
var panel: PanelContainer
var status: Label
var speed_buttons: Dictionary = {}
var money_button: Button

func _ready() -> void:
	layer = 30
	_build.call_deferred()

func _build() -> void:
	game = get_parent()
	var toggle: Button = game._make_text_button("开发者 F3", Vector2(112,32))
	toggle.position = Vector2(16, 360)
	toggle.custom_minimum_size = Vector2(112, 32)
	add_child(toggle)
	toggle.visible = "--developer-tools" in OS.get_cmdline_user_args()
	toggle.pressed.connect(_toggle)
	panel = PanelContainer.new()
	panel.position = Vector2(140, 360)
	panel.custom_minimum_size = Vector2(265, 0)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f2ead9")
	paper.border_color = Color("8ba28a")
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(8)
	paper.content_margin_left = 14
	paper.content_margin_right = 14
	paper.content_margin_top = 12
	paper.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", paper)
	panel.add_theme_color_override("font_color", Color("445f56"))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "开发者 · 快速测试"
	title.add_theme_color_override("font_color", Color("445f56"))
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var preview_tools := HBoxContainer.new()
	preview_tools.name = "PreviewTools"
	preview_tools.add_theme_constant_override("separation", 8)
	box.add_child(preview_tools)
	# Move the original controls so their drawing, tooltips and signals stay intact.
	var shop_tools := game.find_child("ShopTools", true, false)
	if shop_tools != null:
		for tool_name in ["Wardrobe", "DollStudy"]:
			var tool := shop_tools.get_node_or_null(tool_name)
			if tool != null:
				tool.reparent(preview_tools)
	status = Label.new()
	status.add_theme_color_override("font_color", Color("66554c"))
	status.add_theme_font_size_override("font_size", 14)
	box.add_child(status)
	var row := HBoxContainer.new()
	box.add_child(row)
	for speed in [1,4,8,10]:
		var button: Button = game._make_text_button("×%d" % speed, Vector2(64,36))
		button.add_theme_color_override("font_pressed_color", Color("445f56"))
		button.add_theme_stylebox_override("pressed", game._panel_style(Color("bfd0b5"),Color("628574"),1,6))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(64,36)
		button.pressed.connect(func() -> void: game._set_speed(float(speed)); _refresh())
		row.add_child(button)
		speed_buttons[speed] = button
	money_button = game._make_text_button("金钱 +1000", Vector2(0,36))
	money_button.custom_minimum_size.y = 36
	money_button.pressed.connect(func() -> void: game._money += 1000; _refresh())
	box.add_child(money_button)
	var close: Button = game._make_text_button("收起", Vector2(0,32))
	close.pressed.connect(panel.hide)
	box.add_child(close)
	panel.hide()
	_refresh()

func _toggle() -> void:
	if is_instance_valid(panel):
		panel.visible = not panel.visible
		_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if is_instance_valid(panel) and panel.visible:
		_refresh()
		var viewport_size := get_viewport().get_visible_rect().size
		panel.position = Vector2(minf(140, maxf(12, viewport_size.x-panel.size.x-12)), minf(360,maxf(12,viewport_size.y-panel.size.y-12)))

func _refresh() -> void:
	var speed: float = game._wardrobe_return_speed if is_instance_valid(game._wardrobe) and game._wardrobe.visible else game._speed
	status.text = "当前 ×%s · 金钱 %d" % [str(speed),game._money]
	for value in speed_buttons:
		speed_buttons[value].set_pressed_no_signal(is_equal_approx(speed,float(value)))
