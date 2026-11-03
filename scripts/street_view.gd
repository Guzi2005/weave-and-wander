extends Node

var controller: Node
const MIN_ZOOM := -3.0
const MAX_ZOOM := 1.0

var zoom := 0.0
var target_zoom := 0.0
var depth := 1.0
var target_depth := 1.0
var _scroll_idle := 0.0
var exterior := false
var near_size := 12.0
var near_offset := Vector2.ZERO
var far_size := 24.0
var far_offset := Vector2.ZERO
var touches := {}
var touch_gesture_active := false
var pan_offset := Vector2.ZERO
var panning := false
var _pan_button := 0
var _pan_origin := Vector2.ZERO
var _pan_last := Vector2.ZERO
var _touch_pan := -1
var _press_on_roof := false
const DEFAULT_YAW := -8.0
const DEFAULT_PITCH := 24.0
var focus_x := 0.0
var yaw := deg_to_rad(DEFAULT_YAW)
var pitch := deg_to_rad(DEFAULT_PITCH)
var orbiting := false
var _orbit_origin := Vector2.ZERO
var _orbit_last := Vector2.ZERO
var _gesture_center := Vector2.ZERO
var _gesture_pan := Vector2.ZERO
var _gesture_angle := 0.0
var _gesture_yaw := 0.0
var _gesture_span := 0.0
var _gesture_zoom := 0.0
var _gesture_units_per_pixel := 0.0
var follow_target: Node3D
var follow_first_person := false
var follow_mode := 3
var _follow_delta := 1.0/60.0
var _follow_initialized := false
var _camera_space := preload("res://scripts/follow_camera_space.gd").new()
var _mirror_subject: Node3D
var _mirror_only_meshes: Array[GeometryInstance3D] = []


func _ready() -> void:
	process_priority = 200
	get_window().focus_exited.connect(func() -> void:
		touches.clear()
		touch_gesture_active = false
		_end_pan()
		orbiting = false
	)


func interior_interaction() -> bool:
	return absf(depth - 1.0) < .16 and absf(target_depth - 1.0) < .2


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	_follow_delta = clampf(delta,0.0,.1)
	zoom = move_toward(zoom,target_zoom,delta*1.9)
	_scroll_idle += delta
	if _scroll_idle > .24:
		target_depth = roundf(target_depth)
	depth = move_toward(depth, target_depth, delta * 1.25)
	exterior = depth < .5
	apply_view()


func follow(doll: Node3D, first_person: bool) -> void:
	_restore_mirror_only()
	follow_target = doll
	follow_first_person = first_person
	follow_mode = 1 if first_person else 3
	_follow_initialized = false
	doll.visible = true
	apply_view()


func clear_follow() -> void:
	_restore_mirror_only()
	follow_target = null
	follow_first_person = false
	follow_mode = 3
	_follow_initialized = false
	if is_instance_valid(controller._pop_up):
		controller._pop_up.enclosed = false
	controller.camera.fov = 35.0
	controller.camera.near = 0.025
	apply_view()


func apply_view() -> void:
	if is_instance_valid(follow_target):
		_apply_follow()
		return
	if follow_target != null:
		clear_follow()
		return
	controller.camera.fov = 35.0
	controller.camera.near = 0.025
	var t := clampf(zoom, 0, 1)
	var transition := sin((depth - floorf(depth)) * PI)
	var overview := .45 * (1.0 - smoothstep(0.0, 1.0, depth)) + .10 * smoothstep(1.0, 2.0, depth)
	controller.camera.size = lerpf(near_size,far_size,t) * pow(2.0,minf(zoom,0.0)) * (1.0 + overview + transition * .12)
	var offset := near_offset.lerp(far_offset,t)+pan_offset
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var basis := Basis.looking_at(-direction, Vector3.UP)
	var target := Vector3(focus_x, 2.75, .25) + basis * Vector3(offset.x, offset.y, 0)
	# Move through the actual rows, not interchangeable scenes at the same spot.
	target.z -= 6.5 * smoothstep(1.0, 2.0, depth) + 6.5 * smoothstep(2.0, 3.0, depth)
	var distance: float = controller.camera.size / (2.0 * tan(deg_to_rad(controller.camera.fov) * .5))
	controller.camera.position = target + direction * distance
	controller.camera.look_at(target, Vector3.UP)
	controller.camera.h_offset = 0
	controller.camera.v_offset = 0
	if controller.has_node("RenderAB"): controller.get_node("RenderAB").apply_camera()
	if is_instance_valid(controller._pop_up):
		controller._pop_up.apply_depth(depth)


