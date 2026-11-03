class_name StaffCard
extends Control

signal portrait_clicked(doll: PaperDoll)
signal details_clicked(doll: PaperDoll)
signal drag_started(doll: PaperDoll)
signal drag_finished(doll: PaperDoll, screen_position: Vector2)

var doll: PaperDoll
var selected := false
var _pressed := false
var _dragging := false
var _press_position := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(86.0, 112.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "%s：点击头像定位，点击体力条查看详情，拖动部署" % doll.doll_name if is_instance_valid(doll) else "角色"
	set_process(true)


func bind(value: PaperDoll) -> void:
	doll = value
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _process(_delta: float) -> void:
	if is_instance_valid(doll):
		var off_shift := doll.is_off_shift()
		mouse_default_cursor_shape = Control.CURSOR_ARROW if off_shift else Control.CURSOR_POINTING_HAND
		tooltip_text = "%s · 已下班" % doll.doll_name if off_shift else "%s · 拖动部署" % doll.doll_name
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(doll):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed = true
		_dragging = false
		_press_position = get_global_transform_with_canvas() * event.position
		accept_event()


func _input(event: InputEvent) -> void:
	if not _pressed or not is_instance_valid(doll):
		return
	# Track the release outside the card as well, including emulated touch drags.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _dragging:
			drag_finished.emit(doll, event.position)
		elif _pressed:
			var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			if Rect2(7, 7, size.x - 14, 76).has_point(local_position):
				portrait_clicked.emit(doll)
			else:
				details_clicked.emit(doll)
		_pressed = false
		_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressed:
		if not doll.is_off_shift() and not _dragging and event.position.distance_to(_press_position) > 7.0:
			_dragging = true
			drag_started.emit(doll)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("c8dfd0") if selected else Color("f3f4eb")
	paper.set_corner_radius_all(5)
	paper.shadow_color = Color(.18, .27, .26, .16)
	paper.shadow_size = 3
	paper.shadow_offset = Vector2(0, 3)
	draw_style_box(paper, Rect2(Vector2(1, 1), size - Vector2(2, 5)))
	if not is_instance_valid(doll):
		return

	# Draw the same cut-paper pieces as the 3D doll, cropped to a bust portrait.
	for layer in doll.portrait_layers():
		var points := PackedVector2Array()
		for point in layer["points"]:
			points.append(Vector2(size.x * 0.5 + point.x * 54.0, 78.0 + (1.57 - point.y) * 54.0))
		draw_colored_polygon(points, layer["color"])
	_draw_activity_mark(Vector2(size.x - 15.0, 15.0))

	var bar_rect := Rect2(9.0, size.y - 17.0, size.x - 18.0, 7.0)
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color("d0dbd4")
	bar.set_corner_radius_all(4)
	draw_style_box(bar,bar_rect)
	var energy_color := Color("70a687") if doll.energy > 0.35 else Color("cf725e")
	bar.bg_color = energy_color
	draw_style_box(bar,Rect2(bar_rect.position, Vector2(bar_rect.size.x * doll.energy, bar_rect.size.y)))
	if doll.is_off_shift():
		draw_rect(Rect2(Vector2.ONE,size-Vector2(2,5)),Color(.43,.44,.44,.78))
		draw_string(ThemeDB.fallback_font,Vector2(0,size.y*.58),"已下班",HORIZONTAL_ALIGNMENT_CENTER,size.x,15,Color.WHITE)


func _draw_activity_mark(center: Vector2) -> void:
	var color := Color("b7a999")
	match doll.activity:
		"sewing": color = Color("cf665a")
		"stocking": color = Color("6b9e83")
		"checkout": color = Color("dba84e")
		"resting": color = Color("74aab0")
		_: color = Color("b7a999")
	draw_circle(center, 8.0, Color("fff9eb"))
	draw_circle(center, 5.2, color)
