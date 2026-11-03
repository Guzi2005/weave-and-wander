extends Node

const PaperArt = preload("res://scripts/paper_art.gd")
const PaperDollScript = preload("res://scripts/volume_doll.gd")
const CustomerDollScript = preload("res://scripts/customer_doll.gd")
const CustomerProfile = preload("res://scripts/customer_profile.gd")
const ShopInventory = preload("res://scripts/shop_inventory.gd")
const CustomerBehaviorScript = preload("res://scripts/customer_behavior.gd")
const StaffBehaviorScript = preload("res://scripts/staff_behavior.gd")
const Personality = preload("res://scripts/personality.gd")
const CounterMints = preload("res://scripts/counter_mints.gd")
const StaffCardScript = preload("res://scripts/staff_card.gd")
const WorldOverlayScript = preload("res://scripts/world_overlay.gd")
const FloatingButton = preload("res://scripts/floating_button.gd")
const BusinessSessionScript = preload("res://scripts/business_session.gd")
const WorkDispatcherScript = preload("res://scripts/work_dispatcher.gd")
const WorkshopAudioScript = preload("res://scripts/workshop_audio.gd")
const WorkshopCloseupScript = preload("res://scripts/workshop_closeup_and_photo.gd")
const SCREEN_SHADER: Shader = preload("res://shaders/screen_print.gdshader")
const ROOM_ORDER = ["workshop", "shop", "archive"]
const ROOM_NAMES = {"workshop": "织染工坊", "shop": "前店", "archive": "布料资料室"}

const ROOM_INK := Color("5a4038")
const PAPER_WHITE := Color("f2ead9")
const WALL_PINK := Color("dfc6bb")
const FLOOR_LIGHT := Color("c8c6ad")
const FLOOR_DARK := Color("9caf91")
const TEAL := Color("4d7b73")
const CORAL := Color("c75f50")
const MUSTARD := Color("d5aa48")
const BLUE := Color("779ab1")
const BURGUNDY := Color("733f45")
const OPENING_MINUTE := 9.0 * 60.0
const CLOSING_MINUTE := 18.0 * 60.0
const ELECTRICITY_RATE := 0.42

var camera: Camera3D
var facilities: Array = []
var staff: Array[PaperDoll] = []
var customers: Array[PaperDoll] = []
var dragging_doll: PaperDoll

var _actors: Node3D
var _room: Node3D
var _shop: Node3D
var _rooms: Dictionary = {}
var _active_room := "shop"
var _navigation: RefCounted
var _pop_up: Node3D
var _room_label: Label
var _room_left: Button
var _follow_bar: HBoxContainer
var _follow_third: Button
var _follow_first: Button
var _follow_second: Button
var _room_right: Button
var _camera_tween: Tween
var _roof_controls: Node
var _view_controls: Node
var _street: Node3D
var _street_life: Node3D
var _staff_jobs: Dictionary = {}
var _staff_behaviors: Dictionary = {}
var _customer_behaviors: Dictionary = {}
var _restock = preload("res://scripts/staff_restock.gd").new()
var _mints := CounterMints.new()
var _inventory: Node3D
var _production: Node3D
var _production_panel: PanelContainer
var _dye: Node3D
var _dye_panel: PanelContainer
var _supply_catalog: Node
var _order_queue_panel: PanelContainer
var _customer_serial := 0
var _cards: Dictionary = {}
var _selected_doll: PaperDoll
var _world_pressed_doll: PaperDoll
var _world_press_position := Vector2.ZERO
var _speed := 1.0
var _saved_speed := 1.0
var _day_minutes := 9.0 * 60.0
var _day_index := 1
var _money := 620
var _business_state := "open" # open -> closing -> workshop
var _electricity_kwh := 0.0
var _electricity_cost := 0.0
var _daily_electricity_cost := 0.0
var _electricity_paid := 0
var _electricity_fraction := 0.0
var _room_lights := {"shop": true, "workshop": true, "archive": true}
var _next_day_button: Button
var _business_label: Label
var _electricity_label: Label
var _shift_departures_started := false
var _workshop_time_started := false
var _business_chore: RefCounted
var _closing_sign_done := false
var _archive_switch: Node3D
var _sales_count := 0
var _browse_slots: Dictionary = {}
var _spawn_clock := 2.0
var _rng := RandomNumberGenerator.new()
var _trait_rng := RandomNumberGenerator.new()

var _time_label: Label
var _money_label: Label
var _speed_label: Label
var _speed_buttons: Dictionary = {}
var _wardrobe_button: Button
var _detail_title: Label
var _detail_body: Label
var _toast_label: Label
var _toast_tween: Tween
var _overlay: WorldOverlay
var _wardrobe: PanelContainer
var _wardrobe_return_speed := 1.0
var _drag_return_speed := 1.0
var _business_session: RefCounted
var _work_dispatcher: RefCounted
var _workshop_audio: Node
var _workshop_closeup: Node


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	for argument in arguments:
		if argument.begins_with("--test-window="):
			var dimensions := argument.get_slice("=", 1).split("x")
			if dimensions.size() == 2:
				get_window().mode = Window.MODE_WINDOWED
				get_window().size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	_rng.seed = 19430719
	_setup_world()
	_build_room()
	_street = preload("res://scripts/street_scene.gd").new()
	_street.name = "StreetScene"
	add_child(_street)
	_navigation = preload("res://scripts/shop_navigation.gd").new(_rooms, _street)
	_street_life = preload("res://scripts/street_life.gd").new()
	_street_life.name = "StreetLife"
	_street_life.controller = self
	add_child(_street_life)
	_spawn_staff()
	_business_session = BusinessSessionScript.new(self)
	_work_dispatcher = WorkDispatcherScript.new(self)
	_workshop_audio = WorkshopAudioScript.new()
	_workshop_audio.name = "WorkshopAudio"
	_workshop_audio.controller = self
	add_child(_workshop_audio)
	_business_chore = preload("res://scripts/business_chore.gd").new(self)
	var archive: Node3D = _rooms.archive
	_archive_switch = archive._group("ArchiveLightSwitch", Vector3(-6.9,1.4,2.7))
	archive._box(_archive_switch,"Plate",Vector3(.05,.22,.17),Vector3.ZERO,PAPER_WHITE)
	archive._box(_archive_switch,"Rocker",Vector3(.07,.12,.09),Vector3(.02,0,0),TEAL)
	_setup_post_process()
	_setup_ui()
	_roof_controls = preload("res://scripts/roof_interaction.gd").new()
	_roof_controls.name = "RoofInteraction"
	_roof_controls.controller = self
	add_child(_roof_controls)
	_view_controls = preload("res://scripts/street_view.gd").new()
	_view_controls.name = "StreetView"
	_view_controls.controller = self
	add_child(_view_controls)
	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()
	_assign_staff(staff[0], _facility_index("loom"), false)
	_assign_staff(staff[1], _facility_index("counter", "shop"), false)
	_assign_staff(staff[2], _facility_index("sewing"), false)
	_select_doll(staff[1])
	_spawn_customer()
	_set_business_open(true)
	_pop_up = preload("res://scripts/pop_up_world.gd").new()
	_pop_up.name = "PopUpWorld"
	_pop_up.controller = self
	add_child(_pop_up)
	_view_controls.apply_view()
	if "--capture" in arguments:
		_capture_later.call_deferred()
	elif "--smoke-test" in arguments:
		_smoke_test_later.call_deferred()
	var render_ab := preload("res://scripts/render_ab.gd").new()
	render_ab.name = "RenderAB"
	render_ab.game = self
	add_child(render_ab)


func _recover_startup_view() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(_view_controls):
		return
	get_tree().paused = false
	_speed = 1.0
	_saved_speed = 1.0
	_view_controls.clear_follow()
	_view_controls.target_zoom = 0.0
	_view_controls.target_depth = 1.0
	_view_controls.depth = 1.0
	_view_controls.zoom = 0.0
	_view_controls.pan_offset = Vector2.ZERO
	_view_controls.yaw = deg_to_rad(_view_controls.DEFAULT_YAW)
	_view_controls.pitch = deg_to_rad(_view_controls.DEFAULT_PITCH)
	_view_controls.focus_x = _room.global_position.x
	camera.make_current()
	_fit_stage()
	_view_controls.apply_view()


