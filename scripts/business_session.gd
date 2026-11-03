class_name BusinessSession
extends RefCounted

## Decoupled business hours, day-cycle state machine, shift departure rules,
## and room/facility electricity accounting ("Lego Brick" extracted from main.gd).

const OPENING_MINUTE := 9.0 * 60.0
const CLOSING_MINUTE := 18.0 * 60.0
const ELECTRICITY_RATE := 0.42

var controller: Node


func _init(host: Node) -> void:
	controller = host


func set_business_open(value: bool) -> void:
	controller._business_state = "open" if value else "closing"
	controller._room_lights.shop = value
	if value:
		controller._room_lights.workshop = true
		controller._room_lights.archive = true
	if is_instance_valid(controller._street):
		controller._street.set_shop_open(value)
	if is_instance_valid(controller._pop_up) and is_instance_valid(controller._pop_up.desk):
		controller._pop_up.desk.set_shop_open(value)


func begin_closing() -> void:
	if controller._business_state != "open":
		return
	controller._business_state = "closing"
	controller._closing_sign_done = false
	controller._business_chore.start("close_sign", Vector3(1.55, 0, 2.95), Vector3(1.58, 1.92, 3.91))
	controller._shift_departures_started = true
	controller._show_toast("18:00 · 店铺打烊，顾客完成当前环节后离店")
	for customer_value in controller.customers.duplicate():
		var customer := customer_value as PaperDoll
		var behavior: RefCounted = controller._customer_behaviors.get(customer.get_instance_id())
		if behavior != null and behavior.has_method("close_shop"):
			behavior.close_shop()
	for index in controller.staff.size():
		var doll: PaperDoll = controller.staff[index]
		if not is_instance_valid(doll) or index < 2:
			continue
		var job: Dictionary = controller._staff_jobs.get(doll.get_instance_id(), {})
		doll.set_meta("shift_home", true)
		doll.set_meta("shift_home_pending", job.get("phase", "idle") in ["moving", "work", "production", "dyeing"])


func process_shift_departures() -> void:
	if not controller._shift_departures_started:
		return
	for index in range(2, controller.staff.size()):
		var doll: PaperDoll = controller.staff[index]
		if not is_instance_valid(doll) or not bool(doll.get_meta("shift_home", false)):
			continue
		if bool(doll.get_meta("chore_reserved", false)):
			continue
		if bool(doll.get_meta("shift_home_pending", false)):
			var job: Dictionary = controller._staff_jobs.get(doll.get_instance_id(), {})
			if job.get("phase", "idle") in ["moving", "work", "production", "dyeing"]:
				continue
			doll.set_meta("shift_home_pending", false)
		if not bool(doll.get_meta("shift_departing", false)):
			doll.set_meta("shift_departing", true)
			controller._release_staff_facility(doll)
			doll.stop_navigation()
			controller._staff_jobs[doll.get_instance_id()] = {"facility": -1, "phase": "off_shift", "manual": false}
			doll.set_destination(Vector3(52.0 if index % 2 else -52.0, 0, 7.4), "leaving")
		if absf(doll.position.x) > 45.0:
			doll.hide()
			doll.stop_navigation()
			doll.set_meta("shift_home", false)


func try_enter_workshop_time() -> void:
	if controller._business_state != "closing" or controller._workshop_time_started:
		return
	if not controller.customers.is_empty():
		return
	if not controller._closing_sign_done or controller._business_chore.phase != "idle":
		return
	for index in range(2, controller.staff.size()):
		if is_instance_valid(controller.staff[index]) and controller.staff[index].visible:
			return
	controller._business_chore.start("archive_off", controller._rooms.archive.to_global(Vector3(-6.3, 0, 2.7)), controller._archive_switch.global_position)
	controller._workshop_time_started = true


func apply_business_chore(kind: String) -> void:
	match kind:
		"close_sign":
			controller._street.set_shop_open(false)
			controller._room_lights.shop = false
			controller._closing_sign_done = true
		"archive_off":
			controller._room_lights.archive = false
			controller._business_state = "workshop"
			controller._show_toast("顾客已离店 · 进入纯工坊时间，可安排设计与生产")
		"open_sign":
			set_business_open(true)
			controller._spawn_customer()
			controller._show_toast("第 %d 日 09:00 · 店铺重新开门" % controller._day_index)
	if is_instance_valid(controller._pop_up):
		controller._pop_up.desk.set_shop_open(controller._business_state == "open")


func start_next_day() -> void:
	if controller._business_state != "workshop" or controller._business_chore.phase != "idle":
		return
	controller._day_index += 1
	controller._day_minutes = OPENING_MINUTE
	controller._electricity_kwh = 0.0
	controller._electricity_cost = 0.0
	controller._daily_electricity_cost = 0.0
	controller._electricity_paid = 0
	controller._business_state = "opening"
	controller._workshop_time_started = false
	controller._shift_departures_started = false
	controller._mints.reserve = controller._mints.RESERVE_START
	controller._business_chore.start("open_sign", Vector3(1.55, 0, 2.95), Vector3(1.58, 1.92, 3.91))
	for index in range(2, controller.staff.size()):
		var doll: PaperDoll = controller.staff[index]
		if not is_instance_valid(doll):
			continue
		doll.show()
		doll.position = Vector3(46.0 if index % 2 else -46.0, 0, 7.4)
		doll.set_meta("shift_home", false)
		doll.set_meta("shift_departing", false)
		doll.set_meta("shift_home_pending", false)
		doll.energy = 1.0
		if controller._staff_behaviors.has(doll.get_instance_id()):
			controller._staff_behaviors[doll.get_instance_id()].cancel_break()
		controller._assign_staff(doll, controller._facility_index("sewing") if index == 2 else controller._facility_index("loom"), false)
	controller._show_toast("准备开门 · 正在翻回 OPEN 木牌")


func update_electricity(scaled_delta: float) -> void:
	if scaled_delta <= 0.0:
		return
	var lit_rooms := 0
	for enabled in controller._room_lights.values():
		if enabled:
			lit_rooms += 1
	var facility_load := 0.0
	if is_instance_valid(controller._production) and is_instance_valid(controller._production.actor) and controller._production.phase == "sew" and controller._production.actor.has_arrived() and controller._production.actor.navigation_status != "blocked":
		facility_load += 0.48
	if is_instance_valid(controller._dye) and is_instance_valid(controller._dye.actor) and controller._dye.phase == "dye" and controller._dye.actor.has_arrived() and controller._dye.actor.navigation_status != "blocked":
		facility_load += 0.62
	var kwh := (lit_rooms * .055 + facility_load) * scaled_delta * 2.5 / 60.0
	controller._electricity_kwh += kwh
	controller._electricity_cost += kwh * ELECTRICITY_RATE
	controller._daily_electricity_cost = controller._electricity_cost
	controller._electricity_fraction += kwh * ELECTRICITY_RATE
	var charge := floori(controller._electricity_fraction)
	if charge > 0:
		controller._money -= charge
		controller._electricity_paid += charge
		controller._electricity_fraction -= charge