func _apply_follow() -> void:
	var doll := follow_target
	var eye_pose := _eye_pose(doll)
	var forward := eye_pose.basis.z.normalized()
	# Keep the horizon level, while retaining the actual head yaw and pitch.
	forward.y = clampf(forward.y,-.82,.82)
	forward = forward.normalized()
	var camera: Camera3D = controller.camera
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	if is_instance_valid(controller._pop_up):
		controller._pop_up.enclosed = true
		controller._pop_up.apply_depth(depth)
	for room in controller._rooms.values():
		var roof: Node3D = room.get_node("HingedRoof")
		roof.clear_touch()
		roof.animate_lids(1.0,0)
	_camera_space.refresh(controller,doll,_follow_delta,not _follow_initialized)
	var eye := _camera_space.escape(eye_pose.origin)
	var focus := _camera_space.escape(eye-forward*.18-Vector3.UP*.14)
	var desired := eye
	var aim := eye+forward*3.0
	var close_view := follow_first_person
	if not follow_first_person:
		desired = _camera_space.orbit_position(focus,forward,follow_mode == 2,camera.global_position)
		close_view = desired.distance_to(focus) < .72
		if close_view:
			desired = eye
		else:
			aim = focus+forward*.12
	# Never interpolate through the subject when swapping perspectives.
	var blend := 1.0-exp(-9.0*_follow_delta)
	if _follow_initialized and camera.global_position.distance_to(desired) < 4.0 and not close_view:
		var smooth := camera.global_position.lerp(desired,blend)
		smooth = _camera_space.clip(focus,smooth)
		if smooth.distance_to(focus) >= .72 and _camera_space.clear_point(smooth): desired = smooth
	camera.global_position = desired
	var look := (aim-desired).normalized()
	if look.length_squared() < .01: look = forward
	var target_basis := Basis.looking_at(look,Vector3.UP)
	camera.global_basis = camera.global_basis.orthonormalized().slerp(target_basis,1.0-exp(-12*_follow_delta)) if _follow_initialized else target_basis
	camera.fov = 68.0 if close_view else 55.0
	camera.near = .025
	camera.h_offset = 0
	camera.v_offset = 0
	if controller.has_node("RenderAB"): controller.get_node("RenderAB").apply_camera()
	_show_body_to_mirror_only(doll,close_view)
	_follow_initialized = true


func _eye_pose(doll: Node3D) -> Transform3D:
	if doll.get("rig") != null and doll.rig.bones.has("Head"):
		var head: Transform3D = doll.body_rig.global_transform*doll.rig.global_pose(doll.rig.bones.Head)
		return Transform3D(head.basis.orthonormalized(),head*Vector3(0,.292,.285))
	return Transform3D(doll.global_basis,doll.global_position+Vector3.UP*2.3)


func set_follow_mode(mode: int) -> void:
	follow_mode = clampi(mode,1,3)
	follow_first_person = follow_mode == 1
	_follow_initialized = false
	_restore_mirror_only()
	apply_view()

func _show_body_to_mirror_only(doll: Node3D, enabled: bool) -> void:
	if not enabled:
		_restore_mirror_only()
		return
	if _mirror_subject != doll:
		_restore_mirror_only()
		_mirror_subject = doll
	_claim_mirror_only(doll)
	if controller._inventory == null:
		return
	for item in controller._inventory.items:
		if item.holder != null and item.holder.get_ref() == doll:
			_claim_mirror_only(item)