func _process(delta: float) -> void:
	if _navigation.refresh():
		_refresh_facilities()
		_inventory.advance()
	if _speed > 0.0:
		if _business_state == "open":
			_day_minutes += delta * _speed * 2.5
			if _day_minutes >= CLOSING_MINUTE:
				_day_minutes = CLOSING_MINUTE
				_begin_closing()
		_street_life.simulate(delta*_speed,_day_index,_day_minutes)
		for doll in staff:
			if is_instance_valid(doll):
				doll.simulate(delta, _speed)
				doll.set_meta("room", _navigation.room_at(doll.global_position))
		for doll in customers.duplicate():
			if is_instance_valid(doll):
				doll.simulate(delta, _speed)
		_business_chore.advance(delta * _speed)
		_process_staff_jobs(delta * _speed)
		_process_customers(delta * _speed)
		_process_shift_departures()
		_update_electricity(delta * _speed)
		_try_enter_workshop_time()
		_street.update_door(delta*_speed,customers+staff+[_street_life.postman])
		_spawn_clock -= delta * _speed
		if _spawn_clock <= 0.0 and customers.size() < 4:
			_spawn_customer()
			_spawn_clock = _rng.randf_range(6.5, 10.0)
	if is_instance_valid(_workshop_audio):
		_workshop_audio.tick(delta * _speed)
	if is_instance_valid(_workshop_closeup):
		_workshop_closeup.tick(delta)
	_update_ui()


func _set_business_open(value: bool) -> void:
	_business_session.set_business_open(value)


func _begin_closing() -> void:
	_business_session.begin_closing()


func _process_shift_departures() -> void:
	_business_session.process_shift_departures()


func _try_enter_workshop_time() -> void:
	_business_session.try_enter_workshop_time()


func _apply_business_chore(kind: String) -> void:
	_business_session.apply_business_chore(kind)


func _start_next_day() -> void:
	_business_session.start_next_day()


func _update_electricity(scaled_delta: float) -> void:
	_business_session.update_electricity(scaled_delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_HOME:
			_close_wardrobe()
			_recover_startup_view()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if is_instance_valid(_view_controls) and is_instance_valid(_view_controls.follow_target):
				_end_follow()
			elif _wardrobe.visible:
				_close_wardrobe()
			elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_viewport().set_input_as_handled()
		return
	var exterior_view: bool = is_instance_valid(_view_controls) and _view_controls.exterior
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_world_press_position = event.position
			_world_pressed_doll = _pick_person(event.position)
		else:
			if dragging_doll != null and _world_pressed_doll != null and _world_pressed_doll.role == "staff":
				_finish_drag(dragging_doll, event.position)
			elif _world_pressed_doll != null and event.position.distance_to(_world_press_position) <= 8.0:
				_begin_follow(_world_pressed_doll)
				get_viewport().set_input_as_handled()
			elif _selected_doll != null and _selected_doll.role == "staff" and event.position.distance_to(_world_press_position) <= 8.0 and not exterior_view:
				var facility_index := _facility_near_screen(event.position, 72.0)
				if facility_index >= 0:
					_assign_staff(_selected_doll, facility_index, true)
					get_viewport().set_input_as_handled()
			_world_pressed_doll = null
	elif event is InputEventMouseMotion and _world_pressed_doll != null and _world_pressed_doll.role == "staff" and not exterior_view:
		if dragging_doll == null and event.position.distance_to(_world_press_position) > 8.0:
			_start_drag(_world_pressed_doll)


func _setup_world() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e4eaeb")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("f5f7f5")
	environment.ambient_light_energy = 0.80
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)

	var sunlight := DirectionalLight3D.new()
	sunlight.name = "SoftWindowLight"
	sunlight.rotation_degrees = Vector3(-65.0, -24.0, 0.0)
	sunlight.light_color = Color("fff4e4")
	sunlight.light_energy = 0.30
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 30.0
	add_child(sunlight)

	var fill := OmniLight3D.new()
	fill.name = "CoolFill"
	fill.position = Vector3(4.5, 4.5, 4.5)
	fill.light_color = Color("cfe5e2")
	fill.light_energy = 0.08
	fill.omni_range = 13.0
	fill.shadow_enabled = false
	add_child(fill)

	camera = Camera3D.new()
	camera.name = "DollhousePerspectiveCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 35.0
	camera.size = 8.25
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = 1 | 2 | 4
	camera.near = 0.1
	camera.far = 320.0
	camera.position = Vector3(0.0, 19.4, 53.0)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.75, 0.25), Vector3.UP)
	_actors = Node3D.new()
	_actors.name = "AutonomousPaperPeople"
	add_child(_actors)


func _fit_stage() -> void:
	var view_size := get_viewport().get_visible_rect().size
	# Fit actual architecture, including the roof, rather than a wall-sized rectangle.
	var lower := Vector2(INF,INF)
	var upper := Vector2(-INF,-INF)
	# Use a stable front elevation for fitting, independent of the user's orbit.
	var framing_transform := Transform3D(Basis.IDENTITY, Vector3(_room.global_position.x, 19.4, 53.0))
	framing_transform = framing_transform.looking_at(Vector3(_room.global_position.x, 2.75, .25), Vector3.UP)
	var inverse := framing_transform.affine_inverse()
	var roof: Node3D = _room.get_node("HingedRoof")
	for child in _room.find_children("*","MeshInstance3D",true,false):
		var instance := child as MeshInstance3D
		if instance.mesh == null or roof.is_ancestor_of(instance):
			continue
		var bounds := instance.mesh.get_aabb()
		for corner in 8:
			var projected := inverse * instance.global_transform * bounds.get_endpoint(corner)
			lower = lower.min(Vector2(projected.x,projected.y))
			upper = upper.max(Vector2(projected.x,projected.y))
	# Reserve opening clearance once, so hovering never zooms or shifts the camera.
	for point in roof.framing_points():
		var projected: Vector3 = inverse * point
		lower = lower.min(Vector2(projected.x,projected.y))
		upper = upper.max(Vector2(projected.x,projected.y))
	var span := upper-lower
	var closed_top: Vector3 = inverse * _room.to_global(Vector3(0,6.8,-3.0))
	var composition_center := (lower.y+closed_top.y)*.5
	# The focused room stays readable while both neighbors remain visible at the sides.
	camera.size = maxf(span.y*view_size.y/(view_size.y-100),(span.x+6.8)*view_size.y/view_size.x)
	# Place the closed room band at 43% height, reserving the top for raised roofs.
	camera.size = maxf(camera.size,(upper.y-composition_center)/.40)
	camera.h_offset = (lower.x+upper.x)*.5
	camera.v_offset = composition_center-.07*camera.size
	if is_instance_valid(_view_controls):
		_view_controls.near_size = camera.size
		_view_controls.near_offset = Vector2(camera.h_offset,camera.v_offset)
		var far_low := Vector2(INF,INF)
		var far_high := Vector2(-INF,-INF)
		for x in [-17.0,17.0]:
			for y in [0.0,7.0]:
				for z in [-3.0,12.0]:
					var p: Vector3 = inverse*Vector3(x+_room.position.x,y,z)
					far_low = far_low.min(Vector2(p.x,p.y))
					far_high = far_high.max(Vector2(p.x,p.y))
		var far_span := far_high-far_low
		_view_controls.far_size = maxf(far_span.y*view_size.y/(view_size.y-160),far_span.x*view_size.y/view_size.x)
		_view_controls.far_size = maxf(_view_controls.far_size,_view_controls.near_size*1.42)
		_view_controls.far_size = maxf(_view_controls.far_size,(composition_center-far_low.y)/.49)
		_view_controls.far_offset = Vector2((far_low.x+far_high.x)*.5,composition_center-.07*_view_controls.far_size)
		_view_controls.apply_view()


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _build_room() -> void:
	_shop = preload("res://scenes/shop_room.tscn").instantiate()
	add_child(_shop)
	_rooms["shop"] = _shop
	_room = _shop
	for id in ["workshop", "archive"]:
		var side := load("res://scenes/%s_room.tscn" % id).instantiate() as Node3D
		side.position.x = -14.4 if id == "workshop" else 14.4
		add_child(side)
		_rooms[id] = side
	# One partition belongs to the room on its left; don't stack coplanar walls.
	for id in ["shop", "archive"]:
		for piece in ["LeftReturn","EntryLintel","LeftCutEdge","DoorHeader","Threshold","OpenDoor"]:
			_rooms[id].get_node("RoomShell/"+piece).free()
	# Keep front-shop indices stable for the existing customer state machine.
	for id in ["shop", "workshop", "archive"]:
		var room: Node3D = _rooms[id]
		for definition in room.facility_definitions():
			definition[2] = room.to_global(definition[2])
			definition[3] = room.to_global(definition[3])
			_register_facility.callv(definition)
			facilities.back()["room"] = id
			facilities.back()["facing"] = PI if definition[5] != "resting" and definition[0] != "counter" else 0.0
			facilities.back()["anchor"] = room.interaction_anchor(definition[0])
			facilities.back()["label_anchor"] = room.interaction_anchor(definition[0] + "_label")
			facilities.back()["initial_rotation"] = facilities.back()["anchor"].get_parent().global_rotation.y
			var fixture: Node3D = facilities.back()["anchor"].get_parent()
			if fixture.has_meta("rest_capacity"):
				facilities.back()["rest_bench"] = fixture
	_inventory = ShopInventory.new()
	_inventory.name = "ShopInventory"
	_shop.add_child(_inventory)
	_inventory.build(_shop)
	_inventory.service_authorizer = _cashier_present
	_rooms.workshop.get_node("WeavingLoom").inventory = _inventory
	_production = preload("res://scripts/production_flow.gd").new()
	_production.name = "ProductionFlow"
	add_child(_production)
	_production.setup(self)
	# Loom bolts register as the loom's own source packages, never as phantom cabinet stock.
	_rooms.workshop.get_node("WeavingLoom").production = _production
	_restock.setup(self)
	_mints.setup(self)
	_dye = preload("res://scripts/dye_flow.gd").new()
	_dye.name = "DyeFlow"
	add_child(_dye)
	_dye.setup(self)
	_supply_catalog = preload("res://scripts/supply_catalog.gd").new()
	_supply_catalog.name = "SupplyCatalog"
	add_child(_supply_catalog)
	_supply_catalog.setup(self)


