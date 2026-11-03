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
	var toggle := Button.new()
	toggle.text = "开发者 F3"
	toggle.position = Vector2(16, 360)
	toggle.custom_minimum_size = Vector2(112, 32)
	add_child(toggle)
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
	box.add_child(title)
	status = Label.new()
	box.add_child(status)
	var row := HBoxContainer.new()
	box.add_child(row)
	for speed in [1,4,8,10]:
		var button := Button.new()
		button.text = "×%d" % speed
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(72,36)
		button.pressed.connect(func() -> void: game._set_speed(float(speed)); _refresh())
		row.add_child(button)
		speed_buttons[speed] = button
	money_button = Button.new()
	money_button.text = "金钱 +1000"
	money_button.custom_minimum_size.y = 36
	money_button.pressed.connect(func() -> void: game._money += 1000; _refresh())
	box.add_child(money_button)
	var close := Button.new()
	close.text = "收起"
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
	if is_instance_valid(panel) and panel.visible: _refresh()

func _refresh() -> void:
	var speed: float = game._wardrobe_return_speed if is_instance_valid(game._wardrobe) and game._wardrobe.visible else game._speed
	status.text = "当前 ×%s · 金钱 %d" % [str(speed),game._money]
	for value in speed_buttons:
		speed_buttons[value].set_pressed_no_signal(is_equal_approx(speed,float(value)))