func _claim_mirror_only(root: Node) -> void:
	var meshes: Array = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		meshes.append(root)
	for mesh_value in meshes:
		var mesh := mesh_value as GeometryInstance3D
		if not mesh.has_meta("player_layers"):
			mesh.set_meta("player_layers", mesh.layers)
			_mirror_only_meshes.append(mesh)
		mesh.layers = 8


func _restore_mirror_only() -> void:
	for mesh in _mirror_only_meshes:
		if is_instance_valid(mesh) and mesh.has_meta("player_layers"):
			mesh.layers = int(mesh.get_meta("player_layers"))
			mesh.remove_meta("player_layers")
	_mirror_only_meshes.clear()
	_mirror_subject = null


func reset_pan() -> void:
	pan_offset = Vector2.ZERO
	_end_pan()
	apply_view()


func reset_angle() -> void:
	yaw = deg_to_rad(DEFAULT_YAW)
	pitch = deg_to_rad(DEFAULT_PITCH)
	orbiting = false
	apply_view()


func orbit_by(delta: Vector2) -> void:
	yaw = clampf(yaw - delta.x * .004, deg_to_rad(-38), deg_to_rad(38))
	pitch = clampf(pitch + delta.y * .003, deg_to_rad(5), deg_to_rad(55))
	controller._world_pressed_doll = null
	for room in controller._rooms.values():
		room.get_node("HingedRoof").clear_touch()
	apply_view()


func _end_pan() -> void:
	panning = false
	_pan_button = 0
	_touch_pan = -1
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _can_pan(point: Vector2, check_staff: bool = true) -> bool:
	if is_instance_valid(follow_target):
		return false
	if controller._wardrobe.visible or controller.dragging_doll != null or controller._roof_controls._over_ui(point):
		return false
	if check_staff and interior_interaction() and controller._pick_staff(point) != null:
		return false
	return true


func _pan_by(delta: Vector2) -> void:
	pan_offset += Vector2(-delta.x,delta.y) * _pan_scale()
	_clamp_pan()
	controller._world_pressed_doll = null
	for room in controller._rooms.values():
		room.get_node("HingedRoof").clear_touch()
	apply_view()


func _pan_scale() -> float:
	var height := get_viewport().get_visible_rect().size.y
	return controller.camera.size / maxf(height,1.0)


func _clamp_pan() -> void:
	var base := near_offset.lerp(far_offset,smoothstep(0,1,zoom))
	pan_offset.x = clampf(pan_offset.x,-28.0-focus_x-base.x,28.0-focus_x-base.x)
	pan_offset.y = clampf(pan_offset.y,-near_size*.35,near_size*.35)


func _move_pan(point: Vector2) -> void:
	if not panning and point.distance_to(_pan_origin) > 8.0:
		panning = true
		controller._world_pressed_doll = null
	if panning:
		_pan_by(point-_pan_last)
		get_viewport().set_input_as_handled()
	_pan_last = point


func adjust(amount: float) -> void:
	if controller._wardrobe.visible or controller.dragging_doll != null:
		return
	target_zoom = clampf(target_zoom+amount,MIN_ZOOM,MAX_ZOOM)
	if target_zoom > .35:
		controller._world_pressed_doll = null
		for room in controller._rooms.values():
			room.get_node("HingedRoof").clear_touch()


func _scroll_input(event: InputEvent) -> bool:
	if is_instance_valid(follow_target) and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if not controller._roof_controls._over_ui(event.position) and not controller._wardrobe.visible and controller.dragging_doll == null:
			var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			# Some Windows mouse drivers report zero for wheel factor. Treat one
			# physical notch as one step so depth changes are not rounded away.
			var amount := direction * (absf(event.factor) if not is_zero_approx(event.factor) else 1.0)
			if event.ctrl_pressed:
				adjust(-amount * .18)
			else:
				_scroll_idle = 0
				target_depth = clampf(target_depth + amount * .26, 0, 3)
				# Each scroll also changes scale, while the chapter opens on the same base.
				adjust(-amount * .08)
			get_viewport().set_input_as_handled()
		return true
	elif event is InputEventMagnifyGesture:
		if not controller._roof_controls._over_ui(event.position):
			adjust(-log(maxf(event.factor,.01)))
			get_viewport().set_input_as_handled()
		return true
	return false


