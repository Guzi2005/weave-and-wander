class_name WorkDispatcher
extends RefCounted

## Decoupled staff work arbitration across shop counter, restock, sewing,
## dyeing, and loom stations ("Lego Brick" extracted from main.gd).

const StaffBehaviorScript = preload("res://scripts/staff_behavior.gd")

var controller: Node


func _init(host: Node) -> void:
	controller = host


func workshop_wait_reason() -> String:
	var loom = controller._rooms.workshop.get_node("WeavingLoom")
	if not controller._production.order.is_empty():
		return "等待缝纫工位或其他任务完成"
	if not controller._production.auto_restock:
		return "自动缝制未开启，可在供货目录安排订单"
	if controller._inventory.in_location("storage").size() >= controller._production.auto_stock_target:
		return "备用成衣已达到目标 %d 件；可在供货目录追加订单" % controller._production.auto_stock_target
	if loom._free_output_slot() < 0:
		return "织成布架已满，先取用布料制作衣服"
	if not loom.work_available():
		return "待补充同色毛线；缝制请检查所选布料和缝线"
	return "等待空闲工位"


func counter_needs_staff() -> bool:
	if controller.customers.any(func(doll: PaperDoll) -> bool: return doll.get_meta("room", "") == "shop"):
		return true
	return controller._shop.checkout_queue.queue.any(func(entry: WeakRef) -> bool: return is_instance_valid(entry.get_ref()))


func best_open_job() -> int:
	var ranked: Array[int] = []
	var counter: int = controller._facility_index("counter", "shop")
	if counter >= 0 and controller._business_state != "workshop":
		ranked.append(counter)
	var plan: Dictionary = controller._inventory.restock_plan()
	if not plan.is_empty():
		var display := "hats" if plan.item.definition.is_hat() else "rack"
		var stocking: int = controller._facility_index(display, "shop")
		if stocking >= 0:
			ranked.append(stocking)
	if (not controller._production.order.is_empty() and not is_instance_valid(controller._production.actor)) or (controller._production.auto_restock and controller._inventory.in_location("storage").size() < controller._production.auto_stock_target and controller._production.can_start()):
		var sewing: int = controller._facility_index("sewing")
		if sewing >= 0:
			ranked.append(sewing)
	if not controller._dye.order.is_empty() and not is_instance_valid(controller._dye.actor):
		ranked.append(controller._facility_index("dye"))
	for id_value in (["loom"] if controller._business_state == "workshop" else ["loom", "packing", "fabric", "clippings"]):
		var index: int = controller._facility_index(id_value)
		if index >= 0:
			if id_value == "loom" and not controller.facilities[index].anchor.get_parent().work_available():
				continue
			ranked.append(index)
	for index in ranked:
		if index >= 0 and index < controller.facilities.size():
			if controller.facilities[index].activity != "resting" and not is_instance_valid(controller.facilities[index].staff):
				return index
	return -1


func cover_counter() -> void:
	var index: int = controller._facility_index("counter", "shop")
	if index < 0 or not counter_needs_staff() or is_instance_valid(controller.facilities[index].staff):
		return
	var target: Vector3 = controller.facilities[index].anchor.global_position
	var best: PaperDoll
	var best_distance := INF
	for doll in controller.staff:
		if not is_instance_valid(doll) or doll.energy <= StaffBehaviorScript.rest_threshold_for(doll):
			continue
		if bool(doll.get_meta("chore_reserved", false)):
			continue
		if bool(doll.get_meta("shift_home", false)) or bool(doll.get_meta("shift_departing", false)):
			continue
		var behavior: RefCounted = controller._staff_behaviors.get(doll.get_instance_id())
		if behavior != null and behavior.recovering:
			continue
		if bool(controller._staff_jobs.get(doll.get_instance_id(), {}).get("manual", false)):
			continue
		var distance: float = doll.global_position.distance_to(target)
		if distance < best_distance:
			best = doll
			best_distance = distance
	if best != null:
		controller._assign_staff(best, index, false)


func cashier_present() -> bool:
	var index: int = controller._facility_index("counter", "shop")
	if index < 0:
		return false
	var cashier: PaperDoll = controller.facilities[index].staff
	return is_instance_valid(cashier) and cashier.has_arrived() and cashier.global_position.distance_to(controller.facilities[index].anchor.global_position) < .45 and controller._staff_jobs.get(cashier.get_instance_id(), {}).get("phase") == "work"