func _switch_room(id: String, animate: bool = true) -> void:
	# Sliding along the row keeps the current zoom. Forcing the front page fought inspection.
	if is_instance_valid(_view_controls):
		_view_controls.reset_pan()
	if not _rooms.has(id) or id == _active_room:
		return
	if _wardrobe.visible:
		_close_wardrobe()
	_world_pressed_doll = null
	_active_room = id
	_room = _rooms[id]
	if is_instance_valid(_camera_tween):
		_camera_tween.kill()
	var previous_x: float = _view_controls.focus_x
	_view_controls.focus_x = _room.position.x
	_fit_stage()
	if animate:
		_view_controls.focus_x = previous_x
		_camera_tween = create_tween()
		_camera_tween.tween_property(_view_controls,"focus_x",_room.position.x,.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_update_ui()


func _step_room(direction: int) -> void:
	var index := ROOM_ORDER.find(_active_room) + direction
	if index >= 0 and index < ROOM_ORDER.size():
		_switch_room(ROOM_ORDER[index])


func _route_in_room(from: Vector3, to: Vector3, room_id: String) -> PackedVector3Array:
	var room: Node3D = _rooms[room_id]
	var result := PackedVector3Array()
	for point in room.route(room.to_local(from), room.to_local(to)):
		result.append(room.to_global(point))
	return result


func _send_staff_to_facility(doll: PaperDoll, facility: Dictionary) -> void:
	var id := doll.get_instance_id()
	var job: Dictionary = _staff_jobs[id]
	if facility.id in ["rack", "hats"]:
		var plan: Dictionary = _inventory.restock_plan()
		var stocking_hats: bool = not plan.is_empty() and plan.item.definition.is_hat()
		if not plan.is_empty() and facility.id == ("hats" if stocking_hats else "rack"):
			plan.item.reserved_by = "staff:%d" % id
			job["restock_id"] = plan.item.item_id
			job["restock_phase"] = "fetch"
			_staff_jobs[id] = job
			doll.set_destination(plan.fetch if job.restock_phase == "fetch" else plan.place, str(facility.activity))
			return
	doll.move_to_anchor(facility.anchor, str(facility.activity))


func _refresh_facilities() -> void:
	for index in facilities.size():
		var facility: Dictionary = facilities[index]
		if is_instance_valid(facility.anchor):
			facility.use_position = facility.anchor.global_position
			facility.label_position = facility.label_anchor.global_position
			# A moved fixture must invalidate the live staff route immediately.
			# Restock fetch/place jobs own their own target until the item is handled.
			var worker: PaperDoll = facility.get("staff")
			var job: Dictionary = _staff_jobs.get(worker.get_instance_id(), {}) if is_instance_valid(worker) else {}
			if is_instance_valid(worker) and job.get("phase", "") == "moving":
				var restock_phase := str(job.get("restock_phase", ""))
				if restock_phase == "place":
					var plan: Dictionary = _inventory.restock_plan_for(str(job.get("restock_id", "")))
					if not plan.is_empty():
						worker.set_destination(plan.place, str(facility.activity))
					else:
						worker.move_to_anchor(facility.anchor, str(facility.activity))
				elif restock_phase == "fetch":
					var fetch_plan: Dictionary = _inventory.restock_plan_for(str(job.get("restock_id", "")))
					if not fetch_plan.is_empty():
						worker.set_destination(fetch_plan.fetch, str(facility.activity))
				else:
					worker.move_to_anchor(facility.anchor, str(facility.activity))
		facilities[index] = facility


# A future furnishing UI commits here after showing its placement preview.
# Invalid edits are rolled back before any actor or item sees the new layout.
func try_place_fixture(fixture: Node3D, proposed: Transform3D) -> Dictionary:
	if not is_instance_valid(fixture) or fixture.get_parent() not in _rooms.values():
		return {"ok": false, "reason": "不是可摆放的家具"}
	var room: Node3D = fixture.get_parent()
	if not room._footprints.any(func(entry: Dictionary) -> bool: return entry.node == fixture):
		return {"ok": false, "reason": "不是可摆放的家具"}
	if not proposed.basis.get_scale().is_equal_approx(Vector3.ONE) or proposed.basis.y.distance_to(Vector3.UP) > .001 or absf(proposed.origin.y) > .001:
		return {"ok": false, "reason": "家具需要平放在地面上"}
	if fixture.name == "FittingBooth" and room.fitting_room.occupant != null:
		return {"ok": false, "reason": "试衣间正在使用"}
	var previous := fixture.transform
	fixture.transform = proposed
	room.refresh_navigation(true)
	var reason: String = room.layout_problem(fixture)
	if reason.is_empty():
		for person in staff + customers + [_street_life.postman]:
			if not is_instance_valid(person) or not person.visible or _navigation.room_at(person.global_position) == "street":
				continue
			if _rooms[_navigation.room_at(person.global_position)] == room:
				var local := room.to_local(person.global_position)
				if not room.is_walkable(Vector2(local.x, local.z)):
					reason = "这个位置有人"
					break
	if not reason.is_empty():
		fixture.transform = previous
		room.refresh_navigation(true)
		return {"ok": false, "reason": reason}
	_navigation.revision += 1
	_refresh_facilities()
	_inventory.advance()
	return {"ok": true, "reason": ""}



func _register_facility(
		id_value: String,
		title: String,
		use_position: Vector3,
		label_position: Vector3,
		accent: Color,
		activity: String,
		duration: float
	) -> void:
	facilities.append({
		"id": id_value,
		"title": title,
		"use_position": use_position,
		"label_position": label_position,
		"accent": accent,
		"activity": activity,
		"duration": duration,
		"staff": null,
	})


func _spawn_staff() -> void:
	var definitions := [
		{"name": "祖母", "hair": 2, "outfit": 1, "palette": 2, "skin": 1, "hair_color": 2, "position": Vector3(-0.6, 0.0, 2.15)},
		{"name": "阿遥", "hair": 0, "outfit": 0, "palette": 0, "skin": 0, "hair_color": 1, "position": Vector3(0.3, 0.0, 2.15)},
		{"name": "小织", "hair": 1, "outfit": 2, "palette": 3, "skin": 2, "hair_color": 0, "position": Vector3(-3.0, 0.0, 1.8)},
	]
	for definition in definitions:
		var doll := PaperDollScript.new() as PaperDoll
		doll.configure({
			"name": definition["name"],
			"role": "staff",
			"hair": definition["hair"],
			"outfit": definition["outfit"],
			"palette": definition["palette"],
			"skin": definition["skin"],
			"hair_color": definition["hair_color"],
		})
		doll.personality = Personality.roll(_trait_rng)
		doll.position = Vector3((12.0 + staff.size()*2.0) * (1 if staff.size()%2 else -1),0,7.4)
		doll.arrived.connect(_on_doll_arrived)
		doll.appearance_changed.connect(_on_doll_appearance_changed)
		_actors.add_child(doll)
		doll.set_meta("room", "street")
		doll.route_provider = _navigation.route
		doll.navigation_version = _navigation.version
		staff.append(doll)


func _spawn_customer() -> void:
	if _business_state != "open":
		return
	var doll := CustomerDollScript.new()
	_customer_serial += 1
	doll.customer_id = "customer_%03d" % _customer_serial
	doll.visit = self
	doll.profile = CustomerProfile.roll(_rng)
	doll.configure({
		"name": "%s%02d" % [doll.profile.title, _customer_serial],
		"role": "customer",
		"hair": _rng.randi_range(0, 2),
		"outfit": _rng.randi_range(0, 2),
		"palette": _rng.randi_range(0, 3),
		"skin": _rng.randi_range(0, 3),
		"hair_color": _rng.randi_range(0, 3),
		"speed": _rng.randf_range(1.05, 1.35),
	})
	doll.scale = Vector3.ONE * _rng.randf_range(0.88, 1.02)
	var street_side := -1 if _rng.randf() < .5 else 1
	doll.position = Vector3(street_side*(12.0 if customers.is_empty() and _sales_count == 0 else 38.0),0,7.4)
	doll.set_meta("street_exit",Vector3(-street_side*50.0,0,7.4))
	doll.arrived.connect(_on_doll_arrived)
	_actors.add_child(doll)
	doll.set_meta("room", "street")
	doll.route_provider = _customer_route
	doll.navigation_version = _navigation.version
	customers.append(doll)
	var available := 0
	while _browse_slots.values().has(available):
		available += 1
	_browse_slots[doll.get_instance_id()] = available
	_customer_behaviors[doll.get_instance_id()] = CustomerBehaviorScript.new(doll, self, available)
	doll._task_badge.hide()


func _customer_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	return _navigation.route(from,to)


func _assign_staff(doll: PaperDoll, facility_index: int, manual: bool) -> void:
	if is_instance_valid(doll) and bool(doll.get_meta("chore_reserved", false)):
		return
	if is_instance_valid(doll) and (bool(doll.get_meta("shift_home", false)) or bool(doll.get_meta("shift_departing", false))):
		return
	if not is_instance_valid(doll) or facility_index < 0 or facility_index >= facilities.size():
		return
	_release_restock_claim(doll)
	if manual and facilities[facility_index].activity != "resting":
		if doll.energy <= StaffBehaviorScript.rest_threshold_for(doll):
			_show_toast("%s需要先休息" % doll.doll_name)
			return
		if _staff_behaviors.has(doll.get_instance_id()):
			_staff_behaviors[doll.get_instance_id()].cancel_break()
	if facilities[facility_index].activity == "resting" and is_instance_valid(facilities[facility_index].staff) and facilities[facility_index].staff != doll:
		if manual:
			_show_toast("这个休息位有人了")
		return
	var bench: Node3D = facilities[facility_index].get("rest_bench")
	if bench != null and bench.available_span(doll.energy <= .15).is_empty() and not bench.reservations.has(doll.get_instance_id()):
		if manual: _show_toast("长凳已经坐满了")
		return
	if facilities[facility_index].id == "cutting" and not _production.order.is_empty():
		if manual: _show_toast("裁剪台正在处理这件围裙")
		return
	if is_instance_valid(_production) and _production.request_interrupt(doll,_assign_staff.bind(doll,facility_index,manual)):
		return
	_release_staff_facility(doll)
	var occupant: PaperDoll = facilities[facility_index]["staff"]
	if is_instance_valid(occupant) and occupant != doll:
		if _production.actor == occupant:
			if _production.request_interrupt(occupant,_assign_staff.bind(doll,facility_index,manual)): return
		_set_staff_idle(occupant, 1.2)
	var facility: Dictionary = facilities[facility_index]
	if bench == null:
		facility["staff"] = doll
	facilities[facility_index] = facility
	_staff_jobs[doll.get_instance_id()] = {
		"facility": facility_index,
		"phase": "moving",
		"timer": float(facility["duration"]),
		"manual": manual,
	}
	if facility.id == "sewing":
		if _production.assign(doll):
			_staff_jobs[doll.get_instance_id()]["phase"] = "production"
		else:
			_set_staff_idle(doll,1.0)
			doll.set_meta("idle_reason","缝制缺少可用材料或成品库存已满")
			if manual: _show_toast("无法开始缝制：请检查材料与成品库存")
		return
	if facility.id == "dye":
		if _dye.assign(doll):
			_staff_jobs[doll.get_instance_id()]["phase"] = "dyeing"
		else:
			_set_staff_idle(doll,1.0)
			if manual: _dye_panel.show()
		return
	if bench != null:
		doll.move_to_anchor(bench.reserve(doll,doll.energy <= .15),"resting")
	else:
		_send_staff_to_facility(doll, facility)
	if manual:
		_select_doll(doll, false)
		_show_toast("%s 已前往%s" % [doll.doll_name, facility["title"]])


func _set_staff_idle(doll: PaperDoll, delay: float = 1.0) -> void:
	if is_instance_valid(_production) and _production.request_interrupt(doll,_set_staff_idle.bind(doll,delay)):
		return
	_release_restock_claim(doll)
	_release_staff_facility(doll)
	doll.stop_navigation()
	_staff_jobs[doll.get_instance_id()] = {"facility": -1, "phase": "idle", "timer": delay, "manual": false}
	doll.set_activity("idle")


func _release_staff_facility(doll: PaperDoll) -> void:
	if is_instance_valid(_dye): _dye.suspend(doll)
	if is_instance_valid(_production): _production.suspend(doll)
	doll.clear_interaction()
	if is_instance_valid(_shop.checkout_exchange) and _shop.checkout_exchange.active and _shop.checkout_exchange.cashier.get_ref() == doll:
		_shop.checkout_exchange.cancel()
	for index in facilities.size():
		if facilities[index].id == "loom" and facilities[index].staff == doll:
			facilities[index].anchor.get_parent().stop()
		if facilities[index].has("rest_bench"):
			facilities[index].rest_bench.release(doll)
		if facilities[index]["staff"] == doll:
			var facility: Dictionary = facilities[index]
			facility["staff"] = null
			facilities[index] = facility


func _process_staff_jobs(scaled_delta: float) -> void:
	if scaled_delta <= 0.0:
		return
	for doll in staff:
		if not is_instance_valid(doll):
			continue
		var id := doll.get_instance_id()
		if _staff_jobs.get(id, {}).get("phase", "") == "business_chore":
			continue
		if bool(doll.get_meta("shift_departing", false)):
			continue
		if not _staff_jobs.has(id):
			_set_staff_idle(doll, _rng.randf_range(0.4, 1.6))
		if _staff_jobs[id].phase == "work" and not doll.has_arrived():
			_staff_jobs[id].phase = "moving"
		if not _staff_behaviors.has(id):
			_staff_behaviors[id] = StaffBehaviorScript.new(doll, self)
		_staff_behaviors[id].tick(scaled_delta)
	_cover_counter()
	_mints.tick(scaled_delta)
	_production.advance(scaled_delta)
	_dye.advance(scaled_delta)
	_supply_catalog.tick(scaled_delta)


func _tick_staff_job(doll: PaperDoll, scaled_delta: float) -> void:
	var id := doll.get_instance_id()
	var job: Dictionary = _staff_jobs[id]
	if job.phase in ["production","dyeing"]: return
	if not str(job.get("restock_phase", "")).is_empty():
		_restock.advance(doll,job,scaled_delta)
		return
	if job["phase"] == "work" and not doll.has_arrived():
		job["phase"] = "moving"
	if job["phase"] == "work":
		if facilities[job.facility].id == "counter" and _shop.checkout_exchange.active:
			return
		if facilities[job.facility].id == "loom":
			# The loom, not a fixed timer, paces this job: it runs through the
			# whole configured batch and only ends when yarn can no longer
			# start a batch. Reassignment keeps the picks on the loom.
			var loom_status := str(facilities[job.facility].anchor.get_parent().advance(doll,scaled_delta))
			if loom_status in ["no_yarn","output_full"]:
				_show_toast("织成布已放满，请先取用" if loom_status == "output_full" else "没有足够的同色毛线，织布机停工")
				_release_staff_facility(doll)
				job = {"facility": -1, "phase": "idle", "timer": _rng.randf_range(0.7, 2.0), "manual": false}
				doll.stop_navigation()
				doll.set_activity("idle")
			_staff_jobs[id] = job
			return
		job["timer"] = float(job["timer"]) - scaled_delta * (1.0 + Personality.work_bonus(doll.personality))
		if float(job["timer"]) <= 0.0:
			_finish_staff_work(doll, int(job["facility"]))
			_release_staff_facility(doll)
			job = {"facility": -1, "phase": "idle", "timer": _rng.randf_range(0.7, 2.0), "manual": false}
			doll.stop_navigation()
			doll.set_activity("idle")
	elif job["phase"] == "idle":
		job["timer"] = float(job["timer"]) - scaled_delta
		if float(job["timer"]) <= 0.0:
			_staff_jobs[id] = job
			_assign_next_autonomous_job(doll)
			return
	_staff_jobs[id] = job


func _assign_next_autonomous_job(doll: PaperDoll) -> void:
	if _business_chore != null and _business_chore.phase == "waiting":
		return
	if bool(doll.get_meta("chore_reserved", false)):
		return
	if bool(doll.get_meta("shift_home", false)) or bool(doll.get_meta("shift_departing", false)):
		return
	# The row is one workplace: a loom worker can be sent to the front counter.
	var facility_index := _best_open_job()
	var tea := _facility_index("rest", "shop")
	if tea >= 0 and facility_index != _facility_index("counter","shop") and doll.energy < .65 and _mints.can_serve(doll) and not is_instance_valid(facilities[tea].staff) and _mints.stock > _mints.LOW_STOCK:
		facility_index = tea
	if facility_index >= 0:
		doll.set_meta("idle_reason","")
		_assign_staff(doll, facility_index, false)
	else:
		doll.set_meta("idle_reason",_workshop_wait_reason())
		_set_staff_idle(doll, 1.5)


func _workshop_wait_reason() -> String:
	return _work_dispatcher.workshop_wait_reason()


func _facility_index(id_value: String, room_id := "") -> int:
	for index in facilities.size():
		if facilities[index].id == id_value and (room_id.is_empty() or facilities[index].room == room_id):
			return index
	return -1


func _counter_needs_staff() -> bool:
	return _work_dispatcher.counter_needs_staff()


func _best_open_job() -> int:
	return _work_dispatcher.best_open_job()


func _cover_counter() -> void:
	_work_dispatcher.cover_counter()


func _release_restock_claim(doll: PaperDoll) -> void:
	var item_id := str(_staff_jobs.get(doll.get_instance_id(), {}).get("restock_id", ""))
	if item_id.is_empty():
		return
	_restock.cancel(doll,item_id)



func _finish_staff_work(doll: PaperDoll, facility_index: int) -> void:
	var job: Dictionary = _staff_jobs.get(doll.get_instance_id(), {})
	match str(facilities[facility_index].id):
		"rest":
			_mints.serve(doll)
		"rack", "hats":
			pass
		"sewing":
			# Production owns material transfers and completion; a timer cannot create stock.
			pass


func _cashier_present() -> bool:
	return _work_dispatcher.cashier_present()


func _process_customers(scaled_delta: float) -> void:
	for customer_value in customers.duplicate():
		var doll := customer_value as PaperDoll
		if not is_instance_valid(doll):
			customers.erase(doll)
			continue
		doll.set_meta("room", "street" if doll.position.z > 3.4 else "shop")
		doll._task_badge.visible = doll.position.z <= 3.4
		var behavior: RefCounted = _customer_behaviors.get(doll.get_instance_id())
		if behavior != null:
			behavior.tick(scaled_delta)
	_shop.fitting_room.advance(scaled_delta)
	_inventory.advance()


func _complete_customer(doll: PaperDoll) -> void:
	_shop.fitting_room.release(doll)
	_shop.checkout_queue.leave(doll)
	_inventory.release_customer(doll)
	var id := doll.get_instance_id()
	_browse_slots.erase(id)
	_customer_behaviors.erase(id)
	customers.erase(doll)
	doll.queue_free()


func _on_doll_arrived(doll: PaperDoll) -> void:
	var id := doll.get_instance_id()
	doll.set_meta("room", _navigation.room_at(doll.global_position))
	if doll.role == "staff" and _staff_jobs.has(id):
		var job: Dictionary = _staff_jobs[id]
		if job["phase"] == "moving":
			if not str(job.get("restock_phase", "")).is_empty():
				_restock.arrived(doll,job)
				return
			var facility: Dictionary = facilities[int(job["facility"])]
			doll.resting_facing = facility.facing + facility.anchor.get_parent().global_rotation.y - facility.initial_rotation
			job["timer"] = float(facility.duration) * _rng.randf_range(0.86, 1.18)
			job["phase"] = "work"
			_staff_jobs[id] = job


func _setup_post_process() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PrintedPaperFinish"
	layer.layer = 10
	add_child(layer)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	layer.add_child(copy)
	var finish := ColorRect.new()
	finish.name = "SubtlePrintTexture"
	finish.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material_value := ShaderMaterial.new()
	material_value.shader = SCREEN_SHADER
	finish.material = material_value
	layer.add_child(finish)


func _setup_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "GameInterface"
	ui.layer = 20
	add_child(ui)

	_overlay = WorldOverlayScript.new() as WorldOverlay
	_overlay.name = "FacilityOverlay"
	_overlay.controller = self
	ui.add_child(_overlay)

	_setup_floating_hud(ui)

	var wardrobe := PanelContainer.new()
	_wardrobe = wardrobe
	wardrobe.name = "PaperWardrobe"
	wardrobe.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	wardrobe.offset_left = -306.0
	wardrobe.offset_top = 88.0
	wardrobe.offset_right = -18.0
	wardrobe.offset_bottom = -22.0
	wardrobe.add_theme_stylebox_override("panel", _panel_style(Color(0.96, 0.93, 0.85, 1.0), ROOM_INK, 1, 7))
	ui.add_child(wardrobe)
	wardrobe.hide()
	var wardrobe_margin := MarginContainer.new()
	wardrobe_margin.add_theme_constant_override("margin_left", 16)
	wardrobe_margin.add_theme_constant_override("margin_right", 16)
	wardrobe_margin.add_theme_constant_override("margin_top", 16)
	wardrobe_margin.add_theme_constant_override("margin_bottom", 16)
	wardrobe.add_child(wardrobe_margin)
	var wardrobe_content := VBoxContainer.new()
	wardrobe_content.add_theme_constant_override("separation", 12)
	wardrobe_margin.add_child(wardrobe_content)
	var title_row := HBoxContainer.new()
	wardrobe_content.add_child(title_row)
	_detail_title = Label.new()
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_title.add_theme_font_size_override("font_size", 24)
	_detail_title.add_theme_color_override("font_color", BURGUNDY)
	title_row.add_child(_detail_title)
	var close_button := FloatingButton.new()
	close_button.configure("x", "关闭衣橱")
	close_button.pressed.connect(_close_wardrobe)
	title_row.add_child(close_button)
	var rule := HSeparator.new()
	rule.add_theme_color_override("separator", Color("bba58c"))
	wardrobe_content.add_child(rule)
	_detail_body = Label.new()
	_detail_body.custom_minimum_size.y = 74.0
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.add_theme_font_size_override("font_size", 15)
	_detail_body.add_theme_color_override("font_color", ROOM_INK)
	wardrobe_content.add_child(_detail_body)
	wardrobe_content.add_child(_section_label("发型"))
	var hair_row := HBoxContainer.new()
	hair_row.add_theme_constant_override("separation", 6)
	wardrobe_content.add_child(hair_row)
	for hair_data in [["双髻", 0], ["短发", 1], ["长辫", 2], ["齐肩卷发", 3]]:
		var button := _make_text_button(str(hair_data[0]), Vector2(76.0, 44.0))
		button.pressed.connect(_change_hair.bind(int(hair_data[1])))
		hair_row.add_child(button)
	wardrobe_content.add_child(_section_label("鞋型"))
	var shoes := HBoxContainer.new()
	wardrobe_content.add_child(shoes)
	for style in ["基础便鞋", "一字带浅口鞋"]:
		var button := _make_text_button(style, Vector2(110, 44))
		var index := shoes.get_child_count()
		button.pressed.connect(func():
			if is_instance_valid(_selected_doll):
				_selected_doll.set_shoe_style(index))
		shoes.add_child(button)
	wardrobe_content.add_child(_section_label("服装结构"))
	var outfit_row := HBoxContainer.new()
	outfit_row.add_theme_constant_override("separation", 6)
	wardrobe_content.add_child(outfit_row)
	for outfit_data in [["长衫", 0], ["围裙", 1], ["短褂", 2]]:
		var button := _make_text_button(str(outfit_data[0]), Vector2(76.0, 44.0))
		button.pressed.connect(_change_outfit.bind(int(outfit_data[1])))
		outfit_row.add_child(button)
	var ukrainian_button := _make_text_button("乌克兰参考套装", Vector2(160, 44))
	ukrainian_button.pressed.connect(func():
		if is_instance_valid(_selected_doll):
			_selected_doll.wear_ukrainian_set())
	wardrobe_content.add_child(ukrainian_button)
	wardrobe_content.add_child(_section_label("配色纸样"))
	var swatch_row := HBoxContainer.new()
	swatch_row.add_theme_constant_override("separation", 9)
	wardrobe_content.add_child(swatch_row)
	for palette_index in PaperDoll.OUTFIT_PALETTES.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(46.0, 44.0)
		swatch.tooltip_text = "纸样配色 %d" % (palette_index + 1)
		var palette_color: Color = PaperDoll.OUTFIT_PALETTES[palette_index][0]
		swatch.add_theme_stylebox_override("normal", _panel_style(palette_color, ROOM_INK, 1, 5))
		swatch.add_theme_stylebox_override("hover", _panel_style(palette_color.lightened(0.12), MUSTARD, 3, 5))
		swatch.add_theme_stylebox_override("pressed", _panel_style(palette_color.darkened(0.08), MUSTARD, 3, 5))
		swatch.pressed.connect(_change_palette.bind(palette_index))
		swatch_row.add_child(swatch)
	var flexible_space := Control.new()
	flexible_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wardrobe_content.add_child(flexible_space)

	_toast_label = Label.new()
	_toast_label.name = "ShopEvent"
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_label.position = Vector2(-190.0, -120.0)
	_toast_label.size = Vector2(380.0, 42.0)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast_label.add_theme_color_override("font_color", Color("445758"))
	_toast_label.add_theme_color_override("font_outline_color", Color("f6f6ef"))
	_toast_label.add_theme_constant_override("outline_size", 5)
	_toast_label.modulate.a = 0.0
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_toast_label)
	_production_panel = preload("res://scripts/production_panel.gd").new()
	ui.add_child(_production_panel)
	_production_panel.setup(self)
	_dye_panel = preload("res://scripts/dye_panel.gd").new()
	ui.add_child(_dye_panel)
	_dye_panel.setup(self)
	_order_queue_panel = preload("res://scripts/order_queue_panel.gd").new()
	ui.add_child(_order_queue_panel)
	_order_queue_panel.setup(self)


