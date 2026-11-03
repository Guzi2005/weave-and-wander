extends RefCounted

var game: Node
var transfers := {}

func setup(controller: Node) -> void:
	game = controller
	var stock = game._inventory
	stock.storage_support = game._production.output_bin
	stock.storage_access = game._production.cabinet.access
	for item in stock.in_location("storage"):
		stock._store(item)

func item_for(id: String) -> Node3D:
	for item in game._inventory.items:
		if item.item_id == id: return item
	return null

func held_pose(actor: Node3D, item: Node3D) -> Transform3D:
	if item.head_contact.is_finite():
		return actor.body_rig.global_transform * Transform3D(Basis.IDENTITY,Vector3(0,1.35,.50)-item.head_contact)
	return actor.body_rig.global_transform * preload("res://scripts/garment_stack.gd").placement(item,[item],Vector3(0,1.25,.46))

func hands(actor: Node3D, item: Node3D) -> void:
	var center: Vector3 = item.to_global(item.presentation_bounds().get_center())
	if item.head_contact.is_finite(): center = item.to_global(item.head_contact)
	actor.reach("L",center-actor.body_rig.global_basis.x*.16)
	actor.reach("R",center+actor.body_rig.global_basis.x*.16)
	actor.apply_reaches()

func arrived(actor: Node3D, job: Dictionary) -> void:
	var item := item_for(str(job.restock_id))
	if item == null:
		job.restock_phase = ""
		job.phase = "work"
		job.timer = 0.0
		actor.clear_interaction()
		actor.set_meta("material_handling",false)
		return
	if job.restock_phase == "fetch":
		job.restock_phase = "lift"
		transfers[actor.get_instance_id()] = {"start":item.global_transform,"time":0.0}
		if item.display_mount != null and is_instance_valid(item.display_mount.get_ref()):
			var old_mount: Node3D = item.display_mount.get_ref()
			if old_mount.get_meta("physical_storage_mount",false): old_mount.queue_free()
		item.display_mount = null
		item.set_meta("restock_worker",weakref(actor))
		item.location = "staff_carried"
		item.visible = true
		actor.set_meta("material_handling",true)
	elif job.restock_phase == "place":
		job.restock_phase = "hang"
		var start := item.global_transform
		var message: String = game._inventory.restock_item(item.item_id)
		transfers[actor.get_instance_id()] = {"start":start,"target":item.global_transform,"mount":item.display_mount,"time":0.0,"message":message}
		item.display_mount = null
		item.location = "staff_carried"
		item.reserved_by = "staff:%d" % actor.get_instance_id()
		item.global_transform = start

func advance(actor: Node3D, job: Dictionary, delta: float) -> void:
	var item := item_for(str(job.restock_id))
	if item == null:
		job.restock_phase = ""
		job.phase = "work"
		job.timer = 0.0
		actor.clear_interaction()
		actor.set_meta("material_handling",false)
		return
	var id := actor.get_instance_id()
	if job.restock_phase in ["fetch","place"]:
		var plan: Dictionary = game._inventory.restock_plan_for(item.item_id)
		if not plan.is_empty():
			var destination: Vector3 = plan.fetch if job.restock_phase == "fetch" else plan.place
			if actor.destination.distance_to(destination) > .03:
				actor.set_destination(destination,"stocking")
	if job.restock_phase == "place":
		item.global_transform = held_pose(actor,item)
		hands(actor,item)
		return
	if job.restock_phase not in ["lift","hang"]: return
	var transfer: Dictionary = transfers[id]
	transfer.time += delta
	var t := smoothstep(0,1,minf(transfer.time/1.0,1))
	var target: Transform3D = held_pose(actor,item) if job.restock_phase == "lift" else transfer.target
	if job.restock_phase == "hang" and transfer.mount != null and is_instance_valid(transfer.mount.get_ref()):
		target = transfer.mount.get_ref().global_transform
	item.global_transform = transfer.start.interpolate_with(target,t)
	var toward: Vector3 = target.origin - actor.global_position
	actor.resting_facing = atan2(toward.x,toward.z)
	hands(actor,item)
	if transfer.time < 1: return
	if job.restock_phase == "lift":
		var plan: Dictionary = game._inventory.restock_plan_for(item.item_id)
		job.restock_phase = "place"
		actor.set_destination(plan.place,"stocking")
	else:
		item.display_mount = transfer.mount
		item.location = "rack" if item.slot >= 0 else "storage"
		item.reserved_by = ""
		item.remove_meta("restock_worker")
		job.restock_phase = ""
		job.restocked = true
		job.phase = "work"
		job.timer = 1.0
		actor.clear_interaction()
		actor.set_meta("material_handling",false)
		transfers.erase(id)
		game._show_toast("%s%s" % [actor.doll_name,transfer.message])

func cancel(actor: Node3D, item_id: String) -> void:
	var item := item_for(item_id)
	if item != null and item.location == "staff_carried":
		game._inventory.drop_restock(item,actor.global_position)
	if item != null:
		item.reserved_by = ""
		if item.has_meta("restock_worker"): item.remove_meta("restock_worker")
	actor.clear_interaction()
	actor.set_meta("material_handling",false)
	transfers.erase(actor.get_instance_id())
