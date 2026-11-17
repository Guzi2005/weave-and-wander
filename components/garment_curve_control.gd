extends Control
signal edited
var curve: Curve
var selected := -1
var maximum := .12


func _ready() -> void:
	custom_minimum_size = Vector2(220, 140)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _rect() -> Rect2:
	return Rect2(Vector2(16, 12), size - Vector2(32, 32))


func _screen(p: Vector2) -> Vector2:
	var r := _rect()
	return r.position + Vector2(p.x * r.size.x, (1.0 - p.y / maximum) * r.size.y)


func _draw() -> void:
	var r := _rect()
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for i in 5:
		var x := r.position.x + r.size.x * i / 4.0
		var y := r.position.y + r.size.y * i / 4.0
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("d7dfdf"))
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("d7dfdf"))
	if curve == null: return
	var points := PackedVector2Array()
	for i in 101: points.append(_screen(Vector2(i / 100.0, clampf(curve.sample_baked(i / 100.0), 0, maximum))))
	draw_polyline(points, Color("387f75"), 2.5, true)
	for i in curve.point_count:
		draw_circle(_screen(curve.get_point_position(i)), 5, Color("bf6857") if i == selected else Color("387f75"))


func _background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("f8faf9")
	return box


func _gui_input(event: InputEvent) -> void:
	if curve == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click and curve.point_count < 16:
			var r := _rect()
			var at := clampf((event.position.x - r.position.x) / r.size.x, .02, .98)
			var allowed := true
			for i in curve.point_count:
				if absf(curve.get_point_position(i).x - at) < .02: allowed = false
			if allowed:
				curve.add_point(Vector2(at, clampf((r.end.y - event.position.y) / r.size.y, 0, 1) * maximum), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
				edited.emit()
		if event.pressed:
			selected = -1
			var nearest := 14.0
			for i in curve.point_count:
				var distance := _screen(curve.get_point_position(i)).distance_to(event.position)
				if distance < nearest:
					nearest = distance
					selected = i
		else:
			if selected >= 0: edited.emit()
			selected = -1
		queue_redraw()
		accept_event()
	if event is InputEventMouseMotion and selected >= 0:
		var r := _rect()
		var value := Vector2(clampf((event.position.x - r.position.x) / r.size.x, 0, 1),
			clampf((r.end.y - event.position.y) / r.size.y, 0, 1) * maximum)
		if selected == 0: value = Vector2.ZERO
		elif selected == curve.point_count - 1: value.x = 1.0
		else: value.x = clampf(value.x, curve.get_point_position(selected - 1).x + .015, curve.get_point_position(selected + 1).x - .015)
		curve.set_point_offset(selected, value.x)
		curve.set_point_value(selected, value.y)
		queue_redraw()
		accept_event()
