extends Node3D

const ITEM_DURATION := 2.7
const HANDOFF_DURATION := 1.2
const Stack = preload("res://scripts/garment_stack.gd")
var items: Array[Node3D] = []
var buyer: WeakRef
var cashier: WeakRef
var bag: Node3D
var elapsed := 0.0
var phase := "idle"
var index := 0
var source_transform := Transform3D.IDENTITY
var active_item: Node3D
var delivered := false


func begin(customer: Node3D, attendant: Node3D, selection: Array) -> void:
	buyer = weakref(customer)
	cashier = weakref(attendant)
	for item in selection:
		if is_instance_valid(item) and item.location == "carried" and not item.paid:
			items.append(item)
	items = Stack.ordered(items)
	if items.is_empty():
		delivered = true
		return
	bag = preload("res://components/shopping_bag.gd").new()
	bag.name = "PurchaseBag"
	add_child(bag)
	bag.fit_items(items)
	bag.position = Vector3(-.62,1.185,-.28)


func advance(delta: float) -> bool:
	if delivered: return true
	if delta <= 0: return false
	var customer: Node3D = buyer.get_ref()
	var attendant: Node3D = cashier.get_ref()
	if not is_instance_valid(customer) or not is_instance_valid(attendant): return false
	if index >= items.size(): return _handoff(customer,attendant,delta)
	var item: Node3D = items[index]
	if active_item != item:
		active_item = item
		source_transform = item.global_transform
		item.put_on_counter(customer)
		elapsed = 0.0
	elapsed = minf(elapsed+delta,ITEM_DURATION)
	var t := elapsed/ITEM_DURATION
	var table := _table_transform(item)
	if t < .23:
		phase = "place"
		# Slide the bottom garment clear of the remaining stack before lifting it.
		var clear := source_transform
		clear.origin += customer.body_rig.global_basis.z*(Stack.box(item).size.z+.09)
		item.global_transform = source_transform.interpolate_with(clear,smoothstep(0,.10,t)) if t < .10 else clear.interpolate_with(table,smoothstep(.10,.23,t))
		customer.reach("L",item.global_transform*item.presentation_bounds().get_center())
		attendant.reach("R",to_global(Vector3(.20,1.35,-.18)))
	elif t < .70:
		phase = "fold"
		customer.hand_targets.erase("L")
		if not item.definition.is_hat():
			var forms := ["Folded","FoldSides","FoldHalf","Folded"]
			var progress := clampf((t-.23)/.47*3.0,0,2.999)
			var step := int(progress)
			var weight := smoothstep(0,1,progress-step)
			item.forms.blend_forms(item.parts,forms[step],forms[step+1],weight)
			var from_box: AABB = item.presentation_bounds(forms[step])
			var to_box: AABB = item.presentation_bounds(forms[step+1])
			table = _surface_transform(item,AABB(from_box.position.lerp(to_box.position,weight),from_box.size.lerp(to_box.size,weight)))
		item.global_transform = table
		for side in ["L","R"]:
			var x := .30+(-1 if side == "L" else 1)*lerpf(.25,.08,sin((t-.23)/.47*PI))
			attendant.reach(side,to_global(Vector3(x,1.26,-.40)))
	else:
		phase = "insert"
		item.set_presentation("Folded")
		var destination: Transform3D = bag.item_transform(item)
		# Move above the open mouth first, then lower the actual folded mesh into it.
		var above := destination
		above.origin += bag.global_basis.y*(bag.dimensions.y+.10)
		if t < .84:
			item.global_transform = table.interpolate_with(above,smoothstep(.70,.84,t))
		else:
			item.global_transform = above.interpolate_with(destination,smoothstep(.84,1,t))
		var center: Vector3 = item.global_transform*item.presentation_bounds().get_center()
		attendant.reach("L",center+Vector3(-.16,.02,0))
		attendant.reach("R",center+Vector3(.16,.02,0))
	attendant.attend(item)
	if elapsed >= ITEM_DURATION:
		item.pack_into(bag)
		index += 1
		elapsed = 0.0
	return false


func _table_transform(item: Node3D) -> Transform3D:
	return _surface_transform(item,item.presentation_bounds("Folded"))


func _surface_transform(item: Node3D, bounds: AABB) -> Transform3D:
	var orientation := Stack.orientation(item)
	var flat_box := Transform3D(orientation,Vector3.ZERO)*bounds
	return global_transform*Transform3D(orientation,Vector3(.24,1.19+flat_box.size.y*.5,.02)-flat_box.get_center())


func _handoff(customer: Node3D, attendant: Node3D, delta: float) -> bool:
	phase = "handoff"
	elapsed = minf(elapsed+delta,HANDOFF_DURATION)
	var t := elapsed/HANDOFF_DURATION
	var start := Vector3(-.62,1.185,-.28)
	var clear := Vector3(-.62,1.24,.69+bag.dimensions.z*.5)
	if t < .60:
		bag.position = start.lerp(clear,smoothstep(0,.60,t))
	else:
		# Only lower after the complete footprint has cleared the countertop.
		bag.position = clear.lerp(Vector3(clear.x,.60,clear.z),smoothstep(.60,1,t))
	bag.set_closure(smoothstep(.60,1,t))
	var grip: Vector3 = bag.to_global(bag.grip())
	attendant.reach("L",grip+Vector3(0,.02,-.035))
	customer.reach("R",grip+Vector3(0,.02,.035))
	if t >= 1:
		delivered = true
		bag.hand_over(customer)
		customer.refresh_outfit()
	return delivered


func cancel() -> void:
	var customer: Node3D = buyer.get_ref() if buyer != null else null
	for item in items:
		if not is_instance_valid(item) or item.paid: continue
		if is_instance_valid(customer): item.resume_carry(customer)
		# A removed customer is recovered by inventory.advance using holder_lost().
	if is_instance_valid(customer) and customer.shopping_bag == bag: customer.shopping_bag = null
	if is_instance_valid(bag): bag.queue_free()


func finish() -> void:
	bag = null