func _setup_floating_hud(ui: CanvasLayer) -> void:
	var hud := Control.new()
	hud.name = "FloatingHUD"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stats := VBoxContainer.new()
	stats.name = "ShopStatus"
	stats.position = Vector2(24,20)
	stats.add_theme_constant_override("separation",8)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(stats)
	_time_label = _status_line(stats,"sun",Color("ad803f"))
	_money_label = _status_line(stats,"coins",Color("487d74"))
	_business_label = Label.new()
	_business_label.custom_minimum_size.x = 220
	_business_label.add_theme_font_size_override("font_size", 14)
	_business_label.add_theme_color_override("font_color", ROOM_INK)
	_business_label.add_theme_color_override("font_outline_color", PAPER_WHITE)
	_business_label.add_theme_constant_override("outline_size", 5)
	stats.add_child(_business_label)
	_electricity_label = Label.new()
	_electricity_label.custom_minimum_size.x = 220
	_electricity_label.add_theme_font_size_override("font_size", 13)
	_electricity_label.add_theme_color_override("font_color", Color("526b67"))
	_electricity_label.add_theme_color_override("font_outline_color", PAPER_WHITE)
	_electricity_label.add_theme_constant_override("outline_size", 5)
	stats.add_child(_electricity_label)
	_next_day_button = _make_text_button("进入下一天", Vector2(160, 34))
	_next_day_button.pressed.connect(_start_next_day)
	_next_day_button.hide()
	stats.add_child(_next_day_button)
	var production_button := _make_text_button("材料与制作",Vector2(136,36))
	production_button.pressed.connect(func() -> void:
		_production_panel.visible = not _production_panel.visible
		if _production_panel.visible:
			_dye_panel.hide()
			_order_queue_panel.hide()
			_switch_room("workshop")
			_production_panel.refresh()
	)
	stats.add_child(production_button)
	var dye_button := _make_text_button("染缸与配色",Vector2(136,32))
	dye_button.pressed.connect(func() -> void:
		_dye_panel.visible = not _dye_panel.visible
		if _dye_panel.visible:
			_production_panel.hide()
			_order_queue_panel.hide()
			_switch_room("workshop")
			_dye_panel.refresh())
	stats.add_child(dye_button)
	var supply_button := _make_text_button("供应目录",Vector2(136,32))
	supply_button.pressed.connect(func() -> void:
		_order_queue_panel.visible = not _order_queue_panel.visible
		if _order_queue_panel.visible:
			_production_panel.hide()
			_dye_panel.hide()
			_switch_room("workshop")
			_order_queue_panel.refresh())
	stats.add_child(supply_button)
	var reset_view_button := _make_text_button("恢复视角 · Home",Vector2(136,32))
	reset_view_button.pressed.connect(func() -> void:
		if is_instance_valid(_workshop_closeup):
			_workshop_closeup.exit_closeup()
		_close_wardrobe()
		_recover_startup_view()
	)
	stats.add_child(reset_view_button)
	_workshop_closeup = WorkshopCloseupScript.new()
	_workshop_closeup.name = "WorkshopCloseupAndPhoto"
	add_child(_workshop_closeup)
	_workshop_closeup.setup(self, hud)
	var closeup_button := _make_text_button("工位微距 · 助工", Vector2(136, 32))
	closeup_button.pressed.connect(func() -> void:
		_workshop_closeup.cycle_station_closeup()
	)
	stats.add_child(closeup_button)
	var postcard_button := _make_text_button("标本明信片", Vector2(136, 32))
	postcard_button.pressed.connect(func() -> void:
		_workshop_closeup.capture_specimen_postcard()
	)
	stats.add_child(postcard_button)
	var tools_row := HBoxContainer.new()
	tools_row.name = "ShopTools"
	hud.add_child(tools_row)
	tools_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tools_row.offset_left = -180
	tools_row.offset_right = -20
	tools_row.offset_top = 20
	tools_row.offset_bottom = 68
	tools_row.add_theme_constant_override("separation",8)
	tools_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wardrobe_button = FloatingButton.new()
	_wardrobe_button.name = "Wardrobe"
	_wardrobe_button.configure("shirt","角色与换装",true)
	_wardrobe_button.pressed.connect(func() -> void:
		if _wardrobe.visible:
			_close_wardrobe()
		else:
			_open_doll_details(_selected_doll)
	)
	tools_row.add_child(_wardrobe_button)
	var study := FloatingButton.new()
	study.name = "DollStudy"
	study.configure("person-standing","人偶转台（返回时重新开始店铺演示）")
	study.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://tests/appearance_preview.tscn"))
	tools_row.add_child(study)
	var fullscreen := FloatingButton.new()
	fullscreen.name = "Fullscreen"
	fullscreen.configure("maximize","切换全屏")
	fullscreen.pressed.connect(_toggle_fullscreen)
	tools_row.add_child(fullscreen)
	_follow_bar = HBoxContainer.new()
	_follow_bar.name = "FollowView"
	_follow_bar.add_theme_constant_override("separation", 8)
	_follow_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_follow_bar)
	_follow_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_follow_bar.offset_left = -230
	_follow_bar.offset_right = 230
	_follow_bar.offset_top = 20
	_follow_bar.offset_bottom = 68
	_follow_third = Button.new()
	_follow_third.text = "第三人称"
	_follow_third.toggle_mode = true
	_follow_third.focus_mode = Control.FOCUS_NONE
	_follow_third.pressed.connect(_set_follow_perspective.bind(false))
	_follow_bar.add_child(_follow_third)
	_follow_first = Button.new()
	_follow_first.text = "第一人称"
	_follow_first.toggle_mode = true
	_follow_first.focus_mode = Control.FOCUS_NONE
	_follow_first.pressed.connect(_set_follow_perspective.bind(true))
	_follow_bar.add_child(_follow_first)
	_follow_second = Button.new()
	_follow_second.text = "第二人称 · 对面"
	_follow_second.tooltip_text = "从小人目光前方看向小人；遇到遮挡会转到侧面"
	_follow_second.toggle_mode = true
	_follow_second.focus_mode = Control.FOCUS_NONE
	_follow_second.pressed.connect(func() -> void:
		_view_controls.set_follow_mode(2)
		_update_ui())
	_follow_bar.add_child(_follow_second)
	var leave_follow := Button.new()
	leave_follow.text = "返回"
	leave_follow.focus_mode = Control.FOCUS_NONE
	leave_follow.pressed.connect(_end_follow)
	_follow_bar.add_child(leave_follow)
	_follow_bar.hide()
	var cards := HBoxContainer.new()
	cards.name = "StaffCards"
	hud.add_child(cards)
	cards.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	cards.offset_left = 20
	cards.offset_top = -128
	cards.offset_right = 294
	cards.offset_bottom = -16
	cards.add_theme_constant_override("separation",8)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for doll in staff:
		var card := StaffCardScript.new() as StaffCard
		card.bind(doll)
		card.portrait_clicked.connect(_select_doll)
		card.details_clicked.connect(_open_doll_details)
		card.drag_started.connect(_start_drag)
		card.drag_finished.connect(_finish_drag)
		cards.add_child(card)
		_cards[doll.get_instance_id()] = card
	var rooms_row := HBoxContainer.new()
	rooms_row.name = "RoomNavigation"
	hud.add_child(rooms_row)
	rooms_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	rooms_row.offset_left = -112
	rooms_row.offset_right = 112
	rooms_row.offset_top = -68
	rooms_row.offset_bottom = -20
	rooms_row.add_theme_constant_override("separation",8)
	rooms_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_left = FloatingButton.new()
	_room_left.configure("chevron-left", "前往左侧房间")
	_room_left.pressed.connect(_step_room.bind(-1))
	rooms_row.add_child(_room_left)
	_room_label = Label.new()
	_room_label.custom_minimum_size = Vector2(112,48)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_label.add_theme_font_size_override("font_size",18)
	_room_label.add_theme_color_override("font_color",Color("445758"))
	_room_label.add_theme_color_override("font_outline_color",Color("f6f6ef"))
	_room_label.add_theme_constant_override("outline_size",3)
	_room_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rooms_row.add_child(_room_label)
	_room_right = FloatingButton.new()
	_room_right.configure("chevron-right", "前往右侧房间")
	_room_right.pressed.connect(_step_room.bind(1))
	rooms_row.add_child(_room_right)
	var clock_row := HBoxContainer.new()
	clock_row.name = "TimeControls"
	hud.add_child(clock_row)
	clock_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	clock_row.offset_left = -296
	clock_row.offset_right = -20
	clock_row.offset_top = -68
	clock_row.offset_bottom = -20
	clock_row.add_theme_constant_override("separation",8)
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label = Label.new()
	_speed_label.custom_minimum_size.x = 44
	_speed_label.add_theme_color_override("font_color",Color("445758"))
	_speed_label.add_theme_font_size_override("font_size",16)
	_speed_label.add_theme_constant_override("outline_size",4)
	_speed_label.add_theme_color_override("font_outline_color",Color("f6f6ef"))
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_row.add_child(_speed_label)
	for definition in [["pause",0.0,"暂停"],["play",1.0,"正常速度"],["fast-forward",2.0,"二倍速度"],["skip-forward",4.0,"四倍速度"]]:
		var button := FloatingButton.new()
		button.name = str(definition[0]).replace("-", "_")
		button.configure(definition[0],definition[2],true)
		button.pressed.connect(_set_speed.bind(float(definition[1])))
		clock_row.add_child(button)
		_speed_buttons[float(definition[1])] = button


