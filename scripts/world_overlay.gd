class_name WorldOverlay
extends Control

var controller: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(controller) or not is_instance_valid(controller.camera):
		return
	if is_instance_valid(controller._view_controls) and not controller._view_controls.interior_interaction():
		return
	var camera: Camera3D = controller.camera
	var font := get_theme_default_font()
	for facility in controller.facilities:
		if facility["room"] != controller._active_room:
			continue
		var anchor: Vector3 = facility["label_position"]
		if camera.is_position_behind(anchor):
			continue
		var screen := camera.unproject_position(anchor)
		var is_target := controller.dragging_doll != null
		var accent: Color = facility["accent"]
		if not is_target:
			continue
		var chip_rect := Rect2(screen - Vector2(49.0, 15.0), Vector2(98.0, 26.0))
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.98, 0.96, 0.9, 0.9)
		panel.border_color = accent
		panel.set_border_width_all(2)
		panel.set_corner_radius_all(6)
		draw_style_box(panel, chip_rect)
		draw_circle(screen + Vector2(-34.0, -2.0), 5.0, accent)
		draw_string(font, screen + Vector2(-23.0, 4.0), str(facility["title"]), HORIZONTAL_ALIGNMENT_LEFT, 68.0, 14, Color("4b3530"))
		draw_arc(screen + Vector2(0.0, 7.0), 59.0, 0.0, TAU, 40, Color(accent, 0.7), 2.0)
	var bubbles: Array[Rect2] = []
	for customer in controller.customers:
		if is_instance_valid(customer) and customer.get("thought_time") > 0.0 and customer.get_meta("room", "") == "shop":
			_draw_thought(camera, font, customer, bubbles)
	if controller.dragging_doll != null:
		var mouse := get_viewport().get_mouse_position()
		draw_circle(mouse, 27.0, Color(0.98, 0.94, 0.78, 0.75))
		draw_arc(mouse, 27.0, 0.0, TAU, 30, Color("6d4c43"), 2.0)
		draw_circle(mouse, 8.0, controller.dragging_doll.get_outfit_color())


func _draw_thought(camera: Camera3D, font: Font, customer: Node3D, placed: Array[Rect2]) -> void:
	var anchor: Vector3 = customer.global_position + Vector3(0, 3.0 * customer.scale.y, 0)
	if camera.is_position_behind(anchor):
		return
	var tip := camera.unproject_position(anchor)
	var text: String = customer.thought
	var has_swatch: bool = customer.thought_color.a > 0.0
	var size := 13
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + (34.0 if has_swatch else 18.0)
	var rect := Rect2(tip - Vector2(width * 0.5, 38.0), Vector2(width, 26.0))
	while placed.any(func(other: Rect2) -> bool: return other.grow(2.0).intersects(rect)):
		rect.position.y -= 30.0
		tip.y -= 30.0
	placed.append(rect)
	var alpha := clampf(customer.thought_time / 0.35, 0.0, 1.0)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.98, 0.96, 0.9, 0.92 * alpha)
	panel.border_color = Color(0.43, 0.3, 0.26, alpha)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(9)
	draw_style_box(panel, rect)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, -12.5), tip + Vector2(5, -12.5), tip + Vector2(0, -5)]), panel.bg_color)
	var x := rect.position.x + 9.0
	if has_swatch:
		draw_circle(Vector2(x + 6.0, rect.get_center().y), 6.0, Color(customer.thought_color, alpha))
		x += 16.0
	draw_string(font, Vector2(x, rect.get_center().y + 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.29, 0.21, 0.19, alpha))
