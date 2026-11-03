extends SceneTree

var game: Node
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	game._fit_stage()
	game._update_ui()
	for control in game.find_children("*","Control",true,false):
		control.tooltip_text = ""
	var view: Node = game._view_controls
	var anchor := Vector3(0,3.4,.5)
	var initial: Vector2 = game.camera.unproject_position(anchor)
	var height := root.get_visible_rect().size.y
	print("CAMERA_COMPOSITION y_ratio=",initial.y/height," size=",game.camera.size)
	_check(initial.y/height > .30 and initial.y/height < .50,"Room band is not in the upper middle")
	await _snapshot("default")
	var start := Vector2(30,150)
	var delta := Vector2(170,65)
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
		_mouse(button,start,true)
		_motion(start+delta)
		_mouse(button,start+delta,false)
		_check(not view.panning,"Mouse release left camera captured")
		var moved: Vector2 = game.camera.unproject_position(anchor)
		_check(moved.distance_to(initial+delta) < 1.0,"Camera drag does not track pointer")
		_check(game._speed == 0,"Panning changed pause state")
		if button == MOUSE_BUTTON_LEFT:
			await _snapshot("dragged")
		view.reset_pan()
	var initial_yaw: float = view.yaw
	_mouse(MOUSE_BUTTON_RIGHT,start,true)
	_motion(start+Vector2(90,25))
	_mouse(MOUSE_BUTTON_RIGHT,start,false)
	_check(absf(view.yaw-initial_yaw) > .1, "Right drag must orbit the view")
	_check(view.pan_offset == Vector2.ZERO and not view.orbiting, "Orbit must not also pan or remain captured")
	view.reset_angle()
	var ui_point: Vector2 = game.get_node("GameInterface/FloatingHUD/ShopTools").get_global_rect().get_center()
	_mouse(MOUSE_BUTTON_RIGHT,ui_point,true)
	_motion(ui_point+delta)
	_mouse(MOUSE_BUTTON_RIGHT,ui_point+delta,false)
	_check(view.pan_offset == Vector2.ZERO,"Dragging HUD moved camera")
	_touch(0,start,true)
	_touch_drag(0,start+delta)
	_touch(0,start+delta,false)
	_check(game.camera.unproject_position(anchor).distance_to(initial+delta) < 1.0,"Single finger pan failed")
	_check(not view.panning,"Touch release left camera captured")
	view.reset_pan()
	_touch(0,start,true)
	_touch(1,start+Vector2(180,0),true)
	_touch_drag(0,start+delta)
	_touch_drag(1,start+Vector2(180,0)+delta)
	_touch(0,start+delta,false)
	_touch(1,start+Vector2(180,0)+delta,false)
	_check(game.camera.unproject_position(anchor).distance_to(initial+delta) < 1.0,"Two finger pan failed")
	view.target_zoom = 0
	view.reset_pan()
	# Grab a staff member at the front; this gesture belongs to deployment.
	var doll: PaperDoll = game.staff[0]
	doll.position = Vector3(0,0,2.5)
	var staff_point: Vector2 = game.camera.unproject_position(doll.position+Vector3(0,1.2,0))
	_mouse(MOUSE_BUTTON_LEFT,staff_point,true)
	_motion(staff_point+Vector2(30,0))
	_check(game.dragging_doll == doll,"View pan stole staff deployment")
	_check(view.pan_offset == Vector2.ZERO,"Dragging staff also moved camera")
	_touch(0,start,true)
	_touch(1,start+Vector2(100,0),true)
	_touch_drag(1,start+Vector2(180,0))
	_touch(0,start,false)
	_touch(1,start+Vector2(180,0),false)
	_check(not view.touch_gesture_active and view.pan_offset == Vector2.ZERO,"Pinch stole an active staff drag")
	_mouse(MOUSE_BUTTON_LEFT,staff_point+Vector2(30,0),false)
	_check(game.dragging_doll == null,"Staff release did not finish deployment")
	var facility_point: Vector2 = game.camera.unproject_position(game.facilities[1]["label_position"])
	var original_activity: String = doll.activity
	_mouse(MOUSE_BUTTON_LEFT,facility_point,true)
	_motion(facility_point+delta)
	_mouse(MOUSE_BUTTON_LEFT,facility_point+delta,false)
	_check(doll.activity == original_activity,"Dragging across a facility assigned a job")
	_check(view.pan_offset.length() > 0,"Facility background cannot be panned")
	var saved_pan: Vector2 = view.pan_offset
	view.target_zoom = 1
	view.step(1)
	_check(view.pan_offset == saved_pan,"Zoom erased manual panning")
	view.target_zoom = 0
	view.step(1)
	view.reset_pan()
	_mouse(MOUSE_BUTTON_MIDDLE,start,true)
	_motion(start+delta)
	_mouse(MOUSE_BUTTON_MIDDLE,start+delta,false)
	game._switch_room("archive",false)
	_check(view.pan_offset == Vector2.ZERO,"Room navigation did not recenter")
	_mouse(MOUSE_BUTTON_MIDDLE,start,true)
	_motion(start+delta)
	_mouse(MOUSE_BUTTON_MIDDLE,start+delta,false)
	game._select_doll(doll)
	_check(view.pan_offset == Vector2.ZERO,"Staff locate did not recenter")
	_mouse(MOUSE_BUTTON_MIDDLE,start,true)
	_motion(start+Vector2(100000,100000))
	_mouse(MOUSE_BUTTON_MIDDLE,start,false)
	_check(absf(view.pan_offset.y) <= view.near_size*.35+.001,"Vertical pan has no limit")
	_check(absf(view.pan_offset.x+view.focus_x) <= 29,"Horizontal pan has no limit")
	var home := InputEventKey.new()
	home.pressed = true
	home.keycode = KEY_HOME
	root.push_input(home,true)
	_check(view.pan_offset == Vector2.ZERO,"Home did not reset pan")
	_mouse(MOUSE_BUTTON_MIDDLE,start,true)
	_motion(start+delta)
	get_root().focus_exited.emit()
	_check(not view.panning,"Losing focus left pan captured")
	print("CAMERA_PAN_CHECK pan_buttons=2 right_orbit=true single_touch=true two_touch=true staff_ui_isolation=true failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func _mouse(button: int, point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = down
	root.push_input(event,true)


func _motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event,true)


func _touch(index: int, point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	root.push_input(event,true)


func _touch_drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event,true)


func _snapshot(label: String) -> void:
	if not "--capture-camera" in OS.get_cmdline_user_args():
		return
	game._toast_label.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var tag := "%dx%d"%[root.size.x,root.size.y]
	var path := ProjectSettings.globalize_path("res://captures/camera_%s_%s.png"%[label,tag])
	_check(root.get_texture().get_image().save_png(path) == OK,"Camera preview failed")