func _status_line(parent: Node, symbol: String, color: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/icons/%s.svg"%symbol)
	icon.modulate = color
	icon.custom_minimum_size = Vector2(24,24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.custom_minimum_size.x = 160
	label.add_theme_font_size_override("font_size",18)
	label.add_theme_color_override("font_color",Color("445758"))
	label.add_theme_color_override("font_outline_color",Color("f6f6ef"))
	label.add_theme_constant_override("outline_size",4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return label


func _panel_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _make_text_button(text_value: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum_size
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", ROOM_INK)
	button.add_theme_color_override("font_hover_color", BURGUNDY)
	button.add_theme_stylebox_override("normal", _panel_style(Color("efe4d1"), Color("aa8e75"), 1, 6))
	button.add_theme_stylebox_override("hover", _panel_style(Color("f6e9c8"), MUSTARD, 2, 6))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("ddcfb5"), BURGUNDY, 2, 6))
	return button


func _section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("765348"))
	return label


func _update_ui() -> void:
	if is_instance_valid(_room_label):
		_room_label.text = ROOM_NAMES[_active_room] if not is_instance_valid(_pop_up) or _pop_up.is_front_room() else _pop_up.page_name()
		var room_index := ROOM_ORDER.find(_active_room)
		_room_left.disabled = room_index == 0
		_room_right.disabled = room_index == ROOM_ORDER.size()-1
		_room_left.tooltip_text = "前往" + ROOM_NAMES[ROOM_ORDER[maxi(room_index-1,0)]]
		_room_right.tooltip_text = "前往" + ROOM_NAMES[ROOM_ORDER[mini(room_index+1,ROOM_ORDER.size()-1)]]
	if is_instance_valid(_time_label):
		var hour := int(_day_minutes / 60.0) % 24
		var minute := int(_day_minutes) % 60
		_time_label.text = "第 %d 日  %02d:%02d" % [_day_index, hour, minute]
	if is_instance_valid(_business_label):
		_business_label.text = {"opening":"准备开门 · 翻回营业木牌", "open":"营业中 · 09:00–18:00", "closing":"打烊中 · 整理与送客", "workshop":"纯工坊时间 · 等待进入下一天"}.get(_business_state, "")
	if is_instance_valid(_electricity_label):
		_electricity_label.text = "电费 %.2f · %.2f kWh" % [_electricity_cost, _electricity_kwh]
	if is_instance_valid(_next_day_button):
		_next_day_button.visible = _business_state == "workshop"
		_next_day_button.disabled = _business_chore != null and _business_chore.phase != "idle"
	if is_instance_valid(_money_label):
		_money_label.text = "%d" % _money
	if is_instance_valid(_speed_label):
		_speed_label.text = "暂停" if _speed == 0.0 else "x%s" % str(_speed)
	for value in _speed_buttons:
		_speed_buttons[value].set_pressed_no_signal(is_equal_approx(_speed,float(value)))
	if is_instance_valid(_wardrobe_button):
		_wardrobe_button.set_pressed_no_signal(_wardrobe.visible)
	var following := is_instance_valid(_view_controls) and is_instance_valid(_view_controls.follow_target)
	if is_instance_valid(_follow_bar):
		_follow_bar.visible = following
	if following and is_instance_valid(_follow_third):
		_follow_third.set_pressed_no_signal(_view_controls.follow_mode == 3)
		_follow_second.set_pressed_no_signal(_view_controls.follow_mode == 2)
		_follow_first.set_pressed_no_signal(_view_controls.follow_first_person)
	if is_instance_valid(_selected_doll) and is_instance_valid(_detail_body):
		_detail_title.text = _selected_doll.doll_name
		_detail_body.text = "当前：%s\n体力：%d%%" % [
			_activity_name(_selected_doll.activity),
			int(_selected_doll.energy * 100.0),
		]
		if _selected_doll.role == "staff":
			_detail_body.text += "\n" + Personality.describe(_selected_doll.personality)
			if _selected_doll.activity == "idle":
				_detail_body.text += "\n" + str(_selected_doll.get_meta("idle_reason",""))
	for id in _cards:
		var card: StaffCard = _cards[id]
		if is_instance_valid(card):
			card.set_selected(is_instance_valid(_selected_doll) and _selected_doll.get_instance_id() == id)


func _activity_name(value: String) -> String:
	match value:
		"sewing": return "缝制"
		"weaving": return "织布"
		"stocking": return "整理陈列"
		"checkout": return "接待结账"
		"resting": return "长椅休息"
		"napping": return "小睡"
		"browsing": return "挑选"
		"fitting": return "试穿"
		"leaving": return "离店"
		_: return "等待安排"


func _set_speed(value: float) -> void:
	if _wardrobe.visible:
		_wardrobe_return_speed = value
		return
	_speed = value
	if value > 0.0:
		_saved_speed = value


func _select_doll(doll: PaperDoll, locate: bool = true) -> void:
	if not is_instance_valid(doll):
		return
	if is_instance_valid(_selected_doll):
		_selected_doll.set_selected(false)
	_selected_doll = doll
	_selected_doll.set_selected(true)
	if locate:
		if is_instance_valid(_view_controls):
			_view_controls.target_zoom = 0.0
		_switch_room(doll.get_meta("room", "shop"))
	_show_toast("已定位 %s" % doll.doll_name)


func _open_doll_details(doll: PaperDoll) -> void:
	if not is_instance_valid(doll):
		return
	_select_doll(doll)
	if not _wardrobe.visible:
		_wardrobe_return_speed = _speed
	_wardrobe.show()
	_speed = 0.0
	if doll is VolumeDoll:
		doll.face_for_wardrobe()


func _close_wardrobe() -> void:
	_wardrobe.hide()
	_speed = _wardrobe_return_speed


func _change_hair(style_index: int) -> void:
	if is_instance_valid(_selected_doll):
		_speed = 0.0
		_selected_doll.set_hair_style(style_index)


func _change_outfit(style_index: int) -> void:
	if is_instance_valid(_selected_doll):
		_speed = 0.0
		_selected_doll.set_outfit_style(style_index)


func _change_palette(palette_index: int) -> void:
	if is_instance_valid(_selected_doll):
		_speed = 0.0
		_selected_doll.set_palette(palette_index)


func _on_doll_appearance_changed(doll: PaperDoll) -> void:
	if _cards.has(doll.get_instance_id()):
		var card: StaffCard = _cards[doll.get_instance_id()]
		card.queue_redraw()


func _pick_person(screen_position: Vector2) -> PaperDoll:
	var people: Array[PaperDoll] = []
	people.assign(staff)
	for doll in customers:
		people.append(doll)
	return _pick_from(people, screen_position)


func _pick_staff(screen_position: Vector2) -> PaperDoll:
	return _pick_from(staff, screen_position)


func _pick_from(people: Array[PaperDoll], screen_position: Vector2) -> PaperDoll:
	var nearest: PaperDoll
	var nearest_depth := -INF
	for doll in people:
		if not is_instance_valid(doll) or not doll.visible:
			continue
		var anchor := doll.global_position
		if camera.is_position_behind(anchor):
			continue
		var upper := camera.unproject_position(anchor + Vector3(-0.47, PaperDoll.ADULT_HEIGHT + PaperDoll.SOLE_HEIGHT, 0.0))
		var lower := camera.unproject_position(anchor + Vector3(0.47, 0.0, 0.0))
		var hit_rect := Rect2(upper, lower - upper).abs().grow(8.0)
		if hit_rect.has_point(screen_position) and doll.position.z > nearest_depth:
			nearest = doll
			nearest_depth = doll.position.z
	return nearest


func _facility_near_screen(screen_position: Vector2, maximum_distance: float) -> int:
	# Street facades hide the rooms. Any opened page of the row can receive a worker.
	if is_instance_valid(_view_controls) and _view_controls.exterior:
		return -1
	var nearest := -1
	var nearest_distance := maximum_distance
	for index in facilities.size():
		var point: Vector3 = facilities[index]["label_position"]
		if camera.is_position_behind(point):
			continue
		var distance := camera.unproject_position(point).distance_to(screen_position)
		if distance < nearest_distance:
			nearest = index
			nearest_distance = distance
	return nearest


func _begin_follow(doll: PaperDoll) -> void:
	if not is_instance_valid(doll) or not is_instance_valid(_view_controls):
		return
	_view_controls.follow(doll, false)
	if doll.role == "staff":
		_select_doll(doll, false)
	if is_instance_valid(_follow_bar):
		_follow_bar.show()
	_show_toast("正在跟随 %s" % doll.doll_name)
	_update_ui()


func _set_follow_perspective(first_person: bool) -> void:
	if not is_instance_valid(_view_controls) or not is_instance_valid(_view_controls.follow_target):
		return
	_view_controls.follow(_view_controls.follow_target, first_person)
	_update_ui()


func _end_follow() -> void:
	if is_instance_valid(_view_controls):
		_view_controls.clear_follow()
	if is_instance_valid(_follow_bar):
		_follow_bar.hide()
	_update_ui()


func _start_drag(doll: PaperDoll) -> void:
	if not is_instance_valid(doll) or doll.is_off_shift():
		return
	dragging_doll = doll
	_view_controls.target_zoom = 0.0
	_select_doll(doll, false)
	if _wardrobe.visible:
		_close_wardrobe()
	_drag_return_speed = _speed
	_speed = 0.0


func _finish_drag(doll: PaperDoll, screen_position: Vector2) -> void:
	if dragging_doll != doll:
		return
	if not is_instance_valid(doll):
		dragging_doll = null
		return
	var facility_index := _facility_near_screen(screen_position, 105.0)
	if facility_index >= 0:
		_assign_staff(doll, facility_index, true)
	else:
		_show_toast("未放到设施上，安排保持不变")
	dragging_doll = null
	_speed = _drag_return_speed


func _show_toast(message: String) -> void:
	if not is_instance_valid(_toast_label):
		return
	_toast_label.text = message
	if is_instance_valid(_toast_tween):
		_toast_tween.kill()
	_toast_label.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_label, "modulate:a", 1.0, 0.16)
	_toast_tween.tween_interval(1.8)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.35)


