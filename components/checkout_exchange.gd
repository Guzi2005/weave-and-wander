extends Node3D

const DURATION := 1.7
var buyer: WeakRef
var cashier: WeakRef
var elapsed := 0.0
var phase := "idle"
var completed_count := 0
var cash: Node3D
var drawer: MeshInstance3D
var active := false
var packing: Node3D
var goods: Array = []


func _ready() -> void:
	cash = Node3D.new()
	cash.name = "Payment"
	add_child(cash)
	var note := _box(cash,"Banknote",Vector3(.19,.009,.10),Color("91aa7f"))
	note.position = Vector3.ZERO
	var seal := _box(cash,"NoteBand",Vector3(.025,.002,.10),Color("dbd4a8"))
	seal.position.y = .006
	for index in 3:
		var coin := MeshInstance3D.new()
		coin.name = "Coin%d"%index
		var mesh := CylinderMesh.new()
		mesh.top_radius = .037
		mesh.bottom_radius = .037
		mesh.height = .009
		mesh.radial_segments = 20
		coin.mesh = mesh
		coin.position = Vector3(.045,.013+index*.01,.01)
		coin.material_override = _material(Color("c59d48"))
		cash.add_child(coin)
	cash.hide()
	drawer = _box(self,"CashDrawer",Vector3(.40,.065,.33),Color("573b50"))
	drawer.position = Vector3(.75,1.22,-.06)


func _process(_delta: float) -> void:
	if active and (not is_instance_valid(buyer.get_ref()) or not is_instance_valid(cashier.get_ref())):
		cancel()


func _box(parent: Node, label: String, size: Vector3, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = preload("res://components/upholstered_pad.gd").rounded_mesh(size,.004)
	result.material_override = _material(color)
	parent.add_child(result)
	return result


func _material(color: Color) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = preload("res://shaders/room_paper.gdshader")
	result.set_shader_parameter("pigment",color)
	return result


func advance(customer: Node3D, attendant: Node3D, delta: float, selection: Array = []) -> bool:
	if delta <= 0.0: return false
	if not active:
		buyer = weakref(customer)
		cashier = weakref(attendant)
		elapsed = 0.0
		active = true
		goods = selection.duplicate()
	if buyer.get_ref() != customer or cashier.get_ref() != attendant:
		cancel()
		return false
	if is_instance_valid(packing):
		var done: bool = packing.advance(delta)
		phase = packing.phase
		return done
	elapsed = minf(DURATION,elapsed+delta)
	var t := elapsed/DURATION
	customer.resting_facing = get_parent().global_rotation.y+PI
	attendant.resting_facing = get_parent().global_rotation.y
	customer.attend(attendant)
	attendant.attend(customer)
	var front := to_global(Vector3(-.10,1.24,.51))
	var back := to_global(Vector3(-.10,1.24,-.51))
	var customer_hand: Vector3 = customer.body_rig.to_global(Vector3(.20,1.39,.28))
	var staff_hand: Vector3 = attendant.body_rig.to_global(Vector3(.19,1.44,.28))
	if t < .40:
		phase = "offer"
		cash.global_position = customer_hand.lerp(front,smoothstep(0,.34,t))
		customer.reach("R",cash.global_position+Vector3(0,.02,0))
		attendant.reach("L",back+Vector3(0,.09,0))
	elif t < .72:
		phase = "receive"
		cash.global_position = front.lerp(back,smoothstep(.40,.72,t))
		customer.reach("R",front.lerp(customer_hand,smoothstep(.4,.6,t)))
		attendant.reach("L",back+Vector3(0,.025,0))
	else:
		phase = "deposit"
		cash.global_position = back.lerp(staff_hand,smoothstep(.72,.95,t))
		attendant.reach("L",cash.global_position+Vector3(0,.02,0))
		customer.hand_targets.erase("R")
	cash.visible = t < .96
	drawer.position.z = -.06- sin(smoothstep(.65,1.0,t)*PI)*.19
	if elapsed >= DURATION:
		customer.clear_interaction()
		attendant.clear_interaction()
		packing = preload("res://components/counter_packing.gd").new()
		packing.name = "OrderPacking"
		add_child(packing)
		packing.begin(customer,attendant,goods)
		return packing.delivered
	return false


func finish() -> void:
	completed_count += 1
	if is_instance_valid(packing):
		packing.finish()
		packing.queue_free()
	packing = null
	cancel()


func cancel() -> void:
	if is_instance_valid(packing):
		packing.cancel()
		packing.queue_free()
	packing = null
	goods.clear()
	for reference in [buyer,cashier]:
		var actor: Node3D = reference.get_ref() if reference != null else null
		if is_instance_valid(actor): actor.clear_interaction()
	active = false
	elapsed = 0.0
	phase = "idle"
	if is_instance_valid(cash): cash.hide()
	if is_instance_valid(drawer): drawer.position.z = -.06
	buyer = null
	cashier = null
