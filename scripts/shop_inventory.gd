extends Node3D

const Item = preload("res://scripts/garment_item.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const RECIPES = preload("res://scripts/garment_recipes.gd")
const CLOTHING_SLOTS := 6
const SLOT_COUNT := 9
const STORAGE_LIMIT := 9
const OPENING_RACK := [[0, 0], [3, 1], [2, 1], [4, 1], [5, 2], [1, 3], [6, 0], [7, 2], [8, 3]]
const OPENING_STORAGE := [[3, 2], [4, 2], [6, 1], [10, 0], [11, 0], [13, 0], [14, 0], [15, 0], [16, 0]]

var items: Array[Node3D] = []
var slots: Array = []
var transactions: Array[Dictionary] = []
var events: Array[Dictionary] = []
var storage_support: Node3D
var storage_access: Marker3D
var shop: Node3D
var service_authorizer: Callable
var _serial := 0
var fabric_batches: Array[Dictionary] = [{"id":"opening_cloth","meters":8.0,"pattern":"plain","palette":0,"source":"opening"}]
var materials: RefCounted = preload("res://scripts/material_ledger.gd").new()
var produced_orders: Dictionary = {}
var price_policy: Callable

func sale_price(item: Node3D) -> int:
	if not item.reserved_by.is_empty() and item.has_meta("quoted_price"):
		return int(item.get_meta("quoted_price"))
	return int(price_policy.call(item.definition.price)) if price_policy.is_valid() else int(item.definition.price)


func _init() -> void:
	fabric_batches[0].merge({"name":"湖蓝棉布","form":"book","pigment":Color("779ab1"),"material":"cotton","width_m":1.4,"thickness_m":.001,"capacity_m":8.0},true)
	fabric_batches.append_array([
		{"id":"rose_check","name":"蔷薇格纹棉布","meters":6.0,"capacity_m":8.0,"pattern":"check","pattern_code":2,"palette":1,"pigment":Color("bb7986"),"material":"cotton","width_m":1.4,"form":"book"},
		{"id":"sage_linen","name":"鼠尾草亚麻","meters":5.0,"capacity_m":8.0,"pattern":"plain","palette":2,"pigment":Color("8ba28a"),"material":"linen","width_m":1.5,"form":"book"},
		{"id":"gold_stripe","name":"麦黄条纹棉布","meters":3.0,"capacity_m":8.0,"pattern":"stripe","pattern_code":1,"palette":1,"pigment":Color("d2ae66"),"material":"cotton","width_m":1.2,"form":"book"},
		{"id":"cream_roll","name":"本色棉布卷","meters":10.0,"capacity_m":12.0,"pattern":"plain","palette":0,"pigment":Color("dcd2b5"),"material":"cotton","width_m":1.4,"form":"roll"},
	])
	materials.bind_fabrics(fabric_batches)
	materials.thread_batches[0]["name"] = "湖蓝棉线"
	materials.thread_batches.append_array([
		{"id":"thread_rose","name":"蔷薇棉线","meters":64.0,"capacity_m":80.0,"pigment":Color("bb7986"),"material":"cotton"},
		{"id":"thread_cream","name":"本色棉线","meters":80.0,"capacity_m":80.0,"pigment":Color("dcd2b5"),"material":"cotton"},
		{"id":"thread_sage","name":"鼠尾草棉线","meters":48.0,"capacity_m":80.0,"pigment":Color("8ba28a"),"material":"cotton"},
	])
	materials.yarn_batches = preload("res://scripts/material_catalog.gd").extend_opening_stock(fabric_batches,materials.thread_batches)


func create_from_work_order(order: Dictionary) -> Node3D:
	if produced_orders.has(order.id): return produced_orders[order.id]
	if float(order.get("sew_progress",0)) < 1.0 or order.status != "sewn": return null
	var style := int(order.get("outfit_style",1))
	if not RECIPES.valid(style): return null
	var data: Dictionary = order.material_snapshot
	var material_data := data.duplicate(true)
	if style == 12: material_data["garment_skirt_length"] = order.get("skirt_length",.70)
	if style in [10,11,13]: material_data["garment_length"] = order.get("garment_length",.80)
	material_data["thread_pigment"] = order.thread_snapshot.get("pigment",Color.WHITE)
	var item := _create(0 if style == RECIPES.FLOWER_STYLE else style,int(data.get("palette",0)),material_data,"flower" if style == RECIPES.FLOWER_STYLE else "")
	item.apply_material_data(item.definition.material_data)
	item.set_meta("fabric_sources",[{"fabric_id":order.fabric_id,"meters":order.estimate.net_m}])
	item.set_meta("work_order_id",order.id)
	item.set_meta("thread_source",order.thread_id)
	item.set_meta("material_cost",order.estimate.cost_estimate)
	produced_orders[order.id] = item
	events.append({"event":"crafted","item_id":item.item_id,"work_order_id":order.id})
	return item


func store_produced(item: Node3D, support: Node3D) -> void:
	var local := stored_transform(item)
	if item.definition.accessory_kind == "flower": local.origin.x += .28
	item.place("accessory" if item.definition.accessory_kind == "flower" else "storage",support.global_transform*local)
	item.visible = true
	item.set_meta("physical_storage",true)
	var mount := Marker3D.new()
	mount.set_meta("physical_storage_mount",true)
	support.add_child(mount)
	mount.transform = local
	item.display_mount = weakref(mount)


func flower_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for item in items:
		if item.definition.accessory_kind == "" and item.definition.flower_material_data.is_empty() and item.location in ["storage","rack"] and not item.paid and item.reserved_by.is_empty(): result.append(item)
	return result


func attach_flower_to(accessory: Node3D, target_id: String) -> bool:
	if accessory.location != "accessory": return false
	for target in flower_targets():
		if target.item_id != target_id: continue
		if not target.attach_flower(accessory): return false
		if accessory.display_mount != null and is_instance_valid(accessory.display_mount.get_ref()): accessory.display_mount.get_ref().queue_free()
		accessory.display_mount = null
		accessory.location = "attached"
		accessory.hide()
		accessory.set_meta("attached_to",target.item_id)
		events.append({"event":"flower_attached","item_id":accessory.item_id,"target_id":target.item_id})
		return true
	return false

func stored_transform(item: Node3D) -> Transform3D:
	if item.definition.is_hat():
		var contact: Vector3 = item.head_contact if item.head_contact.is_finite() else Vector3(0,item.bottom_height,0)
		var level := .03
		for piece in in_location("storage"):
			if piece != item and not piece.definition.is_hat() and piece.visible:
				level += piece.presentation_bounds("Folded").size.z+.006
		for piece in in_location("storage"):
			if piece == item: break
			if piece.definition.is_hat() and piece.visible:
				var support_y: float = piece.head_contact.y if piece.head_contact.is_finite() else piece.bottom_height
				level += maxf(.08,piece.presentation_bounds().end.y-support_y)+.015
		return Transform3D(Basis.IDENTITY,Vector3(0,level,0)-contact)
	var height := .006
	for piece in in_location("accessory" if item.definition.accessory_kind == "flower" else "storage"):
		if piece != item and not piece.definition.is_hat() and piece.visible and piece.has_meta("physical_storage") and piece.display_mount != null:
			height += piece.presentation_bounds("Folded").size.z+.006
	var bounds: AABB = item.presentation_bounds("Folded")
	var orientation := Basis(Vector3.RIGHT,-PI*.5)
	var local := Transform3D(orientation,Vector3(0,height+bounds.size.z*.5,0)-orientation*bounds.get_center())
	return local


func receive_fabric(batch: Dictionary) -> void:
	if fabric_batches.any(func(existing: Dictionary) -> bool: return existing.id == batch.id): return
	fabric_batches.append(batch.duplicate(true))
	events.append({"event":"woven","fabric_id":batch.id,"meters":batch.meters})


func fabric_meters() -> float:
	var total := 0.0
	for batch in fabric_batches: total += float(batch.meters)
	return total


func _consume_fabric(meters: float) -> Array:
	var used: Array = []
	for batch in fabric_batches:
		var take := minf(meters,float(batch.meters))
		if take <= 0: continue
		batch.meters -= take
		meters -= take
		used.append({"fabric_id":batch.id,"meters":take})
		if meters <= .00001: break
	return used


func build(room: Node3D) -> void:
	shop = room
	slots.resize(SLOT_COUNT)
	for index in SLOT_COUNT:
		slots[index] = []
	for index in OPENING_RACK.size():
		_place_on_slot(_create(OPENING_RACK[index][0], OPENING_RACK[index][1]), index)
	for entry in OPENING_STORAGE:
		_store(_create(entry[0], entry[1]))


func _create(style: int, palette: int, material_data: Dictionary = {}, accessory_kind: String = "") -> Node3D:
	_serial += 1
	var item := Item.new()
	item.item_id = "garment_%03d" % _serial
	item.name = item.item_id
	item.definition = Definition.create(style, palette)
	if style == 12: item.definition.skirt_length = clampf(float(material_data.get("garment_skirt_length",.70)),.35,1.05)
	if style in [10,11,13]: item.definition.garment_length = clampf(float(material_data.get("garment_length",.80)),.55,1.05)
	item.definition.accessory_kind = accessory_kind
	if not material_data.is_empty():
		item.definition.material_data = material_data
		item.definition.compact_apron_folds = style == 1
		item.definition.folded_thickness = .006
	add_child(item)
	item.build()
	items.append(item)
	return item


func slot_transform(index: int, item: Node3D = null) -> Transform3D:
	if item != null and item.display_mount != null and is_instance_valid(item.display_mount.get_ref()):
		return item.display_mount.get_ref().global_transform
	return display_fixture(index).get_node("GarmentMount").global_transform


func display_fixture(index: int) -> Node3D:
	if index >= CLOTHING_SLOTS:
		return shop.get_node("SmallGoodsCabinet/Stand%d" % (index - CLOTHING_SLOTS))
	return shop.get_node("GarmentDisplay/Hanger%d" % index)


func pickup_anchor(item: Node3D) -> Marker3D:
	return shop.interaction_anchor("pickup_%d" % item.slot)


func _basket_transform(item: Node3D, layer: int = -1) -> Transform3D:
	# Folded states keep the same mesh, UVs and stock identity.
	if layer < 0:
		layer = in_location("basket").size()
	var basket := shop.get_node("LaundryBasket") as Node3D
	if item.definition.is_hat():
		# Rest the brim on the rim. Centering the head-space mesh drops the crown through the base.
		if item.head_contact.is_finite():
			return basket.global_transform * Transform3D(Basis.IDENTITY, Vector3.UP * (_basket_rim_y() + layer*.14) - item.head_contact)
		var bounds: AABB = item.rest_bounds
		var y: float = _basket_rim_y() + layer * (bounds.size.y + .03) - bounds.position.y
		var center: Vector3 = bounds.get_center()
		return basket.global_transform * Transform3D(Basis.IDENTITY, Vector3(-center.x, y, -center.z))
	var bounds: AABB = item.presentation_bounds("Folded")
	var orientation := Basis(Vector3.RIGHT, -PI * .5)
	return basket.global_transform * Transform3D(orientation, Vector3(0, .20 + layer * .12, 0) - orientation * bounds.get_center())


func _basket_rim_y() -> float:
	return .67


func _place_on_slot(item: Node3D, index: int) -> void:
	assert(can_display(index, item))
	if item not in slots[index]:
		slots[index].append(item)
	item.place("rack", slot_transform(index), index)
	_sync_slot(index)


func can_display(index: int, item: Node3D) -> bool:
	if index < 0 or index >= SLOT_COUNT or not is_instance_valid(item) or item.paid:
		return false
	if item.definition.accessory_kind != "": return false
	if item in slots[index]:
		return true
	if item.definition.is_hat() != (index >= CLOTHING_SLOTS):
		return false
	if slots[index].is_empty():
		return true
	if index >= CLOTHING_SLOTS:
		# Matching crowns nest; unlike hat types must not interpenetrate.
		return slots[index].size() < 3 and slots[index][0].definition.outfit_style == item.definition.outfit_style
	if slots[index].size() >= 2 or item.definition.hanger_profile().kind != "shoulder":
		return false
	for existing in slots[index]:
		if existing.definition.hanger_profile().kind != "shoulder" or not existing.definition.compatible(item.definition):
			return false
	return true


func display_item(item: Node3D, index: int) -> bool:
	if not can_display(index,item) or not item.reserved_by.is_empty() or item.location not in ["storage", "rack", "basket"]:
		return false
	if item.location == "rack":
		var previous: int = item.slot
		slots[previous].erase(item)
		_sync_slot(previous)
	_place_on_slot(item,index)
	return true


func _sync_slot(index: int) -> void:
	var fixture := display_fixture(index)
	if index < CLOTHING_SLOTS:
		fixture.display(slots[index])
		for item in slots[index]:
			item.display_mount = weakref(fixture.item_mount(item))
			item.update_attachment()
		return
	for child in fixture.get_children():
		if child is Marker3D and child.name != "GarmentMount":
			child.free()
	for layer in slots[index].size():
		var item: Node3D = slots[index][layer]
		var mount := Marker3D.new()
		mount.name = "Mount_" + item.item_id
		fixture.add_child(mount)
		mount.rotation.y = layer * .12
		var contact := Vector3(0,item.bottom_height,0)
		if item.head_contact.is_finite(): contact = item.head_contact
		mount.position = Vector3.UP * layer * .14 - mount.basis * contact
		item.display_mount = weakref(mount)
		item.update_attachment()
		if item.head_contact.is_finite():
			var top: MeshInstance3D = fixture.get_parent().get_node("Top")
			var lip := top.get_aabb().end
			var at := top.to_local(fixture.global_position)
			var edge := top.to_global(Vector3(at.x+.34, lip.y+.021, lip.z+.035))
			var foot: Vector3 = shop.to_local(edge)
			foot.y = .052
			item.drape_on_display(edge, shop.to_global(foot))
		if layer == 0:
			fixture.get_node("GarmentMount").transform = mount.transform


func _store(item: Node3D) -> void:
	if is_instance_valid(storage_support):
		store_produced(item,storage_support)
		return
	item.place("storage", Transform3D(Basis.IDENTITY, shop.to_global(Vector3(-4.65, -4.0, -1.0))))


func in_location(location: String) -> Array[Node3D]:
	var found: Array[Node3D] = []
	found.assign(items.filter(func(item: Node3D) -> bool: return is_instance_valid(item) and item.location == location))
	return found


func free_slot(item: Node3D = null) -> int:
	for index in slots.size():
		if slots[index].is_empty() and (item == null or can_display(index,item)):
			return index
	if item != null:
		for index in slots.size():
			if can_display(index,item):
				return index
	return -1


func on_rack() -> Array[Node3D]:
	var found: Array[Node3D] = []
	found.assign(in_location("rack").filter(func(item: Node3D) -> bool: return item.reserved_by.is_empty()))
	return found


# Picks the garment this customer likes best from what is actually hanging.
func choose_for(customer: Node, profile: RefCounted) -> Dictionary:
	var best: Node3D
	var best_score := -INF
	var styled := false
	for item in on_rack():
		styled = styled or profile.wants(item.definition)
		var score: float = profile.browse_score(item.definition, sale_price(item))
		if score > best_score:
			best_score = score
			best = item
	if best == null or best_score == -INF:
		var reason := "想要的都太贵了" if styled else "没有想要的款式"
		events.append({"event": "browse_failed", "customer_id": customer.customer_id, "reason": reason})
		return {"item": null, "reason": reason}
	var chosen: Array[Node3D] = [best]
	var remaining: int = profile.budget - sale_price(best)
	for candidate in on_rack():
		if chosen.size() >= profile.max_pieces:
			break
		if candidate == best or sale_price(candidate) > remaining:
			continue
		if profile.color_score(candidate.definition) < 0 or not chosen.all(func(piece: Node3D) -> bool: return piece.definition.compatible(candidate.definition)):
			continue
		chosen.append(candidate)
		remaining -= sale_price(candidate)
	for piece in chosen:
		piece.set_meta("quoted_price", sale_price(piece))
		piece.reserve(customer)
		record("reserved", piece, customer)
	return {"item": best, "items": chosen, "reason": ""}


func pick_up(item: Node3D, customer: Node) -> bool:
	var index: int = item.slot
	if index < 0 or item not in slots[index] or not customer.carry_item(item):
		return false
	slots[index].erase(item)
	_sync_slot(index)
	record("picked_up", item, customer)
	return true


func return_item(item: Node3D, customer: Node = null) -> void:
	if item.paid:
		return
	if item.location == "rack" and item.slot >= 0 and item in slots[item.slot]:
		item.reserved_by = ""
		return
	var tried: bool = item.tried_on
	if tried:
		item.place("basket", _basket_transform(item))
	elif free_slot(item) >= 0:
		_place_on_slot(item, free_slot(item))
	else:
		_store(item)
	if customer != null:
		record("returned", item, customer)


# One staff restocking cycle moves exactly one physical garment.
func restock_step() -> String:
	var slot := free_slot()
	var basket := in_location("basket")
	if not basket.is_empty():
		var item: Node3D = basket[-1]
		slot = free_slot(item)
		item.tried_on = false
		if slot >= 0:
			_place_on_slot(item, slot)
		else:
			_store(item)
		events.append({"event": "restocked", "item_id": item.item_id, "from": "basket", "location": item.location})
		return ("把试穿过的%s挂回衣架" if slot >= 0 else "把试穿过的%s叠回库房") % item.definition.display_name()
	var stored := in_location("storage")
	for item in stored:
		slot = free_slot(item)
		if slot >= 0:
			_place_on_slot(item, slot)
			events.append({"event": "restocked", "item_id": item.item_id, "from": "storage", "location": item.location})
			return "补上一件%s" % item.definition.display_name()
	return ""


func can_restock() -> bool:
	if not in_location("basket").is_empty():
		return true
	return in_location("storage").any(func(item: Node3D) -> bool: return free_slot(item) >= 0)


func sew_new(rng: RandomNumberGenerator) -> Node3D:
	if in_location("storage").size() >= STORAGE_LIMIT or fabric_meters() < .8:
		return null
	var choices := [0,1,2,3,4,5,6,7,8,10,11,12,13]
	var item := _create(choices[rng.randi_range(0,choices.size()-1)], rng.randi_range(0, Definition.PALETTE_NAMES.size() - 1))
	item.set_meta("fabric_sources",_consume_fabric(.8))
	_store(item)
	events.append({"event": "sewn", "item_id": item.item_id, "location": item.location})
	return item


func checkout(item: Node3D, customer: Node) -> int:
	if not service_authorizer.is_valid() or not service_authorizer.call():
		return 0
	var amount: int = sale_price(item)
	if not item.settle(customer):
		return 0
	transactions.append({"item_id": item.item_id, "customer_id": customer.customer_id, "price": amount, "worn": item.location == "worn"})
	record("paid", item, customer)
	return amount


func record(event: String, item: Node3D, customer: Node, extra: Dictionary = {}) -> void:
	var entry := {"event": event, "item_id": item.item_id, "customer_id": customer.customer_id, "location": item.location}
	entry.merge(extra)
	events.append(entry)


func restock_plan() -> Dictionary:
	for item in in_location("basket") + in_location("stock_pending"):
		if not item.reserved_by.is_empty():
			continue
		var slot := free_slot(item)
		return {"item": item, "slot": slot, "fetch": fetch_position(item), "place": _stand_for_slot(slot, item)}
	for item in in_location("storage"):
		if not item.reserved_by.is_empty():
			continue
		var slot := free_slot(item)
		if slot >= 0:
			return {"item": item, "slot": slot, "fetch": fetch_position(item), "place": _stand_for_slot(slot, item)}
	return {}


func restock_plan_for(item_id: String) -> Dictionary:
	for item in items:
		if item.item_id == item_id and not item.paid and item.location in ["basket", "storage", "staff_carried", "stock_pending"]:
			var slot := free_slot(item)
			return {"item": item, "slot": slot, "fetch": fetch_position(item), "place": _stand_for_slot(slot, item)}
	return {}


func fetch_position(item: Node3D) -> Vector3:
	if item.location == "stock_pending": return item.get_meta("fetch_position")
	if item.location == "basket":
		return shop.interaction_anchor("return_basket").global_position
	return storage_access.global_position if is_instance_valid(storage_access) else shop.interaction_anchor("return_basket").global_position


func _stand_for_slot(index: int, item: Node3D) -> Vector3:
	if index < 0:
		return storage_access.global_position if is_instance_valid(storage_access) else shop.interaction_anchor("return_basket").global_position
	var mount: Vector3 = slot_transform(index, item if item.location == "rack" else null).origin
	for step in 6:
		var local := shop.to_local(Vector3(mount.x, 0, mount.z + .55 + step * .16))
		if shop.is_walkable(Vector2(local.x, local.z)):
			return shop.to_global(Vector3(local.x, 0, local.z))
	return Vector3(mount.x, 0, mount.z + .9)


func restock_item(item_id: String) -> String:
	for item in items:
		if item.item_id != item_id or item.paid:
			continue
		if str(item.reserved_by).begins_with("staff:"):
			item.reserved_by = ""
		item.tried_on = false
		var slot := free_slot(item)
		if slot >= 0:
			_place_on_slot(item, slot)
		else:
			_store(item)
		events.append({"event": "restocked", "item_id": item.item_id, "from": "claimed", "location": item.location})
		return "补上了%s" % item.definition.display_name()
	return ""


func drop_restock(item: Node3D, access: Vector3) -> void:
	for index in slots.size():
		if item in slots[index]:
			slots[index].erase(item)
			_sync_slot(index)
	var pose: Transform3D = item.global_transform
	var bounds: AABB = pose * item.presentation_bounds()
	pose.origin.y += .052 - ((pose*item.head_contact).y if item.head_contact.is_finite() else bounds.position.y)
	item.place("stock_pending",pose)
	item.set_meta("fetch_position",access)
	item.set_meta("physical_storage",false)
	if item.has_meta("restock_worker"): item.remove_meta("restock_worker")
	if item.head_contact.is_finite():
		var contact: Vector3 = item.to_global(item.head_contact)
		item.drape_on_display(contact+Vector3(.34,0,.10),contact+Vector3(.38,0,.15))


func advance() -> void:
	items = items.filter(func(item: Node3D) -> bool: return is_instance_valid(item))
	var cloth_layer := 0
	var hat_layer := 0
	var stored_heights := {}
	for item in items:
		if item.location == "staff_carried" and item.has_meta("restock_worker") and not is_instance_valid(item.get_meta("restock_worker").get_ref()):
			var access := Vector3(item.global_position.x,0,item.global_position.z+.6)
			drop_restock(item,access)
		if item.holder_lost():
			if item.paid:
				item.collect()
			else:
				return_item(item)
		if item.location == "rack":
			item.global_transform = slot_transform(item.slot, item)
		elif item.location == "basket":
			if item.definition.is_hat():
				var pose := _basket_transform(item, hat_layer)
				var moved: bool = not item.global_transform.is_equal_approx(pose)
				item.global_transform = pose
				if item.head_contact.is_finite() and (moved or not item.has_meta("basket_drape")):
					var basket: Node3D = shop.get_node("LaundryBasket")
					var edge := basket.to_global(Vector3(.32,_basket_rim_y()+.025,.33))
					var foot: Vector3 = shop.to_local(edge)
					foot.y = .052
					item.drape_on_display(edge, shop.to_global(foot))
					item.set_meta("basket_drape",true)
				hat_layer += 1
			else:
				item.global_transform = _basket_transform(item, cloth_layer)
				cloth_layer += 1
		if item.location == "storage" and item.visible and item.display_mount != null:
			var mount: Node3D = item.display_mount.get_ref()
			if is_instance_valid(mount) and mount.get_meta("physical_storage_mount",false):
				var support_id := mount.get_parent().get_instance_id()
				if item.definition.is_hat():
					mount.transform = stored_transform(item)
					item.update_attachment()
					if item.head_contact.is_finite() and (not item.has_meta("storage_drape_pose") or not item.global_transform.is_equal_approx(item.get_meta("storage_drape_pose"))):
						var edge: Vector3 = mount.get_parent().to_global(Vector3(.42,0,.39))
						item.drape_on_display(edge,Vector3(edge.x,.052,edge.z))
						item.set_meta("storage_drape_pose",item.global_transform)
					continue
				var bottom: float = stored_heights.get(support_id,.006)
				var bounds: AABB = item.presentation_bounds("Folded")
				var orientation := Basis(Vector3.RIGHT,-PI*.5)
				mount.transform = Transform3D(orientation,Vector3(0,bottom+bounds.size.z*.5,0)-orientation*bounds.get_center())
				stored_heights[support_id] = bottom+bounds.size.z+.006
		item.update_attachment()


func release_customer(customer: Node3D) -> void:
	for item in items:
		if is_instance_valid(item) and item.reserved_by == customer.customer_id:
			if item.paid:
				item.collect()
			else:
				return_item(item,customer)