func _capture_later() -> void:
	for _frame in 45:
		await get_tree().process_frame
	await get_tree().create_timer(0.65).timeout
	if "--capture-wardrobe" in OS.get_cmdline_user_args():
		_open_doll_details(staff[1])
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var capture_name := "paper_dollhouse"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-name="):
			capture_name = argument.get_slice("=", 1).validate_filename()
	var output_path := ProjectSettings.globalize_path("res://captures/%s.png" % capture_name)
	if image == null:
		push_error("Capture unavailable with the current display driver.")
		get_tree().quit(2)
		return
	var result := image.save_png(output_path)
	print("CAPTURE_RESULT=", result, " SIZE=", image.get_size(), " MODE=", get_window().mode, " PATH=", output_path)
	get_tree().quit()


func _smoke_test_later() -> void:
	await get_tree().create_timer(0.45).timeout
	var customer_start := customers[0].position if not customers.is_empty() else Vector3.ZERO
	staff[1].set_hair_style(2)
	staff[1].set_outfit_style(2)
	staff[1].set_palette(3)
	_assign_staff(staff[1], 0, true)
	_speed = 4.0
	await get_tree().create_timer(2.2).timeout
	var customer_moved := not customers.is_empty() and customers[0].position.distance_to(customer_start) > 0.15
	var passed := customer_moved and facilities.size() == 13 and staff.size() == 3 and _staff_jobs.size() == 3
	print("SMOKE_TEST customer_moved=", customer_moved, " staff=", staff.size(), " facilities=", facilities.size(), " money=", _money)
	if not passed:
		push_error("Paper dollhouse smoke test failed.")
		get_tree().quit(1)
		return
	print("SMOKE_TEST_PASS")
	get_tree().quit()
