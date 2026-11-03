extends Node

var controller: Node
var hovered_roof: Node3D
var hovered_side := 0
var _pointer := Vector2.ZERO
var _pointer_valid := false
var _touch_mode := false
var _touch_consumed := false


func _ready() -> void:
	if get_window().has_signal("mouse_exited"):
		get_window().connect("mouse_exited",_leave_window)
	get_window().focus_exited.connect(_leave_window)


func _leave_window() -> void:
	_pointer_valid = false
	hovered_roof = null
	hovered_side = 0
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(delta: float) -> void:
	step(delta)


func _input(event: InputEvent) -> void:
	if is_instance_valid(controller._view_controls) and not controller._view_controls.interior_interaction():
		return
	if event is InputEventScreenTouch and event.pressed:
		_touch_mode = true
		_touch_consumed = false
		hovered_roof = null
		hovered_side = 0
		if _over_ui(event.position):
			return
		var hit := pick(event.position)
		if not hit.is_empty():
			hit["roof"].toggle_touch(hit["side"])
			_touch_consumed = true
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.device != -1:
		_pointer = event.position
		_pointer_valid = true
		if _touch_mode:
			for room in controller._rooms.values():
				room.get_node("HingedRoof").clear_touch()
		_touch_mode = false
	elif event is InputEventMouseButton:
		if event.device == -1 and _touch_consumed:
			get_viewport().set_input_as_handled()
			return
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed or controller.dragging_doll != null:
			return
		if not _over_ui(event.position) and not pick(event.position).is_empty():
			# Clicking the opaque lid must not assign a facility hidden behind it.
			get_viewport().set_input_as_handled()


func step(delta: float) -> void:
	if is_instance_valid(controller._view_controls) and is_instance_valid(controller._view_controls.follow_target):
		hovered_roof = null
		hovered_side = 0
		for room in controller._rooms.values():
			var roof: Node3D = room.get_node("HingedRoof")
			roof.clear_touch()
			roof.animate_lids(maxf(delta, 1.0), 0)
		return
	var picked := {}
	var transitioning: bool = is_instance_valid(controller._camera_tween) and controller._camera_tween.is_running()
	var interior: bool = not is_instance_valid(controller._view_controls) or controller._view_controls.interior_interaction()
	var panning: bool = is_instance_valid(controller._view_controls) and (controller._view_controls.panning or controller._view_controls.orbiting)
	if interior and not panning and _pointer_valid and not _touch_mode and not transitioning and not _over_ui(_pointer):
		picked = pick(_pointer)
		if picked.is_empty() and is_instance_valid(hovered_roof) and hovered_side != 0:
			if hovered_roof.holds_pointer(controller.camera,_pointer,hovered_side):
				picked = {"roof":hovered_roof,"side":hovered_side}
	hovered_roof = picked.get("roof")
	hovered_side = picked.get("side",0)
	for room in controller._rooms.values():
		var roof: Node3D = room.get_node("HingedRoof")
		roof.animate_lids(delta,hovered_side if roof == hovered_roof else 0)
	Input.set_default_cursor_shape(Input.CURSOR_DRAG if panning else (Input.CURSOR_POINTING_HAND if hovered_side != 0 else Input.CURSOR_ARROW))


func pick(point: Vector2) -> Dictionary:
	var nearest := INF
	var result := {}
	for room in controller._rooms.values():
		var roof: Node3D = room.get_node("HingedRoof")
		var hit: Dictionary = roof.hit_test(controller.camera,point)
		if hit["side"] != 0 and hit["distance"] < nearest:
			nearest = hit["distance"]
			result = {"roof":roof,"side":hit["side"]}
	return result


func _over_ui(point: Vector2) -> bool:
	if not get_viewport().get_visible_rect().has_point(point):
		return true
	if controller._wardrobe.visible and controller._wardrobe.get_global_rect().has_point(point):
		return true
	for name in ["ShopTools","StaffCards","TimeControls","RoomNavigation"]:
		var control: Control = controller.get_node("GameInterface/FloatingHUD/"+name)
		if control.get_global_rect().has_point(point):
			return true
	return false