func _input(event: InputEvent) -> void:
	# Handle wheel before full-viewport decorative controls can consume it.
	if _scroll_input(event):
		return
	# Once a staff drag owns a touch, let its synthesized release finish deployment.
	if controller.dragging_doll != null and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		touches.clear()
		touch_gesture_active = false
		_end_pan()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_HOME and not controller._wardrobe.visible:
		reset_angle()
		reset_pan()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _can_pan(event.position, false):
			orbiting = true
			_orbit_origin = event.position
			_orbit_last = event.position
			controller._world_pressed_doll = null
			get_viewport().set_input_as_handled()
		elif not event.pressed and orbiting:
			orbiting = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and orbiting:
		if event.position.distance_to(_orbit_origin) > 5.0:
			orbit_by(event.position - _orbit_last)
		_orbit_last = event.position
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.device != -1 and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
		if event.pressed:
			if _can_pan(event.position,event.button_index == MOUSE_BUTTON_LEFT):
				_pan_button = event.button_index
				_pan_origin = event.position
				_pan_last = event.position
				_press_on_roof = interior_interaction() and not controller._roof_controls.pick(event.position).is_empty()
				if event.button_index != MOUSE_BUTTON_LEFT:
					get_viewport().set_input_as_handled()
		elif _pan_button == event.button_index:
			var consumed := panning or _press_on_roof or _pan_button != MOUSE_BUTTON_LEFT
			_end_pan()
			if consumed:
				controller._world_pressed_doll = null
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and event.device != -1 and _pan_button != 0:
		_move_pan(event.position)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if touches.is_empty():
				touch_gesture_active = false
				if _can_pan(event.position):
					_touch_pan = event.index
					_pan_origin = event.position
					_pan_last = event.position
			if not controller._roof_controls._over_ui(event.position):
				touches[event.index] = event.position
		else:
			touches.erase(event.index)
			if event.index == _touch_pan:
				if panning:
					touch_gesture_active = true
				_end_pan()
		if touches.size() >= 2:
			_gesture_center = _touch_center()
			_gesture_pan = pan_offset
			_gesture_angle = _touch_angle()
			_gesture_yaw = yaw
			_gesture_span = _span()
			_gesture_zoom = target_zoom
			_gesture_units_per_pixel = _pan_scale()
			_touch_pan = -1
			panning = false
			touch_gesture_active = true
			controller._world_pressed_doll = null
			for room in controller._rooms.values():
				room.get_node("HingedRoof").clear_touch()
		if touch_gesture_active:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and touches.has(event.index):
		touches[event.index] = event.position
		if touches.size() >= 2:
			if not controller._wardrobe.visible and controller.dragging_doll == null:
				# Absolute gesture state avoids drift when fingers report in separate events.
				target_zoom = clampf(_gesture_zoom + (_gesture_span-_span())/get_viewport().get_visible_rect().size.y*4.0, MIN_ZOOM, MAX_ZOOM)
				yaw = clampf(_gesture_yaw + wrapf(_touch_angle() - _gesture_angle, -PI, PI), deg_to_rad(-38), deg_to_rad(38))
				var movement := _touch_center() - _gesture_center
				pan_offset = _gesture_pan + Vector2(-movement.x,movement.y) * _gesture_units_per_pixel
				_clamp_pan()
				apply_view()
			get_viewport().set_input_as_handled()
		elif event.index == _touch_pan:
			_move_pan(event.position)
			if panning:
				touch_gesture_active = true
	elif (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1 and touch_gesture_active:
		get_viewport().set_input_as_handled()


func _touch_center() -> Vector2:
	var center := Vector2.ZERO
	for point in touches.values():
		center += point
	return center/maxi(touches.size(),1)


func _span() -> float:
	var points := touches.values()
	return points[0].distance_to(points[1]) if points.size() >= 2 else 0.0


func _touch_angle() -> float:
	var points := touches.values()
	return (points[1] - points[0]).angle() if points.size() >= 2 else 0.0
